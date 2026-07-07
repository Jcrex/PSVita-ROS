# Web del proyecto — PSVita-ROS

Sitio interactivo que presenta el proyecto, publica las guías y la
documentación, muestra el progreso por fases y — desde la fase de
desarrollo web (`docs/08`) — funciona como **panel de control del
proyecto**: dashboard ROS2 en vivo, comparador C↔Rust, visor 3D/URDF y el
taller (compilador `.vpk` + debug en host). Tema oscuro/azul.

**Stack:** Astro 5 (SSR, adaptador Node standalone) · pnpm (con bloqueo de
build-scripts: solo `better-sqlite3`, `esbuild` y `sharp` aprobados en
`pnpm-workspace.yaml`) · SQLite (better-sqlite3) · three.js (visor 3D) ·
Docker.

## Mapa

| Ruta | Qué muestra |
|---|---|
| `/` | Presentación: la idea, el diagrama, la estrategia dual |
| `/arquitectura` | La pila Fase 1 capa a capa, ADRs, la incógnita dura |
| `/docs` + `/docs/<sección>/<slug>` | **Toda la documentación del repo**, por secciones: Fundación y estado (docs/00-08), ADRs, Aprendiendo Rust (docs/rust/) y Documentación del código (READMEs de módulos, app y MCP) |
| `/guias` + `/guias/<slug>` | Las guías (leídas de `docs/guias-vita/` — una sola fuente de verdad, incluye el tutorial del SDK) con **checklist interactivo persistente** |
| `/comparador` + `/comparador/<módulo>` | **Comparador C ↔ Rust**: los 3 módulos duales en split view con resaltado (lee `modules/*` del repo en build) |
| `/visor3d` | **Visor 3D** URDF/SDF/STL/OBJ/DAE con three.js: sliders de joints, drag&drop, modelo de prueba VitaBot (`public/modelos/`) |
| `/dashboard` | **Dashboard ROS2 editable**: logs netlog UDP de la Vita en vivo (SSE), salud de la sesión XRCE y topics del grafo; layout persistente por visitante |
| `/taller` + `/taller/{compilador,debug}` | **Taller** (solo con `TALLER_ENABLED=1`): compilar el `.vpk` real, descargarlo, deploy FTP a la Vita y gdb batch sobre los parity tests |
| `/progreso` | Fases e hitos con su estado (datos en `src/data/fases.ts`) |
| `/monitor` | Dashboard en vivo del netlog de la Vita, por sesión |
| `/api/monitor/*` | Sesiones, líneas y stream SSE (ver `docs/superpowers/specs/2026-07-01-dashboard-logs-vita-design.md`) |
| `/api/checklist` | GET/POST del checklist (SQLite, validación estricta) |
| `/api/dashboard/*` | `logs` (SSE), `estado`, `topics`, `layout` (SQLite) |
| `/api/taller/*` | `estado`, `build`, `debug`, `deploy`, `job/<id>` (SSE), `vpk` |

### Variables de entorno del servidor

| Variable | Efecto |
|---|---|
| `NETLOG_PORT` (def. 9999) / `NETLOG_DISABLED=1` | Receptor UDP de logs de la Vita para el dashboard. Solo un receptor por puerto: si `tools/netlog-listen.sh` está corriendo, el widget lo indicará. |
| `ZENOH_REST_URL` | URL base de la API REST de `zenoh-bridge-ros2dds` (p. ej. `http://192.168.1.108:8000`, arrancado con `tools/vita-stack.sh bridge up` o `all`). Sin él, el widget de topics lo dice — no inventa datos. |
| `TALLER_ENABLED=1` | Activa el taller (compilador/debug/deploy). **Solo en el PC de desarrollo**: ejecuta procesos locales (cmake, gdb, curl FTP). Nunca en despliegues públicos. |
| `TALLER_REPO_ROOT` | Raíz del repo si el cwd del server no es `web/` (def. `..`). |

**Regla del proyecto:** toda documentación nueva se publica en la web en su
sección. Está automatizado: las colecciones (`src/content.config.ts`) leen
las carpetas del repo con globs, así que basta escribir el `.md` en
`docs/`, `docs/adr/`, `docs/rust/` o `docs/guias-vita/` (o un README de
módulo) y reconstruir el sitio. Sin frontmatter, el título sale del primer
`# encabezado` (`src/lib/docs.ts`); las guías sí llevan frontmatter.

### Cómo funciona el checklist

Cada navegador genera un UUID anónimo (localStorage) y el progreso se
guarda en `data/app.db` (tabla `checklist_progress`). Sin cuentas ni datos
personales.

### Cómo funciona el monitor de logs (`/monitor`)

Reemplaza la lectura manual de `tools/netlog-listen.sh` por una vista web
en vivo. Un proceso Node separado (`scripts/netlog-ingester.mjs`) escucha
el UDP :9999, limpia y clasifica cada línea (normal/hito/fatal) y la
guarda en `data/app.db` (tablas `vita_sessions`/`vita_log_lines`); Astro
expone esos datos por HTTP y por Server-Sent Events. Solo un proceso puede
escuchar el puerto 9999 a la vez, así que `tools/netlog-listen.sh` y este
dashboard son alternativas, no complementos simultáneos.

En Docker, `scripts/docker-entrypoint.sh` arranca ambos procesos: si el
ingestor muere (p. ej. el puerto 9999 falla al abrir), un bucle lo
reinicia solo cada 2s — no hace falta reiniciar el contenedor entero para
recuperar el dashboard.

En desarrollo, arrancar los dos procesos en terminales separadas:
```bash
cd web
pnpm dev          # terminal 1
pnpm ingester     # terminal 2
```

Diseño completo en
`docs/superpowers/specs/2026-07-01-dashboard-logs-vita-design.md`.

## Desarrollo (laptop)

```bash
cd web
corepack enable pnpm   # pnpm sin instalar nada globalmente
pnpm install
pnpm dev               # http://localhost:4321
pnpm build && pnpm start   # probar el build de producción
```

## Producción (Docker)

```bash
cd web
docker compose up -d --build    # http://localhost:4321
```

- La imagen se construye con **contexto en la raíz del repo** (necesita
  `docs/guias-vita/`).
- La base SQLite persiste en `./web/data/` (volumen bind dentro del propio
  repo, todo junto como pide la organización del proyecto).
- El proceso corre como usuario `node` sin privilegios.

## Despliegue futuro en `psvita-ros.jcrex999.com`

El contenedor ya está listo; cuando toque, en el servidor del dominio:

1. Clonar el repo y `cd web && docker compose up -d --build`.
2. Crear el subdominio (registro DNS `A`/`CNAME` de `psvita-ros` →
   servidor).
3. Reverse proxy con TLS apuntando a `:4321`. Ejemplo con Caddy (TLS
   automático):
   ```caddy
   psvita-ros.jcrex999.com {
       reverse_proxy localhost:4321
   }
   ```
   (equivalente con nginx + certbot o Traefik si ya hay uno en el dominio).
4. Si el subdominio final cambia, actualizar `site` en `astro.config.mjs`.

## Decisión: previsualización/emulación en la web

**Descartada por inviable** (se pidió evaluar y solo añadir si era viable):
el único emulador funcional de PS Vita, [Vita3K](https://vita3k.org/), es
nativo de escritorio y no existe port WebAssembly; emular el SO de la
consola en el navegador excede el alcance del proyecto. La alternativa
prevista cuando la Fase 1 se valide en hardware: vídeos/capturas reales en
`/progreso` y, más adelante, telemetría en vivo del grafo ROS2 (la tabla de
SQLite y el patrón de endpoints de `/api/checklist` sirven de base para
ello).

## Mantenimiento de contenido

- **Guías**: editar `docs/guias-vita/*.md` (el build las recoge solas;
  el frontmatter `title/slug/order/description/repo/essential` es el schema
  de la colección en `src/content.config.ts`).
- **Pasos del checklist**: `src/data/checklists.ts` (ids estables: el
  progreso guardado referencia esos ids).
- **Estado de fases**: `src/data/fases.ts`, actualizar al cerrar hitos
  (fuente: `docs/06-bitacora-estado.md`).
