# docs/ia/auditoria — auditoría de la flota (2026-11-01)

Versión larga para Claude. La corta para el usuario: `docs/informes/00-indice-auditoria.md`.
Siete agentes en paralelo, todos de **solo lectura** (no movieron ni editaron nada). Estado del
árbol al empezar: rama `ccr-44e2db2a-mr6xqr`, G7a sin commit.

| Informe | Equipo | Ámbito |
|---|---|---|
| `01a-limpieza-tools-infra.md` | Limpieza A | tools/, docker/, vita-app/, web/, mcp/, skills/, raíz |
| `01b-limpieza-modulos-godot-docs.md` | Limpieza B | modules/, godot/, docs/ |
| `02a-optimizacion-modulos.md` | Optimización A | 8 módulos dual + flags de compilación |
| `02b-optimizacion-ros2vita-apps.md` | Optimización B | ros2_vita, g6/g7, vita-app, loader |
| `03-mapa-rust.md` | Mapa Rust | crates, enlaces, paridad, huecos de docs/rust |
| `04a-dbtsdf-analisis-codigo.md` | DB-TSDF código | algoritmo, dependencias, licencia (commit 663c5a8) |
| `04b-dbtsdf-viabilidad-vita.md` | DB-TSDF Vita | presupuesto, arquitecturas A/B/C, etapas T0–T8 |

## Lista consolidada de acciones (pendiente de decisión del usuario)

> **Estado (2026-11-13, Fase O; detalle en `docs/ia/organizacion/O1b-auditoria-estado.md`):** lotes **0, 1, 2a y 3
> cerrados** en `bbbfa2d` (2026-11-01). **Lote 2b cerrado por la Fase O** (ADR 0014: `vita-app/` y `godot/godot35/`
> con los docs 20–21 pasan a `archivo/` en el paso O2c, tras extraer el paraguas Rust a `modules/paraguas-rust/`, el
> script del cliente XRCE a `tools/` y `netlog.c` a `tools/hwprobe/`). Del lote 4, **R2 y R3 hechos** (`ee4e7b3`,
> `cc824f4`). **Siguen abiertos** el resto del lote 4 (B1–B3, R1, X1) y el lote 5: son código, no organización.
> Los informes `04a`/`04b` están superados por el doc 26 + ADR 0010.

### Lote 0 — antes del commit de G7a
- Añadir `godot/g7-imu/.godot/` a `.gitignore` (01b).

### Lote 1 — borrar (basura, sin referencias)
- `web/localhost:4321`, `mcp/.gitkeep`, `skills/.gitkeep` (01a).
- `godot/godot35/imagenes/rover-iberus.jpeg.import`; `godot/godot35/UI/UIIcons_2.zip` (confirmar) (01b).

### Lote 2 — archivar en `archivo/<ruta original>`
- `docs/superpowers/` (antes: copiar el plan del tutorial 2026-07-12 a `docs/ia/`; actualizar
  `monitor.astro:3`, `netlog-ingester.mjs:7`, `web/README.md:28,78`) (01b).
- Opcional/último: `vita-app/` + taller web (01a) y `godot/godot35/` + docs/20–21 (01b). Requiere
  extraer antes `vita-app/rust-modules` (→ `rust-modules/` raíz), `scripts/build-xrce-client-vita.sh`
  (→ `tools/`), `src/netlog.c` (lo usan hwprobe y godot35) y reescribir rutas (web/Dockerfile,
  content.config.ts, Base.astro, index.astro, .dockerignore, build-rust-pic.sh, SCsub:27-32,
  godot35 `scripts/build-vita-template.sh:18`). Coordinar A y B: no mover uno sin el otro.

### Lote 3 — actualizar docs y marcadores
- README raíz, CLAUDE.md:19,25 (agente en estación docker/), docs/rust/00–02 (8 módulos),
  docs/03:36-52, docs/10:3, docs/11:3, docs/19 (⏳ ya hechos), ADR 0008:3, docs/tutorial/00,
  docs/09-guia-pruebas-stack → 23-, marcadores «validar en hardware» de G4–G6 y ros2_vita,
  API_PARITY.md:29 (msg-ring no se usa), docs/14/15 (NEON no auto-vectoriza: 0 instr. en viz_math).
- Skills `vita-build-package`, `vita-dual-module`, `vita-deploy-logs` (flujo Fase 1 → Godot 4).
- `tools/vita-doctor.sh:46` (ruta `third_party/install` inexistente), `tools/netlog-listen.sh` (filtro Kasa).
- `tools/run-parity-tests.sh`: forzar `RUSTUP_TOOLCHAIN=nightly` + env de `tools/env-devpc.sh`.

### Lote 4 — bugs (cada uno candidato a reto del usuario)
| ID | Dónde | Qué | Origen |
|---|---|---|---|
| B1 | `msg_schema.c:58-73`, `lib.rs:135-144` | sin comprobar `strings_off <= total`: OOB en C (ASan), cuelgue en Rust | 02a |
| B2 | `vita-app/rust-modules/src/lib.rs:23-25` | panic = `loop {}` sin log | 02a |
| B3 | `net_udp.c:260`, `lib.rs:465` | desborde `timeout_ms*1000` | 02a |
| R1 | `ros_runtime.cpp:717` | `shutdown()` desde timer → índice fuera de rango | 02b |
| R2 | ros2_vita | sin detección de agente caído ni reconexión | 02b |
| R3 | `xrce_transport.cpp:425` | 1 mensaje best-effort por frame (ERR_BUSY) | 02b |
| X1 | `output_reliable_stream.c:212` | hipótesis: `poll(0)` por frame impide HEARTBEAT; medir `reliable_full` | 02b |

### Lote 5 — optimizaciones (top consolidado)
1. vita-app compila a -O0 (CMAKE_BUILD_TYPE vacío) → Release.
2. MTU XRCE 512 → ~1400 (02a y 02b coinciden).
3. Decodificación sin árboles por defecto + caché de StringName (`ros_msg.cpp:457,463`).
4. Quitar pools de red duplicados (1–2 MiB, `net_udp.c:40`, `xrce_transport.cpp:103`).
5. `-O2` para los `.c` de módulos en SCsub (-30 % en msg_schema_decode en host).
6. Perfil del crate paraguas: lto, codegen-units=1, panic con log.

## Hechos verificados al consolidar
- Reloj: 333 MHz con WiFi activo, 444 sin WiFi (`docs/14:22,48,63`); 3 núcleos de usuario
  (`docs/14:162`, fuente débil). El prompt de la flota decía 444 MHz: 04b usa 333 (correcto).
- Paridad 16/16 verde (03 y 02a la ejecutaron, con el env de rustup arreglado a mano).

## DB-TSDF — decisión propuesta
Arquitectura B (PC mapea, Vita dibuja 2D) → C (Vita integra nube reducida en volumen local).
A descartada. Primero T0/T1: oráculo en docker y medir K=5/7/21 (el repo y el paper difieren).
Bugs del original: `hits++` no atómico (`tsdf3d_16.hpp:242`), bucle `uint16_t` (`grid_16.hpp:207`).
