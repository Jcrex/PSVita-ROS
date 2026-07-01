# Web del proyecto — PSVita-ROS

Sitio interactivo que presenta el proyecto a alguien nuevo, publica las
guías de instalación de la Vita y muestra el progreso por fases. Tema
oscuro/azul.

**Stack:** Astro 5 (SSR, adaptador Node standalone) · pnpm (con bloqueo de
build-scripts: solo `better-sqlite3`, `esbuild` y `sharp` aprobados en
`pnpm-workspace.yaml`) · SQLite (better-sqlite3) · Docker.

## Mapa

| Ruta | Qué muestra |
|---|---|
| `/` | Presentación: la idea, el diagrama, la estrategia dual |
| `/arquitectura` | La pila Fase 1 capa a capa, ADRs, la incógnita dura |
| `/docs` + `/docs/<sección>/<slug>` | **Toda la documentación del repo**, por secciones: Fundación y estado (docs/00-06), ADRs, Aprendiendo Rust (docs/rust/) y Documentación del código (READMEs de módulos, app y MCP) |
| `/guias` + `/guias/<slug>` | Las 7 guías (leídas de `docs/guias-vita/` — una sola fuente de verdad) con **checklist interactivo persistente** |
| `/progreso` | Fases e hitos con su estado (datos en `src/data/fases.ts`) |
| `/monitor` | Dashboard en vivo del netlog de la Vita, por sesión |
| `/api/monitor/*` | Sesiones, líneas y stream SSE (ver `docs/superpowers/specs/2026-07-01-dashboard-logs-vita-design.md`) |
| `/api/checklist` | GET/POST del checklist (SQLite, validación estricta) |

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
