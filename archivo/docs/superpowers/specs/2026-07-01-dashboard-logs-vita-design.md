# Dashboard web de logs en vivo de la Vita — diseño

**Fecha:** 2026-07-01
**Estado:** aprobado, pendiente de plan de implementación

## Contexto y problema

Con la Fase 1 completa (ver `docs/06-bitacora-estado.md`), verificar que todo
funciona requiere hoy 4 terminales abiertas a mano: el agente micro-ROS, el
listener de netlog (`tools/netlog-listen.sh`), y `ros2 topic echo`/`pub`
dentro de un contenedor ROS2. Esto no escala como forma de trabajar a largo
plazo — en particular, leer los logs de la Vita (arranque de sesión XRCE,
fallos, criterios cumplidos) obliga a tener una terminal fija con
`netlog-listen.sh` y no deja ningún rastro histórico navegable.

La idea original del usuario incluía además: analítica de rendimiento/fallos
sobre esos logs, y un "constructor" web de la propia UI/frontend/backend de
la app homebrew de la Vita. **Ambas cosas quedan fuera de este spec**: son
subproyectos independientes (la analítica depende de que este dashboard
exista primero como fuente de datos estructurados; el constructor de UI es
un proyecto grande y de naturaleza distinta — un editor low-code). Los
topics de ROS2 (`ros2 topic echo`/`pub`) también quedan fuera: se mantienen
como terminales, según decisión explícita del usuario.

**Alcance de este spec:** reemplazar la lectura manual del netlog UDP de la
Vita por un dashboard web en tiempo real, con historial navegable por
sesión, dentro del sitio Astro que ya existe en `web/`.

## Decisiones tomadas durante el brainstorming

- Solo se diseña el dashboard de logs (subproyecto 1 de 3). Analítica y
  constructor de UI quedan para specs futuros y separados.
- Se guarda historial por sesión en SQLite (no solo vista en vivo efímera):
  sienta la base para la futura analítica.
- `tools/netlog-listen.sh` se mantiene como alternativa de terminal para
  cuando la web no esté levantada — con la limitación conocida de que solo
  un proceso puede escuchar el puerto UDP 9999 a la vez.
- El dashboard es una herramienta de desarrollo local: solo accesible en
  `localhost:4321` por ahora, sin autenticación. No se expone en el futuro
  dominio público (`psvita-ros.jcrex999.com`) todavía.
- Arquitectura elegida: ingestor UDP ligero y separado (proceso Node nuevo)
  que escribe en la SQLite ya existente (`web/data/app.db`), más un
  endpoint SSE en Astro que hace poll corto sobre esa misma tabla. Se
  descartó fusionar el socket UDP dentro del proceso de Astro (acopla
  demasiado al adaptador `node` interno) y WebSocket (innecesario: solo se
  empuja servidor→navegador, y SSE es HTTP plano más simple).

## Arquitectura

```
PS Vita (netlog.c)
   │ UDP :9999
   ▼
netlog-ingester.mjs (proceso Node nuevo, mismo contenedor que la web)
   │ limpia bytes no imprimibles, detecta arranque/fin de sesión, escribe
   ▼
web/data/app.db (SQLite, la misma que ya usa el checklist de instalación)
   │ leída por...
   ▼
Astro (proceso existente, sin tocar su arranque)
   ├─ GET /monitor                    → página: lista de sesiones + visor en vivo
   ├─ GET /api/monitor/sessions       → lista de sesiones (JSON)
   ├─ GET /api/monitor/session/[id]   → historial estático de una sesión pasada
   ├─ GET /api/monitor/status         → último timestamp recibido (indicador global)
   └─ GET /api/monitor/stream         → SSE: poll corto a SQLite, empuja líneas nuevas
```

*(Actualizado tras la implementación: la versión final tiene 4 endpoints,
no 3 — `/api/monitor/sessions` y `/api/monitor/status` se añadieron en el
plan. Detalle completo en
`docs/superpowers/plans/2026-07-01-dashboard-logs-vita.md`.)*

Los dos procesos (Astro + `netlog-ingester.mjs`) arrancan en el mismo
contenedor Docker, vía `web/scripts/docker-entrypoint.sh` (no dos `node`
sueltos en el `CMD` como se planteó aquí originalmente): el ingestor corre
en un bucle que lo reinicia si muere, y `exec node dist/server/entry.mjs`
deja a Astro como proceso principal para las señales de Docker. Comparten
el volumen `./data` ya montado. Si `tools/netlog-listen.sh`
corre en paralelo, solo uno de los dos procesos podrá bindear el puerto
9999 — se documenta como limitación conocida, no se resuelve con
`SO_REUSEPORT` ni reintentos (YAGNI para una herramienta de un solo
desarrollador).

## Modelo de datos (nuevas tablas en `app.db`)

```sql
CREATE TABLE vita_sessions (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at   TEXT NOT NULL DEFAULT (datetime('now')),
  ended_at     TEXT,                 -- se rellena al arrancar la siguiente sesión
                                      -- o tras 30s de silencio
  source_ip    TEXT,                 -- IP:puerto de origen del primer paquete UDP
  status       TEXT NOT NULL DEFAULT 'en-curso'
               -- 'en-curso' | 'establecida' | 'fatal' | 'cerrada'
);

CREATE TABLE vita_log_lines (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id   INTEGER NOT NULL REFERENCES vita_sessions(id),
  received_at  TEXT NOT NULL DEFAULT (datetime('now')),
  raw_text     TEXT NOT NULL,
  kind         TEXT NOT NULL DEFAULT 'normal'
               -- 'normal' | 'hito' | 'fatal' (mismo criterio de color que netlog-listen.sh)
);
```

**Detección de sesión:** cada línea recibida se limpia de bytes no
imprimibles al inicio (el "ruido binario" observado en las pruebas del
2026-07-01, ver `docs/06-bitacora-estado.md`). Si el texto limpio contiene
`"red inicializada"`, se cierra la sesión anterior (si seguía abierta) y se
abre una fila nueva en `vita_sessions`. Si pasan más de 30s sin ningún
paquete, la sesión activa se cierra igualmente (`ended_at`), para no dejar
sesiones "en-curso" colgadas si la Vita se apaga sin línea de salida.

`status` se deriva del contenido de las líneas ya vistas en el proyecto:
`SESION XRCE ESTABLECIDA` → `establecida`; `FATAL` → `fatal`; línea de
salida (`"saliendo (START pulsado"`) → `cerrada`. Si una línea queda vacía
tras limpiar bytes no imprimibles, se descarta sin crear fila.

## Página `/monitor` (UI)

- **Columna izquierda:** lista de sesiones (más reciente arriba) con badge
  de estado (🟢 viva / ✅ establecida / 🔴 fatal / ⚪ cerrada). Clic en
  cualquiera carga su historial (`GET /api/monitor/session/[id]`).
- **Panel derecho:** si la sesión seleccionada es la más reciente y sigue
  activa, se conecta por SSE (`EventSource` nativo del navegador) a
  `/api/monitor/stream` y hace autoscroll con las líneas nuevas coloreadas
  igual que `netlog-listen.sh` (fatal=rojo, hitos=verde, resto=normal). Si
  es una sesión antigua, se pinta estática con un solo `fetch`, sin SSE.
- **Indicador global** (arriba a la derecha): 🟢 si llegó algún paquete UDP
  en los últimos 5s, ⚪ si no — para saber de un vistazo si la Vita sigue
  transmitiendo, sin tener que leer texto.
- Reutiliza `src/layouts/Base.astro` y `src/styles/global.css`; sin
  librerías de frontend nuevas (JS vanilla + `EventSource`).

## Manejo de errores

- **Puerto 9999 ocupado** (p. ej. `netlog-listen.sh` corriendo a la vez): el
  ingestor falla al bindear, lo loguea claro a stdout del contenedor y no
  tumba el proceso de Astro (son procesos separados) — el dashboard queda
  sin datos nuevos y el indicador global pasa a ⚪.
- **Líneas corruptas/binarias:** se limpian bytes no imprimibles; líneas
  vacías tras la limpieza se descartan.
- **Pérdida de paquetes UDP:** comportamiento ya existente hoy con
  `netlog-listen.sh`, no es una regresión.
- **Concurrencia SQLite:** el ingestor escribe y Astro lee para el SSE;
  `db.ts` ya activa `journal_mode = WAL`, que soporta bien un escritor +
  lectores concurrentes.
- **Sesión huérfana:** cubierta por el timeout de 30s de silencio.

## Testing

- **Ingestor:** funciones puras (limpiar bytes no imprimibles, detectar
  `"red inicializada"`/`"FATAL"`/`"CUMPLIDO"`, decidir apertura/cierre de
  sesión) probadas con `node:test` sobre strings de ejemplo, sin
  dependencias nuevas — corre en la laptop sin hardware.
- **Endpoint SSE y página:** verificación manual en navegador, simulando la
  Vita con `nc -u 127.0.0.1 9999 <<< "..."` o reutilizando líneas reales
  guardadas en las pruebas del 2026-07-01 — no se automatiza (es una vista,
  no lógica de negocio crítica), igual que el resto de la web hoy
  (`pnpm build` + revisión manual).
- **Regresión:** `tools/run-parity-tests.sh` y los tests del MCP no se ven
  afectados (código nuevo vive solo en `web/`).

## Fuera de alcance (para specs futuros)

- Analítica de rendimiento/fluidez/fallos/retrocompatibilidad sobre el
  historial de logs (subproyecto 2 — depende de que este dashboard exista).
- Constructor web de la UI/frontend/backend de la app homebrew de la Vita
  (subproyecto 3 — proyecto grande e independiente).
- Autenticación / exposición en el dominio público.
- Integrar `ros2 topic echo`/`pub` en la web (se mantienen como terminales).
