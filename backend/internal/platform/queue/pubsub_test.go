package queue

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/hibiken/asynq"
)

type tokenFijo string

func (t tokenFijo) Token(context.Context) (string, error) { return string(t), nil }

func TestElPublicadorEnviaTipoClaveYPayloadAPubSub(t *testing.T) {
	var recibido struct {
		Messages []mensajePubSub `json:"messages"`
	}
	var ruta, autorizacion string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ruta, autorizacion = r.URL.Path, r.Header.Get("Authorization")
		_ = json.NewDecoder(r.Body).Decode(&recibido)
		_, _ = io.WriteString(w, `{"messageIds":["42"]}`)
	}))
	defer srv.Close()

	p := &PublicadorPubSub{Proyecto: "p", Topic: "t", Endpoint: srv.URL, HTTP: srv.Client(), Tokens: tokenFijo("abc"),
		Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	err := p.Encolar(context.Background(), Trabajo{Tipo: TaskProcessMedia, ClaveDeIdempotencia: "activo-1", Payload: map[string]string{"k": "v"}})
	if err != nil {
		t.Fatal(err)
	}
	if ruta != "/v1/projects/p/topics/t:publish" || autorizacion != "Bearer abc" {
		t.Fatalf("ruta %q, autorización %q", ruta, autorizacion)
	}
	if len(recibido.Messages) != 1 {
		t.Fatalf("mensajes: %d", len(recibido.Messages))
	}
	m := recibido.Messages[0]
	datos, _ := base64.StdEncoding.DecodeString(m.Data)
	if m.Attributes[AtributoTipo] != TaskProcessMedia || m.Attributes[AtributoClave] != "activo-1" || string(datos) != `{"k":"v"}` {
		t.Fatalf("mensaje inesperado: %+v (%s)", m, datos)
	}
}

func TestElPublicadorReintentaErroresTransitorios(t *testing.T) {
	llamadas := 0
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		llamadas++
		if llamadas == 1 {
			http.Error(w, "ocupado", http.StatusServiceUnavailable)
			return
		}
		_, _ = io.WriteString(w, `{"messageIds":["1"]}`)
	}))
	defer srv.Close()
	p := &PublicadorPubSub{Proyecto: "p", Topic: "t", Endpoint: srv.URL, HTTP: srv.Client(), Tokens: sinToken{},
		Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	if err := p.Encolar(context.Background(), Trabajo{Tipo: "x", Payload: 1}); err != nil {
		t.Fatal(err)
	}
	if llamadas != 2 {
		t.Fatalf("llamadas: %d", llamadas)
	}
}

func entrega(t *testing.T, tipo string, intento int) *http.Request {
	t.Helper()
	cuerpo := fmt.Sprintf(`{"message":{"data":%q,"attributes":{"tipo":%q,"clave_idempotencia":"a1"},"messageId":"m-1"},"subscription":"projects/p/subscriptions/s","deliveryAttempt":%d}`,
		base64.StdEncoding.EncodeToString([]byte(`{}`)), tipo, intento)
	return httptest.NewRequest(http.MethodPost, RutaPush, strings.NewReader(cuerpo))
}

func manejadorQueDevuelve(err error) (*ManejadorPush, *bytes.Buffer) {
	var b bytes.Buffer
	mux := asynq.NewServeMux()
	mux.HandleFunc(TaskProcessMedia, func(ctx context.Context, _ *asynq.Task) error {
		if e, ok := entregaDe(ctx); !ok || e.MessageID != "m-1" {
			return errors.New("sin datos de la entrega en el contexto")
		}
		return err
	})
	return &ManejadorPush{Manejador: mux, Log: slog.New(slog.NewJSONHandler(&b, nil)), MaxEntregas: 5}, &b
}

func TestUnaTareaCompletadaSeConfirmaConDosCientos(t *testing.T) {
	m, registro := manejadorQueDevuelve(nil)
	w := httptest.NewRecorder()
	m.ServeHTTP(w, entrega(t, TaskProcessMedia, 1))
	if w.Code != http.StatusNoContent {
		t.Fatalf("estado %d", w.Code)
	}
	if !strings.Contains(registro.String(), AccionRecibida) || !strings.Contains(registro.String(), AccionConfirmada) {
		t.Fatalf("faltan registros del recorrido: %s", registro)
	}
}

func TestUnFalloTransitorioNoSeConfirma(t *testing.T) {
	m, _ := manejadorQueDevuelve(errors.New("bd caída"))
	w := httptest.NewRecorder()
	m.ServeHTTP(w, entrega(t, TaskProcessMedia, 1))
	if w.Code < 500 {
		t.Fatalf("un fallo transitorio debe ser nack, estado %d", w.Code)
	}
}

func TestUnActivoArrendadoNoSeConfirma(t *testing.T) {
	m, _ := manejadorQueDevuelve(&Arrendado{})
	w := httptest.NewRecorder()
	m.ServeHTTP(w, entrega(t, TaskProcessMedia, 2))
	if w.Code != http.StatusServiceUnavailable {
		t.Fatalf("estado %d", w.Code)
	}
}

func TestUnErrorPermanenteSeConfirmaSinReintento(t *testing.T) {
	m, _ := manejadorQueDevuelve(fmt.Errorf("ilegible: %w", asynq.SkipRetry))
	w := httptest.NewRecorder()
	m.ServeHTTP(w, entrega(t, TaskProcessMedia, 1))
	if w.Code != http.StatusNoContent {
		t.Fatalf("estado %d", w.Code)
	}
}

func TestElUltimoIntentoFallidoAlerta(t *testing.T) {
	m, registro := manejadorQueDevuelve(errors.New("bd caída"))
	m.ServeHTTP(httptest.NewRecorder(), entrega(t, TaskProcessMedia, 5))
	if !strings.Contains(registro.String(), AccionAgotado) {
		t.Fatalf("el último intento debe alertar: %s", registro)
	}
}

func TestUnTipoDesconocidoSeDescarta(t *testing.T) {
	m, _ := manejadorQueDevuelve(nil)
	w := httptest.NewRecorder()
	m.ServeHTTP(w, entrega(t, "otro:tipo", 1))
	if w.Code != http.StatusNoContent {
		t.Fatalf("estado %d", w.Code)
	}
}
