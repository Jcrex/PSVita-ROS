# O1b — Estado de la auditoría del 2026-11-01 (lotes 0–5), verificado en el código

> Fecha: 2026-11-13 · Agente O1b (solo lectura) · Origen: `docs/ia/auditoria/README.md` y
> `docs/ia/plan-organizacion-y-visor-2026-11-13.md` (fila D6). Rama `ccr-44e2db2a-mr6xqr`, HEAD `b6f4e76`.
> Estados: **HECHO** (evidencia), **PENDIENTE** (sigue igual), **OBSOLETO** (ya no aplica), **REABIERTO**
> (se hizo el 2026-11-01 pero ha vuelto a quedarse desfasado).

Resumen: los lotes 0, 1, 2a y 3 se cerraron en un solo commit, **`bbbfa2d`** (2026-11-01,
«chore(auditoria): … lotes de limpieza 0–3»). Siguen abiertos el **lote 2b** (archivar `vita-app/`
y `godot/godot35/`), varios puntos del lote 3 que se han vuelto a desfasar con el trabajo de
G7c → g1-unitree/plantillas, y casi todo el lote 4–5 (bugs/optimizaciones, que no son organización).
La bitácora lo recoge: `docs/06-bitacora-estado.md:383-384` («Pendiente de decisión: lote 2b …,
lote 4 (7 bugs) y lote 5»).

## Tabla por punto

| Lote | Punto | Estado | Evidencia | Acción propuesta |
|---|---|---|---|---|
| 0 | `.godot/` de `g7-imu` en `.gitignore` | HECHO | `.gitignore:53` (`.godot/`, regla general); `bbbfa2d` | — |
| 1 | Borrar `web/localhost:4321`, `mcp/.gitkeep`, `skills/.gitkeep` | HECHO | ninguno existe; `bbbfa2d` | — |
| 1 | Borrar `godot35/imagenes/rover-iberus.jpeg.import`, `godot35/UI/UIIcons_2.zip` | HECHO | ninguno existe; `bbbfa2d` | — |
| 2a | `docs/superpowers/` → `archivo/docs/superpowers/` | HECHO | `archivo/docs/superpowers/` existe; `archivo/README.md` (tabla); `bbbfa2d` | — |
| 2a | Copiar plan/spec del tutorial a `docs/ia/` | HECHO | `docs/ia/plan-tutorial-2026-07-12.md`, `docs/ia/spec-tutorial-2026-07-12.md` (`bbbfa2d`) | — |
| 2a | Reescribir rutas `monitor.astro:3`, `netlog-ingester.mjs:7`, `web/README.md:28,78` | HECHO | las 4 líneas apuntan ya a `archivo/docs/superpowers/specs/…` | — |
| 2b | Archivar `vita-app/` (+ taller web) | PENDIENTE | `vita-app/` sigue vivo; `archivo/README.md` lo marca «pendiente de decisión» | Decisión del usuario; antes extraer dependencias (ver abajo) |
| 2b | Extraer `vita-app/rust-modules` → `rust-modules/` raíz | PENDIENTE | no existe `rust-modules/`; lo usan `tools/build-rust-pic.sh:16`, `docs/rust/00:61`, `skills/vita-dual-module/SKILL.md:47,116-117`, `godot35/scripts/build-vita-template.sh:40` | Mover y reescribir esas rutas |
| 2b | Extraer `scripts/build-xrce-client-vita.sh` → `tools/` (+ `third_party/`) | PENDIENTE | `tools/build-xrce-client-vita.sh` no existe; **ros2_vita depende** de `vita-app/third_party/xrce-vita-{pic,host}` (`godot/ros2_vita/SCsub:28,33`); `tools/vita-doctor.sh:49-51`; `skills/vita-build-package/SKILL.md:118`; bitácora `docs/06:467,662` | Mover script y destino de libs (p. ej. `toolchains/xrce-vita-*`), reescribir SCsub/doctor/skill/docs |
| 2b | Extraer `src/netlog.c` (hwprobe, godot35) | PENDIENTE | `tools/hwprobe/CMakeLists.txt:24` (`../../vita-app/src`) | Mover a `tools/hwprobe/` o `modules/`, o archivar hwprobe con vita-app |
| 2b | Reescribir web (`Dockerfile`, `content.config.ts`, `Base.astro`, `index.astro`, `.dockerignore`) | PENDIENTE (y en pausa) | `web/Dockerfile:29,55`; `web/src/content.config.ts:54` | Depende de la decisión sobre la web (pausada) |
| 2b | Archivar `godot/godot35/` + `docs/20`–`21` | PENDIENTE | existen `godot/godot35/`, `docs/20-godot35-migracion-historico.md`, `docs/21-…`; referencias en `README.md:13,89,165-166`, `CLAUDE.md`, `godot/README.md`, `docs/18`, `docs/06`; `tools/build-godot-template.sh:70` recoge `godot35/modules/microros` | Archivar junto a vita-app (coordinado); quitar la línea 70 del template o dejarla condicionada |
| 3 | README raíz | REABIERTO | `bbbfa2d` lo actualizó (último cambio 2026-11-01), pero `README.md:10-13` dice «G1–G6 … siguiente G7» y el árbol (`:83-89`) termina en `g7-imu`; faltan G7c, `g1-unitree`, `g1-sensores`, `plantillas/`, `docker/` g1, ADR 0009–0013 (`:164` dice `0001-0008`), docs 24–36 | Reescribir estado, árbol y tabla de docs/ADR |
| 3 | `CLAUDE.md:19,25` (agente en estación `docker/`) | HECHO | tabla de roles: el agente vive en el PC (`docker/vita-ros.sh up`); `bbbfa2d`, último cambio 2026-11-13 | Revisar tablas de `godot/` y `docs/` en O2d |
| 3 | `docs/rust/00–02` (8 módulos) | HECHO | `docs/rust/00:61,95` y `02:114` hablan de «los ocho»; `bbbfa2d` | Si se mueve el paraguas (2b), reescribir `00:61` |
| 3 | `docs/03:36-52` | HECHO | `bbbfa2d` (+12 líneas en docs/03) | — |
| 3 | `docs/10:3` | REABIERTO | `docs/10-plan-objetivos-3-4.md:3`: «el 3D sigue en `vita-app/` (ADR 0008 §5)», pero ADR 0008 se enmendó el 2026-11-11 (§5: el 3D entra en Godot) | Corregir la línea de estado (o archivar el doc como superado) |
| 3 | `docs/11:3` | HECHO | `docs/11-diseno-mini-rviz.md:3` «en pausa desde 2026-10-27» | Candidato a archivo (superado por doc 36/ADR 0013) |
| 3 | `docs/19` (⏳ ya hechos) | HECHO | `bbbfa2d` (30 líneas); los ⏳ restantes (`:85,90-92`, fork/rebase) son tareas realmente abiertas | Candidato a archivo (plan histórico) |
| 3 | `ADR 0008:3` | HECHO | estado «ejecución validada … G4–G6 en hardware», enmienda 2026-11-11 | — |
| 3 | `docs/tutorial/00` | HECHO | `bbbfa2d` (150 líneas reescritas) | — |
| 3 | `docs/09-guia-pruebas-stack` → `docs/23` | HECHO | existe `docs/23-guia-pruebas-stack.md`; no existe `docs/09-guia-…` | — |
| 3 | Marcadores «validar en hardware» G4–G6 / ros2_vita | HECHO | `grep` sin «validar en hardware» en `godot/ros2_vita`, `g4-smoke`, `g5-xrce`, `g6-hmi`; p. ej. `ros_msg.cpp:1` «validado en hardware (G4–G6)» | — |
| 3 | `API_PARITY.md:29` (msg-ring no se usa) | HECHO | `godot/ros2_vita/API_PARITY.md:29` «`msg-ring` aún sin usar» | — |
| 3 | docs/14/15: NEON no auto-vectoriza | HECHO | `docs/14-…:61` «Corrección 2026-11-01 [M]: … no ocurre»; `docs/15` modificado en `bbbfa2d` (`:46` conserva la afirmación general «LLVM puede auto-vectorizar enteros») | — |
| 3 | Skill `vita-build-package` (Fase 1 → Godot 4) | HECHO, levemente REABIERTO | reescrita en `bbbfa2d` (flujo Godot 4 primero); pero `SKILL.md:12` dice «G1–G6 verdes» y `:118` apunta a `vita-app/scripts/…` | Actualizar estado (G7c, plantillas) y rutas si 2b se hace |
| 3 | Skill `vita-dual-module` | HECHO | reescrita en `bbbfa2d`; rutas al paraguas `vita-app/rust-modules` (`:47,116-117`) son correctas hoy | Reescribir rutas si 2b mueve el paraguas |
| 3 | Skill `vita-deploy-logs` | HECHO, levemente REABIERTO | reescrita en `bbbfa2d`; `SKILL.md:81` lista `g5-xrce, g6-hmi, g7-imu…` (sin g1-unitree/plantillas) | Refrescar ejemplos |
| 3 | `tools/vita-doctor.sh:46` (`third_party/install`) | HECHO | ya no aparece `third_party/install`; ahora `:49-51` busca `vita-app/third_party/$v/lib/…` | Reescribir si 2b mueve las libs |
| 3 | `tools/netlog-listen.sh` (filtro Kasa) | HECHO | `tools/netlog-listen.sh:12-13` (filtro de ruido binario del Kasa) | — |
| 3 | `tools/run-parity-tests.sh` (nightly + env) | HECHO | `tools/run-parity-tests.sh:21-27` (`RUSTUP_HOME` de `toolchains/rustup`, `RUSTUP_TOOLCHAIN=nightly`) | — |
| 4 | B1 `strings_off <= total` | PENDIENTE | `modules/msg-schema/impl-c/msg_schema.c:58` comprueba `soff < foff` pero no `soff <= total`; `:73` `strings_len = total - soff` puede dar la vuelta; Rust igual (sin cambios desde `bbbfa2d`/`8b5dd99`) | Añadir la comprobación en C y Rust + caso de paridad |
| 4 | B2 panic = `loop {}` sin log | PENDIENTE | `vita-app/rust-modules/src/lib.rs:23-25` | Log mínimo antes de colgar/abortar |
| 4 | B3 desborde `timeout_ms*1000` | PENDIENTE | `modules/net-udp/impl-c/net_udp.c:261`; `impl-rust/src/lib.rs:465` | Saturar o usar 64 bits |
| 4 | R1 `shutdown()` desde timer | PENDIENTE | `godot/ros2_vita/ros_runtime.cpp:519-525` recorre `timers[i]`; `shutdown()` (`:429-444`) hace `timers.clear()` → la siguiente vuelta indexa fuera de rango | Romper el bucle si `!running` o copiar la lista |
| 4 | R2 sin detección de agente caído ni reconexión | HECHO | `xrce_transport.cpp:224-226,383-416` (`uxr_ping_agent`, `_reconectar`); commit `ee4e7b3` | — |
| 4 | R3 1 mensaje best effort por frame | HECHO | `xrce_transport.cpp:531-538,540-559` (reintento tras `flash` y hasta `BE_MAX_POR_POLL` por poll); commit `cc824f4` | — |
| 4 | X1 hipótesis HEARTBEAT / medir `reliable_full` | PENDIENTE (instrumentado) | contador en `xrce_transport.cpp:54,576,711` (desde `ef31033`); `docs/30:78,141` lo expone, sin conclusión sobre la hipótesis | Medir en hardware y cerrar la hipótesis |
| 5 | 1. vita-app a -O0 → Release | OBSOLETO (de hecho, PENDIENTE en una app histórica) | `vita-app/CMakeLists.txt` sin `CMAKE_BUILD_TYPE`; la app es Fase 1 histórica | No invertir: se archiva con 2b |
| 5 | 2. MTU XRCE 512 → ~1400 | PENDIENTE | `xrce_transport.cpp:140-148` (MTU 512); `docs/27:22-23` lo deja como experimento [?] | Experimento en hardware |
| 5 | 3. Decodificación sin árboles + caché de `StringName` | PENDIENTE | `ros_msg.cpp` crea `StringName(String::utf8(name))` por campo y mensaje (decodificador `:397,416,425,486,505-507`; codificador `:563-664`) | Caché por esquema |
| 5 | 4. Pools de red duplicados | PENDIENTE | `modules/net-udp/impl-c/net_udp.c:41` (1 MiB estático) y `xrce_transport.cpp:107-111` (1 MiB `memalign`) | Unificar el init de red |
| 5 | 5. `-O2` para los `.c` de módulos en SCsub | PENDIENTE | `godot/ros2_vita/SCsub` sin flags `-O` propios | Añadir `CCFLAGS` |
| 5 | 6. Perfil del paraguas: lto, codegen-units=1, panic con log | PENDIENTE | `vita-app/rust-modules/Cargo.toml:33-37` solo `panic = "abort"` | Con B2 y tras mover el paraguas |

## Acciones pendientes de ORGANIZACIÓN (archivar / borrar / actualizar)

1. **Lote 2b — archivar `vita-app/` y `godot/godot35/` (+ `docs/20`–`21`)**, coordinado y con decisión del
   usuario. Antes, sacar lo que está vivo:
   - paraguas Rust `vita-app/rust-modules/` → `rust-modules/` (raíz): reescribir `tools/build-rust-pic.sh:16`,
     `docs/rust/00:61`, `skills/vita-dual-module/SKILL.md:47,116-117`;
   - `vita-app/scripts/build-xrce-client-vita.sh` → `tools/`, y el destino de las libs
     `vita-app/third_party/xrce-vita-{pic,host}` (lo lee `godot/ros2_vita/SCsub:28,33`): reescribir SCsub,
     `tools/vita-doctor.sh:49-54`, `skills/vita-build-package/SKILL.md:118` y las recetas de `docs/06`;
   - `vita-app/src/netlog.c` → junto a `tools/hwprobe/` (`CMakeLists.txt:24`);
   - quitar `godot35/modules/microros` de `tools/build-godot-template.sh:70`;
   - web (`Dockerfile:29,55`, `content.config.ts:54`, `Base.astro`, `index.astro`, `.dockerignore`): solo si
     la web sigue; está en pausa.
2. **Archivar docs superados** (plan D1): `docs/10`, `docs/11`, `docs/19` y `docs/20`–`21` a `archivo/docs/` sin
   renumerar; si `docs/10` se queda, corregir su línea 3 (el 3D ya va en Godot, ADR 0008 enmendado 2026-11-11).
3. **Actualizar README raíz** (estado G7c/g1/plantillas, árbol de `godot/`, ADR 0001–0013, docs 24–36,
   quitar comandos de `vita-app/scripts/check-*.sh` de la sección principal si se archiva).
4. **Refrescar skills** `vita-build-package` (`:12` estado, `:118` ruta) y `vita-deploy-logs` (`:81` ejemplos).
5. **`archivo/README.md`**: añadir cada cosa que se archive en 1–2 (hoy solo lista `docs/superpowers/`).
6. **`docs/ia/auditoria/README.md`**: marcar lotes 0, 1, 2a y 3 como cerrados en `bbbfa2d`, R2 y R3 como hechos.

## Bugs y optimizaciones de CÓDIGO (lotes 4–5; no son organización)

- **Bugs abiertos:** B1 (`msg_schema.c:58-73` + Rust), B2 (panic sin log), B3 (`timeout_ms*1000`),
  R1 (`ros_runtime.cpp:519` tras `shutdown()` desde un timer), X1 (medir `reliable_full` en hardware).
- **Cerrados:** R2 (reconexión, `ee4e7b3`), R3 (cola best effort, `cc824f4`).
- **Optimizaciones abiertas:** MTU 512→~1400 (experimento), caché de `StringName` en la decodificación,
  pool de red duplicado (2 MiB), `-O2` en SCsub, perfil del paraguas (lto/codegen-units/panic con log).
- **Obsoleta:** `-O0` de `vita-app` (app histórica; se archiva con 2b).
