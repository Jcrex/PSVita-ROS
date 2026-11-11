# Auditoría 01a — Limpieza A: scripts e infraestructura (informe largo, para la IA)

- **Fecha:** 2026-11-01 · **Rama:** `ccr-44e2db2a-mr6xqr` (HEAD `d3e7c12`)
- **Ámbito:** `tools/` (incl. `hwprobe/`), `docker/`, `vita-app/`, `web/` (sin `node_modules`), `mcp/`,
  `skills/`, ficheros sueltos de la raíz. No existe `.github/`.
- **Método:** `git ls-files` como base; para cada fichero, `git grep -l -F <basename>` (referencias),
  `git log -1 --format=%cs -- <ruta>` (última modificación) y lectura del código. Auditoría **solo
  lectura**: no se ha movido, borrado ni editado nada; no se ha compilado nada.
- Versión corta para el usuario: `docs/informes/01a-limpieza-tools-infra.md`.

---

## 1. Conclusión en una línea

Casi nada del ámbito está muerto: **todos los scripts de `tools/`, `docker/`, `vita-app/scripts/` y
`web/scripts/` tienen al menos una referencia viva**. Lo que hay es (a) tres ficheros basura triviales
para **BORRAR**, (b) siete ficheros vivos con **referencias o datos desactualizados** (ACTUALIZAR), y
(c) un bloque grande «Fase 1» (`vita-app/` + partes de la web) que es **histórico como producto pero
del que dependen piezas vivas de Godot 4**, por lo que **no se puede archivar en bloque** sin antes
extraer esas piezas. Se propone hacerlo en dos fases.

---

## 2. Hallazgo clave: `vita-app/` NO es un histórico aislado

La app de la Fase 1 (`vita-app/src/main.c`, última modificación 2026-07-10, `c3e4d41`) ya no es el
producto: la sustituye la HMI de Godot 4 (`godot/g6-hmi`, G6 verde, `docs/06-bitacora-estado.md`
bloque 2026-10-30). Pero el pipeline **vivo** de Godot 4 usa tres cosas de dentro de `vita-app/`:

| Pieza de `vita-app/` | Quién la usa (vivo, Godot 4) | Evidencia |
|---|---|---|
| `vita-app/rust-modules/` (crate paraguas `vita_modules_rust`) | `tools/build-rust-pic.sh` (G2/G3) | `tools/build-rust-pic.sh` hace `cd "$REPO/vita-app/rust-modules"` y produce `libvita_modules_rust.a` |
| `vita-app/scripts/build-xrce-client-vita.sh` | `godot/ros2_vita/SCsub:27-32`, `godot/ros2_vita/ros_runtime.cpp:59` | Construye `xrce-vita-pic` / `xrce-vita-host` |
| `vita-app/third_party/xrce-vita{,-pic,-host}/` (salida, no versionada) | `godot/ros2_vita/SCsub:32` | `os.path.join(repo, "vita-app", "third_party", "xrce-vita-pic" if is_vita else "xrce-vita-host")` |
| `vita-app/src/netlog.c` | `tools/hwprobe/CMakeLists.txt:24,28` (sonda pendiente) | `set(APP_DIR .../vita-app/src)` + `${APP_DIR}/netlog.c` |

Además, el histórico `godot/godot35/` (ámbito del equipo B) compila directamente fuentes de
`vita-app/src/` (`godot/godot35/modules/microros/SCsub:23-41`: `uxr_glue.c`, `netlog.c`, `teleop.c`,
`config.c`, y `vita-app/rust-modules`). Y la web lee `vita-app/ui/layout.json` **en runtime**
(`web/Dockerfile:55`).

Comprobado que ningún código de Godot 4 usa el netlog: `git grep -n '9999\|netlog'` sobre
`godot/g4-smoke godot/g5-xrce godot/g6-hmi godot/ros2_vita/*.cpp *.h` no devuelve nada (solo una
mención en `godot/ros2_vita/API_PARITY.md:20`, «consola/netlog»). Por tanto el netlog (y sus
receptores) solo sirven hoy a la Fase 1, a Godot 3.5 y a `hwprobe`.

---

## 3. Inventario por carpeta

Leyenda: **C** = CONSERVAR, **AC** = ACTUALIZAR, **AR** = ARCHIVAR, **B** = BORRAR.
«Refs» = nº de ficheros versionados que lo nombran (sin contar el propio).

### 3.1 `tools/`

| Ruta | Últ. cambio | Refs | Clase | Motivo / evidencia |
|---|---|---|---|---|
| `tools/build-c-pic.sh` | 2026-10-29 | 3 | C | G2: compila `modules/*/impl-c/*.c` en PIC (`tools/build-c-pic.sh:25-29`). Vivo |
| `tools/build-godot-template.sh` | 2026-10-30 | 12 | C | Receta de la plantilla G3 (CLAUDE.md, docs/18) |
| `tools/build-pcre2-vita.sh` | 2026-10-30 | 3 | C | Dependencia de la plantilla (docs/18 §4.5) |
| `tools/build-rust-pic.sh` | 2026-10-30 | 9 | C | G2/G3; **depende de `vita-app/rust-modules`** (ver §2) |
| `tools/check-vita-imports.py` | 2026-10-27 | 12 | C | Verificación de la tabla del loader (G2) |
| `tools/deploy-vpk-ftp.sh` | 2026-10-30 | 3 | C | Despliegue actual (skill `vita-deploy-logs`, `godot/README.md`) |
| `tools/env-devpc.sh` | 2026-06-10 | 17 | C | Entorno del PC; lo usan `build-c-pic.sh`, `build-rust-pic.sh` (`: "${VITASDK:?source tools/env-devpc.sh}"`), la web (`web/src/pages/api/taller/build.ts:43`) |
| `tools/env-devpc.fish` | 2026-06-10 | 8 | C | Variante fish: el usuario usa fish en el PC (CLAUDE.md «Shells»). Parece vieja pero es necesaria |
| `tools/export-vita-vpk.sh` | 2026-10-30 | 11 | C | Exportación G4+ (`godot/g4-smoke/export_presets.cfg`, …) |
| `tools/gen_msg_schema.py` | 2026-10-27 | 10 | C | Genera `.rsch` para `ros2_vita` (`godot/ros2_vita/ros_runtime.cpp`) |
| `tools/install-skills.sh` | 2026-10-29 | 5 | C | Instalador de skills (`skills/INSTALAR.md:40-50`) |
| `tools/netlog-listen.sh` | 2026-07-01 | 18 | **AC** | Vivo (lo llama `tools/vita-stack.sh:147`, `tools/hwprobe/README.md`, skill `vita-deploy-logs:89-90`) pero **no filtra el ruido binario** del Kasa (192.168.1.51 → UDP 9999, memoria del proyecto «Red local: Kasa»): `tools/netlog-listen.sh:32-44` imprime toda línea tal cual. El filtro ya existe en `web/scripts/netlog-parser.mjs:7-10` / `web/src/lib/netlog.ts:26-30`. Además su comentario `:8-10` asume la laptop 192.168.1.108 como receptor por defecto |
| `tools/run-parity-tests.sh` | 2026-06-10 | 26 | C | Suite de paridad; recorre `modules/*/` (`:93`) |
| `tools/vita-doctor.sh` | 2026-10-27 | 7 | **AC** | Comprueba rutas que **ya no existen**: `:46` busca `vita-app/third_party/install/lib/libmicroxrcedds_client.a`, pero `vita-app/scripts/build-xrce-client-vita.sh:61` instala en `third_party/xrce-vita$SUFFIX` (`xrce-vita`, `xrce-vita-pic`, `xrce-vita-host`; confirmado con `ls vita-app/third_party`). Así siempre da «falta cliente XRCE». `:49` busca el `.vpk` solo en `vita-app/build*/` (flujo Fase 1), no los `.vpk` de Godot 4 de `tools/export-vita-vpk.sh`. `:57-58` sugiere VitaGL en «platform/vita/vitagl/README.md» cuando la receta real es `toolchains/vitagl-src` (CLAUDE.md, docs/18 §4.5). Falta comprobar `xrce-vita-pic`/`-host`, `toolchains/pic/` y el editor de host |
| `tools/vita-stack.sh` | 2026-10-30 | 8 | C | Envoltorio de alto nivel: delega en `docker/vita-ros.sh` (`:51-65`, `:78-79`) y añade lo que la estación no hace (puente Zenoh con API REST `:103-111` para el dashboard, web, netlog). Solapa parcialmente con `docker/vita-ros.sh` (agente/bridge) — **no es duplicado**: el `bridge-server` de `vita-ros.sh` no abre REST. Comentarios `:3-10` hablan de `rmf_unified`/IR2134 como alternativa: correctos como opción |
| `tools/hwprobe/` (`CMakeLists.txt`, `README.md`, `src/hwprobe.c`) | 2026-10-27 | ~29 | C (pendiente) | **Nunca compilada** (`tools/hwprobe/README.md:3-5`), pero cierra los [?] de `docs/14` §9, que siguen abiertos (bitácora líneas ~1379-1381). Depende de `vita-app/src/netlog.c` (`CMakeLists.txt:24,28`) y de `NETLOG_IP=192.168.1.108` (`:17`, la laptop) → si se archiva `vita-app/src`, hay que mover `netlog.c` antes. Publicada en la web (`web/Dockerfile:31`, `content.config.ts:57`) |

### 3.2 `docker/`

| Ruta | Últ. cambio | Clase | Motivo |
|---|---|---|---|
| `docker/vita-ros.sh`, `Dockerfile`, `docker-compose.yml`, `docker-compose.nvidia.yml`, `entrypoint.sh`, `.env.example`, `.gitignore`, `README.md` | 2026-10-30 | C | Estación actual (G5–G7). `entrypoint.sh` lo copia `Dockerfile:56-62`; `scripts/` montado en `docker-compose.yml:45` |
| `docker/scripts/vita_monitor.py` | 2026-10-30 | C | `vita-ros.sh monitor` |
| `docker/scripts/turtle_odom.py` | 2026-10-30 | C | `vita-ros.sh sim` (`/odom` para `g6-hmi`) |

Nada que limpiar. Matiz: `docker/README.md` dice «Pendiente: Gazebo/RViz y el puente Zenoh entre dos
equipos» (estado a 2026-10-30): verificar con el usuario si sigue así.

### 3.3 `vita-app/` (Fase 1 + Objetivo 2, cerrados 2026-07-07/10)

| Ruta | Clase | Motivo |
|---|---|---|
| `vita-app/rust-modules/` | **C (vivo)** | Godot 4 (`tools/build-rust-pic.sh`). Candidato a **mover** fuera de `vita-app/` en la fase 2 |
| `vita-app/scripts/build-xrce-client-vita.sh` | **C (vivo)** | Godot 4 (`godot/ros2_vita/SCsub:27-32`). Candidato a mover a `tools/` en la fase 2 |
| `vita-app/.gitignore` | C | Ignora `third_party/` (salida viva) |
| `vita-app/src/netlog.{c,h}` | C (de momento) | Lo usa `tools/hwprobe` y `godot/godot35` |
| `vita-app/src/uxr_glue.{c,h}` | C / AR (fase 2) | Referencia de diseño citada en `godot/ros2_vita/xrce_transport.{h,cpp}` y `modules/microros-transport/README.md:17`; compilada solo por godot35 |
| `vita-app/src/main.c`, `teleop.*`, `config*.{c,h}`, `ui*.{c,h}`, `ui_layout.h`, `ui_types.h`, `src/viz/*` | **AR (fase 2)** | Producto sustituido por Godot 4. Pero `teleop.c`/`config.c` los compila `godot/godot35/modules/microros/SCsub:33-36` y `ui_types.h` es espejo de `web/src/lib/ui-layout.ts:22` |
| `vita-app/CMakeLists.txt` | AR (fase 2) | Solo construye la app Fase 1 (`VITA_IMPL`, `:26,72-82`); lo invoca la web (`web/src/pages/api/taller/build.ts:42-50`) |
| `vita-app/tests/*.c`, `scripts/check-{config,teleop,ui-layout,viz-host}.sh`, `scripts/gen-ui-header.mjs`, `ui/layout.json` | AR (fase 2) | Pruebas/codegen de la Fase 1. `ui/layout.json` lo lee la web en runtime (`web/Dockerfile:55`, `web/src/pages/api/taller/ui/*.ts`) |
| `vita-app/README.md` | AR (fase 2) | Publicado en la web (`web/src/content.config.ts:54`) |

`vita-app/src/viz/` (mini-rviz, ADR 0006/0007, Plan B con vitaGL) queda también sustituido por Godot 4
(ADR 0008) — hipótesis: el usuario no piensa retomarlo; confirmar.

### 3.4 `web/`

| Ruta | Clase | Motivo |
|---|---|---|
| `web/localhost:4321` | **B** | Fichero **vacío** (0 bytes) versionado por accidente en `a343f93` (2026-06-10, «feat(web): sección /docs…»). Ninguna referencia. Hipótesis: salió de una redirección de shell tipo `… > localhost:4321` |
| `web/src/lib/taller.ts`, `web/src/pages/taller/*.astro`, `web/src/pages/api/taller/*.ts` | **AC/AR (fase 2)** | El «taller» solo sabe compilar/desplegar la app **Fase 1**: `build.ts:42-50` (`cd vita-app && cmake …`), `deploy.ts:38-40` (`curl -T vita-app/build-*/vita-ros2-hello.vpk`), `taller.ts:151` (ruta del `.vpk`), `debug.ts:43-44`. Para Godot 4 el flujo es `tools/export-vita-vpk.sh` + `tools/deploy-vpk-ftp.sh`. Opciones: actualizarlo a esos scripts, o archivarlo con `vita-app`. Menú en `web/src/layouts/Base.astro:21` y `web/src/pages/index.astro:96`. Últ. cambio 2026-07-07 |
| `web/src/pages/taller/ui.astro`, `web/src/lib/ui-layout.ts`, `api/taller/ui/*` | AR (fase 2, con `vita-app/ui`) | Editor de la UI declarativa vita2d (ADR 0005) de la Fase 1 |
| `web/scripts/netlog-*.mjs`, `vita-monitor-schema.sql`, `docker-entrypoint.sh`, `src/pages/monitor.astro`, `api/monitor/*` | C | Funcionan; útiles para godot35/hwprobe. Hipótesis: quedarán sin uso si Godot 4 no adopta el netlog |
| `web/src/pages/dashboard.astro`, `lib/ros2bridge.ts`, `api/dashboard/*` | C | Usa Zenoh REST (`tools/vita-stack.sh bridge up`), genérico |
| `web/src/pages/comparador/*`, `lib/comparador.ts` | C | Compara C↔Rust de `modules/` (vivo) |
| `web/src/pages/visor3d.astro`, `public/modelos/vitabot.urdf` | C | `visor3d.astro:219` hace `fetch('/modelos/vitabot.urdf')` |
| `web/Dockerfile`, `docker-compose.yml`, `README.md`, `content.config.ts`, resto | C | Ver §5 para los cambios si se archiva |

### 3.5 `mcp/`

| Ruta | Clase | Motivo |
|---|---|---|
| `mcp/ros2-introspection/**` | C | Vivo; el MCP está cargado en esta sesión. `README.md:31` y `rclpy_backend.py:3` citan `robotnik_dev` como sitio de validación (histórico correcto; hoy también valdría `vita_station`) |
| `mcp/.gitkeep` | **B** | Del esqueleto (`6c5bfd0`); la carpeta ya tiene contenido |

### 3.6 `skills/`

| Ruta | Últ. cambio | Clase | Motivo |
|---|---|---|---|
| `skills/godot4-ros-scripting/`, `skills/rclgd/`, `skills/ros2-vita-godot/` | 2026-10-27/29 | C | Godot 4, vivas |
| `skills/vita-build-package/SKILL.md` | 2026-10-27 | **AC** | Describe solo la ruta Fase 1 (CMake+`VITA_IMPL`) y una «ruta Rust — cargo-vita» (`:76-104`: `cargo vita build vpk`, `rustup target add armv7-sony-vita-newlibeabihf`) que **el repo no usa**: el Rust se enlaza con `cargo +nightly rustc --crate-type staticlib -Zbuild-std` (`vita-app/CMakeLists.txt:79`, `tools/build-rust-pic.sh`; regla de CLAUDE.md). Además el target es tier 3 y no se distribuye por `rustup target add` (por eso `-Zbuild-std`). No menciona el flujo actual de Godot 4 (`tools/build-godot-template.sh`, `tools/export-vita-vpk.sh`) |
| `skills/vita-dual-module/SKILL.md` | 2026-10-27 | **AC** | `:29-30` pide `crate-type = ["staticlib"]` en el `Cargo.toml` del módulo, contrario a la regla del repo (módulos `rlib`, ver `modules/mem-pool/impl-rust/Cargo.toml:12-20`, CLAUDE.md). `:33-35` y `:89` hablan de `CMakeLists.txt` por módulo con targets `parity_test_c/rust` vía `cargo-vita`, pero la paridad se ejecuta con `tools/run-parity-tests.sh` y `tests/host_common_flags` (p. ej. `modules/msg-ring/tests/host_common_flags`); 5 de 8 módulos no tienen `CMakeLists.txt` |
| `skills/vita-deploy-logs/SKILL.md` | 2026-10-30 | **AC** | Contradicción interna: `:77` «Validado en hardware (2026-07-01)» vs `:136-142` «todavía no se confirmó… validar en hardware» (el netlog se usa en vivo desde 2026-07-07 en el monitor web, bitácora ~l.572). La parte de logs (`:79-90`) solo vale para `vita-app` (NETLOG_IP baked-in); las apps Godot 4 no mandan netlog (ver §2): falta decir cómo se depura una app Godot 4 (hipótesis: monitor de la estación/agente `-v6`) |
| `skills/INSTALAR.md` | — | C | Coherente (6 skills, `:29`) |
| `skills/.gitkeep` | — | **B** | Del esqueleto; la carpeta tiene contenido |

### 3.7 Raíz

| Ruta | Clase | Motivo |
|---|---|---|
| `README.md` (2026-10-29) | **AC** | `:66` «docs 00-21» (hay `docs/22`); `:76` «módulo ros2_vita (sin compilar)» — falso desde G1–G6; `:98` «paridad C/Rust de los 3 módulos» (son 8, `:67`); el mapa `:64-86` no lista `docker/`; `:69-70` lista solo 3 de los 8 módulos; no menciona `godot/g4-smoke…g7-imu`. Verificación rápida `:96-112` es toda Fase 1 |
| `CLAUDE.md` | **AC** (con cuidado: lo edita el usuario/Claude principal) | `:19` y `:25` dicen que el agente irá en la laptop vía `robotnik_dev`; hoy el agente corre en la estación `docker/` (`vita_agent`) en el PC (`docker/README.md` «Topología»). `:68` (`robotnik_dev`) es histórico correcto |
| `.gitignore`, `.dockerignore` | C | Coherentes. Si se archiva `godot/godot35` o `vita-app`, sus entradas (`.dockerignore`: `vita-app/rust-modules/target/`, `vita-app/third_party/`, `godot/godot35/build/…`; `.gitignore`: `*.vita.opt.32.o`) deben seguir la nueva ruta |
| `media/2026-07-10-*.mp4` (12 MB) y `.jpg` | C | Lo usa `README.md`. Pesa 12 MB en el historial; no se gana nada borrándolo ahora (ya está en `.git`) |
| `.mcp.json`, `build/`, `build-host/`, `auditoria/`, `Videos/` | — | No versionados (`.gitignore`); fuera de la limpieza git |

---

## 4. Plan propuesto

### Carpeta de archivados

`archivo/` en la raíz, **conservando la ruta original dentro** (`archivo/vita-app/…`,
`archivo/web/src/pages/taller/…`) más un `archivo/README.md` que explique qué hay, de cuándo es y qué
lo sustituye. Ventaja: `git log --follow` sigue funcionando y la ruta indica el origen.

Aviso: lo archivado **deja de compilar** tal cual. P. ej. `godot/godot35/modules/microros/SCsub:15`
calcula `repo_root` subiendo 4 niveles; movido a `archivo/godot/godot35/` apuntaría a `archivo/`
y no encontraría `modules/`. Es aceptable para un archivo, pero debe decirse en `archivo/README.md`.

### Fase 1 — segura (no rompe nada)

1. `git rm web/localhost:4321 mcp/.gitkeep skills/.gitkeep`
2. ACTUALIZAR (ediciones, no movimientos): `tools/vita-doctor.sh`, `tools/netlog-listen.sh`,
   `skills/vita-build-package/SKILL.md`, `skills/vita-dual-module/SKILL.md`,
   `skills/vita-deploy-logs/SKILL.md`, `README.md`, `CLAUDE.md` (líneas 19/25).
3. Web: añadir colección para `docs/informes/` (carpeta nueva de esta auditoría; regla de la web,
   CLAUDE.md) en `web/src/content.config.ts` + sección. `docs/` ya se copia entero
   (`web/Dockerfile:27`), así que no hace falta línea COPY. `docs/ia/` queda fuera a propósito
   (`docs/ia/README.md`). Nota para otro equipo: `docs/superpowers/` tampoco tiene colección.

### Fase 2 — necesita decisión del usuario (archivar la Fase 1)

Orden de `git mv` (primero sacar lo vivo, luego archivar):

1. **Sacar lo vivo de `vita-app/`** (propuesta de nombres, hipótesis — decide el usuario):
   - `git mv vita-app/scripts/build-xrce-client-vita.sh tools/build-xrce-client-vita.sh` y cambiar
     dentro `APP_DIR`/`PREFIX` (`:61-62`) a una salida neutral, p. ej. `toolchains/xrce-vita{,-pic,-host}`
     (ya gitignorada). Referencias a cambiar (22 ficheros): `godot/ros2_vita/SCsub:27-32`,
     `godot/ros2_vita/ros_runtime.cpp:59`, `godot/README.md:64`, `tools/vita-doctor.sh:46-48`,
     `README.md`, `web/src/data/checklists.ts`, `docs/guias-vita/vitasdk-toolchain.md`,
     `docs/02,06,10,12,13,18,20,21`, `.dockerignore`, y los históricos de godot35.
   - `git mv vita-app/rust-modules <nuevo>` (p. ej. `rust-modules/` en la raíz — **no** dentro de
     `modules/`, porque `tools/run-parity-tests.sh:93` recorre `modules/*/` y lo trataría como módulo).
     Referencias (15): `tools/build-rust-pic.sh`, `CLAUDE.md`, `.dockerignore`, `docs/06,10,15,19,20,21`,
     `docs/rust/00,02`, `docs/superpowers/*2026-07-12*`, godot35. Las rutas relativas del
     `Cargo.toml` (`../../modules/...`) cambian de profundidad.
   - `git mv vita-app/src/netlog.{c,h}` junto a `tools/hwprobe/src/` (o actualizar
     `tools/hwprobe/CMakeLists.txt:24` a la ruta archivada).
2. **Archivar el resto:** `git mv vita-app archivo/vita-app`.
3. **Web del taller** (o actualizarla a Godot 4 en vez de archivarla):
   `git mv web/src/pages/taller archivo/web/src/pages/taller`,
   `git mv web/src/pages/api/taller archivo/web/src/pages/api/taller`,
   `git mv web/src/lib/taller.ts web/src/lib/taller-client.ts web/src/lib/ui-layout.ts archivo/web/src/lib/`
   (comprobar antes con `git grep` que `taller-client.ts` no lo importa otra página).
   Cambiar: `web/src/layouts/Base.astro:21`, `web/src/pages/index.astro:96`,
   `web/Dockerfile:29` (`COPY vita-app/` → `archivo/vita-app/` si se quiere seguir publicando su README)
   y `:55` (quitar la copia de `vita-app/ui`), `web/src/content.config.ts:54`
   (`vita-app/README.md` → `archivo/vita-app/README.md`), `web/docker-compose.yml` (`TALLER_ENABLED`).
4. Coordinar con el equipo B: si `godot/godot35` va a `archivo/godot/godot35`, cambiar
   `web/src/content.config.ts:56`, `web/Dockerfile:30` (ya copia `godot/` entero; añadir
   `archivo/`), y `.dockerignore` (`godot/godot35/…`). Lo más simple: **una sola línea
   `COPY archivo/ /app/archivo/`** en `web/Dockerfile` y una colección `archivo` con patrón
   `archivo/**/README.md` en `content.config.ts`.

---

## 5. Referencias que habría que cambiar si se archiva (resumen)

| Si se mueve… | Cambiar en |
|---|---|
| `vita-app/` | `web/Dockerfile:29,55`; `web/src/content.config.ts:54`; `.dockerignore` (2 líneas); `web/src/pages/api/taller/{build,deploy,debug}.ts`; `web/src/lib/taller.ts:151`; `web/src/lib/ui-layout.ts:4-22`; `tools/hwprobe/CMakeLists.txt:24`; `tools/vita-doctor.sh:46-49`; `godot/godot35/modules/microros/SCsub:16-41`; `godot/godot35/scripts/build-vita-template.sh:31-40`; `skills/vita-deploy-logs/SKILL.md:79-82`; `README.md:71-75,99-111`; `CLAUDE.md` («Layout»); docs varios (históricos: basta una nota) |
| `vita-app/rust-modules` | ver §4 fase 2 paso 1 (15 ficheros) |
| `vita-app/scripts/build-xrce-client-vita.sh` | ver §4 fase 2 paso 1 (22 ficheros) |
| `web/…/taller*` | `Base.astro:21`, `index.astro:96`, `web/docker-compose.yml` (`TALLER_ENABLED=1`), `web/README.md` |

---

## 6. Preguntas abiertas para el usuario

1. ¿Se archiva la app Fase 1 (`vita-app/`) o se conserva como «app de referencia en C»?
2. ¿El taller web se actualiza al flujo Godot 4 (`export-vita-vpk.sh` + `deploy-vpk-ftp.sh`) o se archiva?
3. ¿Se quiere que las apps Godot 4 manden netlog (lo que mantendría vivos `netlog-listen.sh` y el
   monitor web) o se depura solo por ROS 2?
4. ¿Se va a ejecutar `hwprobe` (docs/14 §9) o se archiva?
