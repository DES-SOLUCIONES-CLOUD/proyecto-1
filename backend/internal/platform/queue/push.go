package queue

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/hibiken/asynq"
)

// RutaPush es donde la suscripción push de Pub/Sub entrega los mensajes al
// servicio de workers.
const RutaPush = "/pubsub/push"

// Acciones de los registros del recorrido de una tarea por Pub/Sub. Son
// valores estables para poder filtrarlos en Cloud Logging:
//
//	jsonPayload.accion="queue.task_received" OR jsonPayload.accion="queue.task_acked"
const (
	AccionRecibida   = "queue.task_received"
	AccionConfirmada = "queue.task_acked"
	AccionNack       = "queue.task_nacked"
)

// sobrePush es el cuerpo que envía una suscripción push de Pub/Sub.
type sobrePush struct {
	Message struct {
		Data        string            `json:"data"`
		Attributes  map[string]string `json:"attributes"`
		MessageID   string            `json:"messageId"`
		PublishTime string            `json:"publishTime"`
	} `json:"message"`
	Subscription    string `json:"subscription"`
	DeliveryAttempt int    `json:"deliveryAttempt"`
}

// entregaPush es lo que el manejador deja en el contexto para que los
// registros del trabajo lleven el mensaje y el intento (AtributosDeLaTarea).
type entregaPush struct {
	MessageID string
	Intento   int
	Maximo    int
}

type claveEntrega struct{}

func conEntrega(ctx context.Context, e entregaPush) context.Context {
	return context.WithValue(ctx, claveEntrega{}, e)
}

func entregaDe(ctx context.Context) (entregaPush, bool) {
	e, ok := ctx.Value(claveEntrega{}).(entregaPush)
	return e, ok
}

// ManejadorPush recibe las entregas de la suscripción push y las pasa a los
// mismos manejadores que usaba asynq (media y documentos), sin cambiarlos.
//
// La respuesta HTTP es la confirmación:
//
//   - 204 = ack. Se responde solo DESPUÉS de que el manejador terminó y
//     persistió el estado del activo y del recurso (MarkReady o MarkFailed).
//   - 5xx = nack. Pub/Sub reentrega con la retry_policy de la suscripción y,
//     tras max_delivery_attempts, manda el mensaje al topic de dead-letter.
//
// La autenticación no está aquí: el servicio de workers no admite
// invocaciones sin identidad (Cloud Run valida el token OIDC que adjunta la
// suscripción) y solo la cuenta de la suscripción tiene roles/run.invoker.
type ManejadorPush struct {
	Manejador asynq.Handler
	Log       *slog.Logger
	// MaxEntregas es el max_delivery_attempts de la suscripción.
	MaxEntregas int
}

func (m *ManejadorPush) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		w.Header().Set("Allow", http.MethodPost)
		http.Error(w, "método no permitido", http.StatusMethodNotAllowed)
		return
	}
	log := m.Log
	if log == nil {
		log = slog.Default()
	}

	var sobre sobrePush
	if err := json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&sobre); err != nil {
		// Un cuerpo ilegible no se arregla reintentando: se confirma para
		// que no circule hasta la dead-letter, y queda en el registro.
		log.ErrorContext(r.Context(), "pubsub: entrega ilegible, se descarta", "accion", AccionAgotado, "error", err)
		w.WriteHeader(http.StatusNoContent)
		return
	}
	datos, err := base64.StdEncoding.DecodeString(sobre.Message.Data)
	tipo := sobre.Message.Attributes[AtributoTipo]
	if err != nil || tipo == "" {
		log.ErrorContext(r.Context(), "pubsub: mensaje sin tipo o con datos inválidos, se descarta",
			"accion", AccionAgotado, "message_id", sobre.Message.MessageID, "tipo", tipo, "error", err)
		w.WriteHeader(http.StatusNoContent)
		return
	}

	intento := max(sobre.DeliveryAttempt, 1)
	maximo := m.MaxEntregas
	if maximo <= 0 {
		maximo = 5
	}
	entrega := entregaPush{MessageID: sobre.Message.MessageID, Intento: intento, Maximo: maximo}
	ctx := conEntrega(r.Context(), entrega)
	clave := sobre.Message.Attributes[AtributoClave]

	log.InfoContext(ctx, "pubsub: tarea recibida",
		"accion", AccionRecibida, "tarea", tipo, "message_id", entrega.MessageID,
		"clave_idempotencia", clave, "intento", intento, "maximo", maximo,
		"publicada", sobre.Message.PublishTime)

	inicio := time.Now()
	err = m.Manejador.ProcessTask(ctx, asynq.NewTask(tipo, datos))
	duracion := time.Since(inicio).Milliseconds()

	if err == nil {
		log.InfoContext(ctx, "pubsub: tarea terminada y persistida, se confirma (ack)",
			"accion", AccionConfirmada, "tarea", tipo, "message_id", entrega.MessageID,
			"clave_idempotencia", clave, "intento", intento, "duracion_ms", duracion)
		w.WriteHeader(http.StatusNoContent)
		return
	}

	RegistrarIntentoFallido(ctx, log, IntentoFallido{
		Tarea: tipo, ID: entrega.MessageID, Cola: sobre.Subscription,
		Intento: intento, Maximo: maximo, Err: err,
	})

	if errors.Is(err, asynq.SkipRetry) || esTipoDesconocido(err) {
		// Error permanente: el manejador ya dejó el activo en 'failed'.
		// Reintentar el mismo mensaje no cambia nada, así que se confirma.
		log.InfoContext(ctx, "pubsub: error permanente persistido, se confirma (ack) sin reintento",
			"accion", AccionConfirmada, "tarea", tipo, "message_id", entrega.MessageID, "intento", intento)
		w.WriteHeader(http.StatusNoContent)
		return
	}

	log.InfoContext(ctx, "pubsub: no se confirma (nack), Pub/Sub reentregará",
		"accion", AccionNack, "tarea", tipo, "message_id", entrega.MessageID,
		"intento", intento, "duracion_ms", duracion)
	// 503 para retiro y arrendamiento (no son fallos de la tarea), 500 para
	// el resto. A Pub/Sub le basta con que no sea 2xx.
	estado := http.StatusInternalServerError
	var arrendado *Arrendado
	if errors.Is(err, ErrRetiro) || errors.As(err, &arrendado) {
		estado = http.StatusServiceUnavailable
	}
	http.Error(w, "tarea no completada", estado)
}

// esTipoDesconocido reconoce el error de asynq.ServeMux cuando no hay
// manejador para el tipo del mensaje.
func esTipoDesconocido(err error) bool {
	return err != nil && strings.HasPrefix(err.Error(), "handler not found for task")
}
