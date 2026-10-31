package postgres

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type MediaAsset struct {
	ID                uuid.UUID
	ResourceID        uuid.UUID
	OriginalObjectKey string
	MimeType          string
	SizeBytes         int64
	ChecksumSHA256    string
	Status            string
	HLSMasterKey      string
	FailureReason     string
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

type MediaRepo struct{ pool *pgxpool.Pool }

func NewMediaRepo(pool *pgxpool.Pool) *MediaRepo { return &MediaRepo{pool: pool} }

func (r *MediaRepo) Create(ctx context.Context, a *MediaAsset) error {
	_, err := r.pool.Exec(ctx, `
		INSERT INTO media_assets (id, resource_id, original_object_key, mime_type, size_bytes, checksum_sha256, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7)`,
		a.ID, a.ResourceID, a.OriginalObjectKey, a.MimeType, a.SizeBytes, a.ChecksumSHA256, a.Status)
	return err
}

// Asegurar deja un único activo por recurso y rellena a.ID y a.Status con
// lo persistido.
//
// Si el recurso no tenía activo, lo inserta. Si ya tenía uno del mismo
// original (misma clave y mismo checksum), lo reutiliza: confirmar dos veces
// no debe crear dos transcodificaciones. Si el original cambió, reabre el
// activo existente para que el worker vuelva a procesarlo.
func (r *MediaRepo) Asegurar(ctx context.Context, a *MediaAsset) error {
	const mismoOriginal = `media_assets.checksum_sha256 IS NOT DISTINCT FROM EXCLUDED.checksum_sha256
		AND media_assets.original_object_key = EXCLUDED.original_object_key`
	return r.pool.QueryRow(ctx, `
		INSERT INTO media_assets (id, resource_id, original_object_key, mime_type, size_bytes, checksum_sha256, status)
		VALUES ($1,$2,$3,$4,$5,$6,$7)
		ON CONFLICT (resource_id) DO UPDATE SET
			original_object_key = EXCLUDED.original_object_key,
			mime_type = EXCLUDED.mime_type,
			size_bytes = EXCLUDED.size_bytes,
			checksum_sha256 = EXCLUDED.checksum_sha256,
			status = CASE WHEN `+mismoOriginal+` THEN media_assets.status ELSE 'uploaded' END,
			hls_master_key = CASE WHEN `+mismoOriginal+` THEN media_assets.hls_master_key ELSE NULL END,
			derived_pdf_key = CASE WHEN `+mismoOriginal+` THEN media_assets.derived_pdf_key ELSE NULL END,
			failure_reason = CASE WHEN `+mismoOriginal+` THEN media_assets.failure_reason ELSE NULL END,
			processing_started_at = CASE WHEN `+mismoOriginal+` THEN media_assets.processing_started_at ELSE NULL END,
			updated_at = now()
		RETURNING id, status`,
		a.ID, a.ResourceID, a.OriginalObjectKey, a.MimeType, a.SizeBytes, a.ChecksumSHA256, a.Status,
	).Scan(&a.ID, &a.Status)
}

func (r *MediaRepo) GetByID(ctx context.Context, id uuid.UUID) (*MediaAsset, error) {
	var a MediaAsset
	err := r.pool.QueryRow(ctx, `
		SELECT id, resource_id, original_object_key, coalesce(mime_type,''), coalesce(size_bytes,0),
			coalesce(checksum_sha256,''), status, coalesce(hls_master_key,''), coalesce(failure_reason,''),
			created_at, updated_at
		FROM media_assets WHERE id=$1`, id).
		Scan(&a.ID, &a.ResourceID, &a.OriginalObjectKey, &a.MimeType, &a.SizeBytes, &a.ChecksumSHA256,
			&a.Status, &a.HLSMasterKey, &a.FailureReason, &a.CreatedAt, &a.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return &a, err
}

// LeaseProcesamiento es lo que dura el arrendamiento antes de que otro worker
// pueda reclamar un trabajo cuyo dueño no dio señales. Debe superar con
// holgura lo que tarda la transcodificación más larga que se espera.
const LeaseProcesamiento = 30 * time.Minute

// Reclamar intenta tomar el trabajo de transcodificación de forma exclusiva.
//
// Devuelve false, sin error, cuando el activo ya está listo o cuando otro
// worker lo está procesando con el arrendamiento vigente: en ambos casos este
// intento debe descartarse en silencio, que es lo que hace que una entrega
// duplicada no genere salidas repetidas.
//
// La condición vive en el propio UPDATE, así que dos entregas simultáneas se
// resuelven en la base y no queda ventana entre comprobar y actuar.
func (r *MediaRepo) Reclamar(ctx context.Context, id uuid.UUID, ahora time.Time) (bool, error) {
	tag, err := r.pool.Exec(ctx, `
		UPDATE media_assets
		   SET status = 'processing', processing_started_at = $2, updated_at = now()
		 WHERE id = $1
		   AND status <> 'ready'
		   AND (status <> 'processing'
		        OR processing_started_at IS NULL
		        OR processing_started_at < $3)`,
		id, ahora, ahora.Add(-LeaseProcesamiento))
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() == 1, nil
}

// esperaMinimaDeArrendamiento evita reprogramar en el mismo instante cuando el
// arrendamiento acaba de vencer o el activo cambio de estado entre las dos
// consultas.
const esperaMinimaDeArrendamiento = time.Second

// EsperaDeArrendamiento se consulta cuando Reclamar devuelve false: dice si el
// activo ya esta listo, y si no, cuanto falta para poder volver a reclamarlo.
//
// lo que no este listo no se puede descartar. si el dueño del arrendamiento
// murio sin sigterm, esta entrega es la unica que queda del trabajo, y darla
// por terminada dejaria el recurso en 'processing' para siempre
func (r *MediaRepo) EsperaDeArrendamiento(ctx context.Context, id uuid.UUID, ahora time.Time) (espera time.Duration, listo bool, err error) {
	var estado string
	var inicio *time.Time
	if err := r.pool.QueryRow(ctx,
		`SELECT status, processing_started_at FROM media_assets WHERE id=$1`, id,
	).Scan(&estado, &inicio); err != nil {
		return 0, false, err
	}
	if estado == "ready" {
		return 0, true, nil
	}
	if inicio == nil {
		return esperaMinimaDeArrendamiento, false, nil
	}
	// un segundo de mas porque Reclamar exige que el arrendamiento ya haya
	// vencido, no que venza justo ahora
	espera = inicio.Add(LeaseProcesamiento).Sub(ahora) + time.Second
	return max(espera, esperaMinimaDeArrendamiento), false, nil
}

// Liberar devuelve a la cola un activo cuyo worker se esta apagando.
//
// sin esto, cuando asynq reprograma el trabajo, el siguiente worker encuentra
// el activo en 'processing' con el arrendamiento vigente, cree que es una
// entrega duplicada y lo descarta, y el video se queda pegado. no se marca
// como fallido porque no fallo: el original esta bien y solo falta procesarlo.
//
// solo cambia activos en 'processing', asi un activo que ya quedo listo no
// se devuelve aunque el retiro llegue tarde.
func (r *MediaRepo) Liberar(ctx context.Context, id uuid.UUID) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE media_assets
		   SET status='queued', processing_started_at=NULL, updated_at=now()
		 WHERE id=$1 AND status='processing'`, id)
	return err
}

func (r *MediaRepo) MarkReady(ctx context.Context, id uuid.UUID, hlsMasterKey string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE media_assets
		   SET status='ready', hls_master_key=$2, processing_started_at=NULL, updated_at=now()
		 WHERE id=$1`, id, hlsMasterKey)
	return err
}

// MarcarPDFListo registra la vista previa de una presentacion.
//
// Escribe en derived_pdf_key y no en hls_master_key: son derivados distintos y
// mezclarlos obligaria a adivinar cual es cual al entregarlos.
func (r *MediaRepo) MarcarPDFListo(ctx context.Context, id uuid.UUID, clavePDF string) error {
	_, err := r.pool.Exec(ctx, `
		UPDATE media_assets
		   SET status='ready', derived_pdf_key=$2, processing_started_at=NULL, updated_at=now()
		 WHERE id=$1`, id, clavePDF)
	return err
}

func (r *MediaRepo) MarkFailed(ctx context.Context, id uuid.UUID, reason string) error {
	// Se libera el arrendamiento para que el reintento de asynq pueda
	// reclamarlo de inmediato, sin esperar a que venza.
	_, err := r.pool.Exec(ctx, `
		UPDATE media_assets
		   SET status='failed', failure_reason=$2, processing_started_at=NULL, updated_at=now()
		 WHERE id=$1`, id, reason)
	return err
}
