// Package instancia dice en que maquina corre el proceso y que version del
// codigo tiene. Lo usan la api y los workers para que el panel de operacion
// muestre quien atendio cada peticion y quien proceso cada archivo.
package instancia

import (
	"context"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

// Nombre devuelve el nombre de la maquina (en gcp, el de la vm).
func Nombre() string { return nombre() }

// nombre de la maquina que atiende la peticion, se calcula una sola vez
// en gcp se le pregunta al servidor de metadatos (asi sale mooc-api-xxxx y no el id del contenedor)
// fuera de gcp no hay metadatos y se usa el nombre del equipo
var nombre = sync.OnceValue(func() string {
	if n := os.Getenv("MOOC_INSTANCIA"); n != "" {
		return n
	}
	if n := nombreEnGCP(); n != "" {
		return n
	}
	n, _ := os.Hostname()
	return n
})

// pide el nombre de la vm al servidor de metadatos de google, con poco tiempo de espera
// para que en local (donde no existe) no demore el arranque
func nombreEnGCP() string {
	ctx, cancelar := context.WithTimeout(context.Background(), 500*time.Millisecond)
	defer cancelar()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet,
		"http://169.254.169.254/computeMetadata/v1/instance/name", nil)
	if err != nil {
		return ""
	}
	req.Header.Set("Metadata-Flavor", "Google")
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		return ""
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return ""
	}
	cuerpo, err := io.ReadAll(io.LimitReader(res.Body, 256))
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(cuerpo))
}

// version del codigo desplegado (el commit), la pone el dockerfile al construir la imagen
func Version() string {
	if v := os.Getenv("MOOC_VERSION"); v != "" {
		return v
	}
	return "dev"
}
