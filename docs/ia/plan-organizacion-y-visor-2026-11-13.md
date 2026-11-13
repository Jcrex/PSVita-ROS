# Plan de subagentes: organización del proyecto (primero) y visor W13 (después)

> **Estado:** EN EJECUCIÓN desde 2026-11-13 (el usuario aprobó: sacar el respaldo, sus cambios de escena son suyos, archivar decisiones descartadas y ejecutar el plan). Origen: PLAN (petición del usuario, 2026-11-13: «prepara el planning de subagentes […] no
> ejecutes nada aún, prioriza la organización del proyecto»). Revisión rápida hecha por el orquestador (Opus 5.5)
> con comandos de solo lectura. Decisiones de diseño → juez **Fable 5.2** (regla del usuario); acciones
> irreversibles (borrar historia de git, push, PR) → **confirmación del usuario**.

---

## 1. Revisión rápida: qué está desorganizado

### 1.1 Raíz del repo

| # | Hallazgo | Evidencia | Propuesta |
|---|---|---|---|
| R1 | **`respaldo-chat-claude/` (12 MB, 29 transcripciones) versionado y ya en `origin/main` público** (PR #2, 2026-11-11; la primera revisión lo dio por no subido porque las referencias de `origin` estaban desactualizadas) | `git ls-tree origin/main` tras `git fetch` = 29; escaneo de secretos: ninguno, solo rutas `/home/jcrex` | **Hecho (2026-11-13, `ef760eb`):** fuera del árbol y en `.gitignore`, copia local conservada. Purgar el historial exigiría *force-push* a `main`: solo si el usuario lo pide |
| R2 | Basura suelta sin versionar: `0001-perfil-vita-ligero.patch` (446 KB, ya aplicado en `68e75c1`), `34-perfil-vita-ligero.md` (versión **anterior** de `docs/34`, difiere en §7), `sesion-kimi.md` (74 B) | `cmp`/`diff` contra `docs/34`; bitácora 2026-11-13 ya dice «se pueden borrar» | Borrar |
| R3 | Carpetas locales sin regla: `.codex/`, `.obsidian/` (sin ignorar); `auditoria/` (compilaciones de ogre/rcutils de la era RViz, doc 04), `Videos/`, `build-host/` (ignoradas) | `git status`, `.gitignore:32-42` | Ignorar `.codex/` y `.obsidian/`; mover `auditoria/` a `toolchains/` o borrarla (no la usa nada vigente) |
| R4 | `AGENTS.md` es una copia de `CLAUDE.md` hecha con sustituir texto («Codex (claude.ai/code)») y ya se desfasa | `AGENTS.md:3` | Dejar `AGENTS.md` en 5 líneas que apunten a `CLAUDE.md` (o generarlo con un script) |
| R5 | `media/` versiona un mp4 | `git ls-files media` | Aceptable si es pequeño; si no, Git LFS o fuera del repo (decide Fable) |
| R6 | Cambios sin commit en `godot/g1-sensores/project.godot` (física a 30 Hz en la Vita, `gl_compatibility`) y `godot/plantillas/mundo/mundo.tscn` (120 líneas) — parecen del editor al abrir/guardar | `git diff --stat` | Revisar el diff: commitear si es intencionado (T1 de doc 34) o descartar |
| R7 | 69 commits locales sin push desde `origin/main`; rama `ccr-44e2db2a-mr6xqr` | `git log origin/main..HEAD` | Tras R1: push + PR (**preguntar antes**, T3) |

### 1.2 `docs/`

| # | Hallazgo | Propuesta |
|---|---|---|
| D1 | 37 documentos planos numerados que mezclan **vigentes** (24–36, 05, 13–15, 17, 18, 22, 23) con **históricos o superados** (04 RViz2, 07–08 web, 09–11 objetivos/mini-rviz, 16 páginas pendientes, 19 plan multiagente, 20–21 Godot 3.5). Sin índice | `docs/README.md` con tabla: nº, título, estado (vigente / histórico / superado por N), última fecha. Mover los históricos a `archivo/docs/` (lote 2 de la auditoría) **sin renumerar** |
| D2 | `docs/06-bitacora-estado.md` tiene **1 845 líneas**; el «estado para retomar» queda enterrado | Dejar en 06 solo el estado vivo + las 3 últimas sesiones; el resto, a `docs/bitacora/2026-MM.md` por mes |
| D3 | `docs/36` tiene **3 913 líneas / 235 KB** (catálogo + 82 fichas de código) | Partirlo: `36` (decisiones, arquitectura, relay, QoS, presupuesto, trampas, tareas) y `36a-catalogo-displays.md` (fichas). Cuando exista el código (V1+), el código pasa a ser la fuente y las fichas se reducen a la tabla |
| D4 | `docs/ia/` mezcla guiones de tutorial, prompts, planes, la auditoría, logs de la Vita (`revision-kimi/*.log`) y los workshops (1,2 MB de posts) | Subcarpetas: `ia/workshops/`, `ia/auditoria/`, `ia/revisiones/` (kimi), `ia/medidas/` (logs de hardware), `ia/prompts-y-planes/`, `ia/tutorial/` (guiones). README con índice |
| D5 | `docs/informes/` (versiones cortas de la auditoría) está congelado: el usuario ya no pide informes cortos | Dejarlo; marcar en su README que es de 2026-11-01 |
| D6 | **Auditoría del 2026-11-01: lotes 0–5 sin estado actualizado** (no consta qué está hecho) | Verificarlos uno a uno y cerrar o reprogramar (lote 3: README raíz, skills `vita-*` aún con el flujo de la Fase 1, `vita-doctor.sh:46`…) |

### 1.3 `godot/`

| # | Hallazgo | Propuesta |
|---|---|---|
| G1 | 17 carpetas al mismo nivel que mezclan **motor** (`ros2_vita`, `loader-patches`, `vitasdk-stubs`), **hitos ya cerrados** (`g4-smoke`, `g5-xrce`, `g6-hmi`, `g7-imu`, `g7b-imu3d`), **productos vivos** (`plantillas`, `g1-sensores`, `g1-unitree`, `rbkairos-plus`, `dron-mapeo`), **histórico** (`godot35`) y **externo** (`rclgd`, sin versionar) | Opción A (barata): `godot/README.md` con tabla por grupo. Opción B: agrupar en `godot/{motor,hitos,apps,historico}/` reescribiendo rutas (SCsub, `tools/*.sh`, docs, skills). **Decide Fable** con el mapa de impacto de O1 |
| G2 | `godot/comun/` solo contiene un `vita_relay.gd.uid` huérfano; en los proyectos `comun` es un enlace simbólico a `../plantillas` | Borrar `godot/comun/` |
| G3 | Los proyectos comparten código con enlaces simbólicos (`comun → ../plantillas`, `robot → ../g1-unitree/robot`, `anim`, `marcha.gd`) sin documentar en un sitio | Documentarlo en `godot/README.md`; comprobar que la exportación `.vpk` los sigue (ya lo hace hoy) |
| G4 | El visor de W13 irá a `godot/plantillas/visor/` (ADR 0013 D15) → `plantillas` crece como «biblioteca común» con un nombre que dice «plantillas» | Fable decide si se renombra (`godot/comun-lib/`) antes de crear el visor, para no mover dos veces |

### 1.4 Resto

- `CLAUDE.md`: la viñeta de `godot/` es un párrafo de 12 líneas difícil de leer; mezcla español e inglés. Reescribirla
  como tabla tras la reorganización (y la de `docs/`).
- `skills/`: `vita-build-package`, `vita-dual-module` y `vita-deploy-logs` siguen con el flujo de la Fase 1 (lote 3).
- Memoria: `estado-proyecto.md` cita commits del 2026-10-30; actualizar al final.

---

## 2. Plan de subagentes — Fase O (organización), PRIMERO

Modelos según `docs/ia/workshops/README.md` §4.6: Haiku = inventarios; Opus = ejecución y revisión; Fable = decisiones.

### Ola O1 — diagnóstico (en paralelo, solo lectura)

| Agente | Modelo | Encargo | Salida |
|---|---|---|---|
| **O1a inventario de rutas** | Haiku | `grep` de toda referencia a `docs/NN-*`, `godot/<carpeta>/`, `res://comun`, `plantillas/` en código, scripts, SCsub, skills, web y docs; contar por destino | `docs/ia/organizacion/O1a-mapa-rutas.json` (destino → lista de `ruta:línea`) |
| **O1b estado de la auditoría** | Opus | Verificar en el código cada punto de los lotes 0–5 (`docs/ia/auditoria/README.md`): hecho / pendiente / obsoleto, con evidencia | `O1b-auditoria-estado.md` |
| **O1c clasificación de docs** | Opus | Para cada doc de `docs/` y `docs/ia/`: estado (vigente / histórico / superado por N), resumen de 1 línea, enlaces entrantes (usa O1a si ya está; si no, `grep`) | `O1c-clasificacion-docs.md` + borrador de `docs/README.md` |
| **O1d raíz y godot** | Haiku | Listado de R1–R7 y G1–G3 con tamaños, si están versionados/ignorados/en `origin`, y qué los referencia | `O1d-raiz-godot.md` |

### Juez O — decisiones (Fable 5.2, tras O1)

Decide con O1a–O1d: G1 (opción A o B), G4 (renombrar `plantillas`), D1 (mover históricos o solo indexar), D2–D4
(partir bitácora, doc 36, subcarpetas de `docs/ia`), R5 (media), y el orden de los movimientos. Salida:
`docs/ia/organizacion/decision-fable.md` + **ADR 0014 «organización del repositorio»** si cambia la estructura.

### Ola O2 — ejecución (en serie: todas tocan rutas y se pisarían)

| Paso | Agente | Modelo | Encargo | Verde |
|---|---|---|---|---|
| O2.0 | — | usuario | **Confirmar R1** (sacar `respaldo-chat-claude/` del historial local con `git filter-repo`/rebase; solo commits sin push) y R6 | confirmación explícita |
| O2a | raíz | Opus | R1 (si se confirma), R2, R3, R4, `.gitignore`; G2 | `git status` limpio salvo lo decidido |
| O2b | docs | Opus | `docs/README.md`, archivar históricos, partir bitácora y doc 36, subcarpetas de `docs/ia`, reescribir enlaces con el mapa de O1a | comprobador de enlaces (O3) sin rotos |
| O2c | godot | Opus | Lo que decida Fable para G1/G4 + reescritura de rutas en SCsub, `tools/`, skills, docs | `godot/test/run_host_tests.sh`, `pruebas/runner.gd` de plantillas, `tools/run-parity-tests.sh`, exportación de `g1-sensores.vpk` en el PC |
| O2d | guías del agente | Opus | `CLAUDE.md` (tablas de `godot/` y `docs/`), `AGENTS.md` mínimo, skills `vita-*` (lote 3), memoria `estado-proyecto.md` | relectura por O3 |

### Ola O3 — verificación (en paralelo)

| Agente | Modelo | Encargo |
|---|---|---|
| **O3a enlaces** | Haiku | Comprobar todos los enlaces Markdown relativos y las citas `ruta:línea` que apunten a archivos movidos |
| **O3b escéptico** | Opus | Revisar el diff completo de la Fase O contra la decisión de Fable; buscar referencias rotas en scripts (`tools/`, `docker/`, SCsub) y en `project.godot` |

Cierre: un commit por paso (`chore(org): …`, `docs(org): …`), entrada en la bitácora y en `tablero-parches.log`.
Push y PR → **preguntar al usuario** (T3).

---

## 3. Plan de subagentes — Fase V (visor W13), DESPUÉS de la Fase O

Fuente: `docs/36` §10 y `docs/ia/workshops/posts/W13-juez-fable.md` §4 (tareas V1–V15). Rutas según quede la Fase O.
Regla común a todos: `--check-only` de cada `.gd` con el editor de host
(`toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64`), prueba de host verde, comentarios en español,
nada de escenas generadas desde JSON (doc 35), un commit por tarea.

### Fase V1 — visor útil con el relay de hoy

| Ola | Agentes (paralelo dentro de la ola) | Modelo | Depende de |
|---|---|---|---|
| V1-a | **V1 núcleo** (`visor_ros`, `canal_display`, `display_ros_3d/2d/hud`, `registro_displays`, `tiempo_ros`, proyecto `godot/visor-ros/`, `pruebas/visor.gd`) | Opus | Fase O |
| V1-b | **V2 primitivas y paleta** · **V4 HUD** (`gestor_hud`, barra, medidor, batería, joy, estado de meta) | Opus ×2 | V1 |
| V1-c | **V3 displays con el relay actual** (scan, path, pose, mapa, robot_joints + arreglos de `vita_relay.gd` de doc 31 §4.4) | Opus | V2 |
| V1-r | **Escéptico** de la fase + `/code-review` del diff | Opus | V1-c |
| V1-hw | Prueba en la Vita (gates G-W13-H0, E-W8-1; ≥ 55 FPS HMI) | **usuario** | V1-r |

### Fase V2 — relay rev. 2 y displays directos

| Ola | Agentes | Modelo | Depende de |
|---|---|---|---|
| V2-a | **V5 esquemas `TIPOS_VISOR`** + displays directos pequeños | Opus | V1 |
| V2-b | **V6 relay rev. 2** (Python + `vc1.gd`, `rosout`, `diag`, `ritmo`, tope de red) · **V7 herramientas que publican** | Opus ×2 | V5 |
| V2-c | **V8 marcadores** · **V9 TF y poses** (`TfLigero` contra `modules/tf-tree/tests/parity_test.c`) | Opus ×2 | V6 |
| V2-r | Escéptico + `/code-review` | Opus | V2-c |
| V2-hw | G-W13-R0, M1, M3; meta con ✕ hasta Nav2 | **usuario** | V2-r |

### Fase V3 — percepción, costmap, inspector

| Ola | Agentes | Modelo |
|---|---|---|
| V3-a | **V10 percepción** (cámara JPEG, det2d/det3d, nube) · **V11 costmap** · **V12 inspector y trazador** | Opus ×3 (archivos disjuntos) |
| V3-r | Escéptico + `/code-review` | Opus |
| V3-hw | E-W8-5, G-W13-M5 | **usuario** |

### Aparte

- **V13 paquete nativo** (`ros_runtime.cpp`: propiedades de `RosQoS`, `latest_only`, tipo resuelto al suscribir,
  contadores; `RosTfListener` sobre `tf-tree`; `modules/viz-decode/` dual Rust+C): Opus en una **worktree**, solo PC,
  cuando toque recompilar la plantilla; diseño fino del módulo dual → Fable.
- **V14 extras solo PC** (nube en GPU, imágenes con shader, octomap, grid_map, marcadores interactivos): Opus, tras V8.
- **V15 documentación** al cerrar cada fase: Haiku (enlaces, citas) + Opus (README de `visor/`, `API_PARITY.md`,
  corregir la cita `xrce_transport.cpp:411-415` en docs 27 y 31).
- Si surge una decisión no prevista en el ADR 0013 → Fable, sin preguntar al usuario.

---

## 4. Lo que necesita al usuario

1. Confirmar **R1** (reescribir los commits locales para quitar `respaldo-chat-claude/`; nada está subido).
2. Decir si los cambios de **R6** (`g1-sensores/project.godot`, `mundo.tscn`) son suyos e intencionados.
3. Pruebas en la Vita de cada fase V (comandos y criterio de verde los dará cada fase).
4. Aprobar push y PR al final de la Fase O y de cada fase V.
