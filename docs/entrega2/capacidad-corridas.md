# Corridas de capacidad (orden de ejecución)

La infraestructura de la app no se toca. El generador es **otra** VM
(`mooc-k6`, e2-standard-2). k6 1.8.1, mismos scripts que en el repo.

Valores fijos de este informe:

| Campo | Valor |
|---|---|
| `BASE_URL` | `https://34.28.87.172.sslip.io` |
| Zona | `us-central1-a` |
| App | `mooc-web` + `mooc-worker` e2-small |
| Generador | `mooc-k6` e2-standard-2 |
| Semilla | `SEED_STUDENTS=400` `SEED_TEACHERS=3` `SEED_ENROLL=0` |
| `NIVELES` | `50,100,200,300` (+ repetición de 300) |

## 1. Sembrar (Cloud Shell)

No uses Actions si `SEED_ENROLL` no está en `0` en Variables. Desde Cloud Shell:

```bash
gcloud config set project totemic-gravity-509902-u2
gcloud compute ssh mooc-web --zone us-central1-a --tunnel-through-iap --command \
  'sudo SEED_STUDENTS=400 SEED_TEACHERS=3 SEED_ENROLL=0 bash /opt/mooc/actual/deploy/gcp/en-vm.sh sembrar'
```

Tarda unos minutos. Al terminar, el JSON está en el Web:
`/opt/mooc/salida/escenario.json`.

## 2. Crear el generador (Cloud Shell)

```bash
cd ~/proyecto-1 && git pull
bash load/generador-vm.sh crear
# 2-3 minutos
gcloud compute ssh mooc-k6 --zone us-central1-a --command 'test -f /var/lib/mooc-k6-ok && k6 version && ffmpeg -version | head -1'
```

## 3. Código + escenario + perfiles (en mooc-k6)

```bash
gcloud compute ssh mooc-k6 --zone us-central1-a
```

Dentro:

```bash
git clone https://github.com/DES-SOLUCIONES-CLOUD/proyecto-1
cd proyecto-1
mkdir -p load/salida
```

En **otra** pestaña de Cloud Shell (sigue en `~`, no en la VM):

```bash
gcloud compute ssh mooc-web --zone us-central1-a --tunnel-through-iap --command \
  'sudo cat /opt/mooc/salida/escenario.json' > /tmp/escenario.json
gcloud compute scp /tmp/escenario.json mooc-k6:~/proyecto-1/load/salida/escenario.json \
  --zone us-central1-a
```

De vuelta en `mooc-k6`:

```bash
cd ~/proyecto-1
load/perfiles/generar.sh
ls -lh load/perfiles/*.mp4 load/perfiles/audio.wav
```

## 4. Escenario 1

En `mooc-k6`. El reposo por defecto son **10 minutos** (ráfaga de las e2-small).
Para un ensayo de que k6 arranca: `REPOSO_S=30`. La corrida que va al informe: sin eso.

```bash
export BASE_URL=https://34.28.87.172.sslip.io
export NIVELES=50,100,200,300
export MESETA=3m
export WORKER_CONCURRENCY=2
export DB_MAX_CONNS=20
export HABILITAR_NAT=true
export GENERADOR='e2-standard-2 us-central1-a'
load/correr.sh escenario1
```

Duración aproximada: 10 min reposo + ~4 niveles × (30 s rampa + 3 min) × 3 mixes
+ repetición de 300. Cuenta **más de media hora** de k6. No apagues `mooc-web`
ni Cloud SQL.

Al terminar: `load/salida/resumen-escenario1.json`, `corrida-escenario1-*.md`,
`metricas-*.md` si hay `gcloud` en la VM (en `mooc-k6` suele no haber; las
métricas se sacan después desde Cloud Shell):

```bash
# Cloud Shell, con el repo y TF_STATE_BUCKET:
export TF_STATE_BUCKET=totemic-gravity-509902-u2-tfstate
# Ajusta --desde/--hasta a la UTC de corrida-*.md
bash load/metricas.sh --corrida esc1 --desde 2026-09-27T08:00:00Z --hasta 2026-09-27T09:00:00Z
```

## 5. Escenario 2

Otro reposo de 10 min (o `REPOSO_S=30` solo para probar).

```bash
export BASE_URL=https://34.28.87.172.sslip.io
export MESETA=5m
export PROFESORES=3
export ESTUDIANTES=20
export WORKER_CONCURRENCY=2
export DB_MAX_CONNS=20
export HABILITAR_NAT=true
export GENERADOR='e2-standard-2 us-central1-a'
load/correr.sh escenario2
```

Setup sube 3 MP4 + 1 WAV y espera `ready` **antes** de la meseta. Puede tardar
10–15 min extra. Luego profesores y estudiantes 5 min.

## 6. Traer resultados y Monitoring

Desde Cloud Shell:

```bash
mkdir -p ~/evidencias-carga
gcloud compute scp --recurse mooc-k6:~/proyecto-1/load/salida ~/evidencias-carga --zone us-central1-a
```

Consola → Monitoring → Metrics Explorer, mismas ventanas UTC:

- CPU / memoria / disco de `mooc-web` y `mooc-worker`
- CPU y conexiones de `mooc-bd-aeab`

Capturas `YYYYMMDD-cpu-web-esc1.png` etc. en `capacity-planning/evidencias/`.
Copiar números a `capacity-planning/pruebas_de_carga_entrega2.md`.

## 7. Apagar el generador

```bash
bash load/generador-vm.sh borrar
```

Las e2-small y SQL se apagan aparte (`Actions → apagar`) cuando no haya más
corridas ni video ese día.
