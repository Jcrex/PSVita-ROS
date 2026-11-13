# `godot/` — módulo `ros2_vita` para Godot 4 (godot4-vita 4.8-dev7)

> **Estado (2026-11-13): G1–G7c VERDES; apps vivas `g1-unitree`, `g1-sensores`, `rbkairos-plus` y `dron-mapeo`
> sobre `plantillas/`; siguiente: visor de topics (ADR 0013).** Historia de las puertas: compila en host (294/0) y para la Vita (`verify_runtime.py` PASS) y
> **corre en la Vita** en *loopback* (G4) y con **transporte XRCE publica en ROS 2 Jazzy desde la Vita** (G5,
> 2026-10-30: `/vita_hello` y `/cmd_vel` a 10 Hz en `ros2 topic echo`). **G6:** la HMI `g6-hmi` teleopera turtlesim y
> dibuja `/odom` en hardware (`/cmd_vel` 19,5 Hz, `/odom` 62,5 Hz). Decisión y razones:
> `docs/adr/0008-godot-via-modulo-estatico.md`; investigación y plan: **`docs/18-migracion-a-godot4.md`**.

## Qué es

Un módulo C++ **estático** del motor (la Vita no admite GDExtension) que expone a GDScript la API de
[`rclgd`](https://github.com/Ozuba/rclgd) (`docs/17`): `RosNode`, `RosPublisher`, `RosSubscriber`,
`RosTimer`, `RosQoS`, `RosMsg` y el singleton `rclgd` — para que **el mismo script corra en el PC
(rclgd, Godot 4.7.1) y en la Vita (`ros2_vita`, 4.8-dev7)**. Tabla de paridad: `ros2_vita/API_PARITY.md`.

```
GDScript ── RosNode / RosPublisher / RosSubscriber / RosMsg ──►  ros_runtime.cpp / ros_msg.cpp
                                                                    │ msg-schema (CDR guiado por esquema)
                                       transporte intercambiable ◄──┘ modules/ (C o Rust, header C único)
                                         loopback (pruebas)  |  xrce (micro-ROS por UDP; host y Vita)
```

## Contenido por grupos (ADR 0014; `docs/ia/organizacion/decision-fable.md` §3)

Estructura **plana**: no se agrupa en subcarpetas porque `SCsub`, `test/run_host_tests.sh` y
`tools/build-godot-template.sh` calculan la raíz del repo desde aquí (un nivel más rompe el build).

| Grupo | Carpeta | Qué es |
|---|---|---|
| Motor | `ros2_vita/` | El módulo: `config.py`, `SCsub`, `register_types.*`, `ros_msg.*` (mensajes dinámicos), `ros_runtime.*` (singleton, nodo, pub/sub/timer), `xrce_transport.*` (micro-ROS, G5). Paridad con rclgd: `ros2_vita/API_PARITY.md` |
| Motor | `loader-patches/` | `0001-ros2-vita-imports.patch`: imports que faltan en `default_dynlib.c` del loader (red y helpers); **aplica en `d1a5f29`** |
| Motor | `vitasdk-stubs/` | `dlfcn.h` que se copia al SDK (docs/18 §4.5) |
| Motor | `test/` | Pruebas de host del módulo en GDScript (`test/project/runner.gd`) + `run_host_tests.sh` |
| Biblioteca compartida | `plantillas/` | Robots, sensores ROS 2, mundo 3D (`mundo/mundo.tscn`), esquemas y pruebas comunes. En los proyectos se ve como `res://comun` (enlace simbólico). `plantillas` es nombre histórico |
| Apps vivas | `g1-unitree/` | Unitree G1 (URDF → escena, marcha, 60 FPS en la Vita) |
| Apps vivas | `g1-sensores/` | G1 con D435, Mid-360, 3 IMU, joints y topics propietarios Unitree (57–58 FPS en la Vita, perfil ligero) |
| Apps vivas | `rbkairos-plus/` | RB-KAIROS+ con UR10e, IMU, 2×SICK S300, D435, sensores extra del bridge Gazebo y mapa |
| Apps vivas | `dron-mapeo/` | Dron 6DOF con RGB-D frontal/cenital, LiDAR 3D/2D, GNSS, barómetro, magnetómetro, sonar y mapa |
| Puertas cerradas (regresión y lecciones) | `g4-smoke/` | G4: proyecto mínimo (loopback + `Twist`, sin red) |
| Puertas cerradas | `g5-xrce/` | G5: `/vita_hello`, `/cmd_vel` (stick) y suscripción a `/pc_hello` |
| Puertas cerradas | `g6-hmi/` | G6: teleop `/cmd_vel` con el mapeo de docs/09 + vista cenital de `/odom` |
| Puertas cerradas | `g7-imu/` | G7a: IMU de la Vita → `sensor_msgs/Imu` en `/vita/imu` (lección `docs/tutorial/08`); G7c: modelo 3D en la propia Vita a 59 FPS |
| Puertas cerradas | `g7b-imu3d/` | G7b: visor 3D de la IMU de la Vita en el PC |
| Externo, sin versionar | `rclgd/` | Clon local de [`Ozuba/rclgd`](https://github.com/Ozuba/rclgd) (rama `jazzy`, Godot **4.7.1**): editor del PC y referencia de la API que imita `ros2_vita` (`.gitignore`) |

Una puerta cerrada se archiva cuando otra app la **sustituye** como prueba, no por estar cerrada (ADR 0014).
Herramientas relacionadas (en `tools/`): `build-godot-template.sh` (receta de la plantilla), `build-rust-pic.sh`
(staticlib Rust PIC), `check-vita-imports.py`, `export-vita-vpk.sh`, `urdf2godot/` (genera las escenas
`*_pc.tscn`/`*_vita.tscn` y `informe.json` de los robots).

### Enlaces simbólicos versionados

| Enlace | Apunta a |
|---|---|
| `g1-unitree/comun` | `../plantillas` |
| `g1-sensores/comun` | `../plantillas` |
| `rbkairos-plus/comun` | `../plantillas` |
| `dron-mapeo/comun` | `../plantillas` |
| `g1-sensores/robot` | `../g1-unitree/robot` |
| `g1-sensores/anim` | `../g1-unitree/anim` |
| `g1-sensores/marcha.gd` | `../g1-unitree/marcha.gd` |

> **Advertencia:** con `git config core.symlinks false` (Windows, algunos clones) los enlaces se convierten en
> ficheros de texto con la ruta y los proyectos dejan de abrir. `tools/export-vita-vpk.sh` copia el proyecto
> resolviendo los enlaces (hallazgo G3); no los sustituyas por copias. Herramientas que reescriben ficheros en
> masa (`perl -pi`, `sed -i`) también los convierten en ficheros: exclúyelos (`find … -type l`).

### Pruebas y comprobaciones

```bash
GH=toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
godot/test/run_host_tests.sh "$GH"                                                  # módulo (test/project/runner.gd)
"$GH" --headless --path godot/g1-sensores --script res://comun/pruebas/runner.gd    # plantillas (plantillas/pruebas/runner.gd)
cmp godot/g1-unitree/robot/urdf_robot.gd godot/rbkairos-plus/robot/urdf_robot.gd    # deben seguir idénticos
```

Hay **dos `runner.gd`** a propósito: `test/project/runner.gd` prueba el módulo C++; `plantillas/pruebas/runner.gd`
prueba la biblioteca dentro de un proyecto. `urdf_robot.gd` está duplicado en `g1-unitree/robot/` y
`rbkairos-plus/robot/` (lo copia el generador); se unificará en `plantillas/robots/` la primera vez que la Fase V
lo cambie. Los `informe.json` de `*/robot/mallas_*/` guardan rutas relativas al repo (sin rutas de la máquina).

## Puertas de verificación (docs/18 §8)

1. **G1 — host (PC):** compilar el módulo con un Godot de host y correr las pruebas:
   ```bash
   cd <godot4-vita>
   python3 -m SCons platform=linuxbsd target=editor custom_modules=<repo>/godot \
        x11=no wayland=no vulkan=no opengl3=no
   godot/test/run_host_tests.sh <godot4-vita>/bin/godot.linuxbsd.editor.x86_64
   ```
   Prueba: `RosMsg` ↔ CDR **bit a bit** con los 24 tipos de `modules/msg-schema/tests/fixtures`,
   propiedades anidadas, pub/sub por *loopback*, timers, parámetros y ejes.
2. **G2/G3 — PC (cruzada):** `tools/build-godot-template.sh` (necesita VitaSDK, SCons, VitaGL parcheado).
3. **G4 — Vita:** proyecto mínimo `godot/g4-smoke/` (rclgd en *loopback* + pub/sub de `Twist`; fondo verde = OK,
   rojo = fallo). Editor de host **4.8-dev7** (el exportador `psvita` rechaza otra versión):
   ```bash
   cd <godot4-vita>
   GODOT_VERSION_STATUS=dev7 scons platform=linuxbsd target=editor \
        custom_modules=<repo>/godot/ros2_vita x11=no wayland=no vulkan=no opengl3=no
   tools/export-vita-vpk.sh godot/g4-smoke build/g4-smoke.vpk   # exporta sobre una copia
   ```
   `export-vita-vpk.sh` copia el proyecto, le añade el addon `psvita` y `out/vita_release.zip` (variante C) y
   exporta en modo *headless*. Después: instalar el `.vpk` (FTP o modo USB de VitaShell). **Validado en hardware 2026-10-30 (G4 verde).**
4. **G5 — transporte XRCE.** Libs del cliente: `XRCE_PIC=1` (Vita) o `XRCE_HOST=1` (host)
   `tools/build-xrce-client-vita.sh`; el SCsub activa el transporte si las encuentra
   (`ros2_vita: transporte XRCE activado` en la salida de SCons). Prueba en el PC:
   ```bash
   docker run -d --name g5-agent --net=host --ipc=host microros/micro-ros-agent:jazzy udp4 --port 8888
   godot --headless --path <copia de godot/g5-xrce sin el plugin> -- -p agent_ip:=127.0.0.1
   docker run --rm --net=host --ipc=host --entrypoint bash microros/micro-ros-agent:jazzy -c \
     'source /opt/ros/jazzy/setup.bash; ros2 topic echo /vita_hello'
   ```
   `--ipc=host` en **los dos** contenedores: si no, Fast DDS intenta memoria compartida entre contenedores
   distintos, el descubrimiento funciona pero **no llegan datos**. En la Vita: `tools/export-vita-vpk.sh godot/g5-xrce`
   (la IP del agente va en `ros/agent_ip` de `project.godot`).
   Diseño: un solo hilo; `poll()` cada frame con `uxr_run_session_time(0)` (no bloquea). Los mensajes best effort
   se copian a una cola de 64 y se envía uno por frame (`be_pending`/`be_dropped` en el diagnóstico), evitando
   saturar el stream cuando varios sensores publican en el mismo frame. Sin agente, `rclgd.init`
   se bloquea ~10 s (10 intentos de sesión) y devuelve `ERR_CANT_CONNECT`. Los mensajes fiables tienen otra cola
   de 32 con reintento por `poll()` (`reliable_pending`/`reliable_dropped`): si el stream está lleno esperan en vez
   de descartarse o de bloquear a los demás sensores.
5. **G6 — HMI piloto (verde en hardware).** `docker/vita-ros.sh up` + `sim` (turtlesim + `/odom`) y
   `tools/export-vita-vpk.sh godot/g6-hmi` → `tools/deploy-vpk-ftp.sh build/g6-hmi.vpk`. Lecciones de XRCE: un
   mensaje reconstruido de fragmentos **no es contiguo** (copiar con `ucdr_deserialize_array_uint8_t`); a 20 Hz el
   stream fiable de 4 huecos se llenaba (ahora 16 + desvío a *best effort*); clave de cliente distinta por arranque.
   Límite actual: mensajes salientes de hasta ~7,5 KB (16 fragmentos de 512 B); entrantes hasta 16 KB.
6. **G7+ — Vita:** IMU (`Input.get_*`), panel trasero, cámara.

## Reglas heredadas de rclgd (mantener)
- Callbacks de suscripciones y timers: **hilo principal** (`process_frame`).
- Los objetos `Ros*` son `RefCounted`: **guardar la referencia** o se cancelan.
- Convención de ejes REP-103 ↔ Godot idéntica (`rclgd.godot_to_ros_vector`...).
- Los *arrays* de un mensaje son copias: asignar el array entero.

## Esquema de mensajes (`ros/schema.rsch`)
Cada app lleva su `res://ros/schema.rsch` (Godot exige que esté dentro de `res://`); un esquema por proyecto es
intencionado (cada app exporta sus tipos dentro del `.vpk`). Hoy hay **4 versiones**: las 5 puertas (`g4-smoke`,
`g5-xrce`, `g6-hmi`, `g7-imu`, `g7b-imu3d`) llevan el mismo blob que `modules/msg-schema/tests/fixtures/schema.rsch`
(40 tipos: `std_msgs`, `geometry_msgs`, `sensor_msgs`, `nav_msgs`, `tf2_msgs`, `visualization_msgs`…);
`rbkairos-plus` y `dron-mapeo` comparten otra; `g1-unitree` y `g1-sensores` tienen la suya (generadas con
`plantillas/generar_esquemas.py`). Regenerar (laptop o PC, con `rosbags`):
```bash
python3 -m venv /tmp/rbvenv && /tmp/rbvenv/bin/pip install rosbags numpy
/tmp/rbvenv/bin/python modules/msg-schema/tests/gen_fixtures.py          # blob completo de las pruebas
/tmp/rbvenv/bin/python tools/gen_msg_schema.py -o schema.rsch geometry_msgs/msg/Twist sensor_msgs/msg/Imu  # a medida
/tmp/rbvenv/bin/python tools/gen_msg_schema.py --dump geometry_msgs/msg/Twist                          # inspeccionar
```
Después copiar el fichero a cada app que use esos tipos (si se añade un tipo en una y no en otra, esa no lo
sabrá codificar). Automatizarlo en la exportación es M8 (`docs/18:335`).

## Pendientes (docs/18 §10)
M5 compilar en host · M6 cruzada · M7 red + transporte XRCE · M8 exportación de `.rsch` y clases sombra ·
M9 HMI piloto · M10 panel trasero/cámara · M11 TF · M12 servicios · M15 sesgo 4.7.1↔4.8-dev7.

## Histórico
> Godot 3.5 se descartó como destino el 2026-10-27 porque `rclgd` exige Godot 4 (`Callable`/`await`);
> su app (teleop con el módulo `microros`, validada en hardware) está archivada en `archivo/godot/godot35/` desde el
> 2026-11-13 (ADR 0014), con los docs 20–21 en `archivo/docs/`.
