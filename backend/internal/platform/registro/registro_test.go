package registro

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"testing"
)

func TestLasLineasUsanLosCamposDeCloudLogging(t *testing.T) {
	var b bytes.Buffer
	slog.New(NuevoManejadorJSON(&b)).Warn("hola", "accion", "x")
	var linea map[string]any
	if err := json.Unmarshal(b.Bytes(), &linea); err != nil {
		t.Fatal(err)
	}
	if linea["severity"] != "WARNING" || linea["message"] != "hola" || linea["accion"] != "x" {
		t.Fatalf("línea inesperada: %v", linea)
	}
}
