package postgres_test

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/documentos"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/media"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/postgres"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/queue"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/migrations"
)

// baseDePruebas abre la base y deja el esquema aplicado.
func baseDePruebas(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("falta TEST_DATABASE_URL: se omite la prueba de integración")
	}
	ctx := context.Background()
	pool, err := postgres.Connect(ctx, url)
	if err != nil {
		t.Fatalf("PostgreSQL: %v", err)
	}
	t.Cleanup(pool.Close)
	if err := postgres.Migrate(ctx, pool, migrations.FS); err != nil {
		t.Fatalf("migraciones: %v", err)
	}
	if _, err := pool.Exec(ctx, `TRUNCATE audit_logs, users, courses CASCADE`); err != nil {
		t.Fatalf("limpieza: %v", err)
	}
	return pool
}

// activoDePrueba crea la cadena mínima (usuario, curso, versión, módulo,
// unidad, recurso) y devuelve el activo multimedia asociado.
func activoDePrueba(t *testing.T, pool *pgxpool.Pool, estado string) uuid.UUID {
	t.Helper()
	ctx := context.Background()

	profesorID, cursoID, versionID := uuid.New(), uuid.New(), uuid.New()
	moduloID, unidadID, recursoID, activoID := uuid.New(), uuid.New(), uuid.New(), uuid.New()

	sentencias := []struct {
		sql  string
		args []any
	}{
		{`INSERT INTO users (id, email, password_hash, full_name, role, status)
		  VALUES ($1, $2, 'x', 'Profesor', 'teacher', 'active')`, []any{profesorID, profesorID.String() + "@example.com"}},
		{`INSERT INTO courses (id, teacher_id, slug) VALUES ($1, $2, $3)`,
			[]any{cursoID, profesorID, "curso-" + cursoID.String()[:8]}},
		{`INSERT INTO course_versions (id, course_id, version_number, status, title)
		  VALUES ($1, $2, 1, 'draft', 'Curso')`, []any{versionID, cursoID}},
		{`INSERT INTO modules (id, course_version_id, title, position) VALUES ($1, $2, 'M', 1)`,
			[]any{moduloID, versionID}},
		{`INSERT INTO units (id, module_id, title, position) VALUES ($1, $2, 'U', 1)`,
			[]any{unidadID, moduloID}},
		{`INSERT INTO resources (id, unit_id, type, title, position, visible)
		  VALUES ($1, $2, 'video', 'V', 1, true)`, []any{recursoID, unidadID}},
		{`INSERT INTO media_assets (id, resource_id, original_object_key, status)
		  VALUES ($1, $2, 'originales/v.mp4', $3)`, []any{activoID, recursoID, estado}},
	}
	for _, s := range sentencias {
		if _, err := pool.Exec(ctx, s.sql, s.args...); err != nil {
			t.Fatalf("preparando datos (%s): %v", s.sql[:40], err)
		}
	}
	return activoID
}

func TestReclamarSoloLoLograUnWorker(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx, ahora := context.Background(), time.Now().UTC()

	primero, err := repo.Reclamar(ctx, activoID, ahora)
	if err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if !primero {
		t.Fatal("el primer intento debería tomar el trabajo")
	}

	// Segunda entrega del mismo trabajo mientras el primero sigue corriendo.
	// Sin esto, ambos transcodificarían y subirían salidas duplicadas.
	segundo, err := repo.Reclamar(ctx, activoID, ahora.Add(time.Minute))
	if err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if segundo {
		t.Error("una entrega duplicada no debería tomar el trabajo en curso")
	}
}

func TestUnActivoListoNoSeVuelveAProcesar(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx := context.Background()

	if _, err := repo.Reclamar(ctx, activoID, time.Now().UTC()); err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if err := repo.MarkReady(ctx, activoID, "hls/x/master.m3u8"); err != nil {
		t.Fatalf("MarkReady: %v", err)
	}

	reclamado, err := repo.Reclamar(ctx, activoID, time.Now().UTC())
	if err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if reclamado {
		t.Error("un activo ya listo no debería reprocesarse")
	}

	// Y la salida anterior sigue en pie.
	activo, err := repo.GetByID(ctx, activoID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if activo.Status != "ready" || activo.HLSMasterKey != "hls/x/master.m3u8" {
		t.Errorf("el activo debería seguir listo: %+v", activo)
	}
}

func TestUnTrabajoAbandonadoSeRecuperaAlVencerElArrendamiento(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx := context.Background()

	inicio := time.Now().UTC()
	if _, err := repo.Reclamar(ctx, activoID, inicio); err != nil {
		t.Fatalf("Reclamar: %v", err)
	}

	// El worker que lo tomó muere sin marcar nada. Sin arrendamiento, el
	// recurso quedaría en 'processing' para siempre.
	reclamado, err := repo.Reclamar(ctx, activoID, inicio.Add(postgres.LeaseProcesamiento+time.Minute))
	if err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if !reclamado {
		t.Error("vencido el arrendamiento, otro worker debería poder recogerlo")
	}
}

func TestUnFalloLiberaElArrendamientoParaElReintento(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx, ahora := context.Background(), time.Now().UTC()

	if _, err := repo.Reclamar(ctx, activoID, ahora); err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if err := repo.MarkFailed(ctx, activoID, "ffmpeg reventó"); err != nil {
		t.Fatalf("MarkFailed: %v", err)
	}

	// El reintento de asynq llega enseguida y debe poder tomarlo, sin esperar
	// a que venza el arrendamiento del intento que ya falló.
	reclamado, err := repo.Reclamar(ctx, activoID, ahora.Add(time.Second))
	if err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if !reclamado {
		t.Error("tras un fallo, el reintento debería poder tomar el trabajo")
	}
}

func TestLaEsperaDeArrendamientoDiceCuandoReclamar(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx, inicio := context.Background(), time.Now().UTC()

	if _, err := repo.Reclamar(ctx, activoID, inicio); err != nil {
		t.Fatalf("Reclamar: %v", err)
	}

	consulta := inicio.Add(10 * time.Minute)
	espera, listo, err := repo.EsperaDeArrendamiento(ctx, activoID, consulta)
	if err != nil {
		t.Fatalf("EsperaDeArrendamiento: %v", err)
	}
	if listo {
		t.Fatal("un activo en processing no está listo")
	}
	// lo que devuelve tiene que alcanzar: a esa hora Reclamar debe funcionar
	reclamado, err := repo.Reclamar(ctx, activoID, consulta.Add(espera))
	if err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if !reclamado {
		t.Errorf("tras esperar %v el arrendamiento debería haber vencido", espera)
	}

	if err := repo.MarkReady(ctx, activoID, "hls/x/master.m3u8"); err != nil {
		t.Fatalf("MarkReady: %v", err)
	}
	if _, listo, err = repo.EsperaDeArrendamiento(ctx, activoID, consulta); err != nil || !listo {
		t.Errorf("un activo listo debería poder descartarse: listo=%v, err=%v", listo, err)
	}
}

// caidaAbrupta deja el activo como lo deja un worker que muere sin sigterm:
// en 'processing', con el arrendamiento vigente y sin nadie trabajando.
func caidaAbrupta(t *testing.T, repo *postgres.MediaRepo, activoID uuid.UUID) {
	t.Helper()
	if _, err := repo.Reclamar(context.Background(), activoID, time.Now().UTC()); err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
}

func TestLaEntregaTrasUnaCaidaAbruptaSeAplazaEnLugarDePerderse(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)

	casos := []struct {
		nombre  string
		tipo    string
		manejar func(context.Context, *asynq.Task) error
		cuerpo  func(activoID uuid.UUID) any
	}{
		{"video", queue.TaskProcessMedia, (&media.Processor{Assets: repo}).HandleProcessMedia,
			func(id uuid.UUID) any { return queue.MediaProcessPayload{MediaAssetID: id} }},
		{"presentacion", queue.TaskConvertDocument, (&documentos.Procesador{Assets: repo}).HandleConvertDocument,
			func(id uuid.UUID) any { return queue.DocumentConvertPayload{MediaAssetID: id} }},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			activoID := activoDePrueba(t, pool, "uploaded")
			caidaAbrupta(t, repo, activoID)

			cuerpo, err := json.Marshal(c.cuerpo(activoID))
			if err != nil {
				t.Fatalf("payload: %v", err)
			}
			err = c.manejar(context.Background(), asynq.NewTask(c.tipo, cuerpo))

			// nil le diria a asynq que termino, y nadie volveria a encolarlo
			var arrendado *queue.Arrendado
			if !errors.As(err, &arrendado) {
				t.Fatalf("la entrega debería aplazarse, devolvió %v", err)
			}
			if arrendado.Espera <= 0 || arrendado.Espera > postgres.LeaseProcesamiento+time.Second {
				t.Errorf("espera fuera de rango: %v", arrendado.Espera)
			}
			if queue.EsFallo(err) {
				t.Error("aplazar no debería gastar reintentos")
			}
		})
	}
}

func TestUnaEntregaDuplicadaDeUnActivoListoSeDescarta(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx := context.Background()

	if _, err := repo.Reclamar(ctx, activoID, time.Now().UTC()); err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if err := repo.MarkReady(ctx, activoID, "hls/x/master.m3u8"); err != nil {
		t.Fatalf("MarkReady: %v", err)
	}

	cuerpo, err := json.Marshal(queue.MediaProcessPayload{MediaAssetID: activoID})
	if err != nil {
		t.Fatalf("payload: %v", err)
	}
	procesador := &media.Processor{Assets: repo}
	if err := procesador.HandleProcessMedia(ctx, asynq.NewTask(queue.TaskProcessMedia, cuerpo)); err != nil {
		t.Errorf("debería descartarse sin error, devolvió %v", err)
	}
}

func TestUnRetiroDevuelveElActivoParaQueOtroWorkerLoRetome(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx, ahora := context.Background(), time.Now().UTC()

	if _, err := repo.Reclamar(ctx, activoID, ahora); err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	// el worker recibe sigterm a mitad de la transcodificacion
	if err := repo.Liberar(ctx, activoID); err != nil {
		t.Fatalf("Liberar: %v", err)
	}

	activo, err := repo.GetByID(ctx, activoID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if activo.Status != "queued" || activo.FailureReason != "" {
		t.Errorf("el activo debería volver a 'queued' sin marca de fallo: %+v", activo)
	}

	// la tarea reprogramada le llega a otro worker unos segundos despues,
	// mucho antes de que venza el arrendamiento del que se apago
	reclamado, err := repo.Reclamar(ctx, activoID, ahora.Add(5*time.Second))
	if err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if !reclamado {
		t.Error("tras el retiro, otro worker debería poder tomar el trabajo")
	}
}

func TestUnRetiroTardioNoDeshaceUnActivoListo(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx := context.Background()

	if _, err := repo.Reclamar(ctx, activoID, time.Now().UTC()); err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if err := repo.MarkReady(ctx, activoID, "hls/x/master.m3u8"); err != nil {
		t.Fatalf("MarkReady: %v", err)
	}
	if err := repo.Liberar(ctx, activoID); err != nil {
		t.Fatalf("Liberar: %v", err)
	}

	activo, err := repo.GetByID(ctx, activoID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if activo.Status != "ready" || activo.HLSMasterKey != "hls/x/master.m3u8" {
		t.Errorf("un activo listo no debería retroceder: %+v", activo)
	}
}

func TestElOriginalNuncaSeToca(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx := context.Background()

	antes, err := repo.GetByID(ctx, activoID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if _, err := repo.Reclamar(ctx, activoID, time.Now().UTC()); err != nil {
		t.Fatalf("Reclamar: %v", err)
	}
	if err := repo.MarkReady(ctx, activoID, "hls/x/master.m3u8"); err != nil {
		t.Fatalf("MarkReady: %v", err)
	}

	despues, err := repo.GetByID(ctx, activoID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	// El HLS es una salida derivada: se guarda aparte y el original queda
	// intacto, que es lo que exige la conservación del archivo fuente.
	if despues.OriginalObjectKey != antes.OriginalObjectKey {
		t.Errorf("la clave del original cambió: %q -> %q", antes.OriginalObjectKey, despues.OriginalObjectKey)
	}
	if despues.HLSMasterKey == despues.OriginalObjectKey {
		t.Error("el HLS no debería sobrescribir el original")
	}
}

func TestAsegurarReutilizaElActivoDelMismoRecurso(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx := context.Background()

	existente, err := repo.GetByID(ctx, activoID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}

	primero := &postgres.MediaAsset{
		ID: uuid.New(), ResourceID: existente.ResourceID,
		OriginalObjectKey: existente.OriginalObjectKey,
		ChecksumSHA256:    "abc", Status: "uploaded",
	}
	if err := repo.Asegurar(ctx, primero); err != nil {
		t.Fatalf("Asegurar: %v", err)
	}
	if primero.ID != activoID {
		t.Errorf("debería reutilizar %s, llegó %s", activoID, primero.ID)
	}
	if err := repo.MarkReady(ctx, primero.ID, "hls/x/master.m3u8"); err != nil {
		t.Fatalf("MarkReady: %v", err)
	}

	// La misma carga otra vez: el activo listo no se reinicia ni se duplica.
	segundo := &postgres.MediaAsset{
		ID: uuid.New(), ResourceID: existente.ResourceID,
		OriginalObjectKey: existente.OriginalObjectKey,
		ChecksumSHA256:    "abc", Status: "uploaded",
	}
	if err := repo.Asegurar(ctx, segundo); err != nil {
		t.Fatalf("segunda Asegurar: %v", err)
	}
	if segundo.ID != activoID {
		t.Errorf("la segunda confirmación creó otro activo: %s", segundo.ID)
	}
	if segundo.Status != "ready" {
		t.Errorf("el activo listo no debería reiniciarse, quedó %q", segundo.Status)
	}

	var n int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM media_assets WHERE resource_id=$1`, existente.ResourceID).Scan(&n); err != nil {
		t.Fatalf("contar: %v", err)
	}
	if n != 1 {
		t.Errorf("el recurso debería tener un solo activo, tiene %d", n)
	}
}

func TestAsegurarReabreSiElOriginalCambio(t *testing.T) {
	pool := baseDePruebas(t)
	repo := postgres.NewMediaRepo(pool)
	activoID := activoDePrueba(t, pool, "uploaded")
	ctx := context.Background()

	existente, err := repo.GetByID(ctx, activoID)
	if err != nil {
		t.Fatalf("GetByID: %v", err)
	}
	if err := repo.MarkReady(ctx, activoID, "hls/viejo/master.m3u8"); err != nil {
		t.Fatalf("MarkReady: %v", err)
	}

	nuevo := &postgres.MediaAsset{
		ID: uuid.New(), ResourceID: existente.ResourceID,
		OriginalObjectKey: existente.OriginalObjectKey,
		ChecksumSHA256:    "archivo-nuevo", Status: "uploaded",
	}
	if err := repo.Asegurar(ctx, nuevo); err != nil {
		t.Fatalf("Asegurar: %v", err)
	}
	if nuevo.ID != activoID {
		t.Errorf("un recambio debería reabrir el mismo activo, no crear otro: %s", nuevo.ID)
	}
	if nuevo.Status != "uploaded" {
		t.Errorf("el activo debería volver a uploaded, quedó %q", nuevo.Status)
	}
}
