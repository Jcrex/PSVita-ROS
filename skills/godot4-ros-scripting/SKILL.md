---
name: godot4-ros-scripting
description: "Use when designing Godot 4 scenes, nodes and GDScript for robotics apps that use ROS 2 (robot bodies, simulated sensors, HMI/teleop panels, TF, threads, await, signals, headless tests) — with rclgd on PC or ros2_vita on PS Vita. Gives proven patterns from Ozuba/roomba_ws plus Godot 4 essentials and commands to look up the engine docs."
---

# Godot 4 + ROS 2: nodos, escenas y scripts

Complementa a la skill **`rclgd`** (API ROS) con *cómo* estructurar el proyecto Godot. Patrones sacados
del taller oficial `github.com/Ozuba/roomba_ws` (ROSCon 2026, `main@8332acb`): robot diferencial,
sensores `rclgd-sensors` y HMI `roomba_hmi`.

## 0. Documentarse (motor y ejemplos)
```bash
godot --version                                  # con rclgd: ros2 run rclgd godot --version
godot --headless --doctool /tmp/godot-doc        # vuelca la referencia XML de TODAS las clases del motor
grep -l "class name=\"RigidBody3D\"" -r /tmp/godot-doc   # luego leer el XML de la clase
git clone --depth 1 https://github.com/Ozuba/roomba_ws  # patrones de este documento, código completo
```
- Web: `https://docs.godotengine.org/en/stable/` (elige la versión que coincide con `godot --version`).
- Clases y métodos realmente disponibles en tiempo de ejecución: `skills/rclgd/scripts/dump_api.gd`
  con `-- --prefix=<Clase>` (sin verificar).
- `references/godot4-esencial.md` resume lo que más se usa; `references/patrones-roomba.md` explica los
  patrones con el código; `templates/` tiene esqueletos listos.

## 1. Reglas de diseño
1. **Un `RosNode` por entidad lógica** (robot, sensor, HMI) creado en `_ready()`; el contexto lo inicia
   el autoload `ROS` antes de cargar escenas.
2. **Física en `_physics_process`/`_integrate_forces`, cosmética en `_process`.** Publica odometría en el
   paso de física; estado lento con `RosTimer` (p. ej. 10 Hz).
3. **Nada de bucles bloqueantes:** en acciones, avanza con `await get_tree().physics_frame`.
4. **Hilos:** nunca toques el árbol de escena desde otro hilo (servicios ROS, `Thread`); usa
   `call_deferred`. Publicar desde un hilo propio es válido (patrón `PublishQueue`).
5. **Mensajes reutilizados:** crea los `RosMsg` de alta frecuencia una vez (miembros) y rellénalos.
6. **Ejes:** convierte siempre con los helpers de `rclgd` o usa el TF broadcaster.
7. **`@export` = valor por defecto; el parámetro ROS manda:** `declare_parameter` + `get_parameter`.
8. **Sensores:** QoS de sensor (BEST_EFFORT, KEEP_LAST 5, VOLATILE); fase aleatoria de muestreo para no
   publicar todos en el mismo fotograma; sellos como `int` ns en callbacks diferidos de GPU.
9. **Teleop:** publica solo mientras hay entrada y un último cero al soltar (deja conducir a otros nodos);
   el robot se para si no llega `/cmd_vel` en `cmd_vel_timeout`.

## 2. Plantillas (`templates/`)
| Fichero | Para |
|---|---|
| `robot_diff_drive.gd` | `RigidBody3D` con `/cmd_vel`, `/odom`, TF, parámetros, servicio y acción |
| `ros_sensor_base.gd` | base de sensores (nodo propio, TF de montaje, muestreo, QoS de sensor) |
| `hmi_teleop.gd` | panel `Control`: botones → `/cmd_vel`, estado de `/odom`, cliente de servicio con `await` |
| `test_runner.gd` | runner headless `extends SceneTree` (patrón de rclgd) |

## 3. Árbol de escena real de `roomba_rclgd` (`Scenes/main.tscn`, `Scenes/roomba/roomba.tscn`)
```
Main (Node3D, main.gd)
├─ House (instancia; StaticBody3D…)
├─ Roomba (RigidBody3D, roomba.gd, export dock)  ← RosNode "roomba": /cmd_vel, /odom, /bumper,
│  │                                                ~/marker, ~/dock, ~/reset_odometry, ~/rotate_absolute
│  ├─ Collision (CollisionShape3D) · Visuals (MeshInstance3D: Led, SideBrush…)
│  ├─ Lidar  (Node3D + script RosLidar…, extends RosSensor)  ← RosNode propio + TF estático de montaje
│  ├─ Imu    (Node3D + RosImu)       ← publica ~/data (sensor_msgs/Imu) a 100 Hz desde el paso de física
│  └─ Camera (Node3D + RosCamera)
├─ HouseMarkers (Node, house_markers.gd)  ← marcadores para RViz
├─ Camera (Camera3D) · Hud (CanvasLayer/Label)
HMI aparte: paquete roomba_hmi, Control (main.gd) ← RosNode "roomba_hmi"
```

## 4. Si el destino es la PS Vita
Mismos scripts con el módulo `ros2_vita` (sin `rclcpp`): ver skill **`ros2-vita-godot`**
(diferencias de API, 960×544, rendimiento y exportación).
