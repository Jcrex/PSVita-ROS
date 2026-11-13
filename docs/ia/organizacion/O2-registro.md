# Fase O — registro de ejecución de O2 (2026-11-13)

> Orden de trabajo: `decision-fable.md` §0, §1, §4, §5 y §7; regla: `docs/adr/0014-organizacion-del-repositorio.md`.
> Este registro cubre **O2.0, O2a y O2b** (un agente). O2c (godot35 + `vita-app/`) y O2d (README, `CLAUDE.md`,
> `AGENTS.md`, skills) son de otros agentes y deben ampliar este fichero. Sin push.

## O2.0 — línea base (antes de tocar nada)

Árbol limpio en `0555319`. Resultados (PC CachyOS, editor `toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64`):

| Prueba | Resultado |
|---|---|
| `tools/run-parity-tests.sh` (8 módulos, C y Rust) | **OK: paridad verificada** |
| `godot/test/run_host_tests.sh "$GH"` | **294 comprobaciones, 0 fallos** (los `ERROR:` del log son los casos negativos esperados) |
| `"$GH" --headless --path godot/g1-sensores --script res://comun/pruebas/runner.gd` | **RESULTADO: 14/14** |

Nada estaba en rojo, así que no se creó `O2-linea-base.md` (§7 O2.0 solo lo pide si hay rojos).
El mapa `O1a-mapa-rutas.json` se regeneró con `python3 -I …/scratchpad/o1a_mapa.py` antes de reescribir rutas (lo
escribe en `docs/ia/organizacion/`, ignorado desde O2a).

## O2a — raíz · commit `c1ddbb0` «chore(org): limpia la raíz (ADR 0014)»

Hecho:
- `.gitignore`: `docs/ia/organizacion/O1a-mapa-rutas.json` ignorado; quitado el bloque `/auditoria/` (3 líneas).
- `auditoria/`: los 3 `log-*.txt` copiados a `archivo/auditoria/` (versionados); la carpeta (287 MB, clones `ogre`,
  `vitaGL`, `rcutils` con `.git` propio) movida con `mv` a `toolchains/auditoria-rviz2/` (sin versionar).
- Rutas: `docs/04` (cabecera) y ADR 0006 (§Contexto) → «logs en `archivo/auditoria/`; clones en
  `toolchains/auditoria-rviz2/` (sin versionar)».
- `git rm -r godot/comun` (un `.uid` huérfano); `docs/31:357-358` y ADR 0011:73 → `godot/plantillas/`.
- Borrados `tools/__pycache__` (no existía) y `godot/ros2_vita/__pycache__`.
- `archivo/README.md`: fila de los logs.

Verificación: `git check-ignore docs/ia/organizacion/O1a-mapa-rutas.json` responde; `test -d
toolchains/auditoria-rviz2/vitaGL` OK; `grep -rn '"auditoria/' tools godot/ros2_vita` vacío; paridad OK, host
294/0, runner 14/14.

Desviaciones:
- **`AGENTS.md` → puntero (§4, paso 4) NO hecho**: el encargo de este agente excluye `AGENTS.md`. Queda para O2d.
- Los logs copiados contienen rutas locales de su fecha (`/home/jcrex/…`, 10 líneas). Se copian **textualmente**
  (son la evidencia del ADR 0006); anotado en `archivo/README.md`. Si se quiere limpiarlas, es decisión aparte.
- No hizo falta `git add` de `decision-fable.md`, el plan ni el ADR 0014: ya estaban en `0555319`.

## O2b — docs · commit `c686c2a` «docs(org): índice, archivo de docs superados, bitácora y doc 36 partidos»

Hecho:
1. **`tools/check-doc-links.py`** (nuevo): (a) enlaces Markdown relativos de todo `*.md` versionado salvo `archivo/`
   y `godot/rclgd/` (ignora bloques de código); (b) rutas entre comillas invertidas con prefijo `docs/ godot/ tools/
   modules/ skills/ docker/ archivo/`, con `:línea` opcional (comprueba que el fichero tenga esas líneas), en los
   vivos de R-5. Menciones abreviadas (`docs/18`, `docs/rust/03`) se resuelven por número en `docs/…` o
   `archivo/docs/…` (R-2); se ignoran plantillas (`<x>`, `$VAR`, `NN`, `…`, `24+`) y rangos (`00-02`). Sale con 1 si
   hay rotos; `--baseline f` resta los de una salida anterior (clave sin número de línea de origen).
   **Línea base:** 225 rotos antes de O2b (todos anteriores a la Fase O: planes de cosas aún no creadas como
   `godot/plantillas/visor/`, lecciones 02–06 sin escribir, rutas de Godot 3.5, etc.).
   Fichero: `/tmp/claude-1000/-home-jcrex-Proyectos-PSVita-ROS/a9b80dcd-e873-449f-81b6-65810b829273/scratchpad/enlaces-antes.txt`
   y su versión con los 5 guiones renombrados a `docs/ia/tutorial/`: `…/scratchpad/enlaces-antes-O2b.txt` (úsese
   esta en O2c).
2. Archivados con `git mv` (contenido intacto, comprobado con `git diff -M`: 0 líneas): docs 10, 11, 16, 19 →
   `archivo/docs/`; `docs/ia/guion-guia-tutorial-original.md` y `prompt-siguiente-sesion.md` → `archivo/docs/ia/`.
   Rutas completas reescritas en vivos: `README.md` (tabla de docs), docs 04, 18, ADR 0006, 0007.
3. `docs/ia/tutorial/` ← 5 guiones; `docs/ia/medidas/` ← 2 logs de `g1-sensores`. Reescritos: docs 34 y 06,
   `docs/tutorial/00`, `godot/g7-imu/main.gd` (comentario), `W13-visualizacion-topics.md`. Enlaces relativos de los
   guiones movidos ajustados un nivel (`../X` → `../../X`; los hermanos `./…` intactos; 11 y 19 → `archivo/docs/`).
4. **Bitácora** partida por encabezado: `06` = cabecera + 7 sesiones del 2026-11-13 (147 líneas, ≤ 300; un solo
   bloque «Estado para retomar»); `docs/bitacora/2026-11.md` (2026-11-01 → 11-12), `2026-10.md` (10-29 → 10-31),
   `2026-06-07-fases-0-1.md` (bloque «Dónde nos quedamos… HISTÓRICO» hasta el final) y `README.md` (índice + regla).
   Cada fichero mensual lleva una cabecera de 8 líneas; el texto de las sesiones no cambia. Quitada la línea de los
   sueltos de R2 (§4). Citas por línea al 06 desde vivos: `docs/28:36` y `docs/31:63` → «bitácora 2026-11-01, «G7c
   VERDE», en `docs/bitacora/2026-11.md`».
5. **Doc 36** partido: `## 4. Catálogo por tipo` (líneas 1252–3458) → `docs/36a-catalogo-displays.md` con cabecera
   de 5 líneas; en el 36 queda el título de §4 y un párrafo que remite al 36a. No había citas por línea al 36 en vivos.
6. `docs/README.md` creado desde `O1c-borrador-docs-README.md` con los cambios de §5.1 (tabla «Archivados», 36a,
   `bitacora/`, `ia/{tutorial,medidas}`, ADR 0014, «Estado real» de ADRs, `informes/` «2026-11-01, congelado»,
   primera línea «Para retomar»). `docs/ia/README.md` reescrito como índice de carpetas.
   `docs/ia/auditoria/README.md`: bloque de estado (lotes 0, 1, 2a, 3 cerrados en `bbbfa2d`; 2b por la Fase O; R2, R3
   hechos; 4–5 abiertos).
7. Líneas de estado (§1.2) en docs 00, 02, 04, 07, 08, 09, 12, 13; `Estado` de ADR 0004–0008 (§1.3).
8. `archivo/README.md`: una fila por cosa archivada, nota de traslados internos; el párrafo «Pendiente de decisión
   del usuario» sustituido por un remite a O2c.

Verificación:
- `python3 tools/check-doc-links.py --baseline …/enlaces-antes-O2b.txt` → **2 rotos nuevos, ambos transitorios
  hasta O2c** (ver desviaciones). Total 184 (antes 225).
- `wc -l docs/06-bitacora-estado.md` = 147 (≤ 300); `cat 06 + bitacora/2026-*` = 1 871 (≥ 1 845);
  `cat 36 + 36a` = 3 928 (≥ 3 913).
- Paridad completa OK (incluye `msg-cdr` y `viz-math`); host Godot 294/0; runner `g1-sensores` 14/14.

Desviaciones y decisiones conservadoras:
- **Rotos transitorios (los cierra O2c):** ADR 0004 cita `archivo/vita-app/` (texto literal de §1.3; la carpeta la
  crea O2c) y `vita-app/src/viz/README.md:3` cita `docs/11-diseno-mini-rviz.md` (no se toca `vita-app/`; O2c la
  archiva entera y sale del comprobador).
- **No se tocaron** (encargo): `skills/` (refs a docs 19 en `ros2-vita-godot` ×4 y `vita-build-package:92`),
  `CLAUDE.md`, `AGENTS.md`, `vita-app/`, `godot/godot35/` → O2c/O2d. El `mover_ruta` usado excluye esas rutas, los
  enlaces simbólicos y `docs/06` (véase abajo).
- **Cabeceras C (`msg_cdr.h:7`, `viz_math.h:7`) sin cambios**: citan «docs/11» abreviado, y R-2 dice que las
  menciones abreviadas no se reescriben; lo mismo los README de `modules/{msg-cdr,msg-ring,tf-tree,viz-math}`
  (`docs/10`, `docs/11`, `docs/19` abreviados) y `gen_fixtures.py`. El índice los resuelve.
- **Incidencias corregidas antes del commit:** (1) `perl -pi` convirtió el enlace simbólico
  `godot/g1-sensores/marcha.gd` en fichero: restaurado con `git checkout`; `mover_ruta` ahora salta enlaces.
  (2) La reescritura de `docs/10` tocó `docs/11` antes de archivarlo: restaurado su texto original.
  (3) `docs/06` se excluyó de la reescritura automática para no alterar sesiones que pasan a registro; solo se
  reescribieron a mano las 2 rutas de logs de sus sesiones vigentes.
- `README.md` raíz: solo la reescritura de las 4 rutas de su tabla de docs; su reescritura completa es de O2d.
- Docs 20–21 siguen en `docs/` y en la tabla principal de `docs/README.md` («se archiva en O2c»): O2c debe pasarlos a
  la tabla «Archivados» y corregir sus enlaces relativos.
- `web/`: nada que tocar en O2b (`web/Dockerfile` copia `docs/` entera).

## O2c — godot35 y `vita-app/` · commit «chore(org): archiva vita-app y godot35; extrae paraguas Rust y cliente XRCE»

Mapa regenerado antes de reescribir (`python3 -I …/scratchpad/o1a_mapa.py`). Reescritura con el `mover_ruta` de R-5
excluyendo, además de lo de O2b, `README.md` raíz (O2d); lista de vivos en `…/scratchpad/o2c-lib.sh`.

Hecho:
1. **A.** `git mv godot/godot35 archivo/godot/godot35` (se borraron `.import/` y `build/`; `versiones/` con 3 `.vpk`
   sin versionar viajó). Docs 20–21 → `archivo/docs/`; en `docs/README.md` pasan a «Archivados». A mano: comentario de
   `tools/build-godot-template.sh` (paso 3), `godot/vitasdk-stubs/dlfcn.h`, `.gitignore`, doc 18 §4.5 punto 2,
   `godot/README.md` (fila de `godot35/` fuera; nota con la ruta archivada).
2. **B.** `vita-app/rust-modules` → `modules/paraguas-rust/` (`Cargo.toml`: `../../modules/X` → `../X` + comentario de
   traslado; crate y lib sin cambiar). `vita-app/scripts/build-xrce-client-vita.sh` → `tools/` (`REPO`, `PREFIX` y
   `WORK` en `toolchains/xrce/`). `mv` de `xrce-vita{,-pic,-host}` y `_build/` a `toolchains/xrce/` (sin recompilar);
   **se borraron `_build/build-*`**: su `CMakeCache.txt` guardaba la ruta antigua y haría fallar la próxima ejecución del
   script (se regeneran; los clones `Micro-CDR` y `Micro-XRCE-DDS-Client` se quedan). `netlog.{c,h}` copiados a
   `tools/hwprobe/src/`; `tools/hwprobe/CMakeLists.txt` sin `APP_DIR` (sigue «sin compilar: validar en el PC»).
3. **C.** `godot/ros2_vita/SCsub`: ruta por defecto `toolchains/xrce/xrce-vita-pic|host` + marcador «VALIDAR EN EL PC
   en la próxima recompilación de la plantilla». `tools/build-godot-template.sh`: **guarda** antes de «== 3.» (aborta si
   falta `toolchains/xrce/xrce-vita-pic/lib/libmicroxrcedds_client.a`, salvo `ROS2_VITA_SIN_XRCE=1`; documentada en la
   cabecera). `tools/build-rust-pic.sh` → `modules/paraguas-rust`. `tools/vita-doctor.sh`: `toolchains/xrce/$v` (solo
   `-pic` y `-host`; la estática era de la app), sin `libvita2d` ni `vita-app/build*`. `tools/netlog-listen.sh`,
   `ros_runtime.cpp`, `xrce_transport.{h,cpp}`: solo comentarios. `run-parity-tests.sh` no necesitó cambios (salta
   `paraguas-rust`: «sin parity_test.c, omitido»).
4. **D.** Borrados `build-c/`, `build-rust/` y `src/*.o` (regenerables); `git mv vita-app archivo/vita-app`. Rutas
   reescritas en 30 vivos (docs 02, 03, 07, 09, 12, 13, 15, 18, 23, 27, 31, 32; ADR 0005, 0008, 0011; guías `vitasdk-
   toolchain` y `vitashell`; `docs/rust/00`, `02`; tutorial; README de módulos; `microros_transport.h`; `.gitignore`,
   `.dockerignore`). A mano: guía `vitasdk-toolchain` (los dos bloques que hacían `cd vita-app && ./scripts/…`), doc 27
   (cliente → `tools/build-xrce-client-vita.sh`), doc 32 (citas `:63` → `:65` y `:23-27` → `:24-28` por las líneas
   añadidas a la cabecera del script). Web (§2.3): `web/Dockerfile` copia `archivo/vita-app/` y
   `archivo/godot/godot35/README.md` a sus rutas antiguas en la imagen; `.dockerignore`; nota en `web/README.md`. No se
   construyó la web.
5. `archivo/README.md`: filas de `godot35`, docs 20–21 y `vita-app`; tabla de piezas extraídas; «Cómo recompilar la app
   de la Fase 1» (worktree en `30b6585`, o `git mv` de vuelta + `-DXRCE_PREFIX` + `RUST_DIR`; sin probar).

Verificación (PC CachyOS):
- Paridad OK (8 módulos C y Rust; `paraguas-rust` omitido). Host Godot **294/0**. Runner `g1-sensores` **14/14**.
- Libs XRCE en la ruta nueva: las 4 `.a` existen (`XRCE ok`). `tools/build-godot-template.sh --dry-run` imprime la
  lib encontrada y `custom_modules=…/godot/ros2_vita`; con `xrce-vita-pic` renombrada aborta (rc 1) y con
  `ROS2_VITA_SIN_XRCE=1` solo avisa.
- `tools/build-rust-pic.sh` (tras `cargo clean -p vita_modules_rust -p mem_pool_rust`): compila desde
  `modules/paraguas-rust`, **0 relocaciones MOVW/MOVT_ABS**. `tools/vita-doctor.sh`: XRCE `-pic` y `-host` OK.
- `git ls-files | grep -c '^vita-app/\|^godot/godot35/'` = 0. Ninguna ruta viva sin `archivo/` delante, salvo los
  comentarios «antes vita-app/…».
- `check-doc-links.py --baseline …/enlaces-antes-O2b.txt`: los **2 transitorios de O2b resueltos**; total 144 (antes
  184). Quedan **5 rotos nuevos, todos en ficheros de O2d** (no tocados por encargo): `AGENTS.md:68`, `CLAUDE.md:65`,
  `README.md:13` (`godot/godot35/`) y `README.md:165-166` (docs 20–21).

Pendiente / desviaciones:
- **Validar en el PC al recompilar la plantilla:** debe imprimir «ros2_vita: transporte XRCE activado
  (…/toolchains/xrce/xrce-vita-pic)» (marcado en `SCsub`). `tools/hwprobe` sigue sin compilar.
- **O2d** debe arreglar `CLAUDE.md`, `AGENTS.md`, `README.md` raíz (incluidos los `vita-app/scripts/check-*.sh` y
  `cd vita-app` de «Common commands») y skills (`vita-build-package`, `ros2-vita-godot`, `vita-dual-module`, …:
  19 menciones de `vita-app`/`godot35`).
- **No hecho: §7 O2c parte E (higiene de `godot/`: `informe.json`, `urdf2godot.py` relpath, `godot/README.md` por
  grupos)**: fuera del encargo de este agente; solo se quitó la fila de `godot35/` del README de `godot/`. Tampoco se
  ejecutaron las comprobaciones de verde ligadas a E (export de `g1-sensores`, `cmp` de `urdf_robot.gd`, `dron-mapeo`,
  `rbkairos-plus`): ningún fichero de esos proyectos cambió.
- ADR 0014 §Contexto y tabla: `godot/godot35/` → «`godot35/` (en/de `godot/`)» para que el comprobador no lo marque;
  el significado no cambia. Doc 18 §4.5 reformulado igual.
- Docs 20–21: sus enlaces relativos internos no se tocaron (R-1: dentro de `archivo/` no se arreglan).
- `docs/06` sin cambios (no tenía referencias); la nota de «validar en el PC» va en `SCsub` y en este registro.
