# `godot/` — módulo `ros2_vita` para Godot 4 (godot4-vita 4.8-dev7)

> **Estado (2026-10-30): G1–G4 VERDES** — compila en host (294/0) y para la Vita (`verify_runtime.py` PASS) y
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

## Contenido

| Ruta | Qué es |
|---|---|
| `ros2_vita/` | El módulo: `config.py`, `SCsub`, `register_types.*`, `ros_msg.*` (mensajes dinámicos), `ros_runtime.*` (singleton, nodo, pub/sub/timer, transportes) |
| `ros2_vita/API_PARITY.md` | rclgd ↔ Vita, método a método |
| `test/` | Pruebas de host en GDScript (`runner.gd`) + `run_host_tests.sh` |
| `loader-patches/0001-ros2-vita-imports.patch` | Imports que faltan en `default_dynlib.c` del loader (red y helpers); **aplica en `d1a5f29`** |
| `../tools/build-godot-template.sh` | Receta completa: clonar, parchear, compilar con el módulo, verificar, empaquetar |
| `../tools/build-rust-pic.sh` | Staticlib Rust PIC `core` para enlazar en `libgodot.so` (opcional) |
| `../tools/check-vita-imports.py` | Comprueba los imports de cualquier `.a/.o` contra la tabla del loader |
| `../tools/export-vita-vpk.sh` | Exporta un proyecto Godot 4 a `.vpk` con el addon `psvita` y nuestra plantilla (G4) |
| `g4-smoke/` | Proyecto mínimo de la puerta G4 (loopback + `Twist`, sin red) |
| `ros2_vita/xrce_transport.*` | Transporte micro-ROS (G5): sesión XRCE, entidades por XML, streams fiable/best effort |
| `g5-xrce/` | Proyecto de la puerta G5: `/vita_hello`, `/cmd_vel` (stick) y suscripción a `/pc_hello` |
| `g6-hmi/` | HMI piloto (G6): teleop `/cmd_vel` con el mapeo de docs/09 + vista cenital de `/odom` (rejilla, robot, rastro, panel) |

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
   exporta en modo *headless*. Después: instalar el `.vpk` (FTP o modo USB de VitaShell). **Validar en hardware.**
4. **G5 — transporte XRCE.** Libs del cliente: `XRCE_PIC=1` (Vita) o `XRCE_HOST=1` (host)
   `vita-app/scripts/build-xrce-client-vita.sh`; el SCsub activa el transporte si las encuentra
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
   Diseño: un solo hilo; `poll()` cada frame con `uxr_run_session_time(0)` (no bloquea). Sin agente, `rclgd.init`
   se bloquea ~10 s (10 intentos de sesión) y devuelve `ERR_CANT_CONNECT`.
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

## Pendientes (docs/18 §10)
M5 compilar en host · M6 cruzada · M7 red + transporte XRCE · M8 exportación de `.rsch` y clases sombra ·
M9 HMI piloto · M10 panel trasero/cámara · M11 TF · M12 servicios · M15 sesgo 4.7.1↔4.8-dev7.

## Otras carpetas
| Ruta | Qué es |
|---|---|
| `godot35/` | **Histórico, validado en hardware:** la app teleop en **Godot 3.5** (`godot-vita`) con el módulo `microros` (rama `godot-migration`, fusionada el 2026-10-29). Referencia para la HMI piloto y las lecciones del `.vpk`. Ver `godot35/README.md` y `docs/20`/`21` |
| `rclgd/` | Clon local de [`Ozuba/rclgd`](https://github.com/Ozuba/rclgd) (rama `jazzy`, Godot **4.7.1**): el editor/entorno de desarrollo del PC (`ros2 rclgd editor`). **No se versiona** (`.gitignore`); es la referencia de la API que imita `ros2_vita` |

> Godot 3.5 se descartó como destino el 2026-10-27 porque `rclgd` exige Godot 4 (`Callable`/`await`);
> su app sigue funcionando en `godot35/`.
