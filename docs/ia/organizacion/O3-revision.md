# Fase O — O3: revisión escéptica (2026-11-13)

> Revisa `git diff 0555319..1e80463` (6 commits: `c1ddbb0`, `c686c2a`, `30b6585`, `4420423`, `c533152`, `1e80463`)
> contra `decision-fable.md` y ADR 0014, con el registro `O2-registro.md`. PC CachyOS.
> Veredictos: **VERIFICADO** (comprobado hoy, cumple) · **DESAFÍO** (desviación o hueco; se dice si es grave).
> Corrección aplicada: `ef0b52f fix(org): quita la ruta absoluta del scratchpad del registro de O2`.

## 1. ¿Se hizo todo lo decidido?

| Paso | Veredicto | Notas |
|---|---|---|
| O2a raíz (§4, §7) | **VERIFICADO** | `auditoria/` fuera de la raíz (`ls` falla) y 3 logs en `archivo/auditoria/`; bloque `/auditoria/` fuera de `.gitignore`; `O1a-mapa-rutas.json` ignorado; `godot/comun/` borrado; `AGENTS.md` = puntero de 8 líneas (hecho en O2d, desviación registrada). |
| O2b docs (§1, §5) | **VERIFICADO** | Docs 10, 11, 16, 19 y dos de `docs/ia/` archivados como `R100` (contenido intacto, `git diff -M`); `docs/ia/{tutorial,medidas}/`; bitácora partida (06 = 147 líneas); doc 36 + 36a; `docs/README.md`; estados de docs 00–13 y ADR 0004–0008. Los 3 guiones movidos con similitud 88–97 % es por el ajuste de enlaces relativos (permitido por R-1). |
| O2c godot35 + `vita-app` (§2) | **VERIFICADO** | `git ls-files \| grep -c '^vita-app/\|^godot/godot35/'` = 0; paraguas en `modules/paraguas-rust/` (`Cargo.toml` con `../X`, crate sin renombrar, `Cargo.lock` incluido); `tools/build-xrce-client-vita.sh`; libs en `toolchains/xrce/` (las 4 `.a`: «XRCE ok»); `SCsub:27-38` con ruta nueva y marcador «VALIDAR EN EL PC»; guarda en `build-godot-template.sh` antes de «== 3.»; `--dry-run` encuentra la lib; `vita-doctor.sh` da `[OK]` en `-pic` y `-host`; `netlog.{c,h}` copiados a `tools/hwprobe/src/` y `CMakeLists.txt` incluye `src/`. |
| O2c-E higiene `godot/` (§3, §4) | **VERIFICADO** con desviación registrada | `godot/README.md` por grupos; 7 enlaces simbólicos versionados intactos (los 7 resuelven); `informe.json` sin rutas absolutas. Desviación: `urdf2godot.py:147` sigue con `abspath` (justificada: Blender). La hipótesis «nadie lee `informe.json`» era falsa (`g1-unitree/main.gd:112`) pero el campo leído no cambió. |
| O2d guías (§6) | **VERIFICADO** en lo hecho | `README.md`, `CLAUDE.md`, `AGENTS.md`, skills. `grep "vita-app\|godot35"` en README/AGENTS/CLAUDE sin `archivo/` delante: vacío. |
| O2d puntos 3–6 | **DESAFÍO (pendiente, registrado)** | No hechos: entrada de la Fase O y «Estado para retomar» en `docs/06` (sigue apuntando a la Fase V sin mencionar la Fase O); líneas en `docs/ia/workshops/tablero-parches.log`; Fase O cerrada en el plan; memoria `estado-proyecto.md`; borrar el `O1a-mapa-rutas.json` local. Tampoco se cambió la línea `Estado` del ADR 0014 («pendiente de ejecutar», `0014:4-5`), que él mismo pide pasar a «ejecutada (commits …)». No es rotura; es el cierre que falta. |

Desviaciones **no registradas**: ninguna encontrada. R-1 (registros sin reescribir): solo cambian
`archivo/README.md` (lo ordena §7) y `docs/ia/auditoria/README.md` (lo ordena §5.4). R-3: `web/src` sin tocar;
solo `web/Dockerfile`, `.dockerignore` y la nota de `web/README.md` (§2.3).

## 2. Referencias rotas fuera de Markdown

Búsqueda de `vita-app/`, `godot35`, `godot/comun`, `auditoria/`, `docs/1[0169]-`, `docs/2[01]-` en `tools/`,
`docker/`, `modules/`, `godot/**` (SCsub, py, sh, gd, `project.godot`, `export_presets.cfg`), `mcp/`, `skills/`,
`web/` y los dos ignores. **VERIFICADO: ningún roto real.**

| Clase | Casos |
|---|---|
| Roto real | ninguno |
| Mención histórica válida | comentarios «antes `vita-app/…`» en `SCsub:32`, `build-godot-template.sh:72,87`, `build-rust-pic.sh:5`, `build-xrce-client-vita.sh:11`, `paraguas-rust/Cargo.toml:1`, `xrce_transport.h:4` y `.cpp:141`; `plantillas/vita_relay.gd:2` (godot/comun); `msg-ring/README.md:53` y `msg-schema/README.md:61` («integrar en `vita-app`», casillas de tareas viejas); `skills/vita-build-package/SKILL.md:80,108` (`cd vita-app` dentro del *worktree* en `30b6585`, correcto) |
| Ruta ya con `archivo/` | `.gitignore:46`, `.dockerignore:15-17`, `web/Dockerfile:31,33`, `dlfcn.h:11`, `microros_transport.h:15`, README de módulos, skills `vita-deploy-logs`, `tools/hwprobe`, `netlog-listen.sh`, `vita-doctor.sh` |
| Web en pausa (R-3, sin tocar) | `web/scripts/netlog-{ingester,parser}.mjs` (comentarios `vita-app/src/netlog.c`); `web/Dockerfile:58` es ruta **dentro** de la imagen |
| `docker/`, `mcp/`, `project.godot`, `export_presets.cfg` vivos | sin coincidencias |

## 3. Comprobador y pruebas de host

| Prueba | Resultado | Veredicto |
|---|---|---|
| `python3 tools/check-doc-links.py` (sin línea base, O3a) | 138 rotos, rc 1 | **VERIFICADO**: con `--baseline enlaces-antes-O2b.txt` → **0 nuevos**. Contra la base original salen 11 «nuevos» que son los mismos rotos del plan de tutorial con el nombre nuevo (`docs/ia/tutorial/`). Todos son anteriores a la Fase O: rutas futuras (`godot/plantillas/visor/`, `godot/visor-ros/`, `modules/viz-decode/`), lecciones 02–06 sin escribir, nombres de rclgd, y menciones «`godot/comun/` no se resucita» (doc 36:371,1693; ADR 0013:45,195; ADR 0014; plan), que son históricas válidas. |
| `tools/run-parity-tests.sh` | «OK: paridad verificada» (8 módulos, C y Rust) | **VERIFICADO** |
| `godot/test/run_host_tests.sh "$GH"` | 294 comprobaciones, 0 fallos (los `ERROR:` son casos negativos) | **VERIFICADO** |
| runner `g1-sensores` (`res://comun/pruebas/runner.gd`) | RESULTADO 14/14 | **VERIFICADO** |

Sigue **pendiente de validar en el PC** (no bloquea): la próxima recompilación de la plantilla debe imprimir
«ros2_vita: transporte XRCE activado (…/toolchains/xrce/xrce-vita-pic)». `tools/hwprobe` sigue sin compilar.

## 4. `CLAUDE.md` contra `0555319`

**VERIFICADO.** `git diff 0555319..HEAD -- CLAUDE.md` solo toca hechos de rutas: «What this repo is» (Godot 4,
`docs/bitacora/`, `docs/README.md`, ADR 0014; fuera `fases.ts`), paraguas → `modules/paraguas-rust/`, «Common
commands» (+2 pruebas Godot y el comprobador), «Layout» (`vita-app/` fuera, tabla de grupos de `godot/`, viñetas
`docs/` y `archivo/`), y una viñeta nueva en «Conventions» (ADR 0014). **Sin cambios**: roles de máquinas, regla dual
Rust + C, viñeta `web/` (PAUSED), método autónomo y «Reports: long only», shells fish/zsh, regla de escenas
(convención), resto de convenciones y «Sync».
Observación menor (no rotura): la viñeta antigua de `godot/` llevaba el estado G4–G7c; ahora está en la tabla
de forma más breve («G7c 3D on the Vita: no SubViewport»). La lección de SubViewport se conserva.

## 5. Nada privado versionado

| Comprobación | Veredicto |
|---|---|
| `respaldo-chat-claude/`, `.codex/`, `.obsidian/`, `O1a-mapa-rutas.json` en `git ls-files` | **VERIFICADO**: ninguno |
| Rutas absolutas **añadidas** por la Fase O | **DESAFÍO menor**: (a) `O2-registro.md:53` llevaba la ruta completa del *scratchpad* → **corregido** en `ef0b52f`; (b) los 3 logs `archivo/auditoria/log-*.txt` (antes ignorados, ahora versionados) traen `/home/jcrex/…` (≈ 10 líneas): desviación ya registrada en O2a; se dejan textuales como evidencia del ADR 0006. El nombre de usuario ya es público (URL del repo), así que el riesgo es bajo; limpiarlas es decisión aparte. |
| Rutas absolutas anteriores (`docs/26:37`, `docs/34:145`, registros) | Fuera del alcance: existían en `0555319`. |

## Veredicto global

La Fase O **cumple la decisión** en O2a–O2d (lo ejecutado) y no rompe nada en build, pruebas ni referencias vivas.
Falta el **cierre administrativo** (O2d puntos 3–6 y la línea `Estado` del ADR 0014) antes de dar la fase por
cerrada y empezar la Fase V1.
