# Plantillas Godot + ROS 2 para PC y PS Vita

> Biblioteca compartida de los proyectos (enlace `res://comun`); `plantillas` es nombre histórico (ADR 0014).

Biblioteca compartida por `godot/g1-unitree/`, `godot/rbkairos-plus/`, `godot/g1-sensores/` y `godot/dron-mapeo/`. Usa únicamente la API portable de `ros2_vita`: tipos ROS por texto, `RosMsg`, `RosNode`, `RosPublisher`, `RosSubscriber` y `RosQoS`. No usa GDExtension, clases tipadas, shaders propios, MultiMesh ni SubViewport fuera del sensor de cámara de PC.

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
| Mundo | `mundo/mundo.tscn` + `mundo_base.gd`, `caja_mundo.gd`, `asset_mundo.gd` | Bosque, ciudad, parque y casa como nodos editables; colisiones y agentes móviles |
| Aplicación | `aplicacion_robot.gd`, `inicio_robot.gd` | Lee `robot.json`, crea robot, sensores, cámara y HUD en el `InicioRobot` de `main.tscn` |

## Regla de escenas: la escena manda en lo que se ve y dónde (doc 35)

Abre `main.tscn` en Godot: el mundo (`Mundo`, instancia de `comun/mundo/mundo.tscn`), el `Ambiente`, la `Luz` y el
punto de salida del robot (`InicioRobot`, con vista previa del modelo de PC) son nodos. Se editan con el gizmo y el
inspector. `robot.json` queda para lo que NO es colocar cosas: script de control, ROS (topics, Hz, QoS), sensores
montados en links del URDF, cámara de seguimiento y presupuesto. Detalle y motivos en
`docs/35-regla-escenas-editables.md`.

- **El mundo es compartido** por los tres proyectos (`comun -> ../plantillas`): editar `Mundo` en uno lo cambia en
  todos. Para editarlo, abre `comun/mundo/mundo.tscn` (o «Editable Children» en el nodo `Mundo`).
- **Cajas** (`Terreno/*`, `Casa/*`; script `caja_mundo.gd`): mueve con el gizmo, tamaño en `mesh → size`, color en
  `mesh → material`; `solido` = choca. No escales el nodo.
- **Modelos** (`Ciudad/*`, `Bosque/*`…; script `asset_mundo.gd`): rutas `modelo` / `modelo_vita`, `dibujar_en_vita`,
  `lod_vita` y movimiento en el inspector; la colisión es el hijo `Colision`. Para añadir uno, duplica uno parecido.
- **Al cambiar el mundo:** `pruebas/presupuesto.gd` y `pruebas/perfil_ligero.gd` (límite de la Vita) y, si añades
  un `.obj` nuevo de más de 250 triángulos, `python3 tools/generar-lod-vita.py` con el editor cerrado.

## Contrato de formatos compactos (VC/1)

`ros/vc1.gd` produce los mismos bytes que `docker/scripts/vita_relay.py` (comprobado en `pruebas/runner.gd`) y
`vita_relay.gd` los decodifica: scan `[seq & 0x7FFF, ang_min_cdeg, inc_cdeg, n, r…]` en cm (0 = sin impacto),
teselas 32×32 a 2 bit (0 desconocido, 1 libre ≤ 25, 2 ocupado ≥ 65) con `version` = época del mapa, juntas +
`joints_orden` (fiable + TRANSIENT_LOCAL). Nombres: `/vita/<robot>/…`. El G1 de `g1-sensores` usa el prefijo `g1s`
para no chocar con `docker/g1/g1_sim.py` (`/g1/estado`, `/odom`, `/tf`).

## Importar las plantillas en otro robot

1. Copia uno de los tres proyectos y conserva el enlace `comun -> ../plantillas`. El exportador ya lo copia con `cp -rL`.
2. Sustituye `visual_pc` y `visual_vita` por escenas horneadas con `tools/urdf2godot/`. No se parsea URDF en la Vita.
3. Edita `robot.json`: script de control, topics, colisión y sensores. `pos_ros` y `rpy_ros` usan REP-103; la aplicación hace la conversión a Godot. El punto de salida es el nodo `InicioRobot` de `main.tscn` (sin él, se usa `spawn_ros` de `robot.json`).
4. Si el robot necesita otro comportamiento, hereda de `robots/robot_ros.gd`. Si necesita otro sensor, hereda de `ros/sensor_base.gd` o usa un `Node3D` con `contexto` y `robot`.
5. Genera el esquema CDR:
   ```fish
   toolchains/rosbags-venv/bin/python godot/plantillas/generar_esquemas.py --salida godot/<robot>/ros/schema.rsch
   ```
   Para Unitree añade `--unitree godot/g1-sensores/ros/msg`.
6. Incluye `robot.json`, `ros/topics.json` y `ros/*.rsch` en el preset. Excluye el modelo PC del robot del VPK.

## Perfiles de plataforma

- **PC:** cámaras RGB/JPEG y profundidad por rayos, PointCloud2 de 16 anillos, LaserScan completo, OccupancyGrid y mensajes propietarios Unitree.
- **Vita:** IMU, GNSS, odometría compacta, joints compactos, LaserScan estándar de 60 rayos (296 B con `frame_id=laser`), Range, batería, mapa por teselas y formatos Unitree compactos.
- **No directo en Vita:** RGB, profundidad, nubes 3D y OccupancyGrid completo. El port no tiene 3D offscreen y XRCE limita BE a 488 B. Usa `docker/scripts/vita_relay.py` para convertirlos en mensajes pequeños.
- **BE = último valor por publicador** (revisado 2026-11-12): si un topic publica dos veces antes de salir, gana el más nuevo (`be_dropped` cuenta los reemplazos); cada `poll()` vacía la cola en bucle y envía en el mismo fotograma. Diagnóstico: `rclgd.get_transport_info().be_pending/be_dropped`.
- **Fiable:** FIFO de 32 mensajes / 64 KiB vaciada en bucle; descarta los más antiguos con aviso (`reliable_pending/reliable_dropped/reliable_full`).
- **Hora:** con XRCE, `now()` usa la hora del agente sincronizada al abrir la sesión (`uxr_sync_session`).
- **Grandes en PC:** scans completos, JPEG, PointCloud2, Odometry, JointState y LowState usan QoS fiable. En XRCE, las cámaras usan JPEG 160×120 y profundidad 40×30 a 1 Hz; RGB crudo queda opcional y el OccupancyGrid completo se reserva para loopback.

`mapeo_2d.gd` integra un LaserScan con odometría conocida. No es SLAM con scan matching ni cierre de bucles: para eso se usa `slam_toolbox` en PC. Las acciones y los servicios no existen en `ros2_vita`; `JointTrajectory`, `LowCmd` y `unitree_api/Request` sí son topics y funcionan.

## Perfil «Vita ligero» (60 FPS; doc 34)

Activo en la Vita y con `-- lod=vita` en el PC (`-- mundo=completo` lo anula para comparar). Cambia lo que se
dibuja, no lo que choca. Detalle, medidas y prueba de hardware en `docs/34-perfil-vita-ligero.md`.

- **Mundo** (`mundo/mundo_base.gd` sobre `mundo.tscn`): cajas fundidas por color, `modelo_vita` (variante de pocos
  triángulos generada con `tools/generar-lod-vita.py`), `dibujar_en_vita = false` (adorno que no se dibuja),
  `lod_vita` (< 0 no reducir, > 0 otra fracción) y visibilidad por distancia al robot.
- **`robot.json`, clave `mundo`:** `radio_visible` (m; 14 por defecto), `luz_por_vertice` (true por defecto) y
  `presupuesto` (`triangulos`, `mallas`; 15 000 y 80 por defecto, ADR 0011 §6).
- **HUD:** dos líneas cortas; SELECT/H muestra el completo. START/L alterna la luz por vértice del 3D GXM.
- **Contadores:** `ros/perfil.gd` escribe `[perfil-gd]` en stderr cada 300 fotogramas (µs por sección y triángulos
  en vista). En el PC: `-- perfil`.
- **Un robot nuevo** puede dar `linea_hud_corta()` y debe pasar `pruebas/presupuesto.gd`.

```fish
set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
$GH --headless --path godot/g1-sensores --script res://comun/pruebas/perfil_ligero.gd -- sin_ros lod=vita
$GH --headless --path godot/g1-sensores --script res://comun/pruebas/presupuesto.gd -- sin_ros lod=vita
$GH --headless --path godot/g1-sensores --quit-after 700 -- transporte=loopback lod=vita perfil
```

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
