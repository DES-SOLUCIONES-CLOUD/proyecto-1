package queue

import (
	"context"
	"testing"
)

type encoladorFalso struct{ tipos []string }

func (e *encoladorFalso) Encolar(_ context.Context, t Trabajo) error {
	e.tipos = append(e.tipos, t.Tipo)
	return nil
}

func TestEnrutadorMandaElAudioASuTopic(t *testing.T) {
	general, audio := &encoladorFalso{}, &encoladorFalso{}
	e := &Enrutador{Defecto: general, PorTipo: map[string]Encolador{TaskProcessAudio: audio}}

	for _, tipo := range []string{TaskProcessMedia, TaskProcessAudio, TaskConvertDocument} {
		if err := e.Encolar(context.Background(), Trabajo{Tipo: tipo}); err != nil {
			t.Fatal(err)
		}
	}
	if len(audio.tipos) != 1 || audio.tipos[0] != TaskProcessAudio {
		t.Errorf("al topic de audio solo debe ir el audio: %v", audio.tipos)
	}
	if len(general.tipos) != 2 {
		t.Errorf("video y presentaciones siguen en el topic general: %v", general.tipos)
	}
}
