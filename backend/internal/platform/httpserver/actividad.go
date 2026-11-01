package httpserver

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/domain/user"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/redisclient"
)

// quienPidio guarda el usuario de la peticion para que el registro de
// actividad lo pueda leer al final.
//
// el usuario se conoce adentro (en RequireAuth), pero la actividad se anota
// afuera, al terminar; por eso se deja este "buzon" en el contexto
type quienPidio struct {
	u *user.User
}

type ctxKeyQuienPidio struct{}

func anotarUsuario(ctx context.Context, u *user.User) {
	if q, ok := ctx.Value(ctxKeyQuienPidio{}).(*quienPidio); ok {
		q.u = u
	}
}

// peticionRegistrada es lo que se guarda de cada petición para el panel.
type peticionRegistrada struct {
	Hora      string `json:"hora"`
	Metodo    string `json:"metodo"`
	Ruta      string `json:"ruta"`
	Estado    int    `json:"estado"`
	Ms        int64  `json:"ms"`
	Instancia string `json:"instancia"`
	Usuario   string `json:"usuario,omitempty"`
	Rol       string `json:"rol,omitempty"`
}

// rutas que no se anotan: los sondeos de salud (llegan cada pocos segundos)
// y el propio panel, que si no se veria a si mismo todo el tiempo
func sinAnotar(ruta string) bool {
	return ruta == "/healthz" || ruta == "/api/v1/health" || strings.HasPrefix(ruta, "/api/v1/admin/actividad")
}

// RegistrarActividad anota cada petición (quién, qué, cuánto tardó y qué
// réplica la atendió) en la lista compartida de Redis.
func RegistrarActividad(a *redisclient.Actividad) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if sinAnotar(r.URL.Path) {
				next.ServeHTTP(w, r)
				return
			}
			inicio := time.Now()
			quien := &quienPidio{}
			sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
			next.ServeHTTP(sw, r.WithContext(context.WithValue(r.Context(), ctxKeyQuienPidio{}, quien)))

			registro := peticionRegistrada{
				Hora:      inicio.UTC().Format(time.RFC3339),
				Metodo:    r.Method,
				Ruta:      r.URL.Path,
				Estado:    sw.status,
				Ms:        time.Since(inicio).Milliseconds(),
				Instancia: nombreDeInstancia(),
			}
			if quien.u != nil {
				registro.Usuario = quien.u.Email
				registro.Rol = string(quien.u.Role)
			}
			a.Anotar(redisclient.ClavePeticiones, registro)
		})
	}
}

// actividad devuelve lo último que pasó en la plataforma: peticiones a la
// API (de todas las réplicas) y trabajos de los workers.
func (h *handlers) actividad(w http.ResponseWriter, r *http.Request) {
	a := redisclient.NuevaActividad(h.deps.Redis)
	peticiones, err := a.Ultimos(r.Context(), redisclient.ClavePeticiones, 150)
	if err != nil {
		writeError(w, err)
		return
	}
	procesamiento, err := a.Ultimos(r.Context(), redisclient.ClaveProcesamiento, 80)
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"instancia":     nombreDeInstancia(),
		"version":       versionDesplegada(),
		"peticiones":    peticiones,
		"procesamiento": procesamiento,
	})
}
