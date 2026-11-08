// Command worker consume los trabajos asíncronos (transcodificación y
// conversión de presentaciones) que publica la API.
//
// Tiene dos modos, con los mismos manejadores:
//
//   - QUEUE_BACKEND=asynq (por defecto): consume la cola de Redis, con
//     reintentos con backoff y dead-letter queue gestionados por asynq.
//   - QUEUE_BACKEND=pubsub (Cloud Run): servidor HTTP que recibe las entregas
//     de la suscripción push de Pub/Sub en /pubsub/push. El ack es la
//     respuesta 2xx, que se envía después de persistir el resultado.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/hibiken/asynq"

	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/config"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/documentos"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/instancia"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/media"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/postgres"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/queue"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/redisclient"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/registro"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/storage"
)

func main() {
	cfg := config.Load()
	base := registro.NuevoManejadorJSON(os.Stdout)
	log := slog.New(base)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	//los mensajes del procesamiento tambien se copian a redis para el panel de operacion
	//si redis no responde el worker sigue igual, solo que el panel no vera sus trabajos
	if rdb, err := redisclient.Connect(ctx, cfg.RedisAddr); err == nil {
		defer rdb.Close()
		log = slog.New(redisclient.NuevoManejadorConActividad(base, redisclient.NuevaActividad(rdb), instancia.Nombre()))
	} else {
		log.Warn("worker: sin redis para el panel de actividad", "error", err)
	}
	slog.SetDefault(log)
	log.Info("worker iniciado", "env", cfg.Env, "redis", cfg.RedisAddr, "instancia", instancia.Nombre(), "transporte", cfg.QueueBackend)

	pool, err := postgres.ConnectConMaximo(ctx, cfg.DatabaseURL, cfg.DBMaxConns)
	if err != nil {
		log.Error("worker: postgres", "error", err)
		os.Exit(1)
	}
	defer pool.Close()

	storageClient, err := storage.New(ctx, storage.Config{
		Endpoint: cfg.S3Endpoint, AccessKey: cfg.S3AccessKey, SecretKey: cfg.S3SecretKey,
		UseSSL: cfg.S3UseSSL, Bucket: cfg.S3Bucket, BucketHLS: cfg.S3BucketHLS, Region: cfg.S3Region, PublicURL: cfg.S3PublicURL,
		PublicEndpoint: cfg.S3PublicEndpoint, PublicUseSSL: cfg.S3PublicUseSSL, CrearBucket: cfg.S3CreateBucket,
	})
	if err != nil {
		log.Error("worker: storage", "error", err)
		os.Exit(1)
	}

	assets := postgres.NewMediaRepo(pool)
	cursos := postgres.NewCourseRepo(pool)

	processor := &media.Processor{
		Storage: storageClient,
		Assets:  assets,
		Courses: cursos,
		Log:     log,
	}
	// La conversión de presentaciones comparte worker con la
	// transcodificación: las dos son trabajos lentos sobre el mismo activo, y
	// separarlas en procesos distintos duplicaría el despliegue sin ganar nada.
	convertidor := &documentos.Procesador{
		Storage: storageClient,
		Assets:  assets,
		Courses: cursos,
		Log:     log,
	}

	// retiro se cancela al recibir sigterm y corta los trabajos en curso para
	// que liberen su activo antes de volver a la cola (ver queue.Retirable)
	retiro, retirar := context.WithCancel(context.Background())
	defer retirar()

	mux := asynq.NewServeMux()
	mux.Use(queue.Retirable(retiro))
	mux.HandleFunc(queue.TaskProcessMedia, processor.HandleProcessMedia)
	mux.HandleFunc(queue.TaskConvertDocument, convertidor.HandleConvertDocument)

	if cfg.QueueBackend == "pubsub" {
		servirPush(ctx, cfg, log, mux, retirar)
		return
	}

	srv := queue.NewServer(cfg.RedisAddr, cfg.WorkerConcurrency, log)

	// start y no run: run tiene su propio manejador de sigterm y apaga el
	// servidor por su lado, al mismo tiempo que este, sin dejar liberar los
	// activos. el apagado tiene que ser uno solo y en este orden
	if err := srv.Start(mux); err != nil {
		log.Error("worker: no arranco el servidor de la cola", "error", err)
		os.Exit(1)
	}

	<-ctx.Done()
	// 1. dejar de tomar trabajos, si no este mismo worker podria volver a
	//    tomar el trabajo que esta devolviendo
	// 2. cortar los trabajos activos: ffmpeg se detiene, el activo vuelve a
	//    'queued' y la tarea vuelve a redis sin gastar reintento
	// 3. esperar a que los manejadores terminen y cerrar
	log.Info("worker: senal de apagado recibida, retiro seguro en curso", "accion", "worker.retiro")
	srv.Stop()
	retirar()
	srv.Shutdown()
	log.Info("worker detenido")
}

// servirPush atiende las entregas de la suscripción push de Pub/Sub.
//
// Cloud Run manda SIGTERM al retirar una instancia (scale-in, nueva revisión)
// y da 10 s antes de matarla. El orden es el mismo que con asynq: cortar los
// trabajos en curso (retirar) para que liberen su activo y respondan 503
// (nack: Pub/Sub reentrega a otra instancia sin efectos duplicados), y luego
// cerrar el servidor esperando esas respuestas.
func servirPush(ctx context.Context, cfg config.Config, log *slog.Logger, mux *asynq.ServeMux, retirar context.CancelFunc) {
	rutas := http.NewServeMux()
	rutas.Handle(queue.RutaPush, &queue.ManejadorPush{
		Manejador: mux, Log: log, MaxEntregas: queue.MaxEntregas(),
	})
	rutas.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
	})

	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           rutas,
		ReadHeaderTimeout: 10 * time.Second,
	}
	go func() {
		log.Info("worker: esperando entregas de Pub/Sub", "puerto", cfg.Port, "ruta", queue.RutaPush)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Error("worker: servidor http", "error", err)
			os.Exit(1)
		}
	}()

	<-ctx.Done()
	log.Info("worker: senal de apagado recibida, retiro seguro en curso", "accion", "worker.retiro")
	retirar()
	cierre, cancelar := context.WithTimeout(context.Background(), queue.PlazoDeRetiro)
	defer cancelar()
	if err := srv.Shutdown(cierre); err != nil {
		log.Warn("worker: cierre del servidor http", "error", err)
	}
	log.Info("worker detenido")
}
