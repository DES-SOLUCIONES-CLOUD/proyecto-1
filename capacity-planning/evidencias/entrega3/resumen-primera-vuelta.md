# Resumen de la primera vuelta de la Entrega 3

Datos de la primera corrida formal de cada escenario. Falta la segunda vuelta,
por eso aquí no se reporta variación entre corridas ni se presentan estos
valores como resultado final.

Fuentes:

- Entrega 2: [resumen-escenario1.json](../resumen-escenario1.json) y
  [resumen-escenario2.json](../resumen-escenario2.json).
- Entrega 3: [formal-e1-1](formal-e1-1/resumen-escenario1.json) y
  [formal-e2-1](formal-e2-1/resumen-escenario2.json).

## Escenario 1: actividad académica

Mismos niveles en las dos entregas: 50, 100, 200 y 300 VU.

| Métrica | Entrega 2 | Entrega 3 | Cambio |
|---|---:|---:|---:|
| p95 catálogo (ms) | 1.280,1 | 38,3 | -97,0 % |
| p95 consumo (ms) | 2.459,6 | 60,0 | -97,6 % |
| p95 quiz (ms) | 1.626,5 | 53,5 | -96,7 % |
| p95 login (ms) | 2.458,6 | 1.503,8 | -38,8 % |
| Peticiones por segundo | 134,9 | 196,3 | +45,5 % |
| Peticiones totales | 142.493 | 207.488 | +45,6 % |

Tasa de éxito en Entrega 3: 99,9995 % (207.487 de 207.488 peticiones). Se
registró 1 petición fallida.

Comprobaciones funcionales en Entrega 3: 219.981 de 219.981. El reenvío del
quiz devolvió la misma nota en 3.330 de 3.330 casos, sin doble calificación.

El login cumple ahora el umbral de 2.000 ms, que en Entrega 2 no cumplía. Es la
operación más lenta porque Argon2id está calibrado para ser costoso por
seguridad. Ningún login recibió límite de tasa (141 medidos, rate 0).

### Nota sobre los errores de Entrega 2

El 9,92 % de Entrega 2 no es comparable sin corregir. Incluye 14.131 respuestas
409 "ya inscrito", que son un rechazo esperado: la cifra coincide con 14.341
inscripciones menos 210 con estado 201. En Entrega 3 esa respuesta se declara
como esperada, de modo que la mejora de esta tabla debe leerse en latencia y
throughput, no en la tasa de error.

## Escenario 2: multimedia

Carga declarada: 3 profesores y 20 estudiantes.

| Métrica | Entrega 2 | Entrega 3 | Lectura |
|---|---:|---:|---|
| Tiempo hasta `ready`, p50 (s) | 20,4 | 36,5 | Empeoró |
| Tiempo hasta `ready`, p95 (s) | 279,4 | 88,7 | Mejoró |
| Tiempo hasta `ready`, máximo (s) | 288,0 | 93,0 | Mejoró |
| Videos listos | 13 | 8 | Bajó |
| Segmento HLS, p95 (ms) | 72,0 | 70,6 | Igual |
| Transferencia, p95 (ms) | 172,8 | 125,0 | Mejoró |
| Confirmación, p95 (ms) | 259,6 | 141,0 | Mejoró |
| Firma, p95 (ms) | 18,2 | 58,5 | Empeoró |

Peticiones fallidas: 123 de 2.059 en Entrega 2 y 0 de 2.073 en Entrega 3.

Límites de esta lectura:

- `mooc_espera_cola` no separa espera y procesamiento, porque el recurso nunca
  pasa por el estado `processing`. La segunda vuelta mide el procesamiento con
  `load/duraciones-worker.sh`.
- `mig-workers` escaló durante la preparación, antes de la meseta.
- La causa de la mediana más alta y de los videos listos más bajos sigue sin
  demostrar.
- El HLS lo sirve el almacenamiento de objetos, por lo que su resultado no se
  atribuye al autoscaling.

## Intento excluido

`intento-e2-1-setup-timeout` no generó carga: k6 cortó la preparación a los
60 s. Se conserva como registro y no cuenta como corrida válida. El ajuste fue
ampliar `setupTimeout`, sin cambiar la carga medida.
