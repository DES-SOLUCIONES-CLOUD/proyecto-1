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

// al despublicar para editar, el borrador nuevo conserva las preguntas del quiz
// y se puede volver a publicar sin reescribirlas
func TestElBorradorDeActualizacionConservaElQuiz(t *testing.T) {
	env := nuevoEntorno(t)
	_, cursoID := env.cursoConQuiz("prof@example.com", "quiz-actualizado")
	profesor := env.entrar("prof@example.com", clavePrueba)
	borradorID := env.borradorDeActualizacion(profesor, cursoID)

	//el recurso quiz del borrador es otro (id nuevo), pero debe tener sus preguntas
	recursoNuevo := env.consultarTexto(`
		SELECT res.id::text FROM resources res
		JOIN units u ON u.id = res.unit_id
		JOIN modules m ON m.id = u.module_id
		WHERE m.course_version_id = $1 AND res.type = 'quiz'`, borradorID)
	res := profesor.hacer(http.MethodGet, "/courses/versions/"+borradorID+"/resources/"+recursoNuevo+"/quiz", nil)
	if res.Estado != http.StatusOK {
		t.Fatalf("el quiz del borrador deberia existir: %d %s", res.Estado, res.Crudo)
	}
	if preguntas, _ := res.campo(t, "questions").([]any); len(preguntas) != 2 {
		t.Fatalf("el borrador deberia conservar las 2 preguntas: %s", res.Crudo)
	}

	//las preguntas conservan su stable_id, asi los resultados siguen apuntando a la misma pregunta
	iguales := env.contar(`
		SELECT count(*) FROM quiz_questions nueva
		JOIN quizzes qn ON qn.id = nueva.quiz_id AND qn.resource_id = $1
		WHERE nueva.stable_id IN (SELECT stable_id FROM quiz_questions
		                          WHERE quiz_id <> nueva.quiz_id)`, recursoNuevo)
	if iguales != 2 {
		t.Fatalf("las 2 preguntas deberian conservar su stable_id, coinciden %d", iguales)
	}

	if res := profesor.hacer(http.MethodPost, "/courses/versions/"+borradorID+"/publish", nil); res.Estado != http.StatusOK {
		t.Fatalf("el borrador con su quiz copiado deberia publicarse: %d %s", res.Estado, res.Crudo)
	}
}
