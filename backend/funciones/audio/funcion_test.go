package audio

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/hibiken/asynq"

	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/queue"
)

type manejadorFalso struct {
	err    error
	tareas []*asynq.Task
}

func (m *manejadorFalso) ProcessTask(_ context.Context, t *asynq.Task) error {
	m.tareas = append(m.tareas, t)
	return m.err
}

var publicado = time.Date(2026, 11, 17, 12, 0, 0, 0, time.UTC)

func evento(t *testing.T, tipo string) event.Event {
	t.Helper()
	e := event.New()
	e.SetID("evento-1")
	e.SetSource("//pubsub.googleapis.com/projects/p/topics/mooc-audio")
	e.SetType("google.cloud.pubsub.topic.v1.messagePublished")
	err := e.SetData(event.ApplicationJSON, map[string]any{
		"message": map[string]any{
			// base64 de {"k":"v"}
			"data":        "eyJrIjoidiJ9",
			"attributes":  map[string]string{queue.AtributoTipo: tipo, queue.AtributoClave: "activo-1"},
			"messageId":   "mensaje-1",
			"publishTime": publicado.Format(time.RFC3339Nano),
		},
		"subscription": "projects/p/subscriptions/eventarc-x",
	})
	if err != nil {
		t.Fatal(err)
	}
	return e
}

func nueva(m Manejador, minutosDespues int) *Funcion {
	return &Funcion{
		Manejador:         m,
		Log:               slog.New(slog.NewTextHandler(io.Discard, nil)),
		PlazoDeReintentos: time.Hour,
		Ahora:             func() time.Time { return publicado.Add(time.Duration(minutosDespues) * time.Minute) },
	}
}

func TestTareaCorrectaSeConfirmaConElMismoPayload(t *testing.T) {
	m := &manejadorFalso{}
	if err := nueva(m, 0).Procesar(context.Background(), evento(t, queue.TaskProcessAudio)); err != nil {
		t.Fatalf("debería confirmarse: %v", err)
	}
	if len(m.tareas) != 1 || m.tareas[0].Type() != queue.TaskProcessAudio || string(m.tareas[0].Payload()) != `{"k":"v"}` {
		t.Fatalf("el manejador debería recibir la tarea tal cual: %+v", m.tareas)
	}
}

func TestErrorTransitorioPideReintento(t *testing.T) {
	m := &manejadorFalso{err: errors.New("base caída")}
	if err := nueva(m, 1).Procesar(context.Background(), evento(t, queue.TaskProcessAudio)); err == nil {
		t.Fatal("un fallo transitorio debe devolver error para que Eventarc reentregue")
	}
}

func TestActivoArrendadoPideReintento(t *testing.T) {
	m := &manejadorFalso{err: &queue.Arrendado{Espera: time.Minute}}
	if err := nueva(m, 1).Procesar(context.Background(), evento(t, queue.TaskProcessAudio)); err == nil {
		t.Fatal("una entrega que encuentra el activo arrendado debe volver más tarde")
	}
}

func TestErrorPermanenteSeConfirma(t *testing.T) {
	m := &manejadorFalso{err: errors.Join(errors.New("sin pista"), asynq.SkipRetry)}
	if err := nueva(m, 1).Procesar(context.Background(), evento(t, queue.TaskProcessAudio)); err != nil {
		t.Fatalf("un original ilegible no se reintenta: %v", err)
	}
}

func TestPasadoElPlazoSeDaPorAgotada(t *testing.T) {
	m := &manejadorFalso{err: errors.New("base caída")}
	if err := nueva(m, 61).Procesar(context.Background(), evento(t, queue.TaskProcessAudio)); err != nil {
		t.Fatalf("pasado el plazo debe confirmarse para no reintentar sin fin: %v", err)
	}
}

func TestOtroTipoNoSeEjecuta(t *testing.T) {
	m := &manejadorFalso{}
	if err := nueva(m, 0).Procesar(context.Background(), evento(t, queue.TaskProcessMedia)); err != nil {
		t.Fatalf("se confirma y se descarta: %v", err)
	}
	if len(m.tareas) != 0 {
		t.Fatal("la función solo ejecuta la transcodificación de audio")
	}
}
