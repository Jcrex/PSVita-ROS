# Fase O — decisión del juez (Fable 5.2, 2026-11-13)

> Entrada: `docs/ia/plan-organizacion-y-visor-2026-11-13.md` §1–§2, `O1b-auditoria-estado.md`,
> `O1c-clasificacion-docs.md`, `O1c-borrador-docs-README.md`, `O1d-raiz-godot.md` y `O1a-mapa-rutas.json`
> (consultado con python). Encargo del usuario: «arregla la organización archivando decisiones antiguas que han
> sido descartadas pero no limpiadas, luego ejecuta el plan de subagentes». Las decisiones no se le preguntan.
> Regla estructural resultante: `docs/adr/0014-organizacion-del-repositorio.md`.
> Marcas: **[V]** comprobado hoy en el fichero citado · **[I]** inferencia · **[?]** por comprobar en O2.
> Este documento no mueve nada: es la orden de trabajo de O2a–O2d.

## 0. Resumen

| # | Decisión | Refs vivas a reescribir | Riesgo |
|---|---|---|---|
| 1 | Archivar docs **10, 11, 16, 19** y dos de `docs/ia/`; marcar (sin mover) 00, 02, 04, 07, 08, 09, 12, 13; corregir `Estado` de ADR 0004–0008 | ≈ 42 | bajo |
| 2 | Archivar `godot/godot35/` + docs **20–21**; archivar `vita-app/` **ahora**, tras extraer 3 piezas vivas | ≈ 17 + ≈ 65 | medio (SCsub; se mitiga) |
| 3 | `godot/`: **opción A** (plano + `godot/README.md` por grupos). Hitos g4–g7b se quedan. `plantillas` **no** se renombra | 0 | nulo |
| 4 | `auditoria/` → `toolchains/auditoria-rviz2/` (3 logs a `archivo/`); `media/` se queda; `AGENTS.md` = puntero; borrar `godot/comun/`; rutas absolutas de `informe.json` fuera; el resto de duplicados se acepta | ≈ 8 | bajo |
| 5 | `docs/README.md`; bitácora partida por meses; doc 36 partido en 36 + 36a; `docs/ia/{tutorial,medidas}/`; `O1a-mapa-rutas.json` no se versiona | ≈ 35 | bajo |
| 6 | README raíz: 5 secciones; `CLAUDE.md`: solo «What this repo is», línea del paraguas, «Common commands» y «Layout» | — | bajo |

Total ≈ **170** reescrituras en ficheros vivos. La alternativa descartada (opción B para `godot/`) costaba
> 1 000 y tocaba el build de la plantilla.

### Reglas comunes a toda la Fase O

- **R-1 Qué se reescribe.** Solo ficheros **vivos**. Los **registros** no se tocan: `archivo/`,
  `docs/bitacora/`, `docs/ia/workshops/posts/`, `docs/ia/auditoria/`, `docs/ia/revision-kimi/`,
  `docs/ia/organizacion/`, `docs/informes/`. Dicen la ruta que era cierta en su fecha; la tabla de traslados de
  `archivo/README.md` la resuelve. Excepción: los **enlaces Markdown** `[t](ruta)` se arreglan en todo lo que no
  sea `archivo/`.
- **R-2 Menciones abreviadas** («doc 10», `docs/19 §3`) no se reescriben: `docs/README.md` dice dónde está cada
  número. Solo se reescribe la ruta completa (`docs/10-plan-objetivos-3-4.md`).
- **R-3 `web/` está en pausa** (decisión del usuario): no se reescriben sus fuentes. Única excepción: las líneas
  `COPY` de `web/Dockerfile` y `.dockerignore`, para que el build no falle por rutas inexistentes (§2.3).
- **R-4 Un commit por paso** (`chore(org): …` / `docs(org): …`), con los tres juegos de pruebas de host verdes.
  Sin push (lo aprueba el usuario).
- **R-5 Conjunto «vivos»** que usan los comandos de reescritura:

```bash
vivos() { git ls-files -- '*.md' '*.sh' '*.fish' '*.py' '*.gd' '*.cpp' '*.h' '*.c' '*.toml' '*.txt' '*.cfg' \
            '*SCsub' .gitignore .dockerignore \
  | grep -vE '^(archivo/|web/|godot/rclgd/|docs/bitacora/|docs/informes/|docs/ia/(workshops/posts|auditoria|revision-kimi|organizacion)/)'; }
# reescribe una ruta completa sin duplicar el prefijo si ya está archivada
mover_ruta() { vivos | xargs -r perl -pi -e "s{(?<!archivo/)\Q$1\E}{$2}g"; }
```

---

## 1. Docs: qué se archiva y qué solo se marca

Criterio (ADR 0014 §2): se archiva lo **superado** (la decisión o el plan fue sustituido) o **ejecutado y
cerrado** que nadie necesita para trabajar hoy. Lo **histórico pero aún citado como fuente técnica** se queda y
se marca. Sin renumerar: los huecos de numeración los explica `docs/README.md`.

### 1.1 Se archivan en `archivo/docs/`

| Doc | Motivo | Refs totales / vivas (O1a) | Quién se reescribe |
|---|---|---|---|
| `10-plan-objetivos-3-4.md` | Superado: ADR 0008 §5 (enm. 2026-11-11) y ADR 0013 | 35 / 18 | README:154; docs 04 (2), 12, 13 (2); ADR 0006 (2), 0007; `modules/{msg-cdr (3+1 py),tf-tree,viz-math}/README.md` |
| `11-diseno-mini-rviz.md` | Superado: ADR 0013 (visor en Godot) | 36 / 15 | README:155; docs 04, 13, 14; ADR 0007; `modules/msg-cdr/{README.md,include/msg_cdr.h:7}`, `modules/msg-ring/README.md`, `modules/viz-math/{README.md,include/viz_math.h:7}` (comentarios) |
| `16-paginas-pendientes-de-leer.md` | Superado: lista de lectura para Godot 3.5 | 12 / 4 | README:161; doc 17 (2); doc 18:387 |
| `19-plan-multiagente-migracion-godot4.md` | Plan ejecutado (G1–G7 verdes); el método vigente es `docs/ia/workshops/README.md` | 47 / 10 | README:162; doc 18 (2); ADR 0008:66; `modules/tf-tree/README.md:34`; skills `ros2-vita-godot` (4), `vita-build-package:92` |
| `ia/guion-guia-tutorial-original.md` | Superado por `docs/tutorial/00` + `07` | 5 / 0 | `docs/ia/README.md` |
| `ia/prompt-siguiente-sesion.md` | Prompt del 2026-11-13 ya consumido | 1 / 0 | — |

Docs 20 y 21 se archivan en O2c **junto con** `godot/godot35/` (regla del lote 2b: no uno sin el otro).

- **Riesgo:** bajo. Dos cabeceras C cambian un comentario (`msg_cdr.h:7`, `viz_math.h:7`): lo cubre
  `tools/run-parity-tests.sh`.
- **Reversión:** `git revert` del commit de O2b (son `git mv` + sustituciones).

### 1.2 Se quedan y solo se marcan

Se añade o corrige **una** línea de estado bajo el título (`> **Estado (2026-11-13):** …`) y la columna
«Estado» de `docs/README.md`:

| Doc | Línea de estado |
|---|---|
| 00 | «Vigente como marco. El orden estricto por objetivos y “la laptop no instala nada” ya no describen el trabajo: producto = Godot 4 + `ros2_vita` (ADR 0008).» |
| 02 | Quitar «incógnita dura pendiente» (`02:4`): cerrada en hardware (doc 13 §2). |
| 04 | «Histórico. Conclusión vigente (rviz2 no portable). El Plan B mini-rviz está superado por ADR 0008 §5 y ADR 0013.» + nueva ruta de los logs (§4.1). |
| 07, 08 | «EN PAUSA con la web (usuario, 2026-11-01).» En 08 sustituye a «En curso» (`08:4`). **No se mueven**: su suerte es la de `web/`. |
| 09 | «Histórico: Objetivo 2 cerrado en hardware. El mapeo de mandos lo reutiliza `godot/g6-hmi/main.gd`.» (hoy dice «en implementación», `09:3`). |
| 12 | «Histórico. Godot 3.5 y rosbridge descartados (ADR 0008); §4 (XRCE) sigue siendo referencia.» |
| 13 | «Histórico. La tabla de objetivos (`13:34-42`) está superada por doc 33 y doc 18; §3 sigue útil.» |
| `ia/auditoria/04a`, `04b`; `informes/04a`, `04b` | Sin tocar el fichero; en los índices: «superado por doc 26 + ADR 0010». |
| `informes/` | En `docs/README.md`: «2026-11-01, congelado». |

Por qué no se mueven 04, 09, 12 y 13: los cita código o documentación viva como **fuente** (09 ← `g6-hmi`;
04 ← ADR 0006; 12 §4 ← 13, 17; 13 ← `ros2_vita`, `msg-ring`). Moverlos son ≈ 60 reescrituras sin ganar claridad
que no dé ya el índice.

### 1.3 ADRs: no se archivan nunca; se corrige `Estado`

| ADR | Nueva línea `- **Estado:**` |
|---|---|
| 0004 | Aceptado; **alcance reducido desde 2026-10-27**: CMake solo empaqueta `tools/hwprobe` y la app histórica (`archivo/vita-app/`). Las apps se exportan con Godot (ADR 0008; `tools/export-vita-vpk.sh`). |
| 0005 | **Superado** por ADR 0007 (2026-07-10, vitaGL sustituye a vita2d) y por ADR 0008 (2026-10-27, la UI se hace en Godot). |
| 0006 | Aceptado en su primera mitad (rviz2 nativo descartado). **Plan B (mini-rviz) superado** por ADR 0008 §5 (enmienda 2026-11-11) y ADR 0013 (2026-11-13). |
| 0007 | **Superado** por ADR 0008 §5 (enmienda 2026-11-11): `vita-app` es histórica; ADR 0011 descarta su vitaGL. |
| 0008 | Sustituir «G7 en curso» por «G7a–G7c verdes (2026-11-01)»; el resto igual. |

Coste: 5 líneas. Riesgo nulo. Además `docs/README.md` lleva la tabla de ADRs con la columna «Estado real».

---

## 2. `godot/godot35/`, docs 20–21 y `vita-app/`

### 2.1 `godot/godot35/` + docs 20–21 → `archivo/` (O2c)

- **Motivo:** Godot 3.5 descartado por ADR 0008 (2026-10-27). Ya rotulado histórico en tres sitios.
- **Coste:** 85 refs totales; **12 vivas** (`.dockerignore:16-18`, `.gitignore:47-49`, `CLAUDE.md:65`,
  `README.md:13,89`, doc 18:241, `godot/README.md:119,123`, `godot/vitasdk-stubs/dlfcn.h:11`,
  `tools/build-godot-template.sh:70`) + 5 de los docs 20–21.
- **Efecto útil:** `custom_modules=<repo>/godot` deja de encontrar `godot35/modules/microros`
  (`build-godot-template.sh:68-70` [V]); el comentario se actualiza, el argumento no cambia.
- **Local sin versionar** (124 MB): `git mv` de la carpeta la renombra entera, así que viaja todo. Después se
  borran `.import/` y `build/` (69 MB, regenerables) y se conserva `versiones/` (3 `.vpk` validados en hardware).
- **Riesgo:** bajo. `godot35` y `vita-app` conservan su posición relativa dentro de `archivo/`
  (`archivo/godot/godot35/../../vita-app` = `archivo/vita-app`), así que sus referencias mutuas siguen valiendo.
- **Reversión:** `git revert`; lo no versionado se devuelve con `mv`.

### 2.2 `vita-app/`: se extrae lo vivo y se archiva el resto, **ahora** (O2c)

No se pospone: es el resto más visible de decisiones descartadas (teleop vita2d, mini-rviz/VBM, CMake), ADR 0008
§5 la declara histórica desde el 2026-11-11 y la Fase V va a escribir justo en la zona que hoy la cita
(`ros2_vita`, skills). Hacerlo después obligaría a tocar dos veces las mismas líneas.

**Coste real** de las 659 referencias (O1a) [V]:

| Grupo | Nº | Qué se hace |
|---|---|---|
| Dentro de `vita-app/third_party/` (clones de eProsima, sin versionar) | 214 | nada (se mueven con la carpeta) |
| Dentro de `vita-app/` versionado | ≈ 50 | viajan con `git mv` |
| Registros (`docs/ia/`, bitácora, informes, `archivo/`, `godot35`) | ≈ 250 | nada (R-1) |
| `web/src` | 18 | nada (R-3; ver §2.3) |
| Docs 10 y 11 (se archivan) | 40 | nada |
| **Vivas** | **≈ 65** | reescribir (lista en O2c) |

**Destino de las tres piezas vivas:**

| Pieza | Destino | Por qué ahí |
|---|---|---|
| `vita-app/rust-modules/` (crate paraguas, 3 ficheros) | **`modules/paraguas-rust/`** | Es el agregado Rust de los módulos: vive con ellos. No añade otra carpeta a la raíz. `run-parity-tests.sh` lo salta solo («sin parity_test.c, omitido», `tools/run-parity-tests.sh:53` [V]). El nombre del crate (`vita_modules_rust`) y el de la lib (`libvita_modules_rust.a`) **no cambian**; solo las rutas del `Cargo.toml` (`../../modules/X/impl-rust` → `../X/impl-rust`). |
| `vita-app/scripts/build-xrce-client-vita.sh` | **`tools/build-xrce-client-vita.sh`** | Es una receta de build del PC, como `build-rust-pic.sh` y `build-pcre2-vita.sh`. |
| `vita-app/third_party/xrce-vita{,-pic,-host}` (salida, sin versionar) | **`toolchains/xrce/`** | Artefactos regenerables del PC, como `toolchains/pic` y `toolchains/vitagl-src`; ya está ignorado. Descartado `third_party/` en la raíz: otra carpeta ignorada más. |
| `vita-app/src/netlog.{c,h}` | **copia** en `tools/hwprobe/src/` | Único consumidor vivo (`tools/hwprobe/CMakeLists.txt:24` [V]). Se copia (no `git mv`) para que la app archivada quede completa. |

**Riesgo principal y cómo se ata.** `godot/ros2_vita/SCsub:32-36` busca las libs XRCE en
`vita-app/third_party/…` y, **si no las encuentra, compila igual sin transporte** (`SCsub:47` «SIN transporte
XRCE») [V]. Un traslado mal hecho daría una plantilla que arranca y no conecta. Mitigación obligatoria:

1. Mover las libs ya compiladas (`mv`, no recompilar) y cambiar la ruta por defecto del SCsub en el mismo commit.
2. Comprobación estática de que las cuatro `.a` existen en la ruta nueva (comando en O2c).
3. `tools/build-godot-template.sh` gana una guarda antes del paso 3: aborta si falta
   `toolchains/xrce/xrce-vita-pic/lib/libmicroxrcedds_client.a`, salvo `ROS2_VITA_SIN_XRCE=1`.
4. `tools/vita-doctor.sh` apunta a la ruta nueva.
5. **No hace falta recompilar** la plantilla ni el editor de host: ninguna fuente compilada cambia de contenido
   (solo comentarios). Marcador en `SCsub`: «ruta de las libs cambiada el 2026-11-13 (ADR 0014): validar en el PC
   en la próxima recompilación — debe imprimir “transporte XRCE activado (…/toolchains/xrce/xrce-vita-pic)”».

El paraguas Rust sí se puede verificar hoy en este PC con `tools/build-rust-pic.sh` (minutos).

**Reversión:** `git revert` del commit + `mv toolchains/xrce/* vita-app/third_party/`.
La app archivada no compila en su sitio nuevo (su CMake usa `../modules`): para recompilarla,
`git mv archivo/vita-app vita-app` (se anota en `archivo/README.md`).

### 2.3 `web/` (en pausa): mínimo para no romper el build

- `web/Dockerfile:29` → `COPY archivo/vita-app/ /app/vita-app/`; `:55` no cambia (ruta **dentro** de la imagen).
  Así el taller y `content.config.ts:54` siguen viendo `/app/vita-app` sin tocar `web/src`.
- Añadir `COPY archivo/godot/godot35/README.md /app/godot/godot35/README.md` (lo pide `content.config.ts:56`).
- `.dockerignore:11-12,16-18` → rutas nuevas (`modules/paraguas-rust/target/`, `archivo/godot/godot35/…`).
- `web/README.md`: una nota: «Rutas ajustadas a ADR 0014 **sin probar** (web en pausa). `pnpm dev` fuera de Docker
  no verá `vita-app/README.md` ni `godot/godot35/README.md`; los docs archivados (10, 11, 16, 19, 20, 21)
  desaparecen de la colección `docs/*.md` y `fases.ts` conserva enlaces rotos hacia ellos.»
- No se construye la web. Se arreglará o se archivará entera cuando el usuario decida.

---

## 3. `godot/`

### 3.1 Opción A: estructura plana + `godot/README.md` por grupos

**Descartada la opción B** (`motor/`, `hitos/`, `apps/`, `historico/`):

- **Coste:** `ros2_vita` 278 + `plantillas` 277 + `test` 42 + `loader-patches` 24 + `vitasdk-stubs` 10 + apps 250 +
  hitos 137 ≈ **1 018 referencias** (O1a), más 7 enlaces simbólicos versionados (`O1d` §2.1).
- **Riesgo de build:** `SCsub:21` calcula la raíz como `here/../..` y `godot/test/run_host_tests.sh:10` igual
  [V]; `build-godot-template.sh:74` pasa `custom_modules` como ruta absoluta a un build de 1–2 h que solo existe
  en este PC [V]. Un nivel más de carpeta rompe los tres y solo se nota al recompilar.
- **Ganancia:** estética. Tras archivar `godot35` y borrar `comun`, quedan 15 entradas que un README agrupa bien.

Grupos que fija `godot/README.md` (y la tabla de `CLAUDE.md`):

| Grupo | Carpetas |
|---|---|
| Motor | `ros2_vita/`, `loader-patches/`, `vitasdk-stubs/`, `test/` |
| Biblioteca compartida | `plantillas/` (en los proyectos se ve como `res://comun`) |
| Apps vivas | `g1-unitree/`, `g1-sensores/`, `rbkairos-plus/`, `dron-mapeo/` (+ `visor-ros/` en la Fase V) |
| Puertas cerradas (regresión y lecciones) | `g4-smoke/`, `g5-xrce/`, `g6-hmi/`, `g7-imu/`, `g7b-imu3d/` |
| Externo, sin versionar | `rclgd/` |

El README añade la tabla de los 7 enlaces simbólicos (hallazgo G3) y la advertencia de `core.symlinks`.

### 3.2 Hitos g4–g7b: se quedan

No son decisiones descartadas: son las pruebas de regresión de las puertas G4–G7, el material de las lecciones
08–10 y código que cita el doc 36 como patrón (`g6-hmi/main.gd`). Tampoco se agrupan en `godot/hitos/`: 56
reescrituras vivas (tutorial, `docker/vita-ros.sh:55`, skills) para ahorrar cinco líneas de `ls`.
**Regla** (ADR 0014 §3): una puerta se archiva cuando otra app la **sustituye** como prueba, no por estar
cerrada. Candidatas al cerrar la Fase V1: `g6-hmi` y `g7b-imu3d` si `visor-ros` cubre lo que prueban.

### 3.3 `plantillas` no se renombra

- ADR 0013 D15 (aceptado hoy) y el doc 36 ya fijan `godot/plantillas/visor/` (= `res://comun/visor/`), y ADR
  0013:45 dice expresamente que `godot/comun/` «no se resucita» [V].
- Las 393 referencias a `res://comun` **no dependen** del nombre de la carpeta (es el nombre del enlace). Renombrar
  no las toca, pero sí 277 referencias a `godot/plantillas/`, 4 enlaces, la regla de escenas de `CLAUDE.md`, los
  docs 29 y 35 y la memoria. Ganancia: un nombre algo más exacto.
- El visor se crea donde dice el ADR 0013. No hay doble movimiento. `godot/README.md` y `godot/plantillas/README.md`
  aclaran en su primera línea: «biblioteca compartida de los proyectos; `plantillas` es nombre histórico».

Riesgo y reversión: no aplica (no se mueve nada).

---

## 4. Raíz, duplicados y restos

| Tema | Decisión | Motivo | Coste / riesgo / reversión |
|---|---|---|---|
| `auditoria/` raíz (287 MB, ignorada) | `mv auditoria toolchains/auditoria-rviz2`; **copiar** los 3 `log-*.txt` (16 KB) a `archivo/auditoria/` (versionados) | Nada vigente la usa (`build-godot-template.sh` usa `toolchains/vitagl-src`). No se borra: `ogre`, `vitaGL` y `rcutils` son clones con `.git` propio y borrar lo no versionado es irreversible. Los logs son la evidencia que cita ADR 0006 | 3 refs: `docs/04:7`, ADR 0006:18, `.gitignore:39-41` (se quita la regla `/auditoria/`). Nulo. `mv` de vuelta |
| `Videos/` (547 MB, ignorada) | No se toca | Material del usuario | — |
| `media/` (12 MB, 2 ficheros) | Se queda | Ya está en la historia pública (sacarlo no adelgaza el repo) y el README lo enlaza. **Regla nueva:** ningún binario > 1 MB más en git; vídeos y `.vpk` fuera | 0 |
| `AGENTS.md` | Sustituir por un puntero de ≈ 8 líneas: «Lee `CLAUDE.md` entero antes de nada; es la única guía. Donde diga “Claude Code”, léase el agente en uso» | La copia ya ha divergido (28 líneas de `diff`). Descartado el enlace simbólico (rompe con `core.symlinks=false`) y el script generador (otro paso que olvidar) | 0 refs. `git revert` |
| `godot/comun/` | `git rm -r godot/comun` | Solo queda un `.uid` huérfano (`O1d` §5) | 3 menciones vivas que hablan de él como destino: `docs/31:357-358` y ADR 0011:73 → `godot/plantillas/` |
| Assets `PSVita/` idénticos en `g7-imu` y `g7b-imu3d` (24 ficheros, 1,5 MB) | Se aceptan | Proyectos congelados y autocontenidos; un enlace añadiría dependencia entre dos puertas | 0 |
| `urdf_robot.gd` (idéntico en `g1-unitree/robot/` y `rbkairos-plus/robot/`) | **No ahora.** Se unifica en `godot/plantillas/robots/urdf_robot.gd` la primera vez que la Fase V lo modifique (V9, `robot_joints`/TF) | Las 4 escenas `*_pc.tscn`/`*_vita.tscn` son **generadas** (`tools/urdf2godot/urdf2godot.py`): hay que cambiar el generador y regenerar, y son los proyectos a 57–60 FPS validados en hardware. Mientras: `cmp` de ambos en la lista de comprobación de `godot/README.md` | 0 hoy |
| 10 `schema.rsch` (4 versiones) | Se aceptan: un esquema por proyecto es intencionado (cada app lleva sus tipos; lo exporta dentro del `.vpk`) | Unificar es la tarea M8 de `docs/18:335`, no organización | 1: corregir en `godot/README.md` §«Esquema» la frase de «4 copias idénticas» (son 5 + la del módulo) |
| Rutas absolutas en 4 `informe.json` (`/home/jcrex/…`, `/tmp/claude-1000/…`) | Reescribirlas a rutas relativas al repo y corregir el generador (`urdf2godot.py:147,264`: `os.path.abspath` → `os.path.relpath(…, raiz_repo)`) | Repo público; rutas de una máquina. Nada los lee en ejecución [?: O2c lo confirma con `grep`] | 4 ficheros + 2 líneas. Bajo |
| Dos `runner.gd` (`plantillas/pruebas/`, `test/project/`) | Se aceptan; `godot/README.md` nombra ambos con su comando | Renombrar rompe los comandos de docs 29, 34 y 36 | 0 |
| `.codex/`, `.obsidian/` | Ya ignoradas (`.gitignore:61-62` [V]) | — | 0 |
| Sueltos de R2 (`0001-…patch`, `34-…md`, `sesion-kimi.md`) | Ya no existen (`O1c` R-H); quitar la línea que los menciona en la bitácora | — | 1 |

---

## 5. `docs/`

### 5.1 `docs/README.md`

Se crea a partir de `O1c-borrador-docs-README.md`, con estos cambios: los docs archivados salen de la tabla
principal y pasan a una tabla «Archivados» (nº → `archivo/docs/…`, motivo); se añaden `bitacora/`, `36a`,
`ia/tutorial/`, `ia/medidas/` y el ADR 0014; primera línea: «para retomar: `06-bitacora-estado.md`».

### 5.2 Bitácora (1 845 líneas) → `06` + `docs/bitacora/`

`docs/06-bitacora-estado.md` conserva su ruta (115 referencias siguen valiendo) y pasa a contener solo:
cabecera, **un** bloque «Estado para retomar» y las sesiones abiertas (hoy, las siete del 2026-11-13).
**Regla:** tope de 300 líneas; al superarlo o cerrar mes, las sesiones más antiguas bajan al fichero del mes.

| Fichero nuevo | Bloques (por encabezado `## `; líneas de hoy) |
|---|---|
| `docs/bitacora/2026-11.md` | «2026-11-12 (PC, noche) — Revisión del trabajo de Kimi…» hasta «2026-11-01 (PC) — Auditoría de la flota…» (146–393) |
| `docs/bitacora/2026-10.md` | «2026-10-31 (PC, cierre…)» hasta «2026-10-29 (PC) — Fusión de `godot-migration`…» (394–795) |
| `docs/bitacora/2026-06-07-fases-0-1.md` | «Dónde nos quedamos… HISTÓRICO» hasta el final (796–1845) |
| `docs/bitacora/README.md` | índice de 10 líneas y la regla |

Se corta **por encabezado**, no por número de línea. Coste: las citas `docs/06-bitacora-estado.md:NNN` de
ficheros vivos quedan desfasadas [?: pocas; O2b las lista con el comprobador] → se cambian por «bitácora
AAAA-MM-DD». Las de los registros no se tocan (R-1). Riesgo bajo; reversión con `git revert`.

### 5.3 Doc 36 (3 913 líneas) → `36` + `36a`

Se parte **antes** de la Fase V: cada agente V lee solo su parte (V1 → §2; V2 → §3; V3… → fichas de §4).

- `docs/36a-catalogo-displays.md` ← la sección «## 4. Catálogo por tipo» entera (hoy 1252–3458, ≈ 2 200 líneas),
  conservando su numeración (§4.x) y con una cabecera de 5 líneas que remite al 36.
- `docs/36-visualizacion-topics-godot.md` conserva §0–§3 y §5–§12 (≈ 1 700 líneas); en el lugar de §4 queda el
  título y un párrafo: «→ `36a-catalogo-displays.md`».
- Convención: «doc 36 §4.x» significa 36a. Las citas por línea al 36 desde ficheros vivos (ADR 0013, doc 31)
  [?: O2b las lista] se pasan a cita por sección.
- Cuando exista el código (V1+), el código es la fuente y las fichas se reducen a la tabla (ya lo dice el plan).

### 5.4 `docs/ia/`

Mínimo necesario; no se renombra lo que ya tiene carpeta.

| Movimiento | Refs (O1a) |
|---|---|
| `guion-ruta-aprendizaje.md`, `guion-leccion-08-imu.md`, `guion-g7c-3d-en-la-vita.md`, `plan-tutorial-2026-07-12.md`, `spec-tutorial-2026-07-12.md` → `docs/ia/tutorial/` | 5 + 8 + 5 + 4 + 3 = 25 |
| `revision-kimi/g1-sensores-vita-2026-11-13.log`, `…-ligero-vita-2026-11-13.log` → `docs/ia/medidas/` (aquí irán los logs de hardware de los gates de la Fase V) | 5 |
| `guion-guia-tutorial-original.md`, `prompt-siguiente-sesion.md` → `archivo/docs/ia/` | §1.1 |
| Se quedan: `auditoria/`, `revision-kimi/`, `workshops/`, `organizacion/`, `investigacion-flujo-godot-2026-11-01.md`, `plan-organizacion-y-visor-2026-11-13.md`, `README.md` | 0 |

`docs/ia/README.md` se reescribe como índice de carpetas (hoy cita «`docs/00–22`» y no lista workshops, revisión,
medidas ni organización). `docs/ia/auditoria/README.md`: marcar lotes 0, 1, 2a y 3 cerrados en `bbbfa2d`, lote 2b
cerrado por esta fase, R2 y R3 hechos (tabla de `O1b`); lotes 4–5 siguen abiertos (son código, no organización).

### 5.5 `O1a-mapa-rutas.json`

**No se versiona.** Es una foto generada de 487 KB que caduca con el primer `git mv`, y contiene rutas de
ficheros locales (`.claude/settings.local.json`, `.obsidian/`) en un repo público. Se añade a `.gitignore`
(`docs/ia/organizacion/O1a-mapa-rutas.json`), se usa durante O2 y se borra al cerrar O3. Lo que queda versionado
es su resumen: los costes de este documento. `O1b`, `O1c`, `O1d` y este fichero sí se versionan.

---

## 6. README raíz y `CLAUDE.md` (O2d)

**`README.md`:**

| Sección (líneas de hoy) | Cambio |
|---|---|
| Estado (10–13) | G1–G7c verdes; producto vivo = apps Godot 4 (`g1-unitree`, `g1-sensores`, `rbkairos-plus`, `dron-mapeo`) + `plantillas`; siguiente: visor (ADR 0013). Quitar `godot35` |
| «Mapa del repo» (64–104) | Árbol nuevo: sin `vita-app/` ni `godot35/`; con `archivo/`, `docker/`, `modules/paraguas-rust/`, grupos de `godot/` |
| «Verificación rápida» (105–116) | Quitar `vita-app/scripts/check-*.sh`; poner paridad, `godot/test/run_host_tests.sh`, runner de plantillas, `tools/check-doc-links.py` |
| «Compilar para la Vita» (117–145) | Flujo Godot 4 (`build-godot-template.sh` → `export-vita-vpk.sh` → `deploy-vpk-ftp.sh`). La receta de la Fase 1 se reduce a una línea → `archivo/vita-app/README.md` |
| «Documentación» (146–173) | Sustituir la tabla por un enlace a `docs/README.md`; quitar «toda la documentación se publica en la web» (web en pausa) |

**`CLAUDE.md`.** Lo edita O2d porque el plan aprobado por el usuario lo incluye (fila O2d). Límite: **solo
hechos de rutas**; ni una regla de trabajo cambia (método, shells, escenas, web en pausa, convenciones).

| Sección | Cambio |
|---|---|
| «What this repo is» | Añadir «índice de docs: `docs/README.md`»; la bitácora antigua está en `docs/bitacora/`; quitar la mención a `fases.ts` (ya dice que la web está en pausa) |
| «Core architectural constraint» | `vita-app/rust-modules/` → `modules/paraguas-rust/` |
| «Common commands» | Añadir pruebas de host de Godot (las dos) y `tools/check-doc-links.py` |
| «Layout» | Reescribir: viñeta de `vita-app/` fuera (→ `archivo/`); viñeta de `godot/` (12 líneas) → tabla de grupos de §3.1 con una línea por carpeta; nueva viñeta `docs/` (índice, `bitacora/`, `ia/{tutorial,medidas,workshops,auditoria,organizacion}`); `archivo/` con lo archivado hoy; `tools/` con `build-xrce-client-vita.sh` y `toolchains/xrce/` |
| «Conventions» | Una viñeta: «Archivar y mover: reglas del ADR 0014» |

Además: `AGENTS.md` (puntero, §4), skills (`vita-build-package:12,47,54,92,118`; `vita-dual-module:47,116-117`;
`vita-deploy-logs:81,107-123`; `ros2-vita-godot:10,16,40,65`) y después `tools/install-skills.sh`; memoria
`estado-proyecto.md`.

---

## 7. Orden de ejecución

Los comandos son para los agentes (bash). Cada paso empieza con el árbol limpio y acaba en un commit.

### O2.0 — línea base (antes de tocar nada)

```bash
cd /home/jcrex/Proyectos/PSVita-ROS
GH=toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
tools/run-parity-tests.sh                                   2>&1 | tail -20
godot/test/run_host_tests.sh "$GH"                          2>&1 | tail -20
"$GH" --headless --path godot/g1-sensores --script res://comun/pruebas/runner.gd 2>&1 | tail -20
```

Si algo ya está rojo, se anota en `docs/ia/organizacion/O2-linea-base.md` y no se atribuye a la Fase O.

### O2a — raíz (commit `chore(org): limpia la raíz (ADR 0014)`)

```bash
# 1. registros de la Fase O: el mapa no se versiona
printf '\n# Foto generada de referencias (Fase O); caduca con cada movimiento\ndocs/ia/organizacion/O1a-mapa-rutas.json\n' >> .gitignore
# 2. auditoria/ de rviz2: logs al archivo, el resto a toolchains/ (ya ignorado)
mkdir -p archivo/auditoria && cp auditoria/log-*.txt archivo/auditoria/
mv auditoria toolchains/auditoria-rviz2
#    .gitignore: borrar las 3 líneas del bloque «/auditoria/» (comentario incluido)
#    docs/04:7 y docs/adr/0006:18 → «logs en `archivo/auditoria/`; clones en `toolchains/auditoria-rviz2/` (sin versionar)»
# 3. residuo
git rm -r godot/comun
# 4. AGENTS.md → puntero (§4)
# 5. cachés locales
rm -rf tools/__pycache__ godot/ros2_vita/__pycache__
# 6. archivo/README.md: fila de `auditoria/log-*.txt`
git add -A docs/ia/organizacion docs/ia/plan-organizacion-y-visor-2026-11-13.md docs/adr/0014-organizacion-del-repositorio.md
```

Reescrituras: `docs/31:357-358` y ADR 0011:73 (`godot/comun/` → `godot/plantillas/`).
**Verde:** `git status --short` solo muestra lo anterior; `git check-ignore docs/ia/organizacion/O1a-mapa-rutas.json`
responde; `test -d toolchains/auditoria-rviz2/vitaGL`; `grep -rn '"auditoria/' tools godot/ros2_vita` vacío.

### O2b — docs (commit `docs(org): índice, archivo de docs superados, bitácora y doc 36 partidos`)

```bash
# 0. comprobador de enlaces (nuevo; no existe ninguno) y línea base
#    tools/check-doc-links.py: (a) enlaces Markdown relativos de todo *.md versionado salvo archivo/ y godot/rclgd/;
#    (b) rutas entre comillas invertidas que empiecen por docs/ godot/ tools/ modules/ skills/ docker/ archivo/
#        (con o sin :línea) en los ficheros «vivos» de R-5. Sale con 1 si hay rotos; --baseline f.txt los resta.
python3 tools/check-doc-links.py > /tmp/enlaces-antes.txt || true

# 1. archivar docs superados (sin renumerar)
mkdir -p archivo/docs/ia
for d in 10-plan-objetivos-3-4 11-diseno-mini-rviz 16-paginas-pendientes-de-leer 19-plan-multiagente-migracion-godot4; do
  git mv docs/$d.md archivo/docs/$d.md; mover_ruta "docs/$d.md" "archivo/docs/$d.md"; done
git mv docs/ia/guion-guia-tutorial-original.md docs/ia/prompt-siguiente-sesion.md archivo/docs/ia/

# 2. docs/ia: subcarpetas
mkdir -p docs/ia/tutorial docs/ia/medidas
for f in guion-ruta-aprendizaje guion-leccion-08-imu guion-g7c-3d-en-la-vita plan-tutorial-2026-07-12 spec-tutorial-2026-07-12; do
  git mv docs/ia/$f.md docs/ia/tutorial/$f.md; mover_ruta "docs/ia/$f.md" "docs/ia/tutorial/$f.md"; done
for f in g1-sensores-vita-2026-11-13 g1-sensores-ligero-vita-2026-11-13; do
  git mv docs/ia/revision-kimi/$f.log docs/ia/medidas/$f.log
  mover_ruta "docs/ia/revision-kimi/$f.log" "docs/ia/medidas/$f.log"; done

# 3. bitácora: cortar por encabezado (§5.2) → docs/bitacora/{2026-11,2026-10,2026-06-07-fases-0-1,README}.md
# 4. doc 36: sección «## 4. Catálogo por tipo» → docs/36a-catalogo-displays.md (§5.3)
# 5. docs/README.md (§5.1), docs/ia/README.md y docs/ia/auditoria/README.md (§5.4)
# 6. líneas de estado: docs 00, 02, 04, 07, 08, 09, 12, 13 (§1.2) y ADR 0004–0008 (§1.3)
# 7. archivo/README.md: una fila por cosa archivada + quitar el párrafo «Pendiente de decisión del usuario»
```

Enlaces relativos (`(10-plan-…md)`, `../docs/…`) y citas por línea al 06 y al 36: los saca el comprobador; se
arreglan a mano. **Verde:**

```bash
python3 tools/check-doc-links.py --baseline /tmp/enlaces-antes.txt     # 0 rotos nuevos
wc -l docs/06-bitacora-estado.md                                       # ≤ 300
cat docs/06-bitacora-estado.md docs/bitacora/2026-*.md | wc -l         # ≥ 1 845 (no se pierde texto)
cat docs/36-visualizacion-topics-godot.md docs/36a-catalogo-displays.md | wc -l   # ≥ 3 913
tools/run-parity-tests.sh msg-cdr && tools/run-parity-tests.sh viz-math  # comentarios de las cabeceras
```

### O2c — godot y `vita-app` (commit `chore(org): archiva vita-app y godot35; extrae paraguas Rust y cliente XRCE`)

```bash
# --- A. godot35 + docs 20–21 ---------------------------------------------------------------
mkdir -p archivo/godot
git mv godot/godot35 archivo/godot/godot35
rm -rf archivo/godot/godot35/.import archivo/godot/godot35/build        # 69 MB regenerables; versiones/ se queda
git mv docs/20-godot35-migracion-historico.md docs/21-godot35-plan-implementacion-historico.md archivo/docs/
mover_ruta "docs/20-godot35-migracion-historico.md" "archivo/docs/20-godot35-migracion-historico.md"
mover_ruta "docs/21-godot35-plan-implementacion-historico.md" "archivo/docs/21-godot35-plan-implementacion-historico.md"
mover_ruta "godot/godot35/" "archivo/godot/godot35/"
#   a mano: tools/build-godot-template.sh:68-70 (comentario), godot/vitasdk-stubs/dlfcn.h:11, .gitignore:47-49

# --- B. piezas vivas de vita-app -----------------------------------------------------------
git mv vita-app/rust-modules modules/paraguas-rust
rm -rf modules/paraguas-rust/target
perl -pi -e 's{path = "\.\./\.\./modules/}{path = "../}' modules/paraguas-rust/Cargo.toml
#   + comentario en Cargo.toml: «movido desde vita-app/rust-modules el 2026-11-13 (ADR 0014)»
git mv vita-app/scripts/build-xrce-client-vita.sh tools/build-xrce-client-vita.sh
#   en el script: REPO="$(cd "$SCRIPT_DIR/.." && pwd)"; PREFIX="$REPO/toolchains/xrce/xrce-vita$SUFFIX";
#   WORK="$REPO/toolchains/xrce/_build"; comentarios de cabecera (líneas 9, 40)
mkdir -p toolchains/xrce tools/hwprobe/src
mv vita-app/third_party/xrce-vita vita-app/third_party/xrce-vita-pic vita-app/third_party/xrce-vita-host \
   vita-app/third_party/_build toolchains/xrce/
cp vita-app/src/netlog.c vita-app/src/netlog.h tools/hwprobe/src/ && git add tools/hwprobe/src/netlog.[ch]
#   tools/hwprobe/CMakeLists.txt:24 → quitar APP_DIR; usar src/netlog.c (sigue «sin compilar: validar en el PC»)

# --- C. rutas en el build vivo (a mano, una a una) -----------------------------------------
#   godot/ros2_vita/SCsub:28-33   → os.path.join(repo, "toolchains", "xrce", "xrce-vita-pic"|"xrce-vita-host") + marcador §2.2
#   godot/ros2_vita/ros_runtime.cpp:59, xrce_transport.{h:4-5,cpp:71,141} → solo comentarios
#   tools/build-rust-pic.sh:4,12,16 → cd "$REPO/modules/paraguas-rust"
#   tools/build-godot-template.sh  → guarda de §2.2 punto 3, antes de «== 3.»
#   tools/vita-doctor.sh:37,47-54  → toolchains/xrce/$v; tools/build-xrce-client-vita.sh; quitar vita2d y vita-app/build*
#   tools/netlog-listen.sh:2,9     → comentarios (hwprobe)

# --- D. archivar el resto ------------------------------------------------------------------
rm -rf vita-app/build-c vita-app/build-rust                              # 22 MB regenerables
rmdir vita-app/third_party vita-app/sce_sys 2>/dev/null || true
git mv vita-app archivo/vita-app
mover_ruta "vita-app/rust-modules" "modules/paraguas-rust"
mover_ruta "vita-app/scripts/build-xrce-client-vita.sh" "tools/build-xrce-client-vita.sh"
mover_ruta "vita-app/third_party/" "toolchains/xrce/"
mover_ruta "vita-app/" "archivo/vita-app/"          # el resto (citas a src/, CMakeLists.txt, README)
git diff --stat                                      # revisar: ≈ 65 líneas, ninguna en registros (R-1)
#   web/Dockerfile, .dockerignore, web/README.md (§2.3); archivo/README.md (filas + «cómo recompilar la app»)

# --- E. higiene de godot/ ------------------------------------------------------------------
#   informe.json ×4: quitar prefijos absolutos; tools/urdf2godot/urdf2godot.py:147,264 → relpath
grep -rn "informe.json" godot tools --include='*.gd' --include='*.py' | grep -v rclgd    # confirma que nadie lo lee
#   godot/README.md: grupos, enlaces simbólicos, dos runner.gd, schema.rsch, cmp de urdf_robot.gd; «Otras carpetas» fuera
```

**Verde** (todo en este PC; nada exige la Vita):

```bash
GH=toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
tools/run-parity-tests.sh                                                        # 8 módulos, C y Rust
godot/test/run_host_tests.sh "$GH"
"$GH" --headless --path godot/g1-sensores   --script res://comun/pruebas/runner.gd
"$GH" --headless --path godot/dron-mapeo    --script res://comun/pruebas/escena.gd -- sin_ros lod=vita
"$GH" --headless --path godot/rbkairos-plus --quit-after 300 -- transporte=loopback
python3 - <<'E'                                                                   # las libs están donde mira el SCsub
import os; r="toolchains/xrce"
for v in ("xrce-vita-pic","xrce-vita-host"):
    for n in ("libmicroxrcedds_client.a","libmicrocdr.a"):
        assert os.path.isfile(f"{r}/{v}/lib/{n}"), (v,n)
print("XRCE ok")
E
source tools/env-devpc.sh && tools/build-rust-pic.sh                             # paraguas en su ruta nueva: 0 MOVW/MOVT_ABS
tools/vita-doctor.sh                                                             # sin «falta cliente XRCE»
tools/build-godot-template.sh --dry-run | grep -n "custom_modules\|xrce"
tools/export-vita-vpk.sh godot/g1-sensores build/g1-sensores.vpk                 # enlaces simbólicos intactos
cmp godot/g1-unitree/robot/urdf_robot.gd godot/rbkairos-plus/robot/urdf_robot.gd
! grep -rn "/home/jcrex\|/tmp/claude" $(git ls-files 'godot/*informe.json')
python3 tools/check-doc-links.py --baseline /tmp/enlaces-antes.txt
git ls-files | grep -c '^vita-app/\|^godot/godot35/'                             # 0
```

Queda **pendiente de validar en el PC** (marcado en `SCsub` y en la bitácora, no bloquea): la próxima
recompilación de la plantilla debe imprimir «transporte XRCE activado (…/toolchains/xrce/xrce-vita-pic)».
`tools/hwprobe` sigue «sin compilar».

### O2d — guías del agente (commit `docs(org): README, CLAUDE.md, AGENTS.md y skills al día (ADR 0014)`)

1. `README.md` (§6), `CLAUDE.md` (§6, solo rutas), `AGENTS.md` ya hecho en O2a (repasar).
2. Skills: rutas y estado (§6) → `tools/install-skills.sh` → `diff -r skills ~/.claude/skills` sin diferencias de contenido.
3. `docs/06-bitacora-estado.md`: entrada de la Fase O y «Estado para retomar» nuevo (siguiente: Fase V1).
   `docs/ia/workshops/tablero-parches.log`: una línea por paso.
4. Plan: marcar la Fase O cerrada y, en §3, confirmar rutas de la Fase V (`godot/plantillas/visor/`,
   `godot/visor-ros/`, doc 36 / 36a).
5. Memoria `estado-proyecto.md` (commits y rutas nuevas).
6. Borrar el `O1a-mapa-rutas.json` local al cerrar O3.

**Verde:** `python3 tools/check-doc-links.py` sin rotos nuevos;
`grep -n "vita-app/\|godot35" CLAUDE.md README.md AGENTS.md skills -r | grep -v archivo/` vacío; relectura de O3b
contra este documento.

### O3 — verificación (sin cambios respecto al plan)

O3a: `tools/check-doc-links.py` sin línea base (lo que quede roto y sea anterior se lista, no se arregla aquí).
O3b: diff completo contra §1–§7; busca en especial: registros reescritos por error (R-1), `web/src` tocado (R-3),
reglas de `CLAUDE.md` alteradas, y cualquier `vita-app/` sin `archivo/` en `tools/`, `docker/`, `godot/ros2_vita/`.

---

## 8. Lo que queda fuera (anotado, no se hace en la Fase O)

- Lotes 4–5 de la auditoría (bugs B1–B3, R1, X1 y optimizaciones): son código. B2 y el perfil del paraguas
  (`lto`, `codegen-units`) ahora apuntan a `modules/paraguas-rust/`.
- `web/`: decisión del usuario. Si se abandona → `archivo/web/` y con ella los docs 07–08.
- Purgar `respaldo-chat-claude/` de la historia pública: exige *force-push*; solo si el usuario lo pide.
- Unificar `urdf_robot.gd` (Fase V, V9) y los `schema.rsch` (M8, `docs/18:335`).
- Push y PR de la Fase O: los aprueba el usuario.
