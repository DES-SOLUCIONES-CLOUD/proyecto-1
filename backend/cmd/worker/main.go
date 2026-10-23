// Command worker consume los trabajos asíncronos (transcodificación,
// badges) publicados por la API a través de la cola en Redis, con
// reintentos con backoff y dead-letter queue gestionados por asynq.
package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"github.com/hibiken/asynq"

	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/config"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/documentos"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/media"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/postgres"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/queue"
	"github.com/DES-SOLUCIONES-CLOUD/proyecto-1/backend/internal/platform/storage"
)

func main() {
	cfg := config.Load()
	log := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(log)
	log.Info("worker iniciado", "env", cfg.Env, "redis", cfg.RedisAddr)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

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
