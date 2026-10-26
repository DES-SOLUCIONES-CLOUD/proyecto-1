package httpserver

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestIPDelClienteSegunLosProxiesDeConfianza(t *testing.T) {
	casos := []struct {
		nombre  string
		saltos  int
		reenvio string
		quiere  string
	}{
		{"sin cabecera, la conexión", 2, "", "192.0.2.10"},
		// Nginx local: sobrescribe la cabecera con un solo elemento.
		{"nginx, un elemento", 1, "198.51.100.7", "198.51.100.7"},
		// Balanceador de GCP: "<cliente>, <balanceador>".
		{"balanceador, cliente honesto", 2, "198.51.100.7, 34.120.0.1", "198.51.100.7"},
		// El cliente manda su propia cabecera para saltarse el límite de
		// login: el balanceador la conserva delante y añade la IP real.
		{"balanceador, cabecera inventada", 2, "203.0.113.99, 198.51.100.7, 34.120.0.1", "198.51.100.7"},
		{"balanceador, varias inventadas", 2, "1.1.1.1, 2.2.2.2, 198.51.100.7, 34.120.0.1", "198.51.100.7"},
		// Menos elementos de los esperados: no viene del balanceador.
		{"menos elementos que saltos", 2, "198.51.100.7", "192.0.2.10"},
		{"cero equivale a uno", 0, "198.51.100.7", "198.51.100.7"},
	}
	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			var vista string
			h := IPDelCliente(c.saltos)(http.HandlerFunc(func(_ http.ResponseWriter, r *http.Request) {
				vista = clientIP(r)
			}))
			req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
			req.RemoteAddr = "192.0.2.10:1234"
			if c.reenvio != "" {
				req.Header.Set("X-Forwarded-For", c.reenvio)
			}
			h.ServeHTTP(httptest.NewRecorder(), req)
			if vista != c.quiere {
				t.Errorf("X-Forwarded-For %q con %d saltos: IP %q, se esperaba %q", c.reenvio, c.saltos, vista, c.quiere)
			}
		})
	}
}
