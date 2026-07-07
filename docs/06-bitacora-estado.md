# 06 — Bitácora de estado del proyecto

**Última actualización:** 2026-07-07 (PC: **Objetivo 2 implementado y
compilado** — la app es ahora un mando de teleoperación ROS2 que publica
`geometry_msgs/Twist` en `/cmd_vel` a ~20 Hz desde sticks y botones
(diseño y mapeo en `docs/09-objetivo2-control-robot.md`); la lógica del
mapeo (`teleop.c`) es pura y pasa 39 checks en host; libvita2d quedó
instalada vía vdpm y **ambas variantes del `.vpk` compilan con la UI
vita2d enlazada** (pendiente del hito anterior, resuelto). Falta el
deploy (la Vita estaba apagada/sin FTP durante la sesión) y la
verificación en vivo con `ros2 topic echo /cmd_vel` + turtlesim. Estado
previo: laptop, 2026-07-07, tres bugs reales de la web corregidos tras el
primer uso multi-máquina; la Fase 1 sigue **COMPLETA** y confirmada en
hardware real)
**Para qué sirve este documento:** retomar el proyecto en frío. Responde:
¿dónde nos quedamos?, ¿qué hace cada programa?, ¿qué arquitectura se empleó?,
¿cuál es el siguiente paso exacto?

---

## Dónde nos quedamos (resumen de 1 minuto)

La **Fase 0 (fundación)** está completa y la **Fase 1 (topics ROS2) tiene
todo el código escrito y verificado hasta donde la laptop permite**:

- Los 3 módulos duales (`mem-pool`, `net-udp`, `microros-transport`) pasan
  sus tests de paridad C/Rust en host.
- La app `vita-ros2-hello` está completa (sesión XRCE, pub/sub, logs UDP).
- El MCP `ros2-introspection` está 100% implementado y validado contra un
  grafo ROS2 Jazzy vivo (contenedor `robotnik_dev` de la laptop).
- Existen guías de instalación del homebrew de la Vita y una **web**
  (Astro+SQLite+Docker) que las publica, verificada en contenedor.

- **(2026-06-28, en el PC) Todo lo que el PC desbloqueaba está hecho:** el
  cliente XRCE y los 3 módulos cross-compilan para la Vita, la app se empaqueta
  en `.vpk` (variantes C y Rust), y el MCP quedó registrado en Claude Code.

- **(2026-07-01, en el PC) Primer deploy real en la Vita física:** el `.vpk`
  Rust (`vita-app/build/vita-ros2-hello.vpk`, baked con
  `AGENT_IP`/`NETLOG_IP=192.168.1.108`, la laptop) se subió por **USB**
  (modo USB de VitaShell, documentado en
  `docs/guias-vita/vitashell.md#modo-usb-deploy-sin-red`) e instaló sin
  problema. Al lanzarlo: pantalla negra (**esperado**, la app no dibuja
  nada) y se cierra a los ~5 s — eso **no es un cuelgue**, es el camino
  `fatal:` de `vita-app/src/main.c` (línea ~233,
  `sceKernelDelayThread(5*1000*1000)`) que se dispara si `net_udp_init`,
  la apertura del transporte o `uxr_create_session` fallan. Como el PC no
  corre el agente ni el listener de logs (esos van en la laptop, según la
  topología de red del proyecto), no se pudo leer todavía **por qué**
  falló. Se creó `tools/netlog-listen.sh` (visor de logs UDP con
  timestamp y color, reemplaza el `nc -u -l` manual) y se actualizó la
  skill `vita-deploy-logs` con el flujo real. La Vita ya está en la misma
  red WiFi que la laptop (confirmado por el usuario).

- **(2026-07-01, en la laptop) Sesión de pruebas en vivo — causa raíz
  encontrada:** con la Vita corriendo `vita-ros2-hello`, el agente
  (`docker run --net=host microros/micro-ros-agent:jazzy udp4 --port 8888
  -v6`) y `tools/netlog-listen.sh 9999` arriba, más `ros2 topic echo
  /vita_hello` y `ros2 topic pub /pc_hello ...` corriendo dentro del
  contenedor ROS2 Jazzy (`rmf_unified`): la Vita **sí llega por WiFi** al
  agente (tráfico UDP continuo en el puerto 8888, minutos seguidos), pero
  la sesión XRCE **nunca se establece** — el agente recibe el mismo
  paquete de 13 bytes (reintentos de `CREATE_CLIENT`) una y otra vez y
  **jamás responde** (0 mensajes salientes, sin ningún warning/error ni a
  verbosidad máxima `-v6`, en más de 4400 líneas de log). `/vita_hello`
  nunca publica nada y `/pc_hello` se publica sin confirmación de
  recepción. Además se detectó que **`tools/netlog-listen.sh` no recibió
  ni un solo byte** en toda la sesión, pese a que `main.c` manda un log
  justo después de `netlog_init()` y antes de abrir el transporte (que sí
  funciona) — bug de visibilidad: `main.c:100` no comprueba el valor de
  retorno de `netlog_init()`, así que un fallo ahí queda mudo.
  **Causa raíz de la sesión XRCE:** desajuste de versión de protocolo.
  El contenedor `microros/micro-ros-agent:jazzy` corre
  `libmicroxrcedds_agent.so.2.4.3` (confirmado inspeccionando el
  contenedor), pero `vita-app/scripts/build-xrce-client-vita.sh` compila
  el cliente con `XRCE_TAG=v3.0.0` (línea 40). El *release note* oficial
  de eProsima para el cliente v3.0.0 dice explícitamente: *"This version
  is not compatible with eProsima Micro XRCE-DDS Agent version < v3.0.0"*
  (es un release de conveniencia solo para emparejar la major version del
  Agent v3.0.0). El agente v2.4.3 recibe el `CREATE_CLIENT` del cliente
  v3.0.0, no lo reconoce como válido para su versión de protocolo y lo
  descarta en silencio — de ahí el silencio total incluso a verbosidad
  máxima. **No es un problema de red, de sceNet, ni de los módulos
  duales** — la incógnita dura sigue sin resolverse, pero ahora se sabe
  exactamente por qué y cómo arreglarlo (ver "Próximos pasos").

- **(2026-07-01, en el PC) Fix del desajuste de versión aplicado:** en
  `vita-app/scripts/build-xrce-client-vita.sh:40` se cambió
  `XRCE_TAG="${XRCE_TAG:-v3.0.0}"` por `v2.4.3` (coincide con el agente
  `microros/micro-ros-agent:jazzy`). Se confirmó además que `CDR_TAG`
  (v2.0.1) sigue siendo correcto: el `CMakeLists.txt` del cliente v2.4.3
  fija `_microcdr_version=2.0.1` `EXACT REQUIRED`, igual que v3.0.0 —
  no hacía falta tocarlo. Se borró `vita-app/third_party/` y se
  recompiló desde cero (`libmicrocdr.a` + `libmicroxrcedds_client.a`,
  ambas ELF ARM, sin errores). De paso se arregló el bug de visibilidad
  de `vita-app/src/main.c:100`: ahora comprueba el valor de retorno de
  `netlog_init()` y avisa por `sceClibPrintf` si falla, para no quedarse
  ciego si el socket de logs no abre. Las dos variantes del `.vpk` se
  regeneraron limpias (`vita-app/build-c/` y `vita-app/build-rust/`,
  ~77 KB cada una) y la variante Rust se subió por **FTP** (modo FTP de
  VitaShell, `curl -T … ftp://192.168.1.94:1337/ux0:/`) a la Vita, que
  ahora tiene esa IP en la red WiFi del proyecto. **Falta instalar el
  `.vpk` desde VitaShell en la Vita y repetir la prueba en vivo (agente +
  netlog) desde la laptop** — ver "Próximos pasos".

- **(2026-07-01, en la laptop) Incógnita dura RESUELTA — confirmado en
  hardware:** con el `.vpk` Rust reconstruido (cliente XRCE v2.4.3)
  instalado en la Vita (`192.168.1.94`) y, en la laptop, el agente
  (`docker run -it --rm --net=host microros/micro-ros-agent:jazzy udp4
  --port 8888 -v6`) y `tools/netlog-listen.sh 9999` arriba: el log del
  agente muestra `create_client` → `session established` →
  `create_participant`/`create_topic` (x2) /`create_publisher`/
  `create_datawriter`/`create_subscriber`/`create_datareader` → y luego
  `DataWriter.cpp | write` repitiéndose cada ~1 s con el contenido exacto
  que manda la Vita (`"hola desde la vita #0"` … `#17`, incrementando).
  El netlog confirma `*** SESION XRCE ESTABLECIDA: incognita dura OK ***`
  en **4 lanzamientos distintos** de la app (17:36:34, 17:42:42, 17:47:38,
  17:52:35) — resultado reproducible, no un golpe de suerte. El
  diagnóstico de la sesión anterior era exacto: era 100% el desajuste de
  versión de protocolo del cliente XRCE, nada de red/sceNet/módulos.
  (Nota menor: el netlog muestra algo de ruido binario antes de la
  primera línea de texto en cada sesión — probablemente arrastre de un
  paquete UDP truncado/reordenado del propio socket, no afecta al
  resultado; no investigado más a fondo.)

- **(2026-07-01, en la laptop) Criterio 2 bloqueado — segunda causa raíz
  encontrada y resuelta, sin tocar la Vita ni el PC:** con la sesión XRCE
  ya establecida, `ros2 topic list` dentro de `rmf_unified` **sí** mostraba
  `/vita_hello` con publisher/subscriber "emparejados" (1/1), pero
  `ros2 topic echo /vita_hello` no recibía nada, y el netlog tampoco
  mostraba nunca `/pc_hello recibido` pese a que `ros2 topic pub` llevaba
  cientos de mensajes publicados. Se descartó primero que fuera un
  problema general del entorno: un pub/sub normal (`/test_sanity`) dentro
  del propio contenedor `rmf_unified` funcionó sin problema. La causa
  real: el contenedor del agente (`docker run --net=host ...`, sin más
  flags) tiene `IpcMode: private`, mientras que `rmf_unified` corre con
  `IpcMode: host` — **namespaces IPC distintos**. Fast-DDS (la librería DDS
  de ambos) usa memoria compartida (`/dev/shm`) para transportar datos
  entre procesos del mismo host, y Docker **no comparte `/dev/shm` entre
  contenedores salvo que compartan namespace IPC**. El *discovery* SPDP
  (por UDP multicast) sí funciona con solo `--net=host`, por eso los
  topics se veían "emparejados" — pero los datos reales nunca cruzaban.
  Confirmado con la documentación oficial de eProsima (Fast DDS docs,
  sección "Leveraging Fast DDS SHM in Docker deployments"): el fix
  estándar es añadir `--ipc=host` al contenedor. Se relanzó el agente
  como `docker run -d --net=host --ipc=host microros/micro-ros-agent:jazzy
  udp4 --port 8888 -v6`, se relanzó `vita-ros2-hello` en la Vita (sesión
  nueva) y **ambas direcciones del criterio 2 se confirmaron en vivo,
  simultáneamente**: `ros2 topic echo /vita_hello` mostrando
  `"hola desde la vita #14"` … `#18` incrementando, y el netlog mostrando
  `[vita-ros2] /pc_hello recibido: "hola desde el pc"` +
  `criterio 2 de la Fase 1 CUMPLIDO` repitiéndose cada segundo. Los tres
  docs que documentan el comando de arranque del agente
  (`docs/05-setup-entorno-cachyos.md`, `docs/02-arquitectura-fase1-microros.md`,
  `vita-app/README.md`) se actualizaron con `--ipc=host` y la explicación,
  para que este muro no se repita.

**Fase 1 (objetivo 1: topics ROS2) COMPLETA y confirmada en hardware
real**: incógnita dura resuelta + criterio 1 (`/vita_hello` visible) +
criterio 2 (`/pc_hello` recibido), los tres verificados en la misma
sesión en vivo.

- **(2026-07-02, en la laptop) Dashboard web de logs en vivo (`/monitor`)
  — implementado, revisado y mergeado a `main`.** Motivación: usar 4
  terminales a mano (agente, `netlog-listen.sh`, `ros2 topic echo/pub`)
  para verificar la Fase 1 no escala; se decidió reemplazar solo la
  lectura de logs de la Vita por una vista web (los topics de ROS2 se
  quedan en terminal, es una decisión explícita — ver spec). Brainstorm →
  spec → plan → implementación con `subagent-driven-development` (7
  tareas, revisión por tarea + revisión final de toda la rama):
  - Spec: `docs/superpowers/specs/2026-07-01-dashboard-logs-vita-design.md`.
  - Plan: `docs/superpowers/plans/2026-07-01-dashboard-logs-vita.md`.
  - Arquitectura: `web/scripts/netlog-ingester.mjs` (proceso Node nuevo,
    UDP :9999 → SQLite, mismo `web/data/app.db`) + 4 endpoints Astro
    (`/api/monitor/sessions`, `/session/[id]`, `/status`, `/stream` SSE)
    + la página `/monitor` (historial por sesión + vista en vivo
    colorada como `netlog-listen.sh`, autoscroll, indicador 🟢/⚪).
    `tools/netlog-listen.sh` se mantiene como alternativa de terminal
    (solo uno de los dos puede tener el puerto 9999 a la vez).
  - Docker: `web/scripts/docker-entrypoint.sh` arranca los dos procesos
    (Astro + ingestor) en el mismo contenedor; el ingestor se reinicia
    solo si muere. Puerto UDP 9999 publicado en `docker-compose.yml`
    junto al 4321 ya existente.
  - La Task 6 (la página en sí) pasó por **4 rondas de revisión** que
    encontraron y corrigieron bugs reales antes de llegar a producción:
    un bucle infinito de recarga (mala interpretación del evento SSE
    `session-changed`), líneas de log duplicadas (el SSE reenvía todo el
    historial en cada reconexión, sin un "watermark" de dedup), un caso
    borde de arranque sin sesiones todavía, y falta de color/autoscroll
    en el primer render servidor. La Task 7 (Docker) encontró y corrigió
    un bug real del propio plan: un `set -e` en el script de arranque
    mataba el bucle de reinicio del ingestor en su primer fallo.
  - Revisión final de toda la rama (10 commits): **aprobada para
    mergear**, sin hallazgos críticos ni importantes. Se aplicaron dos
    pulidos menores que señaló: ordenar sesiones por `id` en vez de
    `started_at` (coherencia con el ingestor), y actualizar el spec para
    reflejar los 4 endpoints reales y el `docker-entrypoint.sh`.
  - **Verificado solo con paquetes UDP simulados** (Node one-liners +
    `sqlite3` CLI + `docker compose up` real) — funciona de punta a
    punta en ese sentido, pero **nunca se probó con la Vita real
    mandando su netlog de verdad**. Eso es lo único que falta (ver
    "Próximos pasos").

Solo quedan tareas de cierre (ver "Próximos pasos") antes de empezar el
Objetivo 2 (control de robot).

---

## Qué hace cada pieza (mapa de programas y funciones)

### `modules/` — los 3 módulos duales de la Fase 1

Cada uno sigue la estrategia de `docs/03`: header C = contrato único,
`impl-c/` e `impl-rust/` equivalentes, `tests/parity_test.c` corre contra
ambas. Detalle por módulo en su `README.md`.

| Módulo | Funciones clave | Para qué |
|---|---|---|
| `mem-pool` | `mem_pool_create/alloc/free`, `required_size` | Asignador de bloques fijos sin malloc (free-list intrusiva, detección de doble free). Lo usará micro-ROS para no fragmentar el heap en sesiones largas. |
| `net-udp` | `net_udp_init/open/close/send/recv` | Capa de red más baja: sceNet en la Vita / POSIX en host, tabla estática de 4 sockets, parser IPv4 propio, timeouts por llamada. |
| `microros-transport` | `microros_transport_open/close/write/read` | Los 4 callbacks del transporte custom de micro-ROS, con la convención uxr (timeout ≠ error). El núcleo de la incógnita dura. |

**Cómo se testean en la laptop:** `tools/run-parity-tests.sh [módulo]` —
compila la batería con gcc contra impl-c y contra el staticlib Rust
(cargo local o docker `rust:1-slim`). Todos verdes a fecha de esta bitácora.

### `vita-app/` — la app homebrew de la Fase 1

- `src/main.c`: flujo completo → `net_udp_init` → netlog → transporte →
  `uxr_create_session` (**si esto devuelve true, la incógnita dura está
  resuelta**) → entidades DDS por XML (`rt/vita_hello`, `rt/pc_hello`,
  tipo `std_msgs::msg::dds_::String_`) → bucle: publica 1 Hz, atiende la
  sesión, sale con START.
- `src/uxr_glue.c`: adapta nuestros 4 callbacks a `uxrCustomTransport`
  (único archivo que ve headers de micro-ROS).
- `src/netlog.c`: logs por UDP a la laptop (`nc -u -l -p 9999`) usando
  nuestro propio net-udp.
- `rust-modules/`: crate paraguas → un solo `libvita_modules_rust.a` con
  los 3 módulos (regla: un binario, un staticlib Rust).
- `scripts/build-xrce-client-vita.sh`: cross-compila microxrcedds_client
  para armv7/newlib (perfil custom transport, sin POSIX).

### `mcp/ros2-introspection/` — introspección ROS2 para Claude Code

6 tools (`list_topics`, `list_nodes`, `get_topic_type`,
`get_message_definition`, `echo_topic`, `list_interfaces`).
`FakeBackend` para tests sin ROS2 (5 pasan en laptop); `RclpyBackend`
completo y **validado el 2026-06-10 contra un grafo Jazzy vivo** con
publisher real (echo, definiciones de mensajes, errores). Falta solo
registrarlo en el Claude Code del PC (`README.md` del MCP).

### `web/` — el sitio del proyecto

Astro 5 SSR + better-sqlite3 + Docker. Páginas: portada, arquitectura,
guías (lee `docs/guias-vita/*.md` directamente — sin duplicar contenido)
con checklist interactivo persistente en SQLite, progreso por fases
(`src/data/fases.ts` ← **actualizar al cerrar hitos**), y **`/monitor`**
(dashboard en vivo del netlog de la Vita — ver bloque de arriba,
2026-07-02). DB y volúmenes en `web/data/` dentro del repo.
`cd web && docker compose up -d --build` → `localhost:4321`. En
desarrollo, el ingestor del monitor va aparte: `pnpm dev` (terminal 1) +
`pnpm ingester` (terminal 2). Preparada para `psvita-ros.jcrex999.com`
(ver `web/README.md`). Emulación en navegador: evaluada y descartada
(Vita3K no tiene port WASM); decisión documentada.

### `docs/`

- `00-05`: la fundación (visión, hardware, arquitectura Fase 1, estrategia
  dual, investigación rviz2, setup del PC).
- `adr/0001-0004`: decisiones registradas.
- `rust/00-02`: serie de aprendizaje de Rust ligada al código del repo
  (herramientas, lenguaje, FFI/no_std/unsafe + glosario C↔Rust).
- `guias-vita/`: 7 guías homebrew con frontmatter (las consume la web).
- `superpowers/`: specs y planes de brainstorming (Fase 0; dashboard
  `/monitor` 2026-07-02).

### `tools/` y `skills/`

- `tools/run-parity-tests.sh`: el verificador de paridad (host).
- `tools/sync-to-devpc.sh` + test: legado de sync (la transferencia real es git).
- `skills/`: las 3 skills de Claude Code para el PC (scaffold dual, build
  .vpk, deploy+logs).

---

## Decisiones de arquitectura tomadas en esta sesión

1. **Doble plataforma dentro de cada implementación** (`#ifdef __vita__` /
   `#[cfg(target_os = "vita")]`): la rama host existe para testear la
   lógica real en la laptop; la rama Vita se valida en el PC/hardware.
2. **Parser IPv4 propio** idéntico en C y Rust: el comportamiento ante
   entradas inválidas no depende de la libc de la plataforma.
3. **Sin malloc en los módulos**: tablas estáticas y buffers del llamador
   (apto para embebido, casos de agotamiento testeados).
4. **Crates Rust de módulo = rlib**; el `.a` se genera con
   `cargo rustc --crate-type staticlib` solo donde se necesita. Motivo:
   staticlib como dependencia exige panic_handler propio y colisiona al
   componer crates (error vivido y documentado).
5. **Crate paraguas** para la app: un binario = un staticlib Rust.
6. **El transporte no incluye headers de micro-ROS**: expone semántica uxr
   con tipos propios; el glue (5 líneas por callback) vive en la app.
7. **Timeout ≠ error** en read (convención uxr): si se confundieran, el
   cliente XRCE abortaría la sesión en cada espera vacía.
8. **El agente micro-ROS correrá en la laptop** (no en el PC): el PC está
   en ethernet y la Vita solo tiene WiFi; la laptop está en ambas y tiene
   ROS2 Jazzy (docker `robotnik_dev`).

---

## Cómo verificar que todo sigue verde (en la laptop)

```bash
tools/run-parity-tests.sh                 # paridad C/Rust de los 3 módulos
cd mcp/ros2-introspection && .venv/bin/python -m pytest tests/ -q
cd web && pnpm build                      # o: docker compose up -d --build
```

---

## Próximos pasos exactos

### En el PC (CachyOS, con VitaSDK) — desbloquea el resto

1. ~~Seguir `docs/05-setup-entorno-cachyos.md`~~ **HECHO (2026-06-10):**
   todo el entorno quedó instalado **dentro del repo, en `toolchains/`**
   (gitignorado), sin tocar `/usr/local` ni el perfil global:
   - VitaSDK v2.540 (gcc 15.2.0 + vita-elf-create/make-fself/mksfoex/pack-vpk)
   - rustup con nightly 1.98.0 + `rust-src` (`RUSTUP_HOME`/`CARGO_HOME` locales)
   - `cargo-vita` 0.2.2 y cmake 4.3.3 portable (no hay sudo para pacman)
   - imagen docker `microros/micro-ros-agent:jazzy` descargada (el tag existe)

   **Antes de compilar, cargar el entorno:** `source tools/env-devpc.fish`
   (o `tools/env-devpc.sh` en bash/zsh). Exporta `VITASDK` y mete todo al PATH.
2. ~~`cd vita-app && ./scripts/build-xrce-client-vita.sh`~~ **HECHO (2026-06-28):**
   `libmicrocdr.a` + `libmicroxrcedds_client.a` cross-compiladas (ELF ARM EABI5)
   en `vita-app/third_party/xrce-vita/`. El muro **no era newlib** (el cliente
   compila perfecto con perfil custom-transport-only); era el superbuild de
   eProsima que no reenvía el toolchain. El script se reescribió a dos cmake
   separados (microcdr + uclient) encadenados por `CMAKE_PREFIX_PATH`. Detalle
   en `docs/02` (sección "Muro previo (compilación)"). `third_party/` quedó
   gitignored.
3. ~~`cmake … -DVITA_IMPL=c … && cmake --build build` → `.vpk`; repetir con
   `-DVITA_IMPL=rust`~~ **HECHO (2026-06-28): las DOS variantes generan
   `.vpk` instalable** (`build/vita-ros2-hello.vpk`, ~77 KB, con `eboot.bin`
   + `param.sfo`). El segundo muro (Rust tier 3) **no apareció**: el target
   `armv7-sony-vita-newlibeabihf` viene integrado en rustc y compila con
   `-Zbuild-std`. Sí hubo un muro nuevo: `vita-elf-create: Invalid relocation
   type 25!` al empaquetar — lo causaba el código **PIC** de las libs XRCE
   (relocaciones GOT `R_ARM_BASE_PREL`). Solución: recompilarlas con
   `UCLIENT_PIC=OFF`/`UCDR_PIC=OFF` (ya en el script). El homebrew de la Vita
   es estático/position-dependent. **Pendiente de la app:** las IPs del agente
   y del netlog están baked-in en el `.vpk` (`AGENT_IP`/`NETLOG_IP` =
   192.168.1.108 por defecto en `CMakeLists.txt`); al probar en hardware,
   reconfigurar con `-DAGENT_IP=…` si la laptop cambia de IP.
4. ~~Compilación cruzada de los módulos sueltos~~ **HECHO (2026-06-28):** los
   3 módulos cross-compilan standalone en C y Rust (6 libs ELF ARM). Se
   arreglaron dos bugs latentes de los CMakeLists de módulo: (a) el build C de
   `microros-transport` no añadía el include de `net-udp` (necesita
   `net_udp.h`); (b) en Rust+cross el `add_custom_target` no tenía `ALL`, así
   que `cmake --build` no emitía el `.a` (nadie lo consumía, con la paridad
   desactivada en cross). El Rust de los módulos ya estaba probado vía el crate
   paraguas de la app.
5. ~~Registrar el MCP en el Claude Code del PC~~ **HECHO (2026-06-28):**
   `.mcp.json` local (gitignored; ruta del venv específica de la máquina) en
   la raíz, apuntando al venv del MCP. Como el host del PC no tiene `rclpy`
   (ROS2 vive en contenedores), se hizo el server robusto: `main()` elige
   backend por `ROS2_INTROSPECTION_BACKEND` y cae a `FakeBackend` con aviso si
   no hay rclpy (ya no crashea). En el PC hay contenedores ROS2 Jazzy
   utilizables (`~/Documentos/IR2134/DOCKER`, open-RMF) para datos reales si se
   ejecuta el server dentro. Falta: **reiniciar Claude Code** para que cargue
   el MCP (no se puede hot-load en la sesión actual). Plantilla y receta de
   contenedor en el README del MCP.

### Con la Vita (hardware) — **siguiente paso exacto, en el PC**

6. ~~Preparar la consola con `docs/guias-vita/` (VitaShell + PrincessLog)~~
   **HECHO (2026-07-01):** VitaShell ya estaba instalado; el `.vpk` se
   subió por USB (`docs/guias-vita/vitashell.md#modo-usb-deploy-sin-red`)
   e instaló. La Vita ya está en la misma WiFi que la laptop.
7. ~~Repetir el lanzamiento con el agente y el listener corriendo en la
   laptop~~ **HECHO (2026-07-01):** sesión de pruebas completa (agente +
   netlog + `ros2 topic echo/pub` en `rmf_unified`). Resultado: **causa
   raíz encontrada, no es un problema de red** — ver el bloque de arriba.
8. ~~En el PC: recompilar el cliente XRCE con el tag correcto y arreglar
   la visibilidad de `netlog_init`~~ **HECHO (2026-07-01):**
   `XRCE_TAG` pasó a `v2.4.3` en
   `vita-app/scripts/build-xrce-client-vita.sh:40` (`CDR_TAG=v2.0.1` se
   confirmó correcto sin cambios, ver bloque de arriba). Cliente
   recompilado, `.vpk` regenerado en las dos variantes
   (`vita-app/build-c/`, `vita-app/build-rust/`) y la variante Rust
   subida por FTP a la Vita (`192.168.1.94:1337`, modo FTP de VitaShell).
   `vita-app/src/main.c:100` ahora comprueba el retorno de `netlog_init`.
   **Pendiente manual en la Vita:** entrar a VitaShell → `ux0:/` →
   `vita-ros2-hello.vpk` → instalar (sobrescribir la versión anterior).
9. ~~Repetir la prueba (agente + netlog) desde la laptop~~ **HECHO
   (2026-07-01): incógnita dura RESUELTA y confirmada en hardware** — ver
   el bloque de arriba (4 lanzamientos con `SESION XRCE ESTABLECIDA` +
   `DataWriter.write` publicando en bucle).
10. ~~Cerrar el criterio 2 formal, en la laptop~~ **HECHO (2026-07-01):**
    `ros2 topic echo /vita_hello` mostró los mensajes de la Vita en vivo
    y el netlog confirmó `/pc_hello recibido` + `criterio 2 CUMPLIDO`.
    Bloqueado a mitad de camino por un segundo muro (namespace IPC no
    compartido entre contenedores Docker — ver bloque de arriba),
    resuelto con `--ipc=host` en el agente, sin tocar la Vita ni el PC.
11. ~~Actualizar esta bitácora y `web/src/data/fases.ts`~~ **HECHO
    (2026-07-01):** hito "Criterios: /vita_hello visible + /pc_hello
    recibido" marcado `hecho`. **Fase 1 (objetivo 1) cerrada por
    completo.**

### Dashboard `/monitor` — siguiente paso exacto, con la Vita encendida

12. **PENDIENTE:** confirmar con la Vita real (no solo con paquetes UDP
    simulados):
    ```bash
    cd web
    docker compose up -d --build      # o: pnpm dev + pnpm ingester en dos terminales
    ```
    Lanzar `vita-ros2-hello` desde la LiveArea y abrir
    `http://localhost:4321/monitor` en el navegador:
    - Debe aparecer una sesión nueva con las mismas líneas que antes se
      leían en `tools/netlog-listen.sh` (`red inicializada`, `SESION XRCE
      ESTABLECIDA`, `entidades creadas`), en vivo y coloreadas (verde los
      hitos, rojo si hay `FATAL`).
    - Publicar desde ROS2 en `/pc_hello` y confirmar que el netlog
      `/pc_hello recibido` + `criterio 2 CUMPLIDO` aparecen en la web sin
      recargar la página.
    - Si algo no llega o se ve raro, es la primera vez que este código
      toca la Vita real — revisar `docker compose logs` (busca
      `[netlog-ingester]`) antes de sospechar del hardware.
13. Si todo va bien, marcar este punto como confirmado aquí y cerrar el
    tema del dashboard. Si aparece un muro nuevo, documentarlo igual que
    los de la Fase 1 (síntoma exacto + causa raíz + fix).

### Objetivo 2 — control de robot: **siguiente paso exacto (con la Vita)**

- ~~Diseño detallado del Objetivo 2~~ **HECHO (2026-07-07):** `docs/09` +
  implementación completa + `.vpk` compilados — ver el bloque de arriba.
- **PENDIENTE (hardware):**
  1. ~~Subir el `.vpk` por FTP~~ **HECHO (2026-07-07):** está en `ux0:/`
     (165267 bytes, verificado). Falta: **instalar desde VitaShell**
     (sobrescribe "Vita ROS2 Hello").
  2. En la laptop: agente (`docker run -it --rm --net=host --ipc=host
     microros/micro-ros-agent:jazzy udp4 --port 8888 -v6`) + netlog.
  3. Verificar: `ros2 topic echo /cmd_vel` siguiendo los mandos según la
     tabla de docs/09, y la prueba reina con turtlesim
     (`--ros-args -r /turtle1/cmd_vel:=/cmd_vel`).
  4. Marcar los dos hitos `bloqueado-hw` de `fase-2` en
     `web/src/data/fases.ts` y cerrar el Objetivo 2 aquí.
- Levantar la web con docker y dejarla corriendo.
- Más entradas en `docs/rust/` a medida que aparezcan construcciones nuevas.
- Cuando llegue el dominio: DNS + reverse proxy (receta en `web/README.md`).

- **(2026-07-06, en el PC) Decisión: preparar la web hacia el Objetivo
  3/4 por adelantado.** El usuario pidió empezar ya la infraestructura web
  necesaria para el Objetivo 3/4 (rviz2 en la Vita + visualización),
  aunque el Objetivo 2 (control) no haya empezado. Se documentó en
  `docs/07-requisitos-web-ide.md` (recopilación de requisitos de la web:
  dashboard ROS2 editable, editor de la app/VPK, visor URDF/SDF/3D,
  comparador C++↔Rust, compilador web→`.vpk`→Vita, debug integrado,
  tutorial del SDK). Entran en alcance activo ya: el visor 3D/URDF/SDF
  standalone (sin tocar la Vita) y la base del compilador web — esta
  sesión corre en el propio PC de desarrollo (`cachyos-x8664`,
  `192.168.1.65`, `toolchains/vitasdk/` presente), así que el compilador
  puede diseñarse primero como invocación local del toolchain (sin SSH/
  runner remoto) y añadir la capa remota después, para cuando la web
  vuelva a servirse desde la laptop u otro host. Lo que sigue sin empezar:
  el diseño detallado del Objetivo 2 y la integración real de assets
  3D/URDF/SDF *dentro* de la app de la Vita (bloqueada por la incógnita de
  `docs/04-investigacion-portabilidad-rviz2.md`).

- **(2026-07-06, en el PC) Arranca formalmente la fase de desarrollo de la
  web.** Tras repasar de nuevo el Objetivo 2, el usuario decidió darle
  prioridad ahora al desarrollo real de la web por encima del diseño
  detallado del Objetivo 2 (que sigue pendiente, sin empezar). Se declaró
  en `docs/08-fase-desarrollo-web.md`, con alcance limitado a los seis
  frentes que `docs/07-requisitos-web-ide.md` ya identificó como no
  bloqueados: comparador C++/Rust, tutorial del SDK de VitaSDK, dashboard
  ROS2 editable, debug de módulos duales en host, visor 3D/URDF/SDF
  standalone y la base local del compilador web. `web/src/data/fases.ts`
  ganó una entrada `fase-web` para seguirle el estado desde `/progreso`.
  Primer hito definido (ver `docs/08`): comparador navegable + tutorial
  publicado + visor cargando un modelo de prueba + un widget del dashboard
  con datos reales — todo pendiente todavía, ninguno arrancado aún.

- **(2026-07-06, en el PC) Primer hito de la fase web ALCANZADO — los seis
  frentes implementados y verificados en la web real** (no maquetas; cada
  backend se probó con datos/procesos reales en esta misma sesión):
  1. **Comparador C↔Rust** (`/comparador`, `/comparador/<módulo>`): split
     view de los 3 módulos duales con resaltado shiki, el header-contrato
     colgable arriba y "qué mirar al comparar" por módulo. Lee las fuentes
     reales de `modules/*` en build (prerender); nada duplicado.
  2. **Tutorial del SDK** (`docs/guias-vita/vitasdk-toolchain.md`, sale en
     `/guias` con checklist propio): VitaSDK de punta a punta —
     toolchain/stubs/newlib, cmake (`vita.toolchain.cmake` + `vita.cmake`),
     el pipeline `vita-elf-create → vita-make-fself → vita-mksfoex →
     vita-pack-vpk`, anatomía del `.vpk` y los muros reales ya vividos
     (PIC/reloc 25, superbuild, versión XRCE).
  3. **Dashboard ROS2 editable** (`/dashboard`): el backend Astro abre él
     mismo el socket UDP del netlog (puerto 9999, `src/lib/netlog.ts`) y lo
     sirve por **SSE** — widget de logs en vivo con filtro/pausa; widget de
     salud XRCE (IP de la Vita, último paquete, hitos "SESION XRCE
     ESTABLECIDA" y "/pc_hello recibido" detectados en el propio stream);
     widget de topics vía comando configurable `ROS2_TOPICS_CMD`
     (**verificado contra el grafo Jazzy vivo del contenedor
     `robotnik_dev` del PC**). Layout añadir/quitar/reordenar persistido en
     SQLite por client-id (patrón del checklist). Verificado end-to-end
     mandando datagramas UDP reales al 9999 y leyendo el SSE.
  4. **Visor 3D/URDF/SDF** (`/visor3d`): three.js con parser URDF propio
     (primitivas + mallas STL/OBJ/DAE adjuntas, materiales, jerarquía de
     joints con **sliders** para revolute/continuous/prismatic, ejes
     Z-arriba→Y-arriba), SDF básico (links por pose), drag&drop
     multi-archivo y modelo de prueba incluido
     (`web/public/modelos/vitabot.urdf` — robot diferencial con la Vita de
     "cara", carga al entrar).
  5. **Debug de módulos duales en host** (`/taller/debug`): compila el
     parity test vía `tools/run-parity-tests.sh` (con `-g`) y corre **gdb
     --batch** con guion editable (recetas incluidas), salida en vivo.
     Verificado: breakpoint en `mem_pool_alloc`, backtrace hasta
     `parity_test.c` y `info args` reales. De paso quedó confirmado que
     **la paridad C/Rust también pasa en el PC**.
  6. **Base del compilador web** (`/taller/compilador`, docs/07 §5 Opción
     1): endpoint que hace `source tools/env-devpc.sh` + cmake
     (toolchain VitaSDK) + build con salida en streaming, variantes C/Rust,
     `AGENT_IP`/`NETLOG_IP` opcionales, historial en SQLite, descarga del
     `.vpk` y deploy FTP a la Vita (`curl -T … ftp://<vita>:1337/ux0:/`).
     **Verificado: un `.vpk` Rust real compilado y descargado desde la
     web** (eboot.bin + param.sfo, ~77 KB).
  Seguridad/alcance: todo el taller queda detrás de `TALLER_ENABLED=1`
  (solo el PC de desarrollo; en docker/público queda apagado y la página lo
  explica); el receptor netlog tolera `EADDRINUSE` (si `netlog-listen.sh`
  está corriendo, el dashboard lo dice en vez de romperse); el widget de
  topics sin `ROS2_TOPICS_CMD` dice "sin conexión", no inventa datos.
  Pendiente dentro de la misma fase: capa remota del compilador (cuando la
  web no corra en el PC) y el debug en hardware real (investigación
  propia). `web/src/data/fases.ts` actualizado (`fase-web`: 6 hitos
  `hecho` + 1 pendiente).

- **(2026-07-07, en la laptop) Tres bugs reales de la web corregidos tras
  el primer uso multi-máquina** (dashboard en blanco desde otra máquina,
  "logs indescriptibles" en `/monitor` y dashboard sin logs en docker):
  1. **Ruido binario cada 25 s en `/monitor` — causa raíz sorpresa:** un
     dispositivo **TP-Link Kasa** de la casa sondea sus enchufes por
     broadcast UDP **al mismo puerto 9999** que usa el netlog. Se capturó
     el paquete real (58 bytes desde `192.168.1.51`) y se descifró (XOR
     "autokey" del protocolo Kasa):
     `{"system":{"get_sysinfo":{}},"emeter":{"get_realtime":{}}}`.
     Fix: `cleanLine()` (`web/scripts/netlog-parser.mjs`, compartido por
     ingestor y dashboard) ahora descarta líneas con <70 % de ASCII
     imprimible; la basura ya no crea sesiones fantasma ni mantiene vivas
     las inactivas (tests nuevos con el payload real). La DB se limpió
     (101 líneas basura, 1 sesión fantasma).
  2. **Dashboard en blanco al entrar por `http://<ip>:4321`:**
     `crypto.randomUUID()` solo existe en contextos seguros (https o
     localhost); desde otra máquina el TypeError tumbaba el script entero
     de `/dashboard` (y el checklist de las guías). Fix:
     `web/src/lib/client-id.ts` compartido con fallback `Math.random()`.
  3. **Carrera por el puerto 9999 dentro del contenedor:** el ingestor de
     `/monitor` y el `netlog.ts` del dashboard competían por el socket; el
     que perdía dejaba widgets muertos con "reinicia la web". Fix: fuente
     dual en `netlog.ts` — modo `sqlite` (sigue las líneas que el ingestor
     escribe en la DB compartida; fijado con `NETLOG_MODE=sqlite` en
     `docker-compose.yml`, el ingestor es el único dueño del puerto) y, en
     el caso `EADDRINUSE` fuera de docker (p. ej. `netlog-listen.sh`),
     degradación automática a SQLite + reintento del bind cada 15 s (ya no
     hace falta reiniciar la web). El widget de salud muestra la fuente
     ("vía ingestor (SQLite)" vs "escuchando :9999").
  Verificado end-to-end en el contenedor real: datagrama UDP simulado →
  ingestor → SQLite → SSE del dashboard con la línea limpia; 1 minuto con
  ≥2 sondeos Kasa sin ingestar nada; bundle de `/dashboard` con el
  fallback del client-id incluido.

- **(2026-07-07, en la laptop) La app gana UI (declarativa, vita2d) y la
  web gana su editor visual (`/taller/ui`)** — se desbloquea el requisito
  docs/07 §2 en el orden que pidió el usuario: primero capacidad de UI en
  la app, después editarla desde la web.
  1. **Decisión de renderizado (ADR 0005):** vita2d (GPU, solo C, solo
     Vita), elegida por el usuario frente al módulo dual por software.
     Excepción consciente a la regla dual: `ui.c` es código de app sin rama
     host ni paridad Rust; lo que SÍ se verifica en laptop es el dato.
  2. **UI declarativa:** `vita-app/ui/layout.json` (panel/label/valor, con
     bindings `estado_conexion`, `contador_publicados`, `ultimo_pc_hello`,
     `agente`) → codegen `scripts/gen-ui-header.mjs` → `src/ui_layout.h`
     (generado, con banner) → intérprete `src/ui.c` (vita2d, fuente PGF).
     `scripts/check-ui-layout.sh` regenera y compila el header en host
     (gcc `-fsyntax-only`, verde en la laptop). `main.c` reestructurado:
     publica a 1 Hz por timestamp, atiende la sesión en tramos de 50 ms y
     redibuja cada vuelta (~20 fps); errores fatales también en pantalla.
  3. **Editor web `/taller/ui`:** lienzo 960×544 con preview 2D aproximada
     (asumida como aproximación — la emulación se descartó en
     `web/README.md`), paleta panel/label/valor, arrastre con snap de 8 px,
     panel de propiedades, borrador autosave en SQLite por client-id
     (tabla `ui_drafts`), «Cargar el del repo», «Aplicar al proyecto»
     (escribe `layout.json` validado + regenera header + check en host,
     como job del taller con salida en vivo) y compilar/deploy reutilizando
     los endpoints existentes. Validación compartida en
     `web/src/lib/ui-layout.ts` (espejo consciente del codegen). Aplicar
     exige `TALLER_ENABLED=1`; leer/borrador no.
  4. **Verificado en la laptop:** check-ui-layout verde; endpoints GET
     layout / GET+POST borrador (con rechazo de layouts inválidos) / POST
     aplicar probados contra el dev server real — el job regeneró
     `ui_layout.h` y pasó el check con salida SSE completa.
  **Pendiente (PC/hardware):** ~~compilar ambas variantes con libvita2d
  enlazada~~ **HECHO (2026-07-07, en el PC — ver bloque siguiente)**;
  falta el deploy y ver la UI dibujada con datos en vivo en la consola.
  Siguiente dentro de este frente (aún sin empezar): editar
  "funcionalidades" (topics/comportamiento) — el diseño del Objetivo 2
  del que dependía ya existe (docs/09).

- **(2026-07-07, en el PC) Objetivo 2 IMPLEMENTADO y compilado — la app
  pasa de "hello" a mando de teleoperación ROS2** (diseño + código + tests
  host + `.vpk`, en la misma sesión):
  1. **Diseño:** `docs/09-objetivo2-control-robot.md` — topic `/cmd_vel`
     (`rt/cmd_vel`, `geometry_msgs::msg::dds_::Twist_`, 6 doubles = 48
     bytes CDR) a ~20 Hz; mapeo pedido por el usuario: stick izq =
     `linear.x` + `angular.z` proporcionales; stick der horizontal =
     `linear.y` (lateral) y vertical = rampa de `vel_lateral` (±0.5/s);
     cruceta = x/y digitales con prioridad; L/R = `angular.z` ±0.5 fijo;
     △ = `vel_lineal` +0.5 (tope 2.0); ✕ = −0.5 (suelo 0.0 = STOP);
     START = salir. Ejes según REP 103 (y+ = izquierda, rz+ = antihorario).
  2. **`vita-app/src/teleop.{h,c}`:** el mapeo completo como lógica PURA
     (sin headers de la Vita) — zona muerta ±30 reescalada sin salto,
     flancos de △/✕, rampa por `dt`, clamps. Batería en host:
     `vita-app/tests/teleop_test.c` + `scripts/check-teleop.sh` (gcc del
     host), **39/39 checks verdes en el PC**. `main.c` solo traduce
     `SceCtrlData` → `teleop_entrada` (modo `SCE_CTRL_MODE_ANALOG`).
  3. **`main.c`:** tercer topic + datawriter (`rt/cmd_vel`) en la misma
     sesión/participante (8 requests verificados con
     `uxr_run_session_until_all_status`); publica el Twist una vez por
     vuelta del bucle (~20 Hz, serializado con 6 `ucdr_serialize_double`)
     y conserva TODO lo de la Fase 1 (`/vita_hello` 1 Hz + `/pc_hello`)
     como heartbeat/regresión. Los cambios de escala se loguean al netlog
     solo en los flancos (no inunda).
  4. **UI declarativa:** 4 bindings nuevos (`vel_lineal`, `vel_lateral`,
     `cmd_vel`, `contador_cmd`) en `ui_types.h` + codegen + `ui.c` +
     espejo web (`web/src/lib/ui-layout.ts`, editor `/taller/ui` con sus
     ejemplos de preview); `ui/layout.json` rediseñado como pantalla de
     teleop (velocidades grandes, Twist en vivo, chuleta de controles).
     `check-ui-layout.sh` verde (22 widgets). La app se llama ahora
     "Vita ROS2 Teleop" (mismo TITLEID `VROS00001`, versión 02.00 — al
     instalar sobrescribe la anterior).
  5. **Builds en el PC:** se instaló **libvita2d** en el VitaSDK local
     (ojo: el paquete de vdpm se llama `libvita2d`, no `vita2d` — con el
     nombre malo vdpm dice "Successfully installed" aunque el tar falle).
     Las dos variantes compilan y empaquetan limpias: `build-c/` (~106 KB)
     y `build-rust/` (~165 KB), primera vez con vita2d + teleop dentro.
  6. **Deploy por FTP HECHO (misma sesión, con la Vita ya encendida):**
     `vita-app/build-rust/vita-ros2-hello.vpk` subido a `ux0:/` y
     verificado por listado FTP (165267 bytes, tamaño exacto). Nota
     operativa: si el modo FTP de VitaShell se habilita mientras un
     cliente está reintentando conectar, su hilo FTP puede quedarse
     colgado (acepta TCP pero no manda el saludo) — se destraba solo al
     rato, o al instante cerrando (O) y reabriendo (SELECT) el modo FTP.
     **Pendiente manual en la Vita:** instalar el `.vpk` desde VitaShell
     (sobrescribe "Vita ROS2 Hello" con "Vita ROS2 Teleop" v02.00) y
     hacer la verificación en vivo del punto siguiente.
