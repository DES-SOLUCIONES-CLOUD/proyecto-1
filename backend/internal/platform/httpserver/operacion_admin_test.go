package httpserver_test

import (
	"net/http"
	"testing"
	"time"
)

// el administrador crea una cuenta ya activa y esa persona puede entrar de una vez
func TestElAdministradorCreaUnaCuentaActiva(t *testing.T) {
	env := nuevoEntorno(t)
	admin := env.admin("admin@example.com")

	res := admin.hacer(http.MethodPost, "/admin/users", map[string]string{
		"email": "nuevo@example.com", "full_name": "Profe Nuevo", "role": "teacher", "password": clavePrueba,
	})
	if res.Estado != http.StatusCreated {
		t.Fatalf("crear cuenta: %d %s", res.Estado, res.Crudo)
	}
	if res.campo(t, "status") != "active" || res.campo(t, "role") != "teacher" {
		t.Fatalf("la cuenta deberia quedar activa y con rol de profesor: %s", res.Crudo)
	}
	//entra sin pasar por el correo de verificacion
	env.entrar("nuevo@example.com", clavePrueba)

	//el mismo correo no se puede repetir
	if res := admin.hacer(http.MethodPost, "/admin/users", map[string]string{
		"email": "nuevo@example.com", "full_name": "Otro", "role": "student", "password": clavePrueba,
	}); res.Estado == http.StatusCreated {
		t.Fatalf("no deberia crear dos cuentas con el mismo correo: %s", res.Crudo)
	}
}

// solo el administrador crea cuentas y ve el panel de actividad
func TestSoloElAdministradorCreaCuentasYVeLaActividad(t *testing.T) {
	env := nuevoEntorno(t)
	env.registrarYVerificar("estudiante@example.com")
	estudiante := env.entrar("estudiante@example.com", clavePrueba)

	if res := estudiante.hacer(http.MethodPost, "/admin/users", map[string]string{
		"email": "x@example.com", "full_name": "X", "role": "admin", "password": clavePrueba,
	}); res.Estado != http.StatusForbidden {
		t.Errorf("un estudiante no deberia crear cuentas: %d", res.Estado)
	}
	if res := estudiante.hacer(http.MethodGet, "/admin/actividad", nil); res.Estado != http.StatusForbidden {
		t.Errorf("un estudiante no deberia ver la actividad: %d", res.Estado)
	}
}

// el panel de actividad muestra las peticiones con la maquina que las atendio
func TestLaActividadMuestraQuienAtendioCadaPeticion(t *testing.T) {
	env := nuevoEntorno(t)
	admin := env.admin("admin@example.com")
	admin.hacer(http.MethodGet, "/admin/users", nil)

	//la anotacion se hace aparte, se espera un momento a que llegue a redis
	var encontrada map[string]any
	for i := 0; i < 20 && encontrada == nil; i++ {
		time.Sleep(100 * time.Millisecond)
		res := admin.hacer(http.MethodGet, "/admin/actividad", nil)
		if res.Estado != http.StatusOK {
			t.Fatalf("actividad: %d %s", res.Estado, res.Crudo)
		}
		peticiones, _ := res.campo(t, "peticiones").([]any)
		for _, p := range peticiones {
			if m, ok := p.(map[string]any); ok && m["ruta"] == "/api/v1/admin/users" {
				encontrada = m
			}
		}
	}
	if encontrada == nil {
		t.Fatal("la actividad deberia tener la consulta de usuarios")
	}
	if encontrada["instancia"] == "" || encontrada["usuario"] != "admin@example.com" {
		t.Fatalf("cada peticion deberia decir la maquina y quien la hizo: %v", encontrada)
	}
}
