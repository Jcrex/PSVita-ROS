# 29 — Plantillas Godot de robots y sensores ROS 2 para PC y PS Vita

> Implementación de los tres proyectos base solicitados: RB-KAIROS+, Unitree G1 y dron de mapeo.
> Estado: código, escenas, catálogos y pruebas de host/ROS 2 realizados el 2026-11-12. La medición de FPS y
> pérdidas en la Vita física es un gate separado y no se afirma hasta ejecutarla. Marcas: [V] verificado,
> [I] inferencia, [?] pendiente de confirmar. El diagnóstico de rendimiento XRCE y sus cuestiones abiertas está en
> [`docs/30-rendimiento-xrce-plantillas.md`](30-rendimiento-xrce-plantillas.md).

## 1. Entregables

| Proyecto | Robot | Sensores principales | Documentación de topics |
|---|---|---|---|
| `godot/rbkairos-plus/` | RB-KAIROS+ oficial + UR10e, cinemática mecanum | IMU, 2×SICK S300, D435, GPS, rear/PTZ RGB, LiDAR 3D, batería, mapa | `godot/rbkairos-plus/ros/topics.json` |
| `godot/g1-sensores/` | Unitree G1 de `godot/g1-unitree/`, 29 joints | D435 RGB-D, Mid-360 + IMU + scan, IMU pelvis/torso, LowState/LowCmd y API Unitree | `godot/g1-sensores/ros/topics.json` |
| `godot/dron-mapeo/` | Dron propio 6DOF, 552 triángulos | RGB-D frontal/cenital, LiDAR 3D/2D, GNSS, barómetro, magnetómetro, sonar, flujo y mapa | `godot/dron-mapeo/ros/topics.json` |
| `godot/plantillas/` | Biblioteca común | Control, sensores, mundo, esquemas y pruebas | `godot/plantillas/README.md` |

Cada proyecto contiene `project.godot`, `main.tscn`, `robot.json`, `export_presets.cfg`, README, créditos,
`ros/schema.rsch` y `ros/topics.json`. El enlace `comun -> ../plantillas` evita copias y es seguido por
`tools/export-vita-vpk.sh` con `cp -rL`.

## 2. Arquitectura

```
robot.json ──► aplicacion_robot.gd ──► mundo común + robot CharacterBody3D + sensores Node3D
                                      │
                     ROS por texto + RosMsg + RosQoS
                                      │
                            ros2_vita / XRCE / ROS 2 Jazzy
```

- `ros/contexto_ros.gd`: ciclo de vida, QoS y referencias `RefCounted`.
- `ros/sensor_base.gd`: cadencia distinta en PC/Vita, publicador persistente y activación.
- `robots/robot_ros.gd`: comandos, aceleración, límites, timeout de 0,5 s, colisiones y emergencia.
- `pos_ros` y `rpy_ros` del manifiesto usan REP-103; la aplicación convierte a Y-up de Godot.
- No hay GDExtension, clases tipadas, shaders propios ni parseo URDF en la Vita.
- El URDF se hornea con `tools/urdf2godot/`; los nombres de links/joints se conservan.
- Las cámaras de PC comparten el `World3D` principal en un SubViewport. La profundidad se calcula con rayos CPU
  alineados con la cámara (32FC1, 80×60 por defecto); no depende de un shader de profundidad.

### Cola best effort

Se modificó `godot/ros2_vita/xrce_transport.cpp`: los mensajes BE se copian a una cola de 64 y se envía uno por
`poll()`. Al llenarse se descarta el más antiguo. Esto elimina el `ERR_BUSY` observado al publicar varios sensores
en un frame. `rclgd.get_transport_info()` expone `be_pending` y `be_dropped` [V]. La regresión existente sigue en
294 comprobaciones, 0 fallos [V].

En PC se usa QoS fiable para scans completos, JPEG, PointCloud2, Odometry, JointState, OccupancyGrid y LowState.
En Vita el scan estándar se reduce a 60 rayos: 296 B CDR con `frame_id="laser"`, por debajo del límite de 488 B [V].

## 3. Sensores implementados

| Sensor | Mensaje ROS 2 | PC | Vita |
|---|---|---|---|
| IMU cinemática | `sensor_msgs/Imu` | 50 Hz | 30 Hz |
| GNSS con error correlacionado | `sensor_msgs/NavSatFix` | 10 Hz | 5 Hz |
| Odometría + TF base | `nav_msgs/Odometry`, `tf2_msgs/TFMessage` | 30 Hz | `Float32MultiArray` compacto + TF |
| LiDAR 2D por rayos | `sensor_msgs/LaserScan` | 180–360 rayos, fiable | 60 rayos BE + Int16 compacto |
| LiDAR 3D por rayos | `sensor_msgs/PointCloud2`, xyz+intensity | 16 anillos | relay |
| RGB | `sensor_msgs/Image`, rgb8 320×240 | 5 Hz | relay |
| JPEG | `sensor_msgs/CompressedImage` | 5 Hz | relay troceado |
| Intrínsecos | `sensor_msgs/CameraInfo` | alineado con imagen/profundidad | relay |
| Profundidad | `sensor_msgs/Image`, 32FC1 80×60 | rayos CPU | relay |
| Distancia | `sensor_msgs/Range` | 10 Hz | 5 Hz |
| Barómetro | `sensor_msgs/FluidPressure` | 20 Hz | 10 Hz |
| Magnetómetro | `sensor_msgs/MagneticField`, tesla | 20 Hz | 10 Hz |
| Batería | `sensor_msgs/BatteryState` | 1 Hz | 0,2 Hz |
| Articulaciones | `sensor_msgs/JointState` | fiable | Float32 compacto |
| UR10e | `trajectory_msgs/JointTrajectory` y `control_msgs/JointTrajectoryControllerState` | sí | sí |
| Mapa | `nav_msgs/OccupancyGrid` 128×128, 0,25 m | latched | teselas 32×32 a 2 bits, 260 B |
| Unitree | `unitree_hg`, `unitree_go`, `unitree_api` | sí | compactos y mensajes pequeños |

`mapeo_2d.gd` integra el scan usando la pose de odometría. **No es SLAM completo**: no hace scan matching,
optimización de grafo ni cierre de bucles. Para ello se alimenta `slam_toolbox` en PC con `/scan`, `/odom` y `/tf`.

## 4. RB-KAIROS+: procedencia y alcance

Fuentes [V]:

- `RobotnikAutomation/robotnik_simulation` @ `8273bc97470c6c4ec532b4223f0af0e0ab18e644`.
- `robotnik_description` @ `751059edd6af3a9c083018cfaee59e4496d46580`.
- `robotnik_sensors` @ `e5186c343910b86a924201edb256f79eb0f73295`.
- `UniversalRobots/Universal_Robots_ROS2_Description` @ `0eb1a861f7772fceb38510d90fa2f98ec668070c` y
  `ros-controls/control_msgs` @ `ab911bf0746fb064b1a88a2c0d364d6b7abd477b`.

El Xacro del modelo `rbkairos_plus` contiene UR10e, VectorNav, dos SICK S300 y D435 [V,
`robots/rbkairos/rbkairos_plus.urdf.xacro`]. El puente `spawn_robot.launch.py` también declara GPS, cámaras rear y
PTZ y un PointCloud2 superior. Estos últimos se ofrecen como sensores de simulación adicionales, no como una lista
de accesorios físicos de serie [V].

El URDF expandido tiene 40 links y 39 joints. La variante Vita queda en 11 620 triángulos (chasis 3 000) y la de PC
en 67 246. El chasis adicional se redujo con `trimesh` porque el decimador de Blender 5.2 no alcanzó el objetivo en
esa malla [V]. Blender 5.2 tampoco ofrecía `wm.collada_import`; `tools/convertir-urdf-dae.py` convierte 16 DAE a OBJ
con `trimesh`/`pycollada` antes del diezmado [V].

## 5. Unitree G1: procedencia y alcance

Se reutilizan sin duplicar `robot/`, `anim/` y `marcha.gd` de `godot/g1-unitree/`: URDF oficial
`unitree_rl_gym@276801e`, 29 joints y clips oficiales. Los sensores se reparentan a `d435_link`, `mid360_link`,
`imu_in_pelvis` e `imu_in_torso`, por lo que siguen la cinemática del modelo [V].

Las definiciones `.msg` de `unitree_ros2@668d1ec5a05d1c38d3306bdca7d59f2ba3581a88` se incluyen en `ros/msg/`.
El esquema G1 contiene 87 tipos; los estándar contienen 44. Se implementan `LowCmd`, `LowState`, ambas frecuencias
de `SportModeState`, `LidarState`, `WirelessController` y `/api/sport/request` + `response`. `api_id=7105` mueve el
robot. Otros identificadores se responden sin ejecutar funciones no simuladas; los desconocidos devuelven 3401.

El TF completo de 29 joints corresponde a `robot_state_publisher` en PC. `/armsdk` y las acciones no se emulan;
el URDF usado tiene manos `rubber_hand`, no manos dexterous. La compatibilidad de vídeo se limita a mensajes ROS
estándar; no se afirma interoperabilidad con un stream propietario.

## 6. Dron de mapeo

El dron propio se genera en Blender con `tools/generar-assets-plantillas.py` (552 triángulos). Tiene movimiento
cinemático 6DOF, no aerodinámica ni PX4. `linear.z` controla altitud y `angular.z` yaw. Se priorizaron sensores
compatibles con ROS 2 y fuentes independientes para SLAM/fusión: IMU, GNSS, presión, campo magnético, RGB-D en dos
direcciones, PointCloud2, LaserScan y Range. Los rotores y el flujo óptico son salidas de estado, no un controlador
de vuelo certificado.

## 7. Mundo común y assets

El mismo mundo se instancia en los tres proyectos. Tiene cuatro zonas en 52×52 m:

- **Bosque:** árboles, arbustos, rocas, colina y plantas.
- **Ciudad:** tres edificios, carreteras, paso de peatones, valla, berlina y taxi móvil.
- **Parque:** bancos, sendero, flores, cuatro personas, perro, gato, oveja y pelota.
- **Casa (12×10 m):** paredes con puerta, dos tabiques, mesa, sillas, cama, cocina completa, microondas, libros,
  peluche, planta y alimentos. Hay conos y rampa como obstáculos.

Los modelos públicos son Kenney CC0: Nature Kit, Furniture Kit, City Kit Suburban, Car Kit, Food Kit y Animated
Characters 2. Se conservan licencias en `godot/plantillas/mundo/assets/licenses/`. El Animal Pack descargado era 2D;
por eso perro, gato y oveja se generaron en Blender. La persona FBX se diezmó al 25 %. No se redistribuyen paquetes
enteros, solo los OBJ/MTL/texturas usados. Créditos: `godot/plantillas/mundo/CREDITOS.md` [V].

La escena completa en host tiene 91 902 triángulos con RB-KAIROS+ PC, 85 277 con G1 PC y 25 196 con el dron [V].
Al seleccionar `lod=vita`, los robots pesan 11 620 y 12 633, respectivamente, y el total queda por debajo del
presupuesto GXM de 60 000. Solo se usan mallas de triángulos, materiales albedo y una luz direccional sin sombras.

## 8. Generación y uso (PC, fish)

```fish
# Editor con ros2_vita
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
docker/vita-ros.sh up
$G --path godot/rbkairos-plus
$G --path godot/g1-sensores
$G --path godot/dron-mapeo

# Sin red o con loopback, y LOD de Vita en host
$G --path godot/rbkairos-plus -- sin_ros lod=vita
set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
$GH --headless --path godot/dron-mapeo -- transporte=loopback lod=vita

# Esquemas
toolchains/rosbags-venv/bin/python godot/plantillas/generar_esquemas.py --salida godot/rbkairos-plus/ros/schema.rsch
toolchains/rosbags-venv/bin/python godot/plantillas/generar_esquemas.py --salida godot/g1-sensores/ros/schema.rsch --unitree godot/g1-sensores/ros/msg

# VPK
tools/export-vita-vpk.sh godot/rbkairos-plus build/rbkairos-plus.vpk
tools/export-vita-vpk.sh godot/g1-sensores build/g1-sensores.vpk
tools/export-vita-vpk.sh godot/dron-mapeo build/dron-mapeo.vpk
```

Argumentos tras `--`: `sin_ros`, `demo`, `transporte=loopback|xrce`, `agente=IP`, `puerto=N`, `lod=vita`,
`captura=ruta.png`, `fotograma=N`. En headless no se captura RGB; CameraInfo y profundidad sí se ejercitan.

## 9. Verificación ejecutada

1. Suite `godot/test/run_host_tests.sh`: **294/0** tras modificar XRCE [V].
2. `comun/pruebas/runner.gd`: 5/5 estándar y 7/7 con Unitree; CameraInfo, IMU, LaserScan 60 = 296 B, compactos y
   arrays fijos [V].
3. Tres escenas con todos los publicadores en loopback, sin errores [V].
4. Agente micro-ROS real aislado en UDP 8889, sin modificar la estación previa [V]:
   - RB-KAIROS+: IMU, LaserScan, CameraInfo, nombres UR10e y OccupancyGrid recibidos por `ros2 topic echo`.
   - G1: IMU pelvis, `/g1/estado` (19 valores), PointCloud2, profundidad D435, mapa y `/lowstate` anunciado.
   - Dron: IMU, profundidad frontal, PointCloud2, sonar y mapa recibidos.
   - Ninguno de los tres logs contiene `ERROR` tras la cola y las correcciones QoS [V].
5. Generación RB-KAIROS+: 16 Collada convertidos y dos LOD producidos [V].
6. Plantilla Vita reconstruida: `verify_runtime.py` **PASS: ELF layout, relocations, main and 694 imports** [V].
7. Capturas gráficas revisadas con los tres robots y el cenital; edificios, árboles, muebles, comida y dron a escala [V].
8. Prueba de 120 ticks por robot: RB-KAIROS+ apoya a 0,16 m, G1 a 0,1606 m y el dron conserva 3 m; no hay
   atravesar el suelo ni desplazamientos por colisiones escaladas [V].
9. VPK definitivos sin errores de exportación y con `robot.json`, esquema, mundo, `.scn`/`.remap` y sin mallas PC [V]:
   `rbkairos-plus.vpk` 23 997 414 B (`1c8859f036693c44`), `g1-sensores.vpk` 24 106 371 B (`44e8e70c9a7d3326`),
   `dron-mapeo.vpk` 23 609 334 B (`5b5352dc1891aba6`). Los cuatro atlas están incluidos como `.ctex`.
10. Prueba gráfica ROS 2 del dron: JPEG con firma válida (4 376 B), RGB 320×240 `rgb8`, profundidad 80×60 con
   valores positivos y 381 puntos 3D recibidos por `rclpy`; editor gráfico recompilado y log sin `ERROR` [V].
   Las personas se verificaron también con textura, alfa 1 y transparencia desactivada [V].

Pendiente de hardware: FPS sostenidos, `be_dropped`, latencia y frecuencia agregada BE, memoria, apariencia de
materiales y colisiones en la Vita. La cámara RGB se valida en host gráfico, no en el editor headless.

## 10. Limitaciones explícitas

- Acciones y servicios no existen en `ros2_vita`; se usan topics o un puente PC.
- Cámara, profundidad y nube 3D no se capturan en Vita; el relay es obligatorio.
- `/robot_description` no se transmite por XRCE; usar el URDF en PC.
- TF completo del robot se genera en PC; Godot publica odom→base.
- El mapa no sustituye SLAM; el dron no sustituye un controlador de vuelo.
- Los sensores extra del bridge Robotnik se distinguen del equipamiento físico del Xacro.
- La tasa nominal de cada sensor BE no es una garantía agregada: el transporte comparte un datagrama por frame.
