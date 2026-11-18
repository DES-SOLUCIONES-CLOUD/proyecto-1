package queue

import "context"

// Enrutador publica cada trabajo por el Encolador de su tipo y el resto por
// Defecto.
//
// Entrega 5: la transcodificación de audio (TaskProcessAudio) sale del worker
// y la ejecuta una Cloud Function activada por su propio topic. La API sigue
// teniendo un solo Encolador; lo que cambia es a qué topic va cada tipo, y
// eso queda aquí y no repartido por los manejadores HTTP.
type Enrutador struct {
	Defecto Encolador
	PorTipo map[string]Encolador
}

func (e *Enrutador) Encolar(ctx context.Context, t Trabajo) error {
	if destino, ok := e.PorTipo[t.Tipo]; ok {
		return destino.Encolar(ctx, t)
	}
	return e.Defecto.Encolar(ctx, t)
}
