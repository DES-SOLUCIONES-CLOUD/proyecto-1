package httpserver

import "net/http"

func (h *handlers) registerHealth(mux *http.ServeMux) {
	salud := func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	}
	mux.HandleFunc("GET /api/v1/health", salud)
	// El health check del balanceador de GCP y el autohealing de los MIG
	// consultan esta ruta directamente en el puerto 8080 de cada instancia.
	// El balanceador no la expone: solo enruta /api/ a la API.
	mux.HandleFunc("GET /healthz", salud)
}
