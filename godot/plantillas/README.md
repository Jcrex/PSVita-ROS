# Plantillas Godot + ROS 2 para PC y PS Vita

Biblioteca compartida por `godot/rbkairos-plus/`, `godot/g1-sensores/` y `godot/dron-mapeo/`. Usa únicamente la API portable de `ros2_vita`: tipos ROS por texto, `RosMsg`, `RosNode`, `RosPublisher`, `RosSubscriber` y `RosQoS`. No usa GDExtension, clases tipadas, shaders propios, MultiMesh ni SubViewport fuera del sensor de cámara de PC.

## Registro de componentes

| Componente | Scripts | Función |
|---|---|---|
| Contexto ROS | `ros/contexto_ros.gd`, `ros/util_ros.gd` | Inicialización, QoS, referencias, REP-103 y covarianzas |
| Base de sensores | `ros/sensor_base.gd` | Frecuencia PC/Vita, publicador reutilizado y activación |
| Base móvil | `robots/robot_ros.gd`, `robots/base_mecanum.gd` | `/cmd_vel`, límites, hombre muerto, colisión y parada de emergencia |
| RB-KAIROS+ | `robots/rbkairos.gd`, `robots/brazo_trajectory.gd` | Mecanum, cuatro ruedas y UR10e por `JointTrajectory` |
| Humanoide | `robots/humanoide_g1.gd` | 29 joints, clips oficiales y montajes URDF de sensores |
| Dron | `robots/dron.gd` | Movimiento 6DOF cinemático, altitud, yaw y rotores |
| Estado | `sensores/odometria.gd`, `joint_state.gd`, `bateria.gd`, `estado_controlador.gd` | Odometry, JointState, BatteryState y estado JTC |
| Navegación | `sensores/imu.gd`, `gps.gd`, `rango.gd` | IMU, NavSatFix y Range |
| Percepción | `sensores/lidar_2d.gd`, `lidar_3d.gd`, `camara.gd` | LaserScan, PointCloud2, RGB/JPEG, CameraInfo y profundidad 32FC1 |
| Dron | `sensores/barometro.gd`, `magnetometro.gd`, `dron_estado.gd` | FluidPressure, MagneticField, rotores y flujo óptico |
| Mapa | `sensores/mapeo_2d.gd` | OccupancyGrid y teselas 2 bits de 260 B |
| Unitree | `sensores/unitree_estado.gd`, `unitree_control.gd` | LowState/LowCmd, SportModeState, API sport y formato G1 compacto |
| Seguridad | `sensores/estop.gd` | Suscripción Bool que detiene el robot |
| Mundo | `mundo/mundo_base.gd`, `mundo/assets.json` | Bosque, ciudad, parque y casa; colisiones y agentes móviles |
| Aplicación | `aplicacion_robot.gd` | Lee `robot.json`, crea modelo, sensores, cámara y HUD |

## Contrato de formatos compactos (VC/1)

`ros/vc1.gd` produce los mismos bytes que `docker/scripts/vita_relay.py` (comprobado en `pruebas/runner.gd`) y
`vita_relay.gd` los decodifica: scan `[seq & 0x7FFF, ang_min_cdeg, inc_cdeg, n, r…]` en cm (0 = sin impacto),
teselas 32×32 a 2 bit (0 desconocido, 1 libre ≤ 25, 2 ocupado ≥ 65) con `version` = época del mapa, juntas +
`joints_orden` (fiable + TRANSIENT_LOCAL). Nombres: `/vita/<robot>/…`. El G1 de `g1-sensores` usa el prefijo `g1s`
para no chocar con `docker/g1/g1_sim.py` (`/g1/estado`, `/odom`, `/tf`).

## Importar las plantillas en otro robot

1. Copia uno de los tres proyectos y conserva el enlace `comun -> ../plantillas`. El exportador ya lo copia con `cp -rL`.
2. Sustituye `visual_pc` y `visual_vita` por escenas horneadas con `tools/urdf2godot/`. No se parsea URDF en la Vita.
3. Edita `robot.json`: script de control, topics, `spawn_ros`, colisión y sensores. `pos_ros` y `rpy_ros` usan REP-103; la aplicación hace la conversión a Godot. En `mundo/assets.json`, `colision` contiene `[ancho_ROS_X, largo_ROS_Y, alto, centro_x, centro_y, centro_z]` ya escalado en metros; el cuerpo compensa la escala visual del asset.
4. Si el robot necesita otro comportamiento, hereda de `robots/robot_ros.gd`. Si necesita otro sensor, hereda de `ros/sensor_base.gd` o usa un `Node3D` con `contexto` y `robot`.
5. Genera el esquema CDR:
   ```fish
   toolchains/rosbags-venv/bin/python godot/plantillas/generar_esquemas.py --salida godot/<robot>/ros/schema.rsch
   ```
   Para Unitree añade `--unitree godot/g1-sensores/ros/msg`.
6. Incluye `robot.json`, `ros/topics.json`, `ros/*.rsch` y `comun/mundo/assets.json` en el preset. Excluye el modelo PC del VPK.

## Perfiles de plataforma

- **PC:** cámaras RGB/JPEG y profundidad por rayos, PointCloud2 de 16 anillos, LaserScan completo, OccupancyGrid y mensajes propietarios Unitree.
- **Vita:** IMU, GNSS, odometría compacta, joints compactos, LaserScan estándar de 60 rayos (296 B con `frame_id=laser`), Range, batería, mapa por teselas y formatos Unitree compactos.
- **No directo en Vita:** RGB, profundidad, nubes 3D y OccupancyGrid completo. El port no tiene 3D offscreen y XRCE limita BE a 488 B. Usa `docker/scripts/vita_relay.py` para convertirlos en mensajes pequeños.
- **BE = último valor por publicador** (revisado 2026-11-12): si un topic publica dos veces antes de salir, gana el más nuevo (`be_dropped` cuenta los reemplazos); cada `poll()` vacía la cola en bucle y envía en el mismo fotograma. Diagnóstico: `rclgd.get_transport_info().be_pending/be_dropped`.
- **Fiable:** FIFO de 32 mensajes / 64 KiB vaciada en bucle; descarta los más antiguos con aviso (`reliable_pending/reliable_dropped/reliable_full`).
- **Hora:** con XRCE, `now()` usa la hora del agente sincronizada al abrir la sesión (`uxr_sync_session`).
- **Grandes en PC:** scans completos, JPEG, PointCloud2, Odometry, JointState y LowState usan QoS fiable. En XRCE, las cámaras usan JPEG 160×120 y profundidad 40×30 a 1 Hz; RGB crudo queda opcional y el OccupancyGrid completo se reserva para loopback.

`mapeo_2d.gd` integra un LaserScan con odometría conocida. No es SLAM con scan matching ni cierre de bucles: para eso se usa `slam_toolbox` en PC. Las acciones y los servicios no existen en `ros2_vita`; `JointTrajectory`, `LowCmd` y `unitree_api/Request` sí son topics y funcionan.

## Ejecutar y comprobar

```fish
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
$G --path godot/rbkairos-plus
$G --path godot/g1-sensores -- lod=vita
$G --path godot/dron-mapeo -- sin_ros

# Pruebas headless sin red o con pub/sub local
set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
$GH --headless --path godot/rbkairos-plus -- transporte=loopback
$GH --headless --path godot/g1-sensores --script res://comun/pruebas/runner.gd
$GH --headless --path godot/dron-mapeo --script res://comun/pruebas/escena.gd -- sin_ros lod=vita
```

Argumentos tras `--`: `sin_ros`, `demo`, `transporte=loopback|xrce`, `agente=IP`, `puerto=N`, `lod=vita`, `captura=ruta.png`, `fotograma=N`. Las cámaras RGB requieren interfaz gráfica; en headless se validan CameraInfo y profundidad, pero no se inventan imágenes.

## Assets y reglas Vita

Los assets y licencias están en `mundo/CREDITOS.md`. Solo OBJ/materiales simples y triángulos. `tools/generar-assets-plantillas.py` genera animales, pelota y dron en Blender. `tools/convertir-urdf-dae.py` prepara Collada para Blender 5.2 (requiere `trimesh` y `pycollada` en el venv del toolchain).

El detalle de arquitectura, procedencia y validación está en `docs/29-plantillas-robots-sensores.md`. Cada proyecto tiene su README, `robot.json` y catálogo completo `ros/topics.json`.
