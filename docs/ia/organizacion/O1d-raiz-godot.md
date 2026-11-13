# O1d — Inventario de la raíz del repo y de `godot/` (solo lectura)

Fecha: 2026-11-13 · Rama: `ccr-44e2db2a-mr6xqr` · Alcance: entradas de la raíz, carpetas de primer nivel de `godot/`, `tools/`, `docker/`, `skills/`, `modules/` y `mcp/`.

Qué se hizo: solo lectura. No se modificó, borró ni movió nada; ningún comando git escribe (solo `ls-files`, `check-ignore`, `log`, `show`, `status`, `ls-files -s`). Este fichero es la única salida.

Método, en prosa: tamaño con `du -sh` excluyendo `target/`, `node_modules/` y `.godot/` (como se pidió). Esto significa que `mcp/ros2-introspection` sí cuenta su `.venv` (71 MB) y `godot/godot35` cuenta sus cachés de importación. "Versionada" = número de ficheros en `git ls-files`. "Ignorada" = regla que la excluye, con `git check-ignore -v --no-index` (así se ve la regla aunque la ruta esté en el índice). "Último commit" = `git log -1 --format=%cs -- ruta`. Duplicados y `.uid` comparados con `cmp`/`md5sum` y con `git ls-files -s`.

Leyenda de marcas: [V] verificado en el repo con el comando indicado; [I] inferencia a partir de lo verificado; [?] hipótesis sin comprobar.

## Resumen

- La raíz (sin `.git`) suma unos 8,7 GB, y unos 8,5 GB de eso están ignorados y son regenerables: `toolchains/` 7,3 GB, `Videos/` 547 MB, `auditoria/` 287 MB, `build/` 181 MB. `godot/` pesa 182 MB: 124 MB son `godot35/` (cachés ignoradas y tres `.vpk`), 41 MB el clon de `rclgd` (ignorado) y unos 17 MB el resto de lo versionado.
- `godot/` tiene 17 carpetas de primer nivel: 4 de motor (`ros2_vita`, `loader-patches`, `test`, `vitasdk-stubs`); 5 hitos cerrados (`g4-smoke`, `g5-xrce`, `g6-hmi`, `g7-imu`, `g7b-imu3d`); 5 apps vivas (`g1-unitree`, `g1-sensores`, `plantillas`, `rbkairos-plus`, `dron-mapeo`); 1 histórico (`godot35`); 1 externo (`rclgd`, sin versionar); y 1 residuo (`comun`).
- Huérfano confirmado: `godot/comun/vita_relay.gd.uid`, sin su `.gd`. Es el único de 56 `.uid`.
- Duplicados reales: los 24 ficheros de `assets/PSVita/` en `g7-imu` y `g7b-imu3d` son idénticos; `urdf_robot.gd` es idéntico en `g1-unitree` y `rbkairos-plus`; `schema.rsch` existe en 10 copias con 4 versiones distintas.
- Vacías y no generadas: 10 carpetas. Una (`vita-app/sce_sys`) puede hacer falta en la compilación del `.vpk` [?].
- Enlaces simbólicos versionados: 7, todos en `godot/` (modo 120000).

## 1. Raíz del repo

| Entrada | Tamaño | Versionada (ficheros) | Ignorada (regla) | Último commit | README | Qué es |
|---|---|---|---|---|---|---|
| `.git` | 94 M | — | — | — | — | Repositorio git |
| `.claude` | 24 K | 0 | sí, global: `~/.config/git/ignore` (`**/.claude/settings.local.json`) [V] | sin commits | no | Configuración local de Claude Code (solo `settings.local.json`) |
| `.codex` | 8,0 K | 0 | sí, `.gitignore:61` [V] | sin commits | no | Configuración local de Codex (`config.toml`) |
| `.dockerignore` | 4,0 K | 1 | no | 2026-10-29 | no | Exclusiones del contexto de build de Docker |
| `.gitignore` | 4,0 K | 1 | no | 2026-11-13 | no | Reglas de ignorado del repo |
| `.mcp.json` | 4,0 K | 0 | sí, `.gitignore:11` [V] | sin commits | no | Registro local del MCP (ruta del venv de cada máquina) |
| `.obsidian` | 28 K | 0 | sí, `.gitignore:62` [V] | sin commits | no | Configuración local de un vault de Obsidian |
| `AGENTS.md` | 12 K | 1 | no | 2026-11-12 | no | Versión para Codex de `CLAUDE.md` (127 líneas frente a 131; `diff` = 28 líneas) [V] |
| `CLAUDE.md` | 12 K | 1 | no | 2026-11-13 | no | Guía del repo para Claude Code (fuente de verdad) |
| `README.md` | 12 K | 1 | no | 2026-11-01 | es el README | Presentación del proyecto y estado de los objetivos |
| `archivo` | 156 K | 7 | no | 2026-11-01 | sí | Material archivado con su ruta original (`archivo/README.md`) |
| `auditoria` | 287 M | 0 | sí, `.gitignore:41` (`/auditoria/`) [V] | sin commits | no | Restos de compilaciones de prueba de rviz2 (`.gitignore:39-40`, docs/04): `ogre` 224 M, `build-ogre` 33 M, `vitaGL` 27 M, `rcutils` 1,7 M, `build-rcutils` 1,5 M. `ogre`, `vitaGL` y `rcutils` son clones con su propio `.git` (repos anidados) |
| `build` | 181 M | 0 | sí, `.gitignore:14` [V] | sin commits | no | Salida de exportación: 8 `.vpk` (dron-mapeo, g1-sensores, g1-unitree, g4-smoke, g5-xrce, g6-hmi, g7-imu, rbkairos-plus) y sus logs |
| `build-host` | 4,0 M | 0 | sí, `.gitignore:32` [V] | sin commits | no | 16 binarios de paridad de módulos (C y Rust) |
| `docker` | 53 M | 18 | no | 2026-11-13 | sí | Estación ROS 2 Jazzy: agente micro-ROS, monitor, puente Zenoh, simulación del G1. 52 M son caché ignorada (`docker/g1/cache/`) |
| `docs` | 2,9 M | 141 | no | 2026-11-13 | no (la raíz de `docs/` no tiene README) | Documentación: bitácora (`docs/06`), investigación, ADR, guías, auditorías |
| `godot` | 182 M | 722 | `godot/rclgd/` sí, `.gitignore:46` [V] | 2026-11-13 | sí | Módulo `ros2_vita`, proyectos Godot, plantillas (detalle en §2) |
| `media` | 12 M | 2 | no | 2026-07-10 | no | Vídeo `.mp4` y póster del primer control del robot por `cmd_vel` |
| `mcp` | 71 M | 7 | no | 2026-11-01 (ver §7) | no (lo tiene `ros2-introspection`) | Carpeta del servidor MCP; casi todo es su `.venv` |
| `modules` | 1,1 M | 151 | no | 2026-11-01 | no (cada módulo tiene el suyo) | Ocho módulos duales C/Rust tras un header C común |
| `respaldo-chat-claude` | 12 M | 0 | sí, `.gitignore:59` [V] | 2026-11-13 (commit `ef760eb`, que la sacó del repo) | no | Respaldo local de chats (`subagents`, `tool-results`); no se versiona |
| `skills` | 272 K | 40 | no | 2026-11-01 | no (tiene `INSTALAR.md`) | Skills de IA versionadas (seis carpetas) |
| `toolchains` | 7,3 G | 0 | sí, `.gitignore:38` [V] | sin commits | no | SDKs y clones locales: `godot4-vita` 3,7 G, `rustup` 1,6 G, `vitasdk` 428 M, `robotnik_description` 357 M, `cmake` 203 M, `robotnik_sensors` 203 M, `pic` 198 M, `rclgd_sensors` 164 M, y otros |
| `tools` | 204 K | 25 | no | 2026-11-13 | no (tienen README `hwprobe` y `urdf2godot`) | Scripts de build, exportación, despliegue y paridad (§3) |
| `Videos` | 547 M | 0 | sí, `.gitignore:42` [V] | sin commits | no | Vídeo de trabajo y de edición (`proxy`, máscaras, un `.kdenlive`) |
| `vita-app` | 41 M | 37 | `build-c/`, `build-rust/`, `third_party/_build` sí, `vita-app/.gitignore:3,7,8` [V] | 2026-11-01 | sí | App homebrew: Fase 1 y teleop, en C y en Rust |
| `web` | 9,5 M | 65 | `node_modules/` (fuera del cálculo) | 2026-11-01 | sí | Sitio Astro 5 con SQLite. PAUSADO por decisión del usuario (2026-11-01, `CLAUDE.md`) |

Notas de la raíz:
- Sin ficheros sin versionar fuera de la regla de ignorado, salvo `docs/ia/plan-organizacion-y-visor-2026-11-13.md`, que `git status` muestra como `??` [V].
- Ignorado en total, sin contar `.git`: unos 8,5 GB (suma aproximada de las tablas), de los que `toolchains` es casi todo.
- `mcp` aparece con fecha 2026-11-01 porque el último commit que la toca (`1a7dc5e`) solo cambia `mcp/.gitkeep`; ese fichero ya no está en el índice [V]. El contenido real de `mcp/ros2-introspection` no cambia desde 2026-06-28 [V].
- `docs/ia/organizacion/` estaba vacía antes de este informe; ahora contiene este fichero.

## 2. Primer nivel de `godot/`

Clasificación: motor (`ros2_vita` y lo que lo acompaña) · hito cerrado (puerta G verde y sin trabajo activo) · app viva (se toca esta semana) · histórico · externo · residuo.

| Carpeta | Tamaño | Versionada | Ignorada | Último commit | README | Clasificación | Qué es |
|---|---|---|---|---|---|---|---|
| `comun` | 8,0 K | 1 | no | 2026-11-12 | no | residuo (huérfano) | Solo `vita_relay.gd.uid` sin su `.gd`. Nada la referencia: los `comun/` de los proyectos son enlaces a `../plantillas` |
| `dron-mapeo` | 56 K | 10 | no | 2026-11-13 | sí | app viva | Dron 6DOF de 552 triángulos con suite de percepción (IMU, GNSS, RGB-D, LiDAR, sonar) |
| `g1-sensores` | 288 K | 59 | no | 2026-11-13 | sí | app viva | Unitree G1 con sensores ROS 2 y prefijo `g1s`. Reutiliza robot, anim y `marcha.gd` de `g1-unitree` por enlaces |
| `g1-unitree` | 5,6 M | 165 | no | 2026-11-13 | sí | app viva | Unitree G1 con control oficial y casa generada. Es la carpeta más activa |
| `g4-smoke` | 32 K | 5 | no | 2026-11-01 | no | hito cerrado (G4) | Prueba de humo: loopback y `Twist`. Verde en hardware el 2026-10-30 (`godot/README.md`) |
| `g5-xrce` | 36 K | 5 | no | 2026-11-01 | no | hito cerrado (G5) | Publica `/vita_hello` y `/cmd_vel` por XRCE. Verde (`godot/README.md`, puerta 4) |
| `g6-hmi` | 36 K | 5 | no | 2026-11-01 | no | hito cerrado (G6) | HMI de teleop de turtlesim y vista de `/odom`. Verde en hardware (`godot/README.md`, puerta 5) |
| `g7-imu` | 1,6 M | 36 | no | 2026-11-11 | no | hito cerrado (G7a) | IMU de la Vita a `/vita/imu`. Falta validar unidades y ejes en hardware (`godot/README.md`, tabla) |
| `g7b-imu3d` | 1,5 M | 31 | no | 2026-11-01 | no | hito cerrado (G7b y G7c) | Visor 3D de la IMU; en la Vita corre a 59 FPS (G7c, según `CLAUDE.md`, sección de Godot) |
| `godot35` | 124 M | 25 | parcial: `.import/` y `build/` (`godot35/.gitignore:2,4`); `versiones/` por `*.vpk` (`.gitignore:15`) | 2026-11-01 | sí | histórico | App teleop en Godot 3.5, validada en hardware (`godot35/README.md`). De los 124 M: `.import` 50 M, `versiones/` 55 M (3 `.vpk`, 0 ficheros versionados), `build` 19 M |
| `loader-patches` | 8,0 K | 1 | no | 2026-10-30 | no | motor | Parche `0001-ros2-vita-imports.patch` para el loader de godot4-vita |
| `plantillas` | 2,5 M | 258 | no | 2026-11-13 | sí | app viva (biblioteca compartida) | Robots, sensores, mundo 3D y pruebas. La usan `rbkairos-plus`, `g1-sensores`, `dron-mapeo` y `g1-unitree` por enlace |
| `rbkairos-plus` | 6,3 M | 105 | no | 2026-11-13 | sí | app viva | RB-KAIROS+ con UR10e a partir del Xacro oficial (40 links, 39 joints) |
| `rclgd` | 41 M | 0 | sí, `.gitignore:46` (`godot/rclgd/`) [V] | sin commits propios; el clon está en `fb12a65` (2026-10-28) | sí (del clon) | externo | Clon local de `Ozuba/rclgd` (rama jazzy, Godot 4.7.1), con su `.git`. Referencia de la API que imita `ros2_vita` |
| `ros2_vita` | 128 K | 11 | no | 2026-11-13 | no (tiene `API_PARITY.md`) | motor | Módulo C++ estático del motor que expone la API de rclgd a GDScript, con transporte XRCE. Tiene un `__pycache__` ignorado |
| `test` | 28 K | 3 | no | 2026-10-29 | no | motor (pruebas) | Pruebas de host de `ros2_vita` (`test/project/runner.gd`, `run_host_tests.sh`) |
| `vitasdk-stubs` | 8,0 K | 1 | no | 2026-10-30 | no | motor (SDK) | `dlfcn.h` que se copia al SDK de la Vita |

Sin vacías dentro de `godot/` salvo las de §6. Ficheros sueltos de `godot/`: `README.md` (9,5 K, la guía del módulo).

### 2.1 Enlaces simbólicos

`find godot -maxdepth 3 -type l` devuelve 7 enlaces. `git ls-files -s` confirma que los 7 están versionados (modo 120000) [V].

| Enlace | Destino | Efecto |
|---|---|---|
| `godot/g1-unitree/comun` | `../plantillas` | Proyecto usa la biblioteca compartida |
| `godot/rbkairos-plus/comun` | `../plantillas` | Idem |
| `godot/dron-mapeo/comun` | `../plantillas` | Idem |
| `godot/g1-sensores/comun` | `../plantillas` | Idem |
| `godot/g1-sensores/robot` | `../g1-unitree/robot` | `g1-sensores` no tiene su robot: depende de `g1-unitree` |
| `godot/g1-sensores/anim` | `../g1-unitree/anim` | Idem para las animaciones de marcha |
| `godot/g1-sensores/marcha.gd` | `../g1-unitree/marcha.gd` | Idem para el script de marcha |

Riesgo [I]: en un clon con `core.symlinks=false` (habitual en Windows) estos enlaces se convierten en ficheros de texto, y el proyecto `g1-sensores` deja de cargar. No se ha probado [?]. Fuera de `godot/` no hay enlaces versionados. Los enlaces no versionados que sí existen (`web/node_modules/*`, `mcp/ros2-introspection/.venv/*`) son generados e ignorados [V].

## 3. Primer nivel de `tools/`, `docker/`, `skills/`, `modules/` y `mcp/`

| Ruta | Tamaño | Versionada | Ignorada | Último commit | README | Qué es |
|---|---|---|---|---|---|---|
| `tools/hwprobe` | 24 K | 3 | no | 2026-10-27 | sí | Sonda de hardware de la Vita, sin compilar (docs/14 §9) |
| `tools/urdf2godot` | 28 K | 3 | no | 2026-11-12 | sí | URDF a escena `.tscn` con mallas diezmadas, para la Vita |
| `tools/__pycache__` | 36 K | 0 | sí, `.gitignore:2` [V] | sin commits | no | Caché de Python |
| `tools/` (19 scripts sueltos) | — | 19 | no | 2026-11-13 | no | `build-*.sh/.py`, `export-vita-vpk.sh`, `deploy-vpk-ftp.sh`, `vita-stack.sh`, `vita-doctor.sh`, `run-parity-tests.sh`, `install-skills.sh`, `netlog-listen.sh`, `gen_msg_schema.py`, `env-devpc.{sh,fish}`, `generar-*.py`, `diezmar-malla.py`, `convertir-urdf-dae.py`, `check-vita-imports.py` |
| `docker/g1` | 52 M | 5 | caché `docker/g1/cache/` por `.gitignore` raíz (sí) [V] | 2026-11-13 | no (lo cubre `docker/README.md`) | Simulación del G1: `casa.json`, `casa.py`, `g1_sim.py`, `g1.rviz`, `Dockerfile` |
| `docker/scripts` | 64 K | 5 | no | 2026-11-12 | no | Puentes y monitores: `vita_relay.py`, `vita_monitor.py`, `turtle_odom.py`, `fuente_prueba_relay.py`, `test_vita_relay.py` |
| `docker/ws` | 8,0 K | 0 | sí, `docker/.gitignore:2` [V] | sin commits | no | Workspace colcon. `vita-ros.sh:18` crea `ws/src` y `docker-compose.yml:46` lo monta en `/ws`. `ws/src` vacía es lo esperado [V] |
| `skills/godot4-ros-scripting` | 44 K | 7 | no | 2026-10-27 | no | Skill de escena Godot 4 con ROS 2 |
| `skills/rclgd` | 168 K | 28 | no | 2026-10-29 | no | Skill de la API de rclgd y referencias regenerables |
| `skills/ros2-vita-godot` | 12 K | 1 | no | 2026-10-29 | no | Skill del port a la Vita (`SKILL.md`) |
| `skills/vita-build-package` | 12 K | 1 | no | 2026-11-01 | no | Skill de compilación y `.vpk` |
| `skills/vita-deploy-logs` | 12 K | 1 | no | 2026-11-01 | no | Skill de despliegue FTP y logs |
| `skills/vita-dual-module` | 12 K | 1 | no | 2026-11-01 | no | Skill para crear módulos duales |
| `modules/mem-pool` | 76 K | 8 | no | 2026-11-01 | sí | Pool de memoria de tamaño fijo |
| `modules/microros-transport` | 84 K | 10 | no | 2026-11-01 | sí | Transporte micro-ROS (XRCE) |
| `modules/msg-cdr` | 140 K | 18 | no | 2026-11-01 | sí | Serialización CDR |
| `modules/msg-ring` | 80 K | 8 | no | 2026-11-01 | sí | Cola en anillo de mensajes |
| `modules/msg-schema` | 456 K | 82 | no | 2026-11-01 | sí | Esquemas de mensajes (`.rsch`) y sus fixtures |
| `modules/net-udp` | 108 K | 8 | no | 2026-11-01 | sí | Sockets UDP |
| `modules/tf-tree` | 80 K | 9 | no | 2026-11-01 | sí | Árbol de transformadas |
| `modules/viz-math` | 72 K | 8 | no | 2026-11-01 | sí | Matemáticas de visualización |
| `mcp/ros2-introspection` | 71 M | 7 | `.venv/` por `.gitignore:4` [V] | 2026-06-28 | sí | Servidor MCP que expone el grafo ROS 2 (`FakeBackend` y `RclpyBackend`). Sin su `.venv`, pesa unos 110 K |

## 4. Duplicados (comparación byte a byte)

`cmp` sigue los enlaces, así que los pares con enlace no son copias. Lo que no es duplicado a propósito se marca.

| Nombre | Ubicaciones | Resultado | Lectura |
|---|---|---|---|
| `assets/PSVita/*` (24 ficheros, con sus `.import`) | `godot/g7-imu/assets/PSVita/` y `godot/g7b-imu3d/assets/PSVita/` | IGUALES, los 24 [V] | Duplicado real de assets. Candidato a moverlos a `plantillas/` o a enlazarlos |
| `schema.rsch` | 10 ficheros: 6 con md5 `a2645…` (g4, g5, g6, g7-imu, g7b-imu3d y `modules/msg-schema/tests/fixtures`), 2 con `d78ad…` (dron-mapeo, rbkairos-plus), 1 con `2c359…` (g1-unitree), 1 con `98c3e…` (g1-sensores) | 4 versiones distintas [V] | `godot/ros2_vita/README` dice que hay "4 copias idénticas" (g4, g5, g6, g7-imu). Está desactualizado: son 5 idénticas más la del módulo. Ver §7 |
| `urdf_robot.gd` | `godot/g1-unitree/robot/` y `godot/rbkairos-plus/robot/` | IGUALES [V] | Copia real. `tools/urdf2godot/README.md` pide copiarla a mano; candidata a `plantillas/robots/` |
| `vita_relay.gd.uid` | `godot/comun/` y `godot/plantillas/` | DISTINTOS [V] | El de `comun/` es huérfano (§5) |
| `dlfcn.h` | `godot/vitasdk-stubs/` (1483 B) y `godot/godot35/vitasdk-stubs/` (1530 B) | DISTINTOS [V] | El de `godot35` es histórico. El activo es `godot/vitasdk-stubs/` |
| `config.py`, `register_types.{h,cpp}`, `SCsub` | `godot/ros2_vita/` y `godot/godot35/modules/microros/` | DISTINTOS [V] | El módulo de Godot 3.5 es la versión histórica del mismo código |
| `runner.gd` | `godot/plantillas/pruebas/` y `godot/test/project/` | DISTINTOS [V] | Dos ejecutores de pruebas con el mismo nombre: confunde. Ver §7 |
| `main.gd` (6), `filtro.gd` (2) | varias apps | DISTINTOS entre sí [V] | Mismo nombre, otro contenido: cada proyecto tiene su `main.gd`. Esperado |
| `main.tscn` (9), `project.godot` (11), `export_presets.cfg` (9) | un fichero por proyecto | DISTINTOS [V] | Esperado por proyecto |
| `marcha.gd`, `robot/`, `anim/`, `comun/` | `g1-sensores` frente a `g1-unitree` | Enlaces, no copias [V] | Ver §2.1 |
| Mallas `mallas_g1_pc/*.obj` frente a `mallas_g1_vita/*.obj` (35 pares) | `godot/g1-unitree/robot/` | 11 IGUALES, 24 DISTINTAS [V] | La versión Vita es la diezmada (`informe.json`). [I] Las 11 idénticas son probablemente mallas pequeñas que no se diezmaron. La separación PC/Vita es intencional (regla de escenas editables); las copias idénticas sobran [I] |
| Mallas `mallas_rbkairos_pc` frente a `_vita` (21 pares) | `godot/rbkairos-plus/robot/` | 1 IGUAL, 20 DISTINTAS [V] | Igual que arriba |
| `LowCmd.msg` (7 pares en total: `BmsCmd`, `BmsState`, `IMUState`, `LowCmd`, `LowState`, `MotorCmd`, `MotorState`) | `godot/g1-sensores/ros/msg/unitree_go/` frente a `unitree_hg/` | DISTINTOS [V] | Dos dialectos de mensajes Unitree a propósito [I] |
| `robot.json`, `ros/topics.json` | `dron-mapeo`, `rbkairos-plus`, `g1-sensores` | DISTINTOS [V] | Config por robot |
| `CREDITOS.md` (7), `colormap.png` (3) | apps y `plantillas/mundo` | DISTINTOS entre los que se compararon [V] | Cada proyecto acredita sus assets |
| `Dockerfile` | `docker/Dockerfile` y `docker/g1/Dockerfile` | DISTINTOS [V] | Son dos cosas distintas: estación y simulación del G1 |
| `gen_fixtures.py` | `modules/msg-cdr/tests/` y `modules/msg-schema/tests/` | DISTINTOS [V] | Dos generadores de fixtures. `tf_empty.bin` sí es IGUAL en ambos [V] |
| `Cargo.toml` (8), `lib.rs` (8), `parity_test.c` (8), `host_common_flags` (5) | uno por módulo en `modules/` | Distintos [V] | Esperado: un juego por módulo |
| `SKILL.md` (5) | una por skill | Distintos [V] | Esperado |
| `AGENTS.md` y `CLAUDE.md` | raíz | Casi gemelos: la salida de `diff` tiene 28 líneas [V] | Riesgo de que se desincronicen [I] |
| `.gitignore` | `docker/` y `godot/godot35/` | Distintos [V] | Esperado |

Hallazgo aparte: los 4 `informe.json` de `godot/*/robot/mallas_*/` (`g1-unitree` y `rbkairos-plus`, versiones PC y Vita) versionan rutas absolutas de la máquina: `/home/jcrex/Proyectos/PSVita-ROS/toolchains/...` y `/tmp/claude-1000/.../scratchpad/...` [V]. No son portables y exponen rutas locales.

## 5. Archivos `.uid` huérfanos

Hay 56 `.uid` en el árbol (todos versionados; ninguno sin versionar fuera de `rclgd` y `.godot`) [V].

- Huérfano: `godot/comun/vita_relay.gd.uid`. No existe `godot/comun/vita_relay.gd`; el script está en `godot/plantillas/vita_relay.gd` con su propio `.uid` [V].
- Los otros 55 tienen su fuente (`${fichero%.uid}` existe) [V].
- Distribución: `plantillas` 17+7+6+5+3+3 (sensores, pruebas, robots, ros, mundo, raíz); `g7-imu` 4, `g7b-imu3d` 2, `g1-unitree` 4 y `robot` 1, `g1-sensores` 1 y `pruebas` 1, `rbkairos-plus/robot` 1 [V].
- Proyectos sin ningún `.uid`: `g4-smoke`, `g5-xrce`, `g6-hmi` (sus `main.gd` no tienen `.uid`) [V]. Probablemente se crearon antes de que el editor generara `.uid`, o no se han vuelto a abrir [?].

## 6. Carpetas vacías

Total en el repo (sin `toolchains/` ni `.git`): 148 [V]. La mayoría son restos generados: `CMakeFiles/` y `CompilerId*/tmp` de `auditoria/` y `vita-app/`, `target/` de `modules/*/impl-rust`, `.godot/shader_cache/` y `mcp/.venv/include`. Son regenerables.

Las que no son artefactos generados (10):

| Carpeta | Estado | Lectura |
|---|---|---|
| `vita-app/sce_sys` | vacía; no versionada | Ninguna referencia dentro de `vita-app/`. Aparece en `godot35/scripts/build-vita-template.sh:12`, `docs/guias-vita/vitasdk-toolchain.md:174` y `docs/06`. [?] Si el empaquetado `.vpk` espera `sce_sys/` con iconos, un clon limpio fallaría. Validar en el PC |
| `docker/ws/src` | vacía; ignorada | Esperada: punto de montaje (`vita-ros.sh:18`, `docker-compose.yml:46`) [V] |
| `docs/ia/organizacion` | vacía antes de este informe | Carpeta de salida de la auditoría de organización |
| `godot/rclgd/rclgd/godot-cpp` | vacía; dentro de `rclgd` (ignorado) | [I] Submódulo sin inicializar. Dentro del clon externo |
| `Videos/proxy`, `Videos/1794433747822/{workfiles,sequences,preview,masks/source-frames}`, `Videos/1794433676144/masks/source-frames` | 6 vacías; `Videos/` ignorado | Restos de una edición anterior. No afectan al repo, pero ocupan entradas en el disco [I] |

Git no guarda carpetas vacías: ninguna de estas llega a un clon. Lo que dependa de ellas falla en silencio.

## 7. Hallazgos y candidatos (no ejecutados)

Lista de decisiones para el usuario, en orden de impacto. Nada de esto se ha tocado.

1. Borrar `godot/comun/` (`.uid` huérfano). Sin riesgo: nada lo referencia [V].
2. Unificar `schema.rsch`. Hay 4 versiones: la de los hitos y del módulo (md5 `a2645…`), la de `dron-mapeo`/`rbkairos-plus` (`d78ad…`), la de `g1-unitree` (`2c359…`) y la de `g1-sensores` (`98c3e…`). El README de `ros2_vita` está desactualizado. El paso para generarlos desde una fuente es la tarea M8 de `docs/18:335` (citada en `godot/README.md`, sección de esquemas) [V]. Decidir si los 4 esquemas distintos son intencionales [?].
3. Mover los 24 assets de `PSVita/` (idénticos) a `plantillas/` o a un enlace, como ya se hace con `comun/`. También `urdf_robot.gd` a `plantillas/robots/`.
4. Renombrar uno de los dos `runner.gd` (`plantillas/pruebas/` y `test/project/`).
5. Sacar del repo las rutas absolutas de `informe.json` (o no versionarlos). Regenerar con rutas relativas al proyecto (`tools/urdf2godot/urdf2godot.py`).
6. Enlaces simbólicos de `g1-sensores` (7 en total): un clon sin soporte de enlaces rompe el proyecto. Decidir si se sustituyen por copia o por una carpeta de datos compartida [I].
7. Espacio ignorado fuera del repo: `toolchains/godot4-vita` (3,7 G) y `rustup` (1,6 G), `Videos/` (547 M) y `auditoria/ogre` (224 M con su `.git`). Son candidatos a liberar, pero solo el usuario puede decidirlo.
8. `media/` (12 M, dos ficheros) está versionado en git. Candidato a Git LFS o a almacenamiento externo [I].
9. `docs/ia/plan-organizacion-y-visor-2026-11-13.md` está sin versionar (`git status`) [V].
10. `AGENTS.md` y `CLAUDE.md` son casi gemelos. Decidir si `AGENTS.md` se genera desde `CLAUDE.md` [I].
11. `mcp/` figura con fecha 2026-11-01 por `mcp/.gitkeep` (commit `1a7dc5e`), que ya no está en el índice. Causa exacta [?]; no afecta al contenido.
12. `godot/ros2_vita/README` dice "4 copias idénticas" de `schema.rsch`. Actualizar al estado de §4.

## 8. Limitaciones

- No se ejecutó ninguna compilación ni se abrió Godot. Las marcas de hito cerrado (G4–G7) vienen de `godot/README.md` y de los encabezados de `main.gd`, no de pruebas nuevas.
- `du` excluye `target/`, `node_modules/` y `.godot/`, como se pidió. Los tamaños no incluyen los cachés `.godot/`, pero sí incluyen `build/` y `.import/` de `godot35/` (ignorados por su propio `.gitignore`).
- `cmp` solo se aplicó a los pares listados en §4. No se comparó todo el árbol.
- El `.uid` se consideró huérfano si no existe el fichero con el mismo nombre sin `.uid`. No se comprobó lo contrario (scripts o escenas sin `.uid`), salvo en `g4`, `g5` y `g6`.
