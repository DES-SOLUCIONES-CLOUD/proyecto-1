// Package queue encapsula la cola asíncrona (asynq sobre Redis) usada para
// publicar y consumir trabajos con idempotencia, reintentos con backoff y
// dead-letter queue.
package queue

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/hibiken/asynq"
)

const (
	TaskProcessMedia    = "media:process"
	TaskConvertDocument = "document:convert"
	TaskIssueBadge      = "badge:issue"
)

// MaxRetry es el número de reintentos antes de que un trabajo se considere
// agotado y pase al conjunto de tareas muertas (dead-letter) de asynq.
const MaxRetry = 3

// NewClient crea el cliente usado por la API para encolar trabajos.
func NewClient(redisAddr string) *asynq.Client {
	return asynq.NewClient(asynq.RedisClientOpt{Addr: redisAddr})
}

// NewServer crea el servidor consumido por los workers, con colas separadas
// por prioridad, el número de reintentos exigido por la especificación y la
// alerta que debe emitirse cuando un trabajo se agota.
func NewServer(redisAddr string, concurrency int, log *slog.Logger) *asynq.Server {
	if log == nil {
		log = slog.Default()
	}
	return asynq.NewServer(
		asynq.RedisClientOpt{Addr: redisAddr},
		asynq.Config{
			Concurrency:     concurrency,
			ErrorHandler:    NuevoManejadorDeErrores(log),
			IsFailure:       EsFallo,
			RetryDelayFunc:  EsperaAntesDeReintentar,
			ShutdownTimeout: PlazoDeRetiro,
			Queues: map[string]int{
				"critical": 6,
				"default":  3,
				"low":      1,
			},
		},
	)
}

// PlazoDeRetiro es cuanto espera asynq a los trabajos activos al apagarse.
// tiene que ser menor que los 10 s que da docker stop antes de matar el
// proceso, si no el worker muere sin alcanzar a liberar el activo
const PlazoDeRetiro = 8 * time.Second

// ErrRetiro marca un trabajo que se corto porque el worker se esta apagando
// (scale-down del mig, docker stop, despliegue) y no porque haya fallado.
// por eso no debe gastar reintentos ni esperar el backoff: el trabajo esta
// bien y otro worker lo puede tomar de una vez
var ErrRetiro = errors.New("worker en retiro")

// Retirado dice si el contexto del trabajo se cancelo por un retiro.
func Retirado(ctx context.Context) bool {
	return errors.Is(context.Cause(ctx), ErrRetiro)
}

// Retirable es el middleware que avisa del retiro a los trabajos en curso.
//
// cuando se cancela retiro, cancela el contexto de cada trabajo con ErrRetiro
// como causa. ffmpeg y libreoffice corren con exec.CommandContext, asi que se
// detienen de inmediato. el manejador ve Retirado(ctx), libera el activo, y
// su error sale envuelto en ErrRetiro para que EsFallo lo reconozca.
//
// no se usa el BaseContext de asynq porque al cancelarlo asynq da el trabajo
// por terminado y lo reprograma antes de que el manejador libere el activo,
// y el siguiente worker lo encontraria todavia tomado y lo descartaria
func Retirable(retiro context.Context) asynq.MiddlewareFunc {
	return func(next asynq.Handler) asynq.Handler {
		return asynq.HandlerFunc(func(ctx context.Context, t *asynq.Task) error {
			ctx, cancelar := context.WithCancelCause(ctx)
			defer cancelar(nil)
			detener := context.AfterFunc(retiro, func() { cancelar(ErrRetiro) })
			defer detener()

			err := next.ProcessTask(ctx, t)
			if err != nil && Retirado(ctx) && !errors.Is(err, ErrRetiro) {
				return fmt.Errorf("%w: %w", ErrRetiro, err)
			}
			return err
		})
	}
}

// EsFallo es el IsFailure de asynq: un retiro vuelve a la cola sin contar
// como reintento.
func EsFallo(err error) bool {
	return !errors.Is(err, ErrRetiro)
}

// EsperaAntesDeReintentar devuelve un trabajo retirado a la cola de una vez
// y deja el backoff normal de asynq para los fallos de verdad.
func EsperaAntesDeReintentar(n int, err error, t *asynq.Task) time.Duration {
	if errors.Is(err, ErrRetiro) {
		return 0
	}
	return asynq.DefaultRetryDelayFunc(n, err, t)
}

// AtributosDeLaTarea son los datos que asynq guarda en el contexto del
// trabajo en curso: identificador, cola e intento.
//
// Van en todas las líneas del worker, no solo en las de error. Sin el
// identificador no se pueden hilar los registros de un mismo trabajo cuando
// hay cinco corriendo a la vez, y sin el intento no se distingue un trabajo
// que salió bien a la primera de uno que salió bien después de dos fallos y su
// backoff, que es justo lo que hay que poder demostrar.
//
// Devuelve la forma variádica que espera slog en lugar de una estructura: el
// uso es siempre pasarlo a un logger, y envolverlo solo añadiría un paso.
func AtributosDeLaTarea(ctx context.Context) []any {
	id, _ := asynq.GetTaskID(ctx)
	cola, _ := asynq.GetQueueName(ctx)
	intento, _ := asynq.GetRetryCount(ctx)
	return []any{"tarea_id", id, "cola", cola, "intento", intento}
}

// AccionAgotado es la acción que emite la alerta cuando un trabajo agota sus
// reintentos. Se registra con este nombre exacto para que la regla de alerta
// de observabilidad pueda engancharse a un valor estable y no a un texto libre.
const AccionAgotado = "queue.task_dead_letter"

// AccionRetiro aparece en el log cuando un trabajo vuelve a la cola porque su
// worker se apago. es la linea que se busca en la demo de retiro seguro.
const AccionRetiro = "queue.task_requeued_on_shutdown"

// NuevoManejadorDeErrores devuelve el asynq.ErrorHandler que registra cada
// intento fallido y distingue el último.
//
// El enunciado pide que, tras agotar los reintentos, el trabajo llegue a la
// dead-letter queue y emita una alerta. asynq archiva el trabajo por su
// cuenta; lo que falta es la señal, y este manejador la produce: los intentos
// intermedios quedan como aviso y el definitivo como error, que es lo que la
// regla de alerta debe vigilar.
func NuevoManejadorDeErrores(log *slog.Logger) asynq.ErrorHandler {
	return asynq.ErrorHandlerFunc(func(ctx context.Context, t *asynq.Task, err error) {
		intento, _ := asynq.GetRetryCount(ctx)
		maximo, _ := asynq.GetMaxRetry(ctx)
		id, _ := asynq.GetTaskID(ctx)
		cola, _ := asynq.GetQueueName(ctx)

		RegistrarIntentoFallido(ctx, log, IntentoFallido{
			Tarea: t.Type(), ID: id, Cola: cola,
			Intento: intento, Maximo: maximo, Err: err,
		})
	})
}

// IntentoFallido describe un intento de trabajo que terminó en error.
type IntentoFallido struct {
	Tarea   string
	ID      string
	Cola    string
	Intento int
	Maximo  int
	Err     error
}

// Agotado informa si este era el último intento y, por tanto, el trabajo pasa
// a la dead-letter queue.
func (f IntentoFallido) Agotado() bool {
	if errors.Is(f.Err, ErrRetiro) {
		return false
	}
	return f.Intento >= f.Maximo || errors.Is(f.Err, asynq.SkipRetry)
}

// RegistrarIntentoFallido emite la señal que corresponda.
//
// Se separa de la extracción del contexto de asynq para poder ejercitarla:
// lo que importa verificar es que la alerta se emita solo en el último
// intento, no en cada fallo, porque alertar en los intermedios ahogaría la
// señal que de verdad exige atención.
func RegistrarIntentoFallido(ctx context.Context, log *slog.Logger, f IntentoFallido) {
	atributos := []any{
		"tarea", f.Tarea, "id", f.ID, "cola", f.Cola,
		"intento", f.Intento, "maximo", f.Maximo, "error", f.Err,
	}
	if errors.Is(f.Err, ErrRetiro) {
		log.WarnContext(ctx, "worker en retiro: el trabajo vuelve a la cola sin consumir reintento",
			append([]any{"accion", AccionRetiro}, atributos...)...)
		return
	}
	if errors.Is(f.Err, asynq.SkipRetry) {
		log.ErrorContext(ctx, "trabajo descartado: no se reintentará",
			append([]any{"accion", AccionAgotado}, atributos...)...)
		return
	}
	if f.Agotado() {
		log.ErrorContext(ctx, "trabajo agotado: pasa a la dead-letter queue",
			append([]any{"accion", AccionAgotado}, atributos...)...)
		return
	}
	log.WarnContext(ctx, "trabajo fallido: se reintentará con backoff", atributos...)
}

// NewInspector permite consultar el estado de las colas y la dead-letter
// queue (usado por el endpoint de observabilidad/administración).
func NewInspector(redisAddr string) *asynq.Inspector {
	return asynq.NewInspector(asynq.RedisClientOpt{Addr: redisAddr})
}
