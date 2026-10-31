package queue

import (
	"context"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/hibiken/asynq"
)

// TestUnAplazamientoNoGastaReintentosEnAsynq comprueba contra Redis real lo que
// EsFallo y EsperaAntesDeReintentar solo pueden prometer: que asynq vuelve a
// entregar el trabajo con el contador intacto y respetando la espera. Un
// trabajo aplazado varias veces no debe acercarse a la DLQ.
func TestUnAplazamientoNoGastaReintentosEnAsynq(t *testing.T) {
	dir := os.Getenv("TEST_REDIS_ADDR")
	if dir == "" {
		t.Skip("falta TEST_REDIS_ADDR: se omite la prueba de integración")
	}
	// base propia: las pruebas de httpserver corren en paralelo y hacen FlushDB
	// sobre la base 0, que borraría el trabajo mientras espera
	opcion := asynq.RedisClientOpt{Addr: dir, DB: 9}
	cola := "prueba-" + uuid.NewString()
	const espera = 2 * time.Second

	var entregas atomic.Int32
	var primera, segunda atomic.Int64
	reintentos := make(chan int, 2)
	mux := asynq.NewServeMux()
	mux.HandleFunc(TaskProcessMedia, func(ctx context.Context, _ *asynq.Task) error {
		n, _ := asynq.GetRetryCount(ctx)
		reintentos <- n
		if entregas.Add(1) == 1 {
			primera.Store(time.Now().UnixMilli())
			return &Arrendado{Espera: espera}
		}
		segunda.Store(time.Now().UnixMilli())
		return nil
	})

	srv := asynq.NewServer(opcion, asynq.Config{
		Concurrency:     1,
		Queues:          map[string]int{cola: 1},
		IsFailure:       EsFallo,
		RetryDelayFunc:  EsperaAntesDeReintentar,
		ShutdownTimeout: time.Second,
		// el traslado de reintentos a pendientes corre cada 5 s por defecto
		DelayedTaskCheckInterval: 200 * time.Millisecond,
	})
	if err := srv.Start(mux); err != nil {
		t.Fatalf("no arrancó el servidor: %v", err)
	}
	t.Cleanup(srv.Shutdown)

	cliente := asynq.NewClient(opcion)
	t.Cleanup(func() { _ = cliente.Close() })
	if _, err := cliente.Enqueue(asynq.NewTask(TaskProcessMedia, nil), asynq.Queue(cola), asynq.MaxRetry(1)); err != nil {
		t.Fatalf("no se pudo encolar: %v", err)
	}

	for i := range 2 {
		select {
		case n := <-reintentos:
			if n != 0 {
				t.Errorf("entrega %d con %d reintentos gastados, se esperaban 0", i+1, n)
			}
		case <-time.After(30 * time.Second):
			t.Fatalf("la entrega %d no llegó: el trabajo aplazado se perdió", i+1)
		}
	}
	// asynq guarda la hora en segundos enteros, así que puede adelantarse hasta
	// uno. No importa en producción: si llega antes de que venza el
	// arrendamiento, se aplaza otra vez con la espera mínima.
	if d := time.Duration(segunda.Load()-primera.Load()) * time.Millisecond; d < espera-time.Second {
		t.Errorf("la segunda entrega llegó a los %v, antes de la espera de %v", d, espera)
	}
}
