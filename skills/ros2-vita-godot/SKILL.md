---
name: ros2-vita-godot
description: "Use when building or porting a Godot 4 + ROS 2 app to the PS Vita in the PSVita-ROS repo — the ros2_vita in-tree module (rclgd-compatible API over micro-ROS/XRCE), godot4-vita runtime, message schemas (.rsch), loader import table, PIC builds, export with the psvita addon, Vita limits. Points to the exact docs, scripts and gates."
---

# ros2_vita: la API de rclgd en la PS Vita (Godot 4 / godot4-vita)

**Estado (2026-10-27): escrito, SIN COMPILAR.** Solo funciona el transporte `loopback`; el XRCE real
está pendiente (`XrceTransport` es un stub). Lee el estado al día antes de prometer nada:
`docs/06-bitacora-estado.md` (último bloque), `docs/19` §8 (tablero de puertas).

## 0. Documentarse en este repo (comandos)
```bash
sed -n '/2026-10-27, 4.ª sesión/,$p' docs/06-bitacora-estado.md   # estado y siguiente paso
less docs/18-migracion-a-godot4.md        # internals del port, enlace, red, riesgos (R1-R11), backlog
less docs/19-plan-multiagente-migracion-godot4.md   # mapa de tareas T*, agentes, oleadas, briefs
less godot/ros2_vita/API_PARITY.md        # qué de rclgd existe en la Vita y qué no
tools/run-parity-tests.sh                 # módulos duales C/Rust (deben seguir verdes)
tools/vita-doctor.sh                      # entorno del PC (VitaSDK, SCons, clon godot4-vita)
tools/build-godot-template.sh --dry-run   # receta de la plantilla (solo PC)
python3 tools/check-vita-imports.py --help   # imports que el loader no resuelve
```
Para la API de rclgd en sí: skill **`rclgd`**; para escenas y scripts: skill **`godot4-ros-scripting`**.

## 1. Arquitectura en una línea por capa
`GDScript (API rclgd)` → `godot/ros2_vita/*.cpp` (módulo en árbol: `RosMsg`, `RosNode`, `rclgd`…) →
`msg-schema` (CDR genérico guiado por `.rsch`) + transporte (`LoopbackTransport` | `XrceTransport` →
`microros-transport` → `net-udp` → `sceNet`) → `libgodot.so` PIC cargado por el eboot de godot4-vita.
Los módulos C/Rust (`modules/*`) **no dependen de Godot**.

## 2. Diferencias con rclgd que cambian el código del juego
| Tema | rclgd (PC) | ros2_vita (Vita) |
|---|---|---|
| Tipos de mensaje | babel_fish, cualquier tipo instalado | **solo los del esquema** `res://ros/schema.rsch` (o `ros/schema_path`), generado en el PC con `tools/gen_msg_schema.py` |
| Crear `RosMsg` | en cualquier momento tras cargar la extensión | **después de `rclgd.init`** (carga el esquema): créalos en `_ready` |
| Argumentos | línea de órdenes `--ros-args` | no hay CLI: `ros/parameters/*` del proyecto; `-p transport:=loopback|xrce`, `-p schema:=…`, `-p agent_ip:=…` (**[pendiente con XRCE]**) |
| Descubrimiento | DDS | un **agente micro-ROS** en el PC; una sesión XRCE = un participante |
| Implementado hoy | todo | `init/shutdown/ok/get_dropped`, ejes, `ros_ready`; `RosNode` pub/sub/timer, `~` y relativos, `now()` local, parámetros locales + `parameter_changed`; `RosQoS` (history, depth, reliability, durability) |
| Pendiente | — | servicios, acciones, TF broadcaster/listener, `RosLogger`/`/rosout`, grafo (`count_*`), clases tipadas nativas (`docs/19` T3.*) |
| GDExtension | sí | **no** (módulo compilado dentro del motor) |
| Entrega de mensajes | `call_deferred` | cola acotada (256, descarta la más vieja; `rclgd.get_dropped()`) volcada en `process_frame` |

## 3. Límites de la Vita que importan al escribir scripts
- CPU Cortex-A9 a 333/444 MHz, 4 núcleos (el cuarto lo reserva el sistema, fuente débil: docs/14); WorkerThreadPool = 2 hilos en godot4-vita; RAM útil ~365 MiB.
- Pantalla 960×544; renderer **Compatibility**; ruta GXM 2D validada (3D experimental).
- Recrear texturas por fotograma es caro (`texture_2d_update` recrea): evita cámaras a pantalla completa.
- Reutiliza `RosMsg`; usa `Packed*Array`; publica estado a 10 Hz, no por fotograma.
- Entrada: IMU ya en `Input` (accel/gyro/gravity); táctil frontal; trasero pendiente (T1.4.2).

## 4. Flujo de trabajo (PC CachyOS, sin Windows)
1. Desarrollar con el editor **4.7.1 de rclgd** contra ROS real (`ros2 rclgd editor`).
2. Generar esquema (necesita `rosbags` en un venv):
   `python3 -m venv /tmp/rbvenv && /tmp/rbvenv/bin/pip install rosbags numpy`
   `/tmp/rbvenv/bin/python tools/gen_msg_schema.py -o <proyecto>/ros/schema.rsch geometry_msgs/msg/Twist nav_msgs/msg/Odometry …`
   (`--dump <tipo>` muestra la definición). Servicios/acciones: listar sus `*_Request/_Response/_Goal…`.
3. Exportar con el **editor 4.8-dev7 Linux** + addon `psvita` + plantilla propia (`vita_release.zip`),
   sobre una **copia** del proyecto (headless). Filtros de no-recursos: `*.rsch`, `package.xml`.
4. Instalar el VPK con VitaShell; agente `microros/micro-ros-agent:jazzy` con `--net=host --ipc=host`.

## 5. Reglas del repo al tocar esto
- Paridad C/Rust nunca en rojo; docs/comentarios/commits en español (`feat(godot4): …`).
- Todo lo no verificado lleva «validar en el PC / en hardware».
- Rust nuevo: explicar cada construcción (`docs/rust/`).
- No reabrir decisiones de `docs/19` §1 (Godot 4, red opción A, solo Linux, fork mínimo).
