package redisclient

import (
	"context"
	"encoding/json"
	"log/slog"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

// Claves de las dos listas de actividad que lee el panel de operación.
//
// viven en redis porque es lo unico que comparten todas las maquinas: asi el
// panel ve juntas las peticiones de las 3 replicas de la api y los trabajos
// de todos los workers, sin entrar por ssh a cada una
const (
	ClavePeticiones    = "mooc:actividad:peticiones"
	ClaveProcesamiento = "mooc:actividad:procesamiento"
	maximoDeRegistros  = 300
)

// Actividad guarda los últimos movimientos de la plataforma en listas cortas
// de Redis.
type Actividad struct {
	c *redis.Client
}

func NuevaActividad(c *redis.Client) *Actividad {
	return &Actividad{c: c}
}

// Anotar agrega un registro al principio de la lista y la recorta.
//
// se hace aparte (goroutine) y con poco tiempo de espera: si redis se demora,
// la peticion del usuario no tiene por que esperar a que se anote
func (a *Actividad) Anotar(clave string, registro any) {
	if a == nil || a.c == nil {
		return
	}
	datos, err := json.Marshal(registro)
	if err != nil {
		return
	}
	go func() {
		ctx, cancelar := context.WithTimeout(context.Background(), 500*time.Millisecond)
		defer cancelar()
		tubo := a.c.Pipeline()
		tubo.LPush(ctx, clave, datos)
		tubo.LTrim(ctx, clave, 0, maximoDeRegistros-1)
		_, _ = tubo.Exec(ctx)
	}()
}

// Ultimos devuelve los n registros más recientes de una lista.
func (a *Actividad) Ultimos(ctx context.Context, clave string, n int64) ([]json.RawMessage, error) {
	if a == nil || a.c == nil {
		return nil, nil
	}
	crudos, err := a.c.LRange(ctx, clave, 0, n-1).Result()
	if err != nil {
		return nil, err
	}
	salida := make([]json.RawMessage, 0, len(crudos))
	for _, c := range crudos {
		salida = append(salida, json.RawMessage(c))
	}
	return salida, nil
}

// ManejadorConActividad es un slog.Handler que, además de escribir el log
// normal, copia a Redis los mensajes del procesamiento de archivos.
//
// asi el panel de operacion muestra en vivo que worker tomo cada archivo,
// cuando termino y si fallo, sin cambiar el codigo de los procesadores
type ManejadorConActividad struct {
	slog.Handler
	actividad *Actividad
	instancia string
	atributos []slog.Attr
}

func NuevoManejadorConActividad(base slog.Handler, a *Actividad, instancia string) *ManejadorConActividad {
	return &ManejadorConActividad{Handler: base, actividad: a, instancia: instancia}
}

func (m *ManejadorConActividad) Handle(ctx context.Context, r slog.Record) error {
	//solo interesan los mensajes de los procesadores de video, audio y documentos
	if strings.HasPrefix(r.Message, "media:") || strings.HasPrefix(r.Message, "documentos:") {
		registro := map[string]any{
			"hora":      r.Time.UTC().Format(time.RFC3339),
			"worker":    m.instancia,
			"mensaje":   r.Message,
			"nivel":     r.Level.String(),
			"atributos": map[string]any{},
		}
		extra := registro["atributos"].(map[string]any)
		for _, a := range m.atributos {
			extra[a.Key] = valor(a)
		}
		r.Attrs(func(a slog.Attr) bool {
			extra[a.Key] = valor(a)
			return true
		})
		m.actividad.Anotar(ClaveProcesamiento, registro)
	}
	return m.Handler.Handle(ctx, r)
}

func (m *ManejadorConActividad) WithAttrs(attrs []slog.Attr) slog.Handler {
	copia := *m
	copia.Handler = m.Handler.WithAttrs(attrs)
	copia.atributos = append(append([]slog.Attr{}, m.atributos...), attrs...)
	return &copia
}

func (m *ManejadorConActividad) WithGroup(nombre string) slog.Handler {
	copia := *m
	copia.Handler = m.Handler.WithGroup(nombre)
	return &copia
}

// los errores no se convierten bien a json, se guardan como texto
func valor(a slog.Attr) any {
	v := a.Value.Resolve().Any()
	if e, ok := v.(error); ok {
		return e.Error()
	}
	return v
}
