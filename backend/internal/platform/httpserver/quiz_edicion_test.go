package httpserver_test

import (
	"net/http"
	"strings"
	"testing"
)

//pruebas de la edicion de quizzes por el profesor y de la regla de publicacion

//el profesor puede leer su quiz guardado (con las respuestas correctas) para editarlo
func TestElProfesorLeeSuQuizParaEditarlo(t *testing.T) {
	env := nuevoEntorno(t)
	recursoID, cursoID := env.cursoConQuiz("prof@example.com", "quiz-editable")
	versionID := env.consultarTexto(`SELECT current_published_version_id::text FROM courses WHERE id = $1`, cursoID)
	profesor := env.entrar("prof@example.com", clavePrueba)

	res := profesor.hacer(http.MethodGet, "/courses/versions/"+versionID+"/resources/"+recursoID+"/quiz", nil)
	if res.Estado != http.StatusOK {
		t.Fatalf("leer quiz: %d %s", res.Estado, res.Crudo)
	}
	preguntas, _ := res.campo(t, "questions").([]any)
	if len(preguntas) != 2 {
		t.Fatalf("se esperaban 2 preguntas, llegaron %d: %s", len(preguntas), res.Crudo)
	}
	//al dueño si le llega cual opcion es la correcta, para poder editarla
	if !strings.Contains(res.Crudo, `"is_correct":true`) {
		t.Fatalf("la definicion del profesor debe traer las respuestas correctas: %s", res.Crudo)
	}
}

//otro profesor y un estudiante no pueden leer la definicion con las respuestas
func TestNadieMasLeeLasRespuestasDelQuiz(t *testing.T) {
	env := nuevoEntorno(t)
	recursoID, cursoID := env.cursoConQuiz("prof@example.com", "quiz-secreto")
	versionID := env.consultarTexto(`SELECT current_published_version_id::text FROM courses WHERE id = $1`, cursoID)
	ruta := "/courses/versions/" + versionID + "/resources/" + recursoID + "/quiz"

	otro := env.otroProfesor("otro@example.com")
	if res := otro.hacer(http.MethodGet, ruta, nil); res.Estado == http.StatusOK {
		t.Fatalf("otro profesor no deberia leer el quiz ajeno: %s", res.Crudo)
	}

	estudiante := env.inscribir("ana@example.com", cursoID)
	if res := estudiante.hacer(http.MethodGet, ruta, nil); res.Estado == http.StatusOK {
		t.Fatalf("un estudiante no deberia leer las respuestas: %s", res.Crudo)
	}
}
