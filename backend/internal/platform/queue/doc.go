// Package queue implementa la publicación y el consumo de trabajos
// asíncronos. Hay dos transportes: asynq sobre Redis (local y Entregas 2-3) y
// Cloud Pub/Sub con suscripción push autenticada (Entrega 4, Cloud Run). Los
// manejadores de trabajos son los mismos en los dos.
package queue
