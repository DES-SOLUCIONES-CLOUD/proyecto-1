package queue

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Atributos de cada mensaje de Pub/Sub. Viajan fuera del cuerpo para que el
// worker sepa qué manejador usar sin deserializar el payload, y para que se
// puedan filtrar en la consola y en los registros.
const (
	AtributoTipo  = "tipo"
	AtributoClave = "clave_idempotencia"
)

// PublicadorPubSub implementa Encolador sobre la API REST de Cloud Pub/Sub.
//
// Se habla REST y no el SDK de Go a propósito: publicar es un POST con un
// token de la cuenta de servicio, y el SDK arrastra gRPC y decenas de módulos
// a la imagen de la API para hacer lo mismo. El token sale del servidor de
// metadatos (Cloud Run lo expone para la cuenta de servicio del servicio), así
// que no hay llaves en la imagen ni en el repositorio.
//
// Con PUBSUB_EMULATOR_HOST definido publica contra el emulador local, sin
// token y por http, igual que hacen los SDK oficiales.
type PublicadorPubSub struct {
	Proyecto string
	Topic    string
	// Endpoint es la base de la API. Vacío: https://pubsub.googleapis.com, o
	// el emulador si PUBSUB_EMULATOR_HOST está definido.
	Endpoint string
	HTTP     *http.Client
	Tokens   FuenteDeTokens
	Log      *slog.Logger
}

// FuenteDeTokens entrega un token OAuth de acceso. Vacío significa sin
// autenticación (emulador).
type FuenteDeTokens interface {
	Token(ctx context.Context) (string, error)
}

// NuevoPublicadorPubSub arma el publicador con el endpoint y la fuente de
// tokens que correspondan al entorno.
func NuevoPublicadorPubSub(proyecto, topic string, log *slog.Logger) *PublicadorPubSub {
	p := &PublicadorPubSub{
		Proyecto: proyecto,
		Topic:    topic,
		HTTP:     &http.Client{Timeout: 15 * time.Second},
		Log:      log,
	}
	if emulador := os.Getenv("PUBSUB_EMULATOR_HOST"); emulador != "" {
		p.Endpoint = "http://" + emulador
		p.Tokens = sinToken{}
	} else {
		p.Endpoint = "https://pubsub.googleapis.com"
		p.Tokens = NuevoTokenDeMetadatos()
	}
	return p
}

type mensajePubSub struct {
	Data       string            `json:"data"`
	Attributes map[string]string `json:"attributes"`
}

// Encolar publica el trabajo y vuelve en cuanto Pub/Sub confirma que lo
// guardó: la petición HTTP del usuario no espera la transcodificación.
//
// La clave de idempotencia viaja como atributo. Pub/Sub entrega al menos una
// vez y puede repetir un mensaje, y un cliente puede repetir la confirmación
// de una carga; lo que impide efectos duplicados es que el worker reclama el
// activo con un UPDATE condicional y descarta lo que ya está listo.
func (p *PublicadorPubSub) Encolar(ctx context.Context, t Trabajo) error {
	cuerpo, err := json.Marshal(t.Payload)
	if err != nil {
		return fmt.Errorf("queue: no se pudo serializar el trabajo %s: %w", t.Tipo, err)
	}
	atributos := map[string]string{AtributoTipo: t.Tipo}
	if t.ClaveDeIdempotencia != "" {
		atributos[AtributoClave] = t.ClaveDeIdempotencia
	}
	peticion, err := json.Marshal(map[string]any{
		"messages": []mensajePubSub{{
			Data:       base64.StdEncoding.EncodeToString(cuerpo),
			Attributes: atributos,
		}},
	})
	if err != nil {
		return err
	}

	url := fmt.Sprintf("%s/v1/projects/%s/topics/%s:publish", strings.TrimRight(p.Endpoint, "/"), p.Proyecto, p.Topic)

	// Unos pocos reintentos cortos ante errores transitorios de la API. Si
	// se agotan, el error sube y la API responde 5xx: el cliente reintenta la
	// confirmación con la misma clave de idempotencia.
	var ultimo error
	for intento := 1; intento <= 3; intento++ {
		ids, reintentable, err := p.publicar(ctx, url, peticion)
		if err == nil {
			p.log().InfoContext(ctx, "pubsub: tarea publicada",
				"accion", "queue.task_published",
				"tarea", t.Tipo, "clave_idempotencia", t.ClaveDeIdempotencia,
				"message_id", strings.Join(ids, ","), "topic", p.Topic)
			return nil
		}
		ultimo = err
		if !reintentable || ctx.Err() != nil {
			break
		}
		time.Sleep(time.Duration(intento*200) * time.Millisecond)
	}
	return fmt.Errorf("queue: no se pudo publicar %s en %s: %w", t.Tipo, p.Topic, ultimo)
}

func (p *PublicadorPubSub) publicar(ctx context.Context, url string, cuerpo []byte) (ids []string, reintentable bool, err error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(cuerpo))
	if err != nil {
		return nil, false, err
	}
	req.Header.Set("Content-Type", "application/json")
	token, err := p.Tokens.Token(ctx)
	if err != nil {
		return nil, true, fmt.Errorf("token: %w", err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := p.HTTP.Do(req)
	if err != nil {
		return nil, true, err
	}
	defer res.Body.Close()
	respuesta, _ := io.ReadAll(io.LimitReader(res.Body, 64<<10))
	if res.StatusCode != http.StatusOK {
		reintentable = res.StatusCode == http.StatusTooManyRequests || res.StatusCode >= 500
		return nil, reintentable, fmt.Errorf("pubsub respondió %d: %s", res.StatusCode, strings.TrimSpace(string(respuesta)))
	}
	var r struct {
		MessageIDs []string `json:"messageIds"`
	}
	if err := json.Unmarshal(respuesta, &r); err != nil {
		return nil, false, fmt.Errorf("respuesta de pubsub ilegible: %w", err)
	}
	return r.MessageIDs, false, nil
}

func (p *PublicadorPubSub) log() *slog.Logger {
	if p.Log != nil {
		return p.Log
	}
	return slog.Default()
}

type sinToken struct{}

func (sinToken) Token(context.Context) (string, error) { return "", nil }

// TokenDeMetadatos pide al servidor de metadatos un token de acceso de la
// cuenta de servicio del servicio de Cloud Run y lo cachea hasta poco antes
// de que venza.
type TokenDeMetadatos struct {
	http   *http.Client
	mu     sync.Mutex
	token  string
	vence  time.Time
	ahora  func() time.Time
	origen string
}

// NuevoTokenDeMetadatos crea la fuente de tokens del servidor de metadatos.
func NuevoTokenDeMetadatos() *TokenDeMetadatos {
	return &TokenDeMetadatos{
		http:   &http.Client{Timeout: 5 * time.Second},
		ahora:  time.Now,
		origen: "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
	}
}

func (t *TokenDeMetadatos) Token(ctx context.Context) (string, error) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.token != "" && t.ahora().Before(t.vence) {
		return t.token, nil
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, t.origen, nil)
	if err != nil {
		return "", err
	}
	req.Header.Set("Metadata-Flavor", "Google")
	res, err := t.http.Do(req)
	if err != nil {
		return "", err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return "", fmt.Errorf("servidor de metadatos respondió %d", res.StatusCode)
	}
	var r struct {
		AccessToken string `json:"access_token"`
		ExpiresIn   int    `json:"expires_in"`
	}
	if err := json.NewDecoder(res.Body).Decode(&r); err != nil {
		return "", err
	}
	if r.AccessToken == "" {
		return "", errors.New("servidor de metadatos sin access_token")
	}
	t.token = r.AccessToken
	// un minuto de margen para no usar un token que vence en pleno vuelo
	t.vence = t.ahora().Add(time.Duration(r.ExpiresIn)*time.Second - time.Minute)
	return t.token, nil
}

// MaxEntregas lee de PUBSUB_MAX_ENTREGAS el max_delivery_attempts de la
// suscripción (5 por defecto), para que el worker sepa cuándo una entrega es
// la última antes de la dead-letter.
func MaxEntregas() int {
	if n, err := strconv.Atoi(os.Getenv("PUBSUB_MAX_ENTREGAS")); err == nil && n > 0 {
		return n
	}
	return 5
}
