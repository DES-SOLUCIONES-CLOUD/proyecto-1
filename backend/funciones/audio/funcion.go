// Package audio es la Cloud Function (Cloud Run functions, 2ª generación) que
// transcodifica las pistas de audio a HLS. Entrega 5: es la tarea que salió
// del worker.
//
//	mooc-api --publica--> topic mooc-audio --Eventarc--> TranscodificarAudio
//	                                                       |-> Cloud Storage (hls/<recurso>/...)
//	                                                       '-> Cloud SQL (activo y recurso 'ready')
//
// El trabajo lo hace el mismo media.Processor.HandleProcessMedia que usaba el
// worker, sin cambios: mismo FFmpeg, mismas claves en el bucket, mismos
// estados en la base. Lo único propio de la función es cómo llega el mensaje
// (un CloudEvent de Pub/Sub) y cómo se traduce el resultado a ack o reintento.
//
// Reintentos sin efectos duplicados: Eventarc entrega al menos una vez y, con
// retry_policy = RETRY_POLICY_RETRY, devolver error es pedir otra entrega.
// HandleProcessMedia reclama el activo con un UPDATE condicional en Cloud SQL
// (arrendamiento): una entrega repetida de un activo ya listo se descarta, y
// una que llega mientras otra lo procesa se aplaza.
//
// En el despliegue este archivo queda en la raíz del código de la función
// (deploy/gcp/preparar-funcion.sh), que es donde el buildpack de Go la busca.
package audio

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"sync"
	"time"

	"github.com/GoogleCloudPlatform/functions-framework-go/functions"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/hibiken/asynq"

	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/config"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/media"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/postgres"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/queue"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/registro"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/storage"
)

// PuntoDeEntrada es el entry_point de la función en Terraform.
const PuntoDeEntrada = "TranscodificarAudio"

// Acciones de los registros, con el mismo vocabulario que el worker para
// filtrarlos juntos en Cloud Logging.
const (
	AccionRecibida   = queue.AccionRecibida
	AccionConfirmada = queue.AccionConfirmada
	AccionReintento  = queue.AccionNack
	AccionAgotado    = queue.AccionAgotado
)

func init() {
	functions.CloudEvent(PuntoDeEntrada, TranscodificarAudio)
}

// mensajePublicado es el data del CloudEvent
// google.cloud.pubsub.topic.v1.messagePublished. Data llega en base64 y
// encoding/json lo decodifica solo por ser []byte.
type mensajePublicado struct {
	Message struct {
		Data        []byte            `json:"data"`
		Attributes  map[string]string `json:"attributes"`
		MessageID   string            `json:"messageId"`
		PublishTime time.Time         `json:"publishTime"`
	} `json:"message"`
	Subscription string `json:"subscription"`
}

// Manejador es lo que la función necesita del procesador. Es una interfaz para
// poder probar la traducción a ack/reintento sin FFmpeg ni base de datos.
type Manejador interface {
	ProcessTask(ctx context.Context, t *asynq.Task) error
}

// Funcion procesa un CloudEvent. TranscodificarAudio la arma una vez por
// instancia con las dependencias reales.
type Funcion struct {
	Manejador Manejador
	Log       *slog.Logger
	// PlazoDeReintentos acota los reintentos: Eventarc no informa el número de
	// entrega, así que se mide la antigüedad del mensaje. Pasado este plazo, un
	// fallo transitorio se da por agotado (se confirma y queda registrado
	// como queue.task_dead_letter), igual que el worker al llegar a la DLQ.
	PlazoDeReintentos time.Duration
	Ahora             func() time.Time
}

var (
	unaVez      sync.Once
	funcion     *Funcion
	errDeInicio error
)

// TranscodificarAudio es el punto de entrada registrado en el Functions
// Framework.
func TranscodificarAudio(ctx context.Context, e event.Event) error {
	unaVez.Do(func() { funcion, errDeInicio = nuevaFuncion(context.Background()) })
	if errDeInicio != nil {
		// Sin base o sin almacén no se puede hacer nada; el error hace que
		// Eventarc vuelva a entregar el mensaje más tarde.
		slog.Error("audio: la función no pudo iniciar", "error", errDeInicio)
		return errDeInicio
	}
	return funcion.Procesar(ctx, e)
}

// Procesar traduce el resultado del manejador a lo que entiende Eventarc:
// nil confirma el mensaje y un error pide reintento con backoff.
func (f *Funcion) Procesar(ctx context.Context, e event.Event) error {
	log := f.Log
	var msg mensajePublicado
	if err := e.DataAs(&msg); err != nil {
		// Un evento ilegible no se arregla reintentando.
		log.ErrorContext(ctx, "audio: evento ilegible, se descarta", "accion", AccionAgotado, "evento", e.ID(), "error", err)
		return nil
	}
	tipo := msg.Message.Attributes[queue.AtributoTipo]
	clave := msg.Message.Attributes[queue.AtributoClave]
	if tipo != queue.TaskProcessAudio {
		log.ErrorContext(ctx, "audio: mensaje de otro tipo en el topic de audio, se descarta",
			"accion", AccionAgotado, "message_id", msg.Message.MessageID, "tipo", tipo)
		return nil
	}

	ctx = queue.ConMensajePubSub(ctx, msg.Message.MessageID)
	antiguedad := f.ahora().Sub(msg.Message.PublishTime)
	log.InfoContext(ctx, "audio: tarea recibida desde Pub/Sub",
		"accion", AccionRecibida, "tarea", tipo, "message_id", msg.Message.MessageID,
		"clave_idempotencia", clave, "publicada", msg.Message.PublishTime,
		"antiguedad_ms", antiguedad.Milliseconds())

	inicio := time.Now()
	err := f.Manejador.ProcessTask(ctx, asynq.NewTask(tipo, msg.Message.Data))
	atributos := []any{"tarea", tipo, "message_id", msg.Message.MessageID,
		"clave_idempotencia", clave, "duracion_ms", time.Since(inicio).Milliseconds()}

	switch {
	case err == nil:
		log.InfoContext(ctx, "audio: tarea terminada y persistida, se confirma (ack)",
			append([]any{"accion", AccionConfirmada}, atributos...)...)
		return nil
	case errors.Is(err, asynq.SkipRetry):
		// El manejador ya dejó el activo en 'failed': reintentar el mismo
		// original no cambia nada.
		log.ErrorContext(ctx, "audio: error permanente persistido, se confirma sin reintento",
			append([]any{"accion", AccionAgotado, "error", err}, atributos...)...)
		return nil
	case f.PlazoDeReintentos > 0 && antiguedad > f.PlazoDeReintentos:
		log.ErrorContext(ctx, "audio: tarea agotada, se confirma y no se reintenta",
			append([]any{"accion", AccionAgotado, "error", err, "plazo", f.PlazoDeReintentos}, atributos...)...)
		return nil
	}

	var arrendado *queue.Arrendado
	if errors.As(err, &arrendado) {
		log.InfoContext(ctx, "audio: activo arrendado por otra entrega, se reintentará",
			append([]any{"accion", queue.AccionArrendado, "espera", arrendado.Espera}, atributos...)...)
	} else {
		log.WarnContext(ctx, "audio: tarea fallida, Eventarc la reentregará",
			append([]any{"accion", AccionReintento, "error", err}, atributos...)...)
	}
	return err
}

func (f *Funcion) ahora() time.Time {
	if f.Ahora != nil {
		return f.Ahora()
	}
	return time.Now()
}

// nuevaFuncion arma las dependencias con la misma configuración (variables de
// entorno) que el worker.
func nuevaFuncion(ctx context.Context) (*Funcion, error) {
	log := slog.New(registro.NuevoManejadorJSON(os.Stdout))
	slog.SetDefault(log)
	cfg := config.Load()

	if err := ubicarFFmpeg(log); err != nil {
		return nil, err
	}

	pool, err := postgres.ConnectConMaximo(ctx, cfg.DatabaseURL, cfg.DBMaxConns)
	if err != nil {
		return nil, fmt.Errorf("audio: postgres: %w", err)
	}
	almacen, err := storage.New(ctx, storage.Config{
		Endpoint: cfg.S3Endpoint, AccessKey: cfg.S3AccessKey, SecretKey: cfg.S3SecretKey,
		UseSSL: cfg.S3UseSSL, Bucket: cfg.S3Bucket, BucketHLS: cfg.S3BucketHLS, Region: cfg.S3Region,
		CrearBucket: false,
	})
	if err != nil {
		pool.Close()
		return nil, fmt.Errorf("audio: storage: %w", err)
	}

	procesador := &media.Processor{
		Storage: almacen,
		Assets:  postgres.NewMediaRepo(pool),
		Courses: postgres.NewCourseRepo(pool),
		Log:     log,
	}
	plazo, err := time.ParseDuration(getEnv("PLAZO_REINTENTOS", "1h"))
	if err != nil {
		return nil, fmt.Errorf("audio: PLAZO_REINTENTOS: %w", err)
	}
	log.Info("audio: función lista", "ffmpeg", media.BinarioFFmpeg, "plazo_reintentos", plazo)
	return &Funcion{
		Manejador:         asynq.HandlerFunc(procesador.HandleProcessMedia),
		Log:               log,
		PlazoDeReintentos: plazo,
	}, nil
}

// ubicarFFmpeg apunta media.BinarioFFmpeg y media.BinarioFFprobe a los
// ejecutables empaquetados con la función.
//
// La imagen base por defecto de Cloud Run functions para Go (google-24) no
// trae FFmpeg, así que preparar-funcion.sh mete una compilación estática en
// bin/. El buildpack de Go deja el código en /workspace (en algunas versiones
// dentro de serverless_function_source_code), así que se prueban las dos.
// Si el PATH ya tiene ffmpeg y ffprobe (imagen -full, local) se usan esos.
func ubicarFFmpeg(log *slog.Logger) error {
	if _, err := exec.LookPath("ffmpeg"); err == nil {
		if _, err := exec.LookPath("ffprobe"); err == nil {
			return nil
		}
	}
	dirs := []string{"bin", "serverless_function_source_code/bin",
		"/workspace/bin", "/workspace/serverless_function_source_code/bin"}
	if exe, err := os.Executable(); err == nil {
		dirs = append(dirs, filepath.Join(filepath.Dir(exe), "bin"))
	}
	for _, dir := range dirs {
		ffmpeg, ffprobe := filepath.Join(dir, "ffmpeg"), filepath.Join(dir, "ffprobe")
		if !existe(ffmpeg) || !existe(ffprobe) {
			continue
		}
		var err error
		if ffmpeg, err = ejecutable(ffmpeg); err != nil {
			return err
		}
		if ffprobe, err = ejecutable(ffprobe); err != nil {
			return err
		}
		media.BinarioFFmpeg, media.BinarioFFprobe = ffmpeg, ffprobe
		log.Info("audio: FFmpeg empaquetado", "ffmpeg", ffmpeg, "ffprobe", ffprobe)
		return nil
	}
	return fmt.Errorf("audio: no se encontró ffmpeg ni en el PATH ni en %v", dirs)
}

func existe(ruta string) bool {
	info, err := os.Stat(ruta)
	return err == nil && !info.IsDir()
}

// ejecutable devuelve una ruta que se puede ejecutar. El zip se arma con
// permisos 0755, pero si el bit se perdió y el código está en un sistema de
// archivos de solo lectura, se copia a /tmp.
func ejecutable(ruta string) (string, error) {
	abs, err := filepath.Abs(ruta)
	if err != nil {
		return "", err
	}
	if info, err := os.Stat(abs); err == nil && info.Mode()&0o111 != 0 {
		return abs, nil
	}
	if err := os.Chmod(abs, 0o755); err == nil { //nolint:gosec // es un ejecutable
		return abs, nil
	}
	destino := filepath.Join(os.TempDir(), "mooc-bin", filepath.Base(abs))
	if err := os.MkdirAll(filepath.Dir(destino), 0o700); err != nil {
		return "", err
	}
	origen, err := os.Open(abs)
	if err != nil {
		return "", err
	}
	defer origen.Close()
	copia, err := os.OpenFile(destino, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o700) //nolint:gosec // ruta fija bajo TempDir
	if err != nil {
		return "", err
	}
	if _, err := io.Copy(copia, origen); err != nil {
		copia.Close()
		return "", err
	}
	return destino, copia.Close()
}

func getEnv(clave, defecto string) string {
	if v := os.Getenv(clave); v != "" {
		return v
	}
	return defecto
}
