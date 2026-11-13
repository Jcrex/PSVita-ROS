# ADR 0014: Organización del repositorio — qué se archiva, dónde vive cada cosa y qué no se mueve

- **Estado:** Aceptada (juez Fable 5.2, 2026-11-13).
  - Decidida, **pendiente de ejecutar** por los pasos O2a–O2d del plan
    `docs/ia/plan-organizacion-y-visor-2026-11-13.md`. Al cerrarlos, esta línea pasa a «ejecutada (commits …)».
  - Detalle de cada decisión (coste en referencias, riesgo, reversión y comandos):
    `docs/ia/organizacion/decision-fable.md`. Diagnóstico previo: `O1b`–`O1d` en la misma carpeta.
  - Por regla del usuario (2026-11-13) las decisiones de diseño no se le preguntan: las toma el juez. Lo
    irreversible (borrar historia, push, PR) sigue siendo suyo.
- **Fecha:** 2026-11-13
- **Cierra:** el lote 2b de la auditoría del 2026-11-01 (`docs/ia/auditoria/README.md`), abierto desde entonces.
- **No cambia:** ninguna decisión técnica. Corrige la línea `Estado` de los ADR 0004–0008 (§5).

## Contexto

1. **Decisiones descartadas sin limpiar** [V]. El producto vivo es Godot 4 + `ros2_vita` (ADR 0008), pero la raíz
   aún presenta como vigentes la app de la Fase 1 (`vita-app/`: teleop vita2d, mini-rviz con vitaGL, CMake) y
   `godot/godot35/`; seis documentos numerados describen planes sustituidos (10, 11, 16, 19, 20, 21) y los ADR
   0005–0007 dicen «Aceptado» aunque los superaron los ADR 0007, 0008 y 0013
   (`docs/ia/organizacion/O1c-clasificacion-docs.md` §1).
2. **`vita-app/` no se puede archivar entera** [V]: el build vigente de Godot 4 lee tres piezas suyas — las libs
   del cliente XRCE (`godot/ros2_vita/SCsub:32-36`), el crate paraguas Rust (`tools/build-rust-pic.sh:16`) y
   `netlog.c` (`tools/hwprobe/CMakeLists.txt:24`).
3. **El build de la plantilla solo existe en el PC** y tarda 1–2 h (`tools/build-godot-template.sh:66`). El SCsub
   calcula la raíz del repo como `../..` (`SCsub:21`) y, si no encuentra las libs XRCE, **compila sin transporte
   y sin error** (`SCsub:47`).
4. **`docs/`** no tiene índice; la bitácora mide 1 845 líneas y el doc 36, 3 913.
5. **La web está en pausa** por decisión del usuario (2026-11-01): no se reestructura.
6. Cada movimiento cuesta referencias: el inventario O1a cuenta 659 a `vita-app/`, 393 a `res://comun`, 278 a
   `godot/ros2_vita/` y 277 a `godot/plantillas/`.

## Decisión

### 1. Estructura de carpetas

| Carpeta | Contenido | Cambio |
|---|---|---|
| `modules/` | Los 8 módulos duales y **`modules/paraguas-rust/`** (crate `vita_modules_rust`, la única staticlib Rust por binario) | el paraguas viene de `vita-app/rust-modules/` |
| `tools/` | Recetas de build, exportación, despliegue y comprobación; **`tools/build-xrce-client-vita.sh`**; `tools/hwprobe/` con su propio `netlog.c`; `tools/check-doc-links.py` | script y `netlog` vienen de `vita-app/` |
| `toolchains/` (sin versionar) | SDKs, clones y artefactos regenerables del PC; **`toolchains/xrce/xrce-vita{,-pic,-host}`** (libs del cliente XRCE); `toolchains/auditoria-rviz2/` | libs desde `vita-app/third_party/`; clones desde `auditoria/` |
| `godot/` | **Plana**, con grupos declarados en `godot/README.md` (§3) | sale `godot35/`; se borra `comun/` |
| `docs/` | Numerados vigentes, `adr/`, `bitacora/`, `guias-vita/`, `ia/`, `informes/`, `rust/`, `tutorial/` e índice `docs/README.md` (§4) | índice y `bitacora/` nuevos |
| `archivo/` | Lo archivado, con su ruta original debajo (§2) | entran `vita-app/`, `godot/godot35/`, 6 docs, 2 guiones, 3 logs |
| `docker/`, `mcp/`, `skills/`, `media/`, `web/` | Sin cambios | — |

`vita-app/` deja de existir en la raíz. Ya no hay `auditoria/` en la raíz.

### 2. Cuándo y cómo se archiva

1. **Se archiva** lo que cumple una de dos condiciones: (a) **superado** — otra decisión aceptada lo sustituye;
   (b) **plan ejecutado y cerrado** que nadie necesita para trabajar hoy. Lo histórico que aún se cita como
   fuente técnica **se queda y se marca** con una línea de estado y en el índice.
2. **Antes de archivar código** se extrae lo que use un build vivo y se reescriben esas rutas en el mismo commit.
3. **Destino:** `archivo/<ruta original>`, sin renumerar documentos. Dos cosas archivadas conservan así su
   posición relativa (p. ej. `archivo/godot/godot35` y `archivo/vita-app`).
4. **`archivo/README.md`** lleva una fila por traslado (qué, cuándo, motivo, qué lo sustituye). Es la tabla que
   resuelve las rutas antiguas.
5. **Qué se reescribe.** Solo los ficheros vivos. Los **registros** conservan las rutas de su fecha: `archivo/`,
   `docs/bitacora/`, `docs/ia/workshops/posts/`, `docs/ia/auditoria/`, `docs/ia/revision-kimi/`,
   `docs/ia/organizacion/`, `docs/informes/`. Los enlaces Markdown sí se arreglan fuera de `archivo/`. Las
   menciones abreviadas («doc 10») no se tocan: las resuelve `docs/README.md`.
6. **Los ADR no se archivan.** Se corrige su línea `Estado` («Superado por ADR N», «alcance reducido»).
7. **Lo archivado no se garantiza compilable.** Para recompilar algo, se devuelve a su sitio con `git mv`.
8. **Lo no versionado no se borra para «limpiar»** salvo cachés regenerables (`build*/`, `.import/`, `target/`,
   `__pycache__/`); lo demás se mueve a `toolchains/`.

### 3. `godot/`: plana, por grupos; nada se renombra

| Grupo | Carpetas | Regla |
|---|---|---|
| Motor | `ros2_vita/`, `loader-patches/`, `vitasdk-stubs/`, `test/` | **No se mueven**: su profundidad está en `SCsub`, `run_host_tests.sh` y `build-godot-template.sh` |
| Biblioteca compartida | `plantillas/` | En los proyectos es el enlace `comun -> ../plantillas` (`res://comun`). **No se renombra.** El visor de ADR 0013 va en `godot/plantillas/visor/` |
| Apps vivas | `g1-unitree/`, `g1-sensores/`, `rbkairos-plus/`, `dron-mapeo/`; en la Fase V, `visor-ros/` | Proyecto nuevo: nombre de lo que es, sin prefijo `gN-`; enlace `comun` |
| Puertas cerradas | `g4-smoke/`, `g5-xrce/`, `g6-hmi/`, `g7-imu/`, `g7b-imu3d/` | Se quedan como regresión y material de lecciones. Una puerta se archiva cuando otra app la **sustituye** como prueba, no por estar cerrada |
| Externo | `rclgd/` (ignorado) | — |

Los enlaces simbólicos versionados (7) se documentan en `godot/README.md`. Duplicados aceptados: los assets
`PSVita/` de `g7-imu` y `g7b-imu3d`, y un `schema.rsch` por proyecto. `urdf_robot.gd` se unifica en
`plantillas/robots/` cuando la Fase V lo modifique. Los `informe.json` versionados no llevan rutas absolutas.

### 4. `docs/`

1. **`docs/README.md`** es el índice: número, título, estado (vigente / en pausa / histórico / archivado en…),
   y la tabla de ADRs con su estado real.
2. **Bitácora.** `docs/06-bitacora-estado.md` conserva su ruta y contiene el estado para retomar y las sesiones
   abiertas, con un tope de 300 líneas. Lo anterior baja a `docs/bitacora/AAAA-MM.md`.
3. **Documentos largos.** Un documento que pase de ≈ 2 000 líneas se parte en `NN` (decisiones) y `NNa`
   (catálogo o fichas), conservando la numeración de secciones. Primer caso: `36` + `36a-catalogo-displays.md`.
4. **`docs/ia/`**: `tutorial/` (guiones), `medidas/` (logs de hardware), `workshops/`, `auditoria/`,
   `revision-kimi/`, `organizacion/`; sueltos en la raíz, solo el `README.md`, el plan en ejecución y la
   investigación de flujo.
5. **Fotos generadas** (inventarios de referencias como `O1a-mapa-rutas.json`) no se versionan.
6. **Binarios:** nada nuevo de más de 1 MB en git. `media/` se queda como está.

### 5. Estado corregido de ADRs anteriores

| ADR | Estado desde hoy |
|---|---|
| 0004 | Aceptado; alcance reducido desde 2026-10-27 a `tools/hwprobe` y a la app archivada. Las apps se exportan con Godot (ADR 0008) |
| 0005 | **Superado** por ADR 0007 (2026-07-10) y ADR 0008 (2026-10-27) |
| 0006 | Aceptado en «rviz2 nativo descartado»; su **Plan B (mini-rviz) está superado** por ADR 0008 §5 (enm. 2026-11-11) y ADR 0013 |
| 0007 | **Superado** por ADR 0008 §5 (enmienda 2026-11-11) |
| 0008 | Vigente; «G7 en curso» → «G7a–G7c verdes (2026-11-01)» |

### 6. Guardas

- `tools/build-godot-template.sh` aborta si faltan las libs de `toolchains/xrce/xrce-vita-pic`, salvo
  `ROS2_VITA_SIN_XRCE=1`: el SCsub no vuelve a degradar el transporte en silencio.
- `tools/check-doc-links.py` comprueba enlaces Markdown y rutas citadas en los ficheros vivos; se pasa antes de
  cada commit que mueva o renombre algo.
- `AGENTS.md` es un puntero a `CLAUDE.md`: una sola guía.
- `web/`: solo se ajustan las líneas `COPY` del `Dockerfile` y `.dockerignore`, sin probar; el resto espera a la
  decisión del usuario.

## Alternativas descartadas

- **`godot/{motor,hitos,apps,historico}/` (opción B):** ≈ 1 018 referencias y 7 enlaces simbólicos; rompe la
  profundidad que asumen `SCsub`, `run_host_tests.sh` y el `custom_modules` de un build de 1–2 h que solo se puede
  repetir en el PC. La ganancia es de aspecto y la da un README.
- **`godot/hitos/` solo para g4–g7b:** 56 reescrituras vivas (tutorial, estación docker, skills) por cinco líneas
  menos en un `ls`.
- **Renombrar `plantillas` (a `comun-lib` o `comun`):** `res://comun` no depende del nombre; cuesta 277
  referencias y contradice el ADR 0013 («`godot/comun/` no se resucita»), aceptado el mismo día.
- **Posponer `vita-app/` hasta decidir la web:** dejaría en la raíz el mayor resto de decisiones descartadas y
  obligaría a la Fase V a escribir sobre rutas que luego cambian. La web se sostiene con dos líneas de `COPY`.
- **Paraguas Rust en `rust-modules/` de la raíz** y **libs en `third_party/` de la raíz:** dos carpetas más en la
  raíz para tres ficheros y para artefactos sin versionar.
- **Mover también los docs 04, 09, 12 y 13:** históricos, pero citados como fuente por código y ADRs vivos; ≈ 60
  reescrituras sin más claridad que la del índice.
- **Reescribir las rutas dentro de los registros:** falsea lo que se hizo en su fecha y multiplica el coste por
  tres (≈ 250 referencias solo de `vita-app/`).
- **Borrar `auditoria/` (287 MB):** son clones con `.git` propio; borrar lo no versionado no tiene vuelta atrás.
- **`AGENTS.md` como enlace simbólico o generado por script:** el enlace falla con `core.symlinks=false`; el
  script es otro paso que olvidar.
- **Versionar `O1a-mapa-rutas.json`:** 487 KB que caducan con el primer `git mv` y que incluyen rutas de ficheros
  locales en un repo público.

## Consecuencias

- La raíz y `docs/` muestran solo lo que se usa; lo descartado está en `archivo/` con el motivo al lado.
- ≈ 170 reescrituras en ficheros vivos, repartidas en cuatro commits reversibles con `git revert` (más un `mv`
  de vuelta para `toolchains/xrce/` y `toolchains/auditoria-rviz2/`).
- **Por validar en el PC** [?]: la próxima recompilación de la plantilla debe imprimir «ros2_vita: transporte
  XRCE activado (…/toolchains/xrce/xrce-vita-pic)». Hasta entonces la ruta nueva del SCsub solo está comprobada de
  forma estática. `tools/hwprobe` sigue sin compilar.
- La app de la Fase 1 deja de compilar en su sitio (`archivo/vita-app/`): es historia, no producto.
- La web en pausa pierde de su colección los docs archivados y conserva enlaces rotos en `fases.ts`; queda
  anotado en `web/README.md`.
- Las citas `docs/06-bitacora-estado.md:NNN` de los registros dejan de coincidir; valen como fecha, no como línea.
- La Fase V arranca con rutas estables: `godot/plantillas/visor/`, `godot/visor-ros/`, doc 36 (arquitectura) y
  36a (fichas).
