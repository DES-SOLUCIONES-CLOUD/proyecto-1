package httpserver_test

import (
	"net/http"
	"strings"
	"testing"
)

//pruebas de la edicion de quizzes por el profesor y de la regla de publicacion

// el profesor puede leer su quiz guardado (con las respuestas correctas) para editarlo
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

// otro profesor y un estudiante no pueden leer la definicion con las respuestas
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

// un curso con un quiz visible sin preguntas no se puede publicar,
// y el motivo dice cual quiz es
func TestNoSePublicaUnQuizSinPreguntas(t *testing.T) {
	env := nuevoEntorno(t)
	c, versionID := env.profesorConCurso("prof@example.com", "quiz-vacio")
	unidadID := env.unidadVacia(c, versionID)

	res := c.hacer(http.MethodPost, "/courses/versions/"+versionID+"/units/"+unidadID+"/resources",
		map[string]any{"type": "quiz", "title": "Quiz vacio", "position": 1, "visible": true, "required": true})
	if res.Estado != http.StatusCreated {
		t.Fatalf("crear quiz: %d %s", res.Estado, res.Crudo)
	}
	if res := c.hacer(http.MethodPatch, "/courses/versions/"+versionID,
		map[string]any{"title": "Curso", "summary": "Resumen"}); res.Estado != http.StatusOK {
		t.Fatalf("metadatos: %d %s", res.Estado, res.Crudo)
	}

	res = c.hacer(http.MethodPost, "/courses/versions/"+versionID+"/publish", nil)
	if res.Estado != http.StatusUnprocessableEntity {
		t.Fatalf("se esperaba 422 al publicar un quiz vacio, llego %d %s", res.Estado, res.Crudo)
	}
	if !strings.Contains(res.Crudo, "sin preguntas") || !strings.Contains(res.Crudo, "Quiz vacio") {
		t.Fatalf("el motivo debe nombrar el quiz sin preguntas: %s", res.Crudo)
	}
}
