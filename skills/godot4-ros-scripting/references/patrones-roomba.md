# Patrones del taller `roomba_ws` (Ozuba, ROSCon 2026) explicados

Rutas relativas a `roomba_ws/src/`. Tres paquetes: `roomba_rclgd_starter` (punto de partida, solo
física), `roomba_rclgd` (solución con ROS paso a paso), `roomba_hmi` (panel de control).

## 1. Robot diferencial (`roomba_rclgd/Scenes/roomba/roomba.gd`)
- `RigidBody3D` con `drive(lin, ang)` que fija objetivos; `_integrate_forces` aplica rampa de
  aceleración (`move_toward`) y fija `state.linear_velocity` a lo largo de `-basis.z` y
  `state.angular_velocity = UP * ang`; teleport pendiente aplicado en el siguiente paso de física.
- **Paso 2 `/cmd_vel`:** suscripción → `drive(msg.linear.x, msg.angular.z)`; guarda la hora del último
  comando y para si pasa `cmd_vel_timeout` (0,5 s) — como las bases reales.
- **Paso 3 odometría + TF:** `RosNavMsgsOdometry` reutilizado; pose relativa al origen de odom
  (`_odom_origin.affine_inverse() * global_transform`), convertida con `godot_to_ros_vector/quat`;
  twist en el marco del robot; `map→odom` estático, `odom→base_link` cada tick con `send_transform`.
- **Paso 5 estado:** `/bumper` (`std_msgs/Bool`) y `~/marker` (`visualization_msgs/Marker`, CYLINDER),
  publicados al cambiar (señal Godot) **y** a 10 Hz (`RosTimer`).
- **Paso 6 servicios:** `~/dock` (Trigger) y `~/reset_odometry` (Empty). Callback en hilo del executor:
  rellena `res`, y `teleport.call_deferred(_dock_pose)`; la pose del dock se lee **antes** en el hilo
  principal porque el callback no debe tocar nodos.
- **Paso 6 parámetros:** declarar con el `@export` como defecto y releer; `parameter_changed` con `match`.
- **Paso 7 acción:** `~/rotate_absolute` (`turtlesim/action/RotateAbsolute`); bucle con
  `await get_tree().physics_frame`, control proporcional, feedback por tick, cancelación con
  `is_cancel_requested()` → `canceled(result)`, *preemption* si llega otro goal → `abort(result)`.
  Mientras hay goal, se ignora `/cmd_vel`.

## 2. Sensores (`roomba_rclgd/addons/rclgd-sensors/`)
- `ros_sensor.gd` (`@abstract class_name RosSensor extends Node3D`): nodo ROS propio
  (`name.to_snake_case()`, `ros_namespace`), TF **estático** de montaje respecto a `parent_frame_id`
  (`~base_link`), `frame_id` con `~` = bajo el namespace, `_start_sampling(rate)` con **fase aleatoria**,
  `_advertise()` con QoS de sensor, colas de publicación paradas en `EXIT_TREE`/`PREDELETE`.
- `publish_queue.gd`: hilo propio con `Mutex` + `Semaphore`; publica capturas **en orden**, máximo 3 en
  cola (descarta la más vieja); `stop()` antes de que ROS se apague.
- Sellos de tiempo como `int` ns (`to_ns`, `write_stamp`) en callbacks de lectura de GPU: un `RosMsg`
  retenido al cerrar el motor provoca un crash tras descargar rclgd.
- `ros_imu.gd`: velocidad del punto de montaje (`get_velocity_at_local_position`), derivada → aceleración
  propia, ruido blanco + *random walk*, filtro paso bajo, publica a `publish_rate` desde `_physics_process`.
- Cámara/lidar/GPS/fisheye: compositores y lecturas de GPU; gizmos de editor (`*_gizmo.gd`, `plugin.gd`).

## 3. HMI (`roomba_hmi/main.gd`)
- `Control` con botones de flechas; timer de 10 Hz publica `/cmd_vel` **solo** si hay tecla pulsada, y
  un último cero al soltar (si no, se calla para que otros nodos puedan conducir).
- `/odom` → `Label`, `/bumper` → `modulate` rojo; cámara `sensor_msgs/Image` con QoS BEST_EFFORT →
  `Image.create_from_data(... FORMAT_RGBA8 ...)` → `ImageTexture` (caro; en la Vita, evitar recrear).
- Servicio `/roomba/dock`: `var r: RosMsg = await client.async_send_request(client.create_request()).completed`.
