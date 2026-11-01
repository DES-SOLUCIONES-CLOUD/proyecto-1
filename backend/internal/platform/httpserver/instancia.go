package httpserver

import (
	"net/http"

	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/instancia"
)

func nombreDeInstancia() string { return instancia.Nombre() }

func versionDesplegada() string { return instancia.Version() }

// ServidoPor agrega a cada respuesta la cabecera X-Servido-Por con la
// instancia que la atendió.
//
// sirve para ver en el navegador (pestaña red) que el balanceador reparte
// las peticiones entre las replicas y que la sesion sigue igual en todas
func ServidoPor(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Servido-Por", nombreDeInstancia())
		next.ServeHTTP(w, r)
	})
}
