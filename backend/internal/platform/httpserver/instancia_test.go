package httpserver

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

// cada respuesta dice que instancia la atendio, para poder ver el reparto del balanceador
func TestCadaRespuestaDiceQueInstanciaLaAtendio(t *testing.T) {
	h := ServidoPor(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusNoContent)
	}))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/health", nil))

	if rec.Header().Get("X-Servido-Por") == "" {
		t.Fatal("falta la cabecera X-Servido-Por")
	}
}

// la salud tambien devuelve la instancia y la version desplegada
func TestLaSaludDiceInstanciaYVersion(t *testing.T) {
	mux := http.NewServeMux()
	(&handlers{}).registerHealth(mux)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/api/v1/health", nil))

	var cuerpo map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &cuerpo); err != nil {
		t.Fatalf("respuesta no es json: %v", err)
	}
	if cuerpo["status"] != "ok" || cuerpo["instancia"] == "" || cuerpo["version"] == "" {
		t.Fatalf("salud incompleta: %v", cuerpo)
	}
}
