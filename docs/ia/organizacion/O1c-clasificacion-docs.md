# O1c — Clasificación de `docs/` y restos de decisiones descartadas (2026-11-13)

> Agente O1c (Opus 5.5), **solo lectura** (no se movió ni borró nada). Encargo: `docs/ia/plan-organizacion-y-visor-2026-11-13.md`
> §1.2 (D1, D4–D6) y §2 (ola O1). Petición del usuario: «archivar decisiones antiguas que han sido descartadas pero no
> limpiadas». Las propuestas de mover/borrar son para el **juez Fable** (decisión) y el usuario (lo irreversible).
> Marcas: **[V]** verificado en el fichero citado · **[I]** inferencia · **[?]** por confirmar.

## 0. Leyenda y criterio

| Estado | Significado | Acción por defecto |
|---|---|---|
| **VIGENTE** | Describe lo que se usa hoy o una decisión aceptada que sigue en pie | Se queda en `docs/` |
| **VIGENTE·P** | Vigente pero **en pausa** por decisión del usuario (web, modo aprendizaje) | Se queda; marcar «en pausa» en el índice |
| **HISTÓRICO** | Trabajo cerrado; vale como registro (cómo se llegó, medidas, lecciones) | Indexar; archivar solo si estorba |
| **SUPERADO** | La decisión o el plan fue sustituido por otro (se dice por cuál) | Archivar en `archivo/<ruta original>` (convención de `archivo/README.md`), **sin renumerar** |

Cadena de decisiones que explica casi todos los SUPERADOS [V]:

1. **2026-07-10 — ADR 0006**: rviz2 nativo no portable → Plan B mini-rviz con vitaGL dentro de `vita-app/`
   (`docs/adr/0006-decision-rviz2-vs-mini-rviz.md:1`). ADR 0007 elige «todo vitaGL» y retira vita2d de ADR 0005
   (`docs/adr/0007-convivencia-vita2d-vitagl.md:1,9-10`; `vita-app/CMakeLists.txt:102`).
2. **2026-10-27 — ADR 0008**: Godot 4 (`godot4-vita`) como producto; se descarta Godot 3.5
   (`docs/adr/0008-godot-via-modulo-estatico.md:42-45`; `docs/12-investigacion-godot-ros2-vita.md:3-5`). El plan de
   Objetivos 3–4 y el mini-rviz quedan **en pausa** (`docs/10-plan-objetivos-3-4.md:3`, `docs/11-diseno-mini-rviz.md:3`).
3. **2026-11-01 — web en pausa** (decisión del usuario, `CLAUDE.md:12-13,86-88`). Informes cortos y modo aprendizaje:
   aprendizaje en pausa desde 2026-11-11 y no se escriben informes cortos (`CLAUDE.md:98-105`).
4. **2026-11-11 — enmienda de ADR 0008 §5**: el 3D general se delega en Godot; «`vita-app/` (ADR 0007) queda como app
   histórica» (`docs/adr/0008-godot-via-modulo-estatico.md:46-51`). ADR 0011 descarta expresamente el vitaGL de
   `vita-app` (`docs/adr/0011-presupuesto-render-vita.md:58`).
5. **2026-11-13 — ADR 0013**: el visualizador de topics es un **visor propio en Godot** (`godot/plantillas/visor/`), no
   el mini-rviz (`docs/adr/0013-visualizacion-topics-godot.md:1-3`). Cierra definitivamente la vía mini-rviz/VBM.

---

## 1. Clasificación documento a documento

Columna «Entran»: nº de ficheros fuera del propio doc que lo citan (grep de su nombre o `docs/NN`, sin `archivo/`,
`toolchains/`, `godot/rclgd/` ni los posts JSON de workshops). Se dan los citadores relevantes para mover.

### 1.1 `docs/` raíz numerada

| Nº | Título (corto) | Estado | Superado por / motivo | Evidencia | Entran |
|---|---|---|---|---|---|
| 00 | Visión y objetivos | **VIGENTE** (con matiz) | Los 6 objetivos siguen como marco; la regla «la laptop no instala nada» y el orden estricto por objetivos ya no describen el trabajo (Godot priorizado fuera de orden, ADR 0008) | `00:3-4,40-42` | 9 (README, web) |
| 01 | Hardware y plataforma VitaSDK | **VIGENTE** | Base técnica; se complementa con 14 | `01:3-4` | 3 |
| 02 | Arquitectura Fase 1: micro-ROS + UDP | **VIGENTE** (cabecera desfasada) | La arquitectura XRCE/UDP es la de `ros2_vita` hoy; la línea «incógnita dura pendiente» está obsoleta (cerrada en hardware, 13 §2) | `02:4`; `13:36` | 8 (incl. `modules/microros-transport`) |
| 03 | Estrategia dual Rust + C/C++ | **VIGENTE** | Regla del repo (`CLAUDE.md:30-37`); lote 3 pide actualizar `03:36-52` | `03:3-4,26` | 26 |
| 04 | Investigación portabilidad de rviz2 | **HISTÓRICO** | Investigación ejecutada; la conclusión (rviz2 no portable) **sigue válida**; el «Plan B mini-rviz» que activa está **superado** por ADR 0008 §5 enm. + ADR 0013 | `04:4-8`; ADR 0008:46-51 | 10 (`.gitignore`, ADR 0006, 10, 11, `web/src/data/fases.ts`) |
| 05 | Setup del entorno en CachyOS | **VIGENTE** | Receta del PC (VitaSDK, rustup) que usan `tools/env-devpc.*` | `05:4` | 11 |
| 06 | Bitácora de estado | **VIGENTE** | Documento vivo (1 845 líneas; D2 propone partirlo) | `06:3-5` | muchas |
| 07 | Requisitos: web como IDE/panel | **SUPERADO** | Web **en pausa** (2026-11-01, `CLAUDE.md:86-88`); su «taller» compila y edita la UI de `vita-app` (vita2d/CMake), producto sustituido por Godot 4 (ADR 0008) | `07:3-5`; `web/src/pages/api/taller/build.ts:44-49` | 14 (todo `web/`, ADR 0005, 08) |
| 08 | Fase de desarrollo: la web | **SUPERADO** (en pausa) | Dice «En curso» (`08:4`) pero la web está pausada y quizá se abandone (`CLAUDE.md:86-88`) | `08:3-6` | 9 (`web/`) |
| 09 | Objetivo 2: control de robot | **HISTÓRICO** | Objetivo 2 **cerrado en hardware** (`13:37`); su cabecera dice «en implementación» (`09:3`). El mapeo de mandos sigue reutilizado por `godot/g6-hmi/main.gd` | `09:3`; `godot/README.md:38` | 19 (`vita-app/src/*`, `g6-hmi`, 20, 23) |
| 10 | Plan Objetivos 3 y 4 (rviz2/mini-rviz) | **SUPERADO** | En pausa desde 2026-10-27 (`10:3`); el 3D pasó a Godot (ADR 0008 §5 enm., 2026-11-11) y la visualización a ADR 0013 (2026-11-13) | `10:3`; ADR 0008:46-51; ADR 0013:1-3 | 18 (README:154, 04, 11, 12, 13, 20) |
| 11 | Diseño del mini-rviz (Plan B) + VBM | **SUPERADO** | Mismo motivo que 10. Aún lo citan comentarios de `vita-app/src/viz/*`, `vita-app/src/config.h`, README raíz:155 y READMEs de `modules/{msg-cdr,tf-tree,viz-math,msg-ring}` | `11:3`; ADR 0013 | 23 |
| 12 | Investigación Godot + ROS2 en la Vita | **HISTÓRICO** (parte SUPERADA) | Lo de Godot 3.5 y la vía rosbridge está descartado por la propia cabecera (→ 17, 18, ADR 0008); lo de micro-ROS/XRCE §4 sigue citado por 13 y 16 | `12:3-13` | 18 (incl. `godot/godot35/*`) |
| 13 | Infraestructura de desarrollo (mapa maestro) | **HISTÓRICO** (parcialmente superado) | Su tabla de objetivos (`13:34-42`) da el 3/4 como mini-rviz «en curso» y Godot como «Investigado»: obsoleta. §3 (plan de medición XRCE) aún útil. Sustituto natural: 33 (estación robótica) + 18 | `13:3,34-42` | 11 |
| 14 | Hardware: memoria, hilos, CPU/GPU | **VIGENTE** | Referencia citada por `CLAUDE.md`, la skill `ros2-vita-godot` y `tools/hwprobe/`; lote 3: corregir NEON (O1b) | `14:3` | 26 |
| 15 | Rust nativo y optimización | **VIGENTE** | Igual que 14 (mismo apunte NEON) | `15:3` | 13 |
| 16 | Páginas pendientes de leer | **SUPERADO** | Lista de lectura de 2026-10-27 orientada a **Godot 3.5** (prioridad A: plantilla 3.5, módulos 3.5, hilos 3.5) y a rclgd (ya leído, filas tachadas). La parte 3.5 la descartó ADR 0008; el resto (micro-ROS, godot4-vita) no tiene dueño | `16:17-31` | 7 |
| 17 | rclgd: estado del arte | **VIGENTE** | Base de la API (`godot/ros2_vita/API_PARITY.md`, `register_types.cpp`) | `17:3` | 19 |
| 18 | Migración a Godot 4 | **VIGENTE** | Puertas G0–G7, receta del template (§4.5) citada por `CLAUDE.md` y skills | `18:3` | 52 |
| 19 | Plan multiagente migración Godot 4 | **HISTÓRICO** | Plan **ejecutado** (G1–G7 verdes, `06`); el doc nunca se cerró: 64 marcas ⏳ (lote 3: «⏳ ya hechos»). El método multiagente vigente es `docs/ia/workshops/README.md` | `19:1-11,78-85`; `ia/auditoria/README.md:35-36` | 17 (skills `vita-build-package`, `ros2-vita-godot`) |
| 20 | (Histórico) Godot 3.5: diseño | **SUPERADO** | Godot 3.5 → Godot 4 (ADR 0008, 2026-10-27). Ya marcado HISTÓRICO en su cabecera; lote 2b lo archiva **junto con** `godot/godot35/` | `20:3-10`; `ia/auditoria/README.md:29-33` | 11 |
| 21 | (Histórico) Godot 3.5: plan | **SUPERADO** | Igual que 20 | `21:3-10` | 6 |
| 22 | Acceso remoto al PC | **VIGENTE** (sin aplicar) | Recomendación pendiente (Tailscale) | `22:3`; `06:648-649` | 3 |
| 23 | Guía de pruebas del stack | **VIGENTE** | Estación `docker/` + `tools/vita-stack.sh` | `23:1-51` | 3 |
| 24 | Portabilidad Ozuba (gdviz…) | **VIGENTE** | Cerrado (W4) y base de ADR 0013 | `24:3` | — |
| 25 | URDF en Godot | **VIGENTE** | ADR 0009, implementado | `25:3` | — |
| 26 | DB-TSDF en la Vita | **VIGENTE** | ADR 0010 (por medir). **Sustituye** a `docs/ia/auditoria/04a`/`04b` y a `docs/informes/04a`/`04b` | `26:3-4` | — |
| 27 | XRCE: límites y relay | **VIGENTE** | ADR 0012 | `27:3` | — |
| 28 | Sensores y visión | **VIGENTE** | W12 cerrado | `28:3` | — |
| 29 | Plantillas de robots y sensores | **VIGENTE** | Producto vivo | `29:4` | — |
| 30 | Rendimiento XRCE de plantillas | **VIGENTE** (registro) | Diagnóstico 2026-11-12; cuello resuelto | `30:3-6,119` | — |
| 31 | Render sin shaders | **VIGENTE** | ADR 0011 | `31:3` | — |
| 32 | Acciones y puente PC | **VIGENTE** | ADR 0012 | `32:3` | — |
| 33 | Estación robótica (maestro) | **VIGENTE** | Documento maestro LT1–LT8 | `33:3` | — |
| 34 | Perfil Vita ligero | **VIGENTE** | Trabajo en curso (T1–T3) | `34:3` | — |
| 35 | Regla de escenas editables | **VIGENTE** | Regla del usuario (`CLAUDE.md:121-127`) | `35:3` | — |
| 36 | Visualizar topics en Godot | **VIGENTE** | ADR 0013; D3 propone partirlo | `36:3` | — |

### 1.2 `docs/adr/`

Ningún ADR anterior al 0008 lleva marca de «superado»: todos dicen «Aceptado» (`0005:3`, `0006:3`, `0007:3`). Es el
resto más visible de decisiones descartadas sin limpiar. **Propuesta:** los ADR **no se archivan** (son el registro de
decisiones; ruta estable citada por código y web); se **enmienda su línea `Estado:`** y se refleja en el índice.

| ADR | Estado real | Superado por | Evidencia | Propuesta de línea `Estado` |
|---|---|---|---|---|
| 0001 VitaSDK | **VIGENTE** | — | `tools/env-devpc.*`, `build-godot-template.sh` | sin cambio |
| 0002 micro-ROS + UDP propio | **VIGENTE** | — | `godot/ros2_vita/xrce_transport.*` usa `microros-transport`/`net-udp` | sin cambio |
| 0003 Rust armv7-sony-vita | **VIGENTE** | — | `tools/build-rust-pic.sh` | sin cambio |
| 0004 `.vpk` con CMake | **PARCIAL** | Para las apps: export de Godot (`tools/export-vita-vpk.sh`, ADR 0008/doc 18). CMake solo sobrevive en `vita-app/` y `tools/hwprobe/` | `tools/hwprobe/CMakeLists.txt:24` | «Aceptado; desde 2026-10-27 solo para `vita-app` (histórico) y `tools/hwprobe`; las apps se empaquetan con Godot (ADR 0008)» |
| 0005 UI vita2d + layout declarativo | **SUPERADO** | ADR 0007 (2026-07-10: vitaGL sustituye a vita2d) y luego ADR 0008 (UI en Godot) | `0007:9-10`; `vita-app/CMakeLists.txt:102` | «Superado por ADR 0007 (2026-07-10) y ADR 0008 (2026-10-27)» |
| 0006 rviz2 descartado → mini-rviz | **PARCIAL** | La mitad «rviz2 no portable» sigue en pie; el Plan B mini-rviz lo superan ADR 0008 §5 enm. (2026-11-11) y ADR 0013 (2026-11-13) | ADR 0008:46-51; ADR 0013 | «Aceptado (rviz2 descartado). Plan B superado por ADR 0008 §5 enm. y ADR 0013» |
| 0007 todo vitaGL | **SUPERADO** | ADR 0008 §5 enm. (2026-11-11): `vita-app` histórica; ADR 0011:58 descarta su vitaGL | ADR 0008:50; ADR 0011:58 | «Superado por ADR 0008 §5 (enmienda 2026-11-11)» |
| 0008 Godot vía módulo estático | **VIGENTE** | — (enmendado) | `0008:3` | Cabecera aún dice «G7 en curso» → actualizar (lote 3) |
| 0009 URDF horneado | **VIGENTE** | — | `0009:3` | — |
| 0010 DB-TSDF | **VIGENTE** (por medir) | — | `0010:3` | — |
| 0011 Presupuesto render | **VIGENTE** (por medir) | — | `0011:3` | — |
| 0012 Puente PC | **VIGENTE** | — | `0012:3` | — |
| 0013 Visor de topics | **VIGENTE** | — | `0013:3` | — |

### 1.3 `docs/ia/` (material para Claude)

| Fichero | Estado | Motivo / superado por | Evidencia |
|---|---|---|---|
| `README.md` | **VIGENTE** (desfasado) | Índice de 2026-10-31: no lista workshops, revision-kimi, prompts ni planes; cita `docs/00–22` (`ia/README.md:8`) | — |
| `guion-ruta-aprendizaje.md` | **VIGENTE·P** | Modo aprendizaje en pausa (2026-11-11, `CLAUDE.md:98-100`) | — |
| `guion-leccion-08-imu.md` | **HISTÓRICO** | G7a cerrada (2026-11-01); acompaña a `tutorial/08` | `06` |
| `guion-g7c-3d-en-la-vita.md` | **HISTÓRICO** | Guion para G7c, hito cerrado 2026-11-01 (`tutorial/10` escrito) | `guion-g7c:3-4` |
| `guion-guia-tutorial-original.md` | **SUPERADO** | Por `docs/tutorial/00` + `07` (la guía nueva); describe la rama `tutorial-vita` y el sandbox `practica/` | `ia/README.md:22-23` |
| `plan-tutorial-2026-07-12.md` | **HISTÓRICO** (en pausa) | Copia del plan de `archivo/docs/superpowers/`; único guion de lecciones 02–06 sin escribir; formato «superpowers» | `ia/README.md:24-26`; `plan-tutorial:3` |
| `spec-tutorial-2026-07-12.md` | **HISTÓRICO** (en pausa) | Igual | `spec-tutorial:3-6` |
| `investigacion-flujo-godot-2026-11-01.md` | **VIGENTE** (referencia) | Flujo IA+Godot; base de `informes/05` | `:1-4` |
| `prompt-siguiente-sesion.md` | **HISTÓRICO** | Prompt de arranque del 2026-11-13, consumido; el plan en ejecución es `plan-organizacion-y-visor-2026-11-13.md` | `prompt:1-4` |
| `plan-organizacion-y-visor-2026-11-13.md` | **VIGENTE** | En ejecución | `:3` |
| `auditoria/README.md` | **VIGENTE** (lotes sin estado, D6 → O1b) | Índice de la auditoría 2026-11-01 | `auditoria/README.md:17-60` |
| `auditoria/01a`, `01b`, `02a`, `02b`, `03` | **HISTÓRICO** | Fotos del 2026-11-01; sus acciones viven en los lotes del README | — |
| `auditoria/04a`, `04b` (DB-TSDF) | **SUPERADO** | Por `docs/26` + ADR 0010 (2026-11-12) | `26:3-4` |
| `revision-kimi/README.md`, `R1`–`R4`, `arreglos-gdscript.md`, `g1-sensores-controles.md` | **HISTÓRICO** | Revisión 2026-11-12/13 integrada (`docs/29`, `30`, plantillas) | `revision-kimi/README.md:3-5` |
| `revision-kimi/*.log` (2) | **HISTÓRICO** (medidas) | Logs de hardware citados por `06` y `34 §7.1`; D4 propone `ia/medidas/` | `06` bloque mediodía |
| `workshops/README.md`, `W-oleada1.md`, `W13-visualizacion-topics.md`, `tablero.json`, `tablero-parches.log` | **VIGENTE** (método) / **HISTÓRICO** (registros) | El README es el método multiagente vigente (sustituye a `docs/19` como método) | `workshops/README.md:1-4` |
| `workshops/posts/*` (40 ficheros, W1–W13) | **HISTÓRICO** | Material fuente de los docs 24–36 | — |

### 1.4 `docs/informes/`

Todos **HISTÓRICO (congelado)**: versiones cortas de la auditoría 2026-11-01; el usuario ya no pide informes cortos
(`CLAUDE.md:103-104`). `04a`/`04b` además **SUPERADOS** por `docs/26` (`26:3-4`). `05-flujo-trabajo-godot.md`: vigente
como resumen. Propuesta D5: conservar y anotar «2026-11-01, congelado» en el índice; no mover (no tienen restos fuera).

### 1.5 `docs/tutorial/`, `docs/rust/`, `docs/guias-vita/`

| Carpeta | Estado | Notas |
|---|---|---|
| `tutorial/00`, `01`, `07`–`10` | **VIGENTE·P** | Modo aprendizaje en pausa (`CLAUDE.md:98-100`); lecciones 02–06 nunca escritas (`ia/README.md:24-26`). `00` necesita revisión (lote 3) |
| `rust/00`–`05` | **VIGENTE** | Regla «explicar cada construcción Rust» (`CLAUDE.md:75-77`). Lote 3: `00`–`02` aún hablan de menos módulos que los 8 actuales |
| `guias-vita/*` (9) | **VIGENTE** | Guías de homebrew; la web las renderiza (en pausa) |

---

## 2. Restos de decisiones descartadas fuera de `docs/`

Formato: **qué** · decisión que lo superó · quién lo referencia aún · **propuesta**.

### R-A. `vita-app/` (app Fase 1: teleop + UI vita2d/vitaGL + mini-rviz)

- **Superado por:** ADR 0008 §5 enm. (2026-11-11: «`vita-app/` queda como app histórica», `0008:50`) y ADR 0011:58.
- **No se puede archivar entera**: tres partes alimentan el build **vigente** de Godot 4 [V]:
  - `vita-app/scripts/build-xrce-client-vita.sh` + `vita-app/third_party/xrce-vita-{pic,host}` → `godot/ros2_vita/SCsub:28-33`,
    `ros_runtime.cpp:59`, `tools/vita-doctor.sh:47-51`, `godot/README.md:68`, skill `vita-build-package/SKILL.md:47,118`.
  - `vita-app/rust-modules/` (crate paraguas de los 8 módulos) → `tools/build-rust-pic.sh:16`, `CLAUDE.md:36`,
    skill `vita-dual-module/SKILL.md:47,116-117`.
  - `vita-app/src/netlog.c` → `tools/hwprobe/CMakeLists.txt:24` (y `godot/godot35`).
- **Restos muertos**: `src/` (teleop, `ui.c`, `viz/` = mini-rviz/VBM), `ui/`, `sce_sys/`, `tests/`, `CMakeLists.txt`,
  `scripts/check-*.sh` y `gen-ui-header.mjs`; los build locales `build-c/`, `build-rust/` (11 MB c/u, ignorados).
  Referencias vivas: `README.md:78,109-112,129-139`, `CLAUDE.md:53-55`, `AGENTS.md:36,53`, `web/Dockerfile:29,55`,
  `web/src/content.config.ts:54`, `web/src/pages/api/taller/build.ts:44-49`, `.dockerignore:11-12`, comentarios de
  `godot/ros2_vita/xrce_transport.{h:4-5,cpp:71,141}` (solo historia, inofensivos).
- **Propuesta (= lote 2b de `ia/auditoria/README.md:29-33`, que sigue sin hacer):**
  1. Extraer lo vivo: `vita-app/rust-modules/` → `rust-modules/` (raíz) o `modules/rust-modules/`;
     `build-xrce-client-vita.sh` → `tools/`; `third_party/` → `toolchains/xrce/` (ya ignorado) o `third_party/` raíz;
     `netlog.c` → `tools/hwprobe/src/`. Reescribir `SCsub:28-33`, `ros_runtime.cpp:59`, `build-rust-pic.sh:16`,
     `vita-doctor.sh:37,47-54`, skills y `CLAUDE.md`/`AGENTS.md`.
  2. Archivar el resto en `archivo/vita-app/` (código versionado, ~pocos cientos de KB; los `build-*` se borran).
  3. **Requiere** decidir antes la web (R-D), porque `web/Dockerfile:29,55` copia `vita-app/`.

### R-B. `godot/godot35/` (teleop en Godot 3.5)

- **Superado por:** ADR 0008 (2026-10-27, Godot 3.5 descartado, `0008:42-45`). Ya marcado histórico en
  `godot/README.md:119-123`, `CLAUDE.md:65`, `README.md:13,89`.
- **Referencias vivas:** `tools/build-godot-template.sh:70` (comentario: SCons recoge también `godot35/modules/microros`
  — [?] comprobar que el build de Godot 4 no lo arrastra; el comentario dice «solo se activa con platform=vita» del 3.5),
  `godot/vitasdk-stubs/dlfcn.h:11` (comentario), `.dockerignore:16-18`, `.gitignore:47-49`, `web/src/content.config.ts:56`,
  `web/src/data/fases.ts`, docs 20/21, `docs/ia/revision-kimi/R3-procedencia.md`.
- Versionado: 25 ficheros / 128 KB; local 124 MB (builds y versiones del motor, ignorados).
- **Propuesta:** archivar `godot/godot35/` → `archivo/godot/godot35/` **junto con** docs 20–21 → `archivo/docs/`
  (lote 2b, «no mover uno sin el otro»); dependencia de `vita-app/src/netlog.c` deja de importar al archivarse.
  Borrar los 124 MB locales no versionados (o moverlos fuera del repo). Lote 1 ya pedía borrar
  `godot35/imagenes/rover-iberus.jpeg.import` y `godot35/UI/UIIcons_2.zip`.

### R-C. `auditoria/` en la raíz (compilaciones de rviz2/OGRE/rcutils/vitaGL, 287 MB, ignorado)

- **Decisión:** ADR 0006 (2026-07-10), evidencia ya volcada en `docs/04` y en el ADR (`0006:16-19`; `04:6-7`).
- **Referencias:** `.gitignore` (`/auditoria/`), `docs/04:6-7`, ADR 0006:18, y `vita-app/CMakeLists.txt:104`
  (usa `auditoria/vitaGL/samples/rotating_cube` como referencia de libs). **Ningún build vigente** lo usa:
  `build-godot-template.sh` usa `toolchains/vitagl-src` (`:14,34`).
- **Propuesta:** guardar los 3 `log-*.txt` (16 KB) en `archivo/auditoria/` (versionados: son la evidencia citada por
  ADR 0006) y **borrar** `build-*/`, `ogre/`, `rcutils/`, `vitaGL/` (clones/compilaciones regenerables). Ajustar la
  línea de `docs/04` y ADR 0006 a la nueva ruta de los logs.

### R-D. `web/` (en pausa) y su «taller»

- **Decisión:** pausa del usuario 2026-11-01 (`CLAUDE.md:84-94`); el taller (`web/src/pages/taller/*`,
  `api/taller/build.ts:44-49`, `debug.ts`) compila y depura **`vita-app` con CMake**, flujo superado por ADR 0008.
  `web/src/data/fases.ts` sigue citado como lugar a actualizar en `CLAUDE.md:12`, `docs/10:38`, `docs/19`.
- **Propuesta:** **no tocar** hasta que el usuario decida el futuro de la web (regla explícita de `CLAUDE.md:86-88`).
  Si se abandona: `archivo/web/`. Si sigue: retirar el taller y las páginas de mini-rviz/visor3d/comparador. Mientras,
  quitar la instrucción «actualizar `fases.ts`» de `CLAUDE.md:12-13` es seguro (ya dice que está en pausa).

### R-E. `tools/`

| Script | Decisión que lo superó | Quién lo usa | Propuesta |
|---|---|---|---|
| `netlog-listen.sh` | Netlog UDP de la Fase 1; Godot 4 usa `godot_stderr.log` por FTP y el agente (`skills/vita-deploy-logs`) | `tools/vita-stack.sh:20,144-147`, `tools/hwprobe/*`, skill `vita-deploy-logs:147`, README raíz | **Conservar** mientras viva `tools/hwprobe/` (sonda vigente, doc 14 §9); lote 3: filtro Kasa |
| `vita-doctor.sh` | — (vigente) pero chequea `cmake` «para vita-app» (`:37`), `vita2d`/`vitaGL` y `vita-app/build*/*.vpk` (`:54`) | `CLAUDE.md` | **Conservar**; reescribir las comprobaciones de Fase 1 al extraer R-A |
| `env-devpc.sh/.fish`, `build-*-pic.sh`, `check-vita-imports.py`, `export-vita-vpk.sh`, `deploy-vpk-ftp.sh`, `run-parity-tests.sh`, `gen_msg_schema.py`, `urdf2godot/`, `convertir-urdf-dae.py`, `diezmar-malla.py`, `generar-*.py`, `install-skills.sh`, `vita-stack.sh` | — | builds/plantillas vigentes | Conservar |
| `tools/__pycache__/` | — | nadie (ignorado) | Borrar (local) |

### R-F. Skills `vita-*` con el flujo Fase 1

`skills/vita-build-package/SKILL.md:13,70-101` (sección «Fase 1» con CMake), `skills/vita-deploy-logs/SKILL.md:82,107-123,161`
(netlog y monitor web), `skills/vita-dual-module/SKILL.md:47,116-117` (paraguas en `vita-app/rust-modules`). Ya están
rotuladas «histórico» en parte. **Propuesta:** conservar las skills (vigentes para Godot 4); recortar las secciones
Fase 1 a una línea con enlace a `archivo/` tras R-A, y actualizar la ruta del paraguas Rust (lote 3).

### R-G. `CLAUDE.md`, `AGENTS.md` y `README.md`

- `CLAUDE.md:21,27,70`: `robotnik_dev` en la laptop (ya marcado «historical»; conservar mientras se use para ROS 2 en
  la laptop [?]). `:36,53-55`: describe `vita-app/` como app vigente → reescribir tras R-A. `:65`: `godot35` histórico →
  quitar tras R-B. `:84-94`: regla de la web suspendida → mantener la nota de pausa, borrar el detalle cuando se decida.
- `AGENTS.md` es una **copia desfasada** de `CLAUDE.md` para Codex (127 vs 131 líneas: le falta la regla de escenas
  editables, `CLAUDE.md:121-127`; tiene una línea de plantillas que `CLAUDE.md` no tiene). **Propuesta:** generar
  `AGENTS.md` desde `CLAUDE.md` (o enlace simbólico) para que no diverjan; ambos heredan los restos anteriores.
- `README.md` raíz: `:78` y `:129-139` presentan la Fase 1 con su receta; `:109-112` lista `check-*.sh` de `vita-app`
  (incl. «cámara orbital del mini-rviz») como «Verificación rápida»; `:145-170` tabla de docs que **omite 22, 24–36 y
  ADR 0009–0013**, presenta 10/11/16/19 como guías vivas y afirma que «toda la documentación se publica en la web».
  **Propuesta:** sustituir la tabla por un enlace a `docs/README.md` (borrador O1c) y mover la receta Fase 1 a
  `archivo/vita-app/README.md` (lote 3).

### R-H. Otros restos

| Resto | Decisión | Referencias | Propuesta |
|---|---|---|---|
| `godot/comun/` (solo `vita_relay.gd.uid`, versionado) | `comun` es ahora un enlace a `../plantillas` en cada proyecto | `godot/plantillas/vita_relay.gd` | **Borrar** (= G2 del plan) |
| `godot/g4-smoke`, `g5-xrce`, `g6-hmi`, `g7-imu`, `g7b-imu3d` | Hitos cerrados (no superados) | `tools/export-vita-vpk.sh:6`, `godot/README.md:35-100`, `docker/vita-ros.sh` (g6), skills, tutorial 08–10 | **Conservar** (regresión y lecciones); agrupar según G1 del plan |
| `media/` (12 MB versionados: vídeo del primer `/cmd_vel`, 2026-07-10) | Histórico | web | Conservar (R5 del plan lo decide Fable) |
| `Videos/` (547 MB, ignorado) | — | nadie | Fuera del repo (local) |
| `docs/ia/guion-guia-tutorial-original.md` | Superado por `tutorial/00`+`07` | `ia/README.md:22` | `archivo/docs/ia/` |
| `docs/ia/auditoria/04a`,`04b`, `docs/informes/04a`,`04b` | Superados por `docs/26` | `26:3-4`, índices | Marcar en índice; archivar opcional |
| Ficheros sueltos de la raíz que cita `06` (`0001-perfil-vita-ligero.patch`, `34-perfil-vita-ligero.md`, `sesion-kimi.md`) | — | `06` bloque «escenas editables» | **Ya no existen** [V] (`ls` vacío): quitar la línea de `06` |

---

## 3. Propuesta de lote de archivo (para el juez Fable)

Orden por dependencias; cada paso deja la paridad y el build de Godot verdes.

1. **Sin dependencias (seguro):** `archivo/docs/` ← docs **10, 11, 16, 20, 21** y `docs/ia/guion-guia-tutorial-original.md`;
   enmendar `Estado:` de ADR 0004–0007; índice `docs/README.md`; borrar `godot/comun/`.
   Reescribir enlaces en README raíz (`:154-158,165-166`), docs 04/12/13/17/18, `godot/README.md:119`, skills
   `vita-build-package`/`ros2-vita-godot` (citan 19), `web/src/data/fases.ts` (web en pausa: tolerar el enlace roto).
2. **Docs 04, 07, 08, 09, 12, 13, 19:** HISTÓRICO/SUPERADO pero muy citados (09 por `vita-app/src/*` y `g6-hmi`;
   04 por ADR 0006). **Propuesta: no moverlos**; solo marcar en el índice. Mover 07–08 cuando se decida la web.
3. **`auditoria/` raíz:** logs → `archivo/auditoria/`, borrar el resto (local, ignorado).
4. **R-A + R-B juntos** (lote 2b): extraer lo vivo de `vita-app`, archivar `vita-app/` y `godot/godot35/`,
   reescribir rutas, `CLAUDE.md`/`AGENTS.md`/README/skills.
5. **R-D web:** solo tras decisión del usuario.
