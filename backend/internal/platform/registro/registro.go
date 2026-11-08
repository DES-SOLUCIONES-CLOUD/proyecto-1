// Package registro arma el manejador de slog que escriben la API y los
// workers: JSON por stdout con los nombres de campo que Cloud Logging
// reconoce ("severity" y "message"), para que cada línea llegue como entrada
// estructurada con su nivel y se pueda filtrar por jsonPayload.<campo>.
package registro

import (
	"io"
	"log/slog"
)

// NuevoManejadorJSON devuelve el manejador JSON con nivel Info.
func NuevoManejadorJSON(w io.Writer) slog.Handler {
	return slog.NewJSONHandler(w, &slog.HandlerOptions{
		Level:       slog.LevelInfo,
		ReplaceAttr: paraCloudLogging,
	})
}

func paraCloudLogging(grupos []string, a slog.Attr) slog.Attr {
	if len(grupos) > 0 {
		return a
	}
	switch a.Key {
	case slog.MessageKey:
		a.Key = "message"
	case slog.LevelKey:
		a.Key = "severity"
		if nivel, ok := a.Value.Any().(slog.Level); ok {
			a.Value = slog.StringValue(severidad(nivel))
		}
	}
	return a
}

func severidad(n slog.Level) string {
	switch {
	case n >= slog.LevelError:
		return "ERROR"
	case n >= slog.LevelWarn:
		return "WARNING"
	case n >= slog.LevelInfo:
		return "INFO"
	default:
		return "DEBUG"
	}
}
