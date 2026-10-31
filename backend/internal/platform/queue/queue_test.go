package queue

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/hibiken/asynq"
)

// registroEnMemoria captura las líneas emitidas por el manejador.
type registroEnMemoria struct{ b strings.Builder }

func (r *registroEnMemoria) logger() *slog.Logger {
	return slog.New(slog.NewTextHandler(&r.b, &slog.HandlerOptions{Level: slog.LevelDebug}))
}

func TestSeAlertaSoloCuandoElTrabajoAgotaSusReintentos(t *testing.T) {
	// El enunciado pide que la alerta se emita al agotar los reintentos, no en
	// cada fallo: alertar en los intermedios ahogaría la señal que importa.
	casos := []struct {
		nombre  string
		intento int
		maximo  int
		alerta  bool
	}{
		{"primer fallo", 0, 3, false},
		{"penúltimo fallo", 2, 3, false},
		{"último fallo", 3, 3, true},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			var reg registroEnMemoria
			RegistrarIntentoFallido(context.Background(), reg.logger(), IntentoFallido{
				Tarea: TaskProcessMedia, ID: "tarea-1", Cola: "default",
				Intento: c.intento, Maximo: c.maximo, Err: errors.New("ffmpeg reventó"),
			})

			salida := reg.b.String()
			alerto := strings.Contains(salida, AccionAgotado)
			if alerto != c.alerta {
				t.Errorf("alerta=%v, se esperaba %v. Salida:\n%s", alerto, c.alerta, salida)
			}
			nivel := "level=WARN"
			if c.alerta {
				nivel = "level=ERROR"
			}
			if !strings.Contains(salida, nivel) {
				t.Errorf("se esperaba %s en la salida:\n%s", nivel, salida)
			}
			// La causa siempre debe quedar registrada, alerte o no.
			if !strings.Contains(salida, "ffmpeg") {
				t.Errorf("el error original debería registrarse:\n%s", salida)
			}
		})
	}
}

func TestElManejadorSeMontaSobreAsynqSinPanic(t *testing.T) {
	var reg registroEnMemoria
	manejador := NuevoManejadorDeErrores(reg.logger())
	// Un contexto sin metadatos de tarea no debe provocar un panic dentro del
	// worker: registrar un fallo nunca puede ser peor que el fallo mismo. Sin
	// metadatos, intento y máximo valen cero, así que cuenta como agotado.
	manejador.HandleError(context.Background(), asynq.NewTask(TaskProcessMedia, nil), errors.New("boom"))
	if !strings.Contains(reg.b.String(), AccionAgotado) {
		t.Errorf("debería haberse registrado la alerta:\n%s", reg.b.String())
	}
}

func TestReintentosMaximosSegunLaEspecificacion(t *testing.T) {
	if MaxRetry != 3 {
		t.Errorf("el enunciado fija tres reintentos antes de la DLQ, hay %d", MaxRetry)
	}
}

func TestUnErrorPermanenteSeDescartaSinReintento(t *testing.T) {
	var reg registroEnMemoria
	RegistrarIntentoFallido(context.Background(), reg.logger(), IntentoFallido{
		Tarea: TaskProcessMedia, ID: "tarea-1", Cola: "default",
		Intento: 0, Maximo: 3,
		Err: fmt.Errorf("%w: %w", errors.New("el original no contiene una pista reproducible"), asynq.SkipRetry),
	})
	salida := reg.b.String()
	if !strings.Contains(salida, AccionAgotado) {
		t.Errorf("un error permanente debería alertar, no reintentar:\n%s", salida)
	}
	if strings.Contains(salida, "se reintentará con backoff") {
		t.Errorf("no debería anunciarse un reintento:\n%s", salida)
	}
}

func TestUnRetiroVuelveALaColaSinConsumirReintento(t *testing.T) {
	// un worker que se apaga no hace fallar el trabajo. si contara como fallo,
	// tres scale-down seguidos mandarian a la dlq un video que estaba bien
	err := fmt.Errorf("%w: %w", ErrRetiro, errors.New("ffmpeg: signal: killed"))
	if EsFallo(err) {
		t.Error("un retiro no debería contar como fallo")
	}
	if d := EsperaAntesDeReintentar(0, err, asynq.NewTask(TaskProcessMedia, nil)); d != 0 {
		t.Errorf("un retiro debería volver a la cola sin backoff, espera %v", d)
	}
	if !EsFallo(errors.New("ffmpeg reventó")) {
		t.Error("un error normal sí debería contar como fallo")
	}
}

func TestUnRetiroSeRegistraSinAlertar(t *testing.T) {
	var reg registroEnMemoria
	RegistrarIntentoFallido(context.Background(), reg.logger(), IntentoFallido{
		Tarea: TaskProcessMedia, ID: "tarea-1", Cola: "default",
		Intento: 2, Maximo: 3,
		Err: fmt.Errorf("%w: %w", ErrRetiro, context.Canceled),
	})
	salida := reg.b.String()
	if strings.Contains(salida, AccionAgotado) {
		t.Errorf("un retiro no debería mandar el trabajo a la DLQ:\n%s", salida)
	}
	if !strings.Contains(salida, AccionRetiro) || !strings.Contains(salida, "level=WARN") {
		t.Errorf("se esperaba el aviso de retiro:\n%s", salida)
	}
}

func TestUnRetiroEnElUltimoIntentoAlerta(t *testing.T) {
	var reg registroEnMemoria
	// asynq compara el contador antes de consultar IsFailure: este trabajo se
	// archiva aunque no haya fallado, y el registro tiene que decirlo
	RegistrarIntentoFallido(context.Background(), reg.logger(), IntentoFallido{
		Tarea: TaskProcessMedia, ID: "tarea-1", Cola: "default",
		Intento: 3, Maximo: 3,
		Err: fmt.Errorf("%w: %w", ErrRetiro, context.Canceled),
	})
	if salida := reg.b.String(); !strings.Contains(salida, AccionAgotado) {
		t.Errorf("debería alertar, el trabajo pasa a la DLQ:\n%s", salida)
	}
}

func TestUnActivoArrendadoSeAplazaSinConsumirReintento(t *testing.T) {
	espera := 7 * time.Minute
	err := &Arrendado{Espera: espera}
	if EsFallo(err) {
		t.Error("una entrega aplazada no debería contar como fallo")
	}
	if d := EsperaAntesDeReintentar(0, err, asynq.NewTask(TaskProcessMedia, nil)); d != espera {
		t.Errorf("debería esperar lo que falta del arrendamiento, espera %v", d)
	}

	// un retiro no le quita el aplazamiento: el activo sigue siendo de otro
	envuelto := fmt.Errorf("%w: %w", ErrRetiro, err)
	if d := EsperaAntesDeReintentar(0, envuelto, asynq.NewTask(TaskProcessMedia, nil)); d != espera {
		t.Errorf("envuelto en un retiro debería seguir esperando, espera %v", d)
	}
}

func TestUnAplazamientoSeRegistraSinAlertar(t *testing.T) {
	var reg registroEnMemoria
	RegistrarIntentoFallido(context.Background(), reg.logger(), IntentoFallido{
		Tarea: TaskProcessMedia, ID: "tarea-1", Cola: "default",
		Intento: 1, Maximo: 3,
		Err: &Arrendado{Espera: time.Minute},
	})
	salida := reg.b.String()
	if strings.Contains(salida, AccionAgotado) || !strings.Contains(salida, AccionArrendado) {
		t.Errorf("se esperaba el aviso de aplazamiento, sin alerta:\n%s", salida)
	}
}

func TestRetirableCortaElTrabajoYMarcaElError(t *testing.T) {
	retiro, retirar := context.WithCancel(context.Background())
	empezo := make(chan struct{})
	var visto bool

	manejador := Retirable(retiro)(asynq.HandlerFunc(func(ctx context.Context, _ *asynq.Task) error {
		close(empezo)
		<-ctx.Done() // lo mismo que haria exec.CommandContext con ffmpeg
		visto = Retirado(ctx)
		return ctx.Err()
	}))

	resultado := make(chan error, 1)
	go func() { resultado <- manejador.ProcessTask(context.Background(), asynq.NewTask(TaskProcessMedia, nil)) }()
	<-empezo
	retirar()
	err := <-resultado

	if !visto {
		t.Error("el manejador debería ver Retirado(ctx) para liberar el activo")
	}
	if !errors.Is(err, ErrRetiro) {
		t.Errorf("el error debería salir envuelto en ErrRetiro, salió %v", err)
	}
}

func TestRetirableNoTocaUnTrabajoNormal(t *testing.T) {
	retiro, retirar := context.WithCancel(context.Background())
	defer retirar()
	falla := errors.New("ffmpeg reventó")

	err := Retirable(retiro)(asynq.HandlerFunc(func(ctx context.Context, _ *asynq.Task) error {
		if Retirado(ctx) {
			t.Error("sin retiro el contexto no debería estar marcado")
		}
		return falla
	})).ProcessTask(context.Background(), asynq.NewTask(TaskProcessMedia, nil))

	if !errors.Is(err, falla) || errors.Is(err, ErrRetiro) {
		t.Errorf("el error debería pasar intacto, salió %v", err)
	}
}

func TestElPlazoDeRetiroCabeEnElDeDocker(t *testing.T) {
	// docker stop mata el proceso a los 10 s, si asynq esperara mas el worker
	// moriria sin liberar el activo
	if PlazoDeRetiro >= 10*time.Second {
		t.Errorf("el plazo de retiro (%v) debe quedar por debajo de los 10 s de docker stop", PlazoDeRetiro)
	}
}
