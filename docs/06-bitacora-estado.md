# 06 — Bitácora de estado del proyecto

**Última actualización:** 2026-06-28 (PC CachyOS: cliente XRCE cross-compilado — muro #1 superado)
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

**El proyecto está bloqueado únicamente por pasos que exigen el PC (con
VitaSDK) y la consola física.** Ver "Próximos pasos" al final.

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
con checklist interactivo persistente en SQLite, y progreso por fases
(`src/data/fases.ts` ← **actualizar al cerrar hitos**). DB y volúmenes en
`web/data/` dentro del repo. `cd web && docker compose up -d --build` →
`localhost:4321`. Preparada para `psvita-ros.jcrex999.com` (ver
`web/README.md`). Emulación en navegador: evaluada y descartada (Vita3K no
tiene port WASM); decisión documentada.

### `docs/`

- `00-05`: la fundación (visión, hardware, arquitectura Fase 1, estrategia
  dual, investigación rviz2, setup del PC).
- `adr/0001-0004`: decisiones registradas.
- `rust/00-02`: serie de aprendizaje de Rust ligada al código del repo
  (herramientas, lenguaje, FFI/no_std/unsafe + glosario C↔Rust).
- `guias-vita/`: 7 guías homebrew con frontmatter (las consume la web).
- `superpowers/`: spec y plan de la Fase 0.

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
3. **(SIGUIENTE)** `cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake
   -DVITA_IMPL=c -B build && cmake --build build` → `.vpk`. Repetir con
   `-DVITA_IMPL=rust` (segundo muro posible: target tier 3).
4. Compilación cruzada de los módulos sueltos: `cmake` en cada
   `modules/*/` con el toolchain (los CMakeLists ya están).
5. Registrar el MCP en el Claude Code del PC.

### Con la Vita (hardware)

6. Preparar la consola con `docs/guias-vita/` (VitaShell + PrincessLog).
7. Lanzar en la laptop: agente (`docker run --net=host
   microros/micro-ros-agent:jazzy udp4 --port 8888 -v6`) y `nc -u -l -p 9999`.
8. Instalar el `.vpk`, abrir la app y mirar el netlog: la línea
   `SESION XRCE ESTABLECIDA` responde la incógnita dura.
9. Criterios Fase 1: `ros2 topic echo /vita_hello` y publicar `/pc_hello`.
10. Actualizar esta bitácora y `web/src/data/fases.ts` con el resultado.

### En la laptop (sin bloqueo, cuando se quiera)

- Levantar la web con docker y dejarla corriendo.
- Más entradas en `docs/rust/` a medida que aparezcan construcciones nuevas.
- Cuando llegue el dominio: DNS + reverse proxy (receta en `web/README.md`).
