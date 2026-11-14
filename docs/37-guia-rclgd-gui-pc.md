# 37 · Guía: rclgd real (jazzy) y el visor de topics con interfaz gráfica en el PC

**Fecha:** 2026-11-15 · **Máquina:** PC CachyOS (192.168.1.65, KDE Plasma en Wayland) · **Estado:** guía verificada
sin pantalla (§1.2); lo que solo se ve en pantalla va marcado **[usuario] verificar en pantalla**.

Objetivo: abrir el editor Godot 4.7.1 con **rclgd 3.0.0 compilado desde fuente** (rama `jazzy` @ `d8221d3`), hacer
una prueba de humo con una demo de rclgd y probar **el visor del repo** (`godot/visor-ros`, ADR 0013, doc 36) con
rclgd en vez de con `ros2_vita`. Es la prueba pendiente de doc 36 §13.4 («el visor no se ha ejecutado nunca con
rclgd»). No cambia código del repo: todo va en `tools/rclgd-gui.sh`, `tools/rclgd-gui/` y un **proyecto puente**
fuera del repo. Las decisiones de diseño (un modo «rclgd» permanente en `godot/visor-ros`) quedan para otra sesión
(§7).

Comandos para el PC en **fish** (los scripts con shebang valen en cualquier shell). Todos desde la raíz del repo:

```fish
cd ~/Proyectos/PSVita-ROS
```

---

## 1. Qué hay y qué se ha comprobado

### 1.1 Piezas

| Pieza | Dónde | Notas |
|---|---|---|
| rclgd 3.0.0 + Godot 4.7.1 | `~/Proyectos/rclgd-estudio/ws-jazzy/install/` (`rclgd/lib/rclgd/{godot-bin,librclgd.so}`) | receta: `skills/rclgd/references/versiones.md` §Compilar |
| Imagen `psvita-ros-rclgd:jazzy` | la crea `tools/rclgd-gui.sh imagen` | `psvita-ros-station:jazzy` + `ros-jazzy-ros-babel-fish` (rclgd la necesita en ejecución), `tf2-ros`, `rclcpp-action`, `octomap-msgs`, `grid-map-msgs` (tipos V14 que la estación no trae) |
| `tools/rclgd-gui.sh` | repo (nuevo) | contenedor con tu usuario, `--net=host --ipc=host`, pantalla X11/XWayland y GPU; órdenes en §2 |
| Proyecto puente del visor | `~/Proyectos/rclgd-estudio/visor-rclgd/` (lo genera `tools/rclgd-gui.sh puente`) | **copia** de `godot/visor-ros` + `godot/plantillas` (como `res://comun`), con `package.xml`, `rclgd.gdextension` y un parche (§6, P1) |
| `tools/rclgd-gui/comprobar_visor.gd` | repo (nuevo); el puente lo copia como `res://comprobar_rclgd.gd` | comprobación **sin pantalla**: carga una escena y vuelca cada display (topic, tipo, estado, recibidos) |
| `tools/rclgd-gui/fuente_v14.py` | repo (nuevo) | fuente de los extras solo PC (V14): Octomap, GridMap, marcadores interactivos, profundidad 16UC1 |
| Demos migradas | `~/Proyectos/rclgd-estudio/migrados/{roomba_rclgd,rclgd_sensors}` (`tools/rclgd-gui.sh migrar`) | copias; los clones de `rclgd-estudio` no se tocan |

**Por qué un proyecto puente** y no abrir `godot/visor-ros` tal cual [V, comprobado 2026-11-15]:

1. `godot/visor-ros/project.godot` es de godot4-vita 4.8-dev7: `config/features` «4.8» y el plugin
   `res://addons/psvita/plugin.cfg`, que solo existe en el editor de la Vita.
2. rclgd 3.0.0 carga desde un `.gdextension` del proyecto y registra las **clases tipadas** desde
   `res://package.xml` (`skills/rclgd/references/mensajes-y-tipos.md` §2); `visor-ros` no tiene ninguno de los dos
   (con `ros2_vita` todo es un módulo estático).
3. Con rclgd, `godot/plantillas/ros/contexto_ros.gd:16` **no compila** (§6, P1).
4. El editor 4.7.1 reimporta los `.obj` de `plantillas/mundo` y crea `.uid`: en una copia no ensucia el repo
   (comprobado: `git status` limpio tras abrir el puente).

`puente` vuelve a copiar con `rsync` (úsalo cuando cambie el repo). **Lo que edites en el puente no vuelve al repo**
(`LEEME-PUENTE.txt` lo recuerda). `comun/pruebas/` no se copia: esas pruebas usan API solo de `ros2_vita` (§6, P3).

### 1.2 Verificado sin pantalla (2026-11-15, por Claude)

| Comprobación | Resultado |
|---|---|
| `tools/rclgd-gui.sh doctor` | sesión `wayland`, `WAYLAND_DISPLAY=wayland-1`, `DISPLAY=:0` (XWayland), `xauth` en `/run/user/1000/xauth_*`, `/dev/dri`, runtime NVIDIA, Godot 4.7.1, `librclgd.so`, imagen y puente: todo ✓ |
| Imagen | `ros2 pkg list` dentro: `ros_babel_fish`, `octomap_msgs`, `grid_map_msgs`, `rclgd`, `rclgd_cli`, `colcon_rclgd` |
| Import del puente (`godot --headless --editor --import`) | 63 recursos, **0 errores** |
| Clases tipadas desde el `package.xml` del puente | `RosSensorMsgsLaserScan`, `RosNavMsgsOccupancyGrid`, `RosVisualizationMsgsMarkerArray`, `…InteractiveMarkerUpdate`, `RosOctomapMsgsOctomap`, `RosGridMapMsgsGridMap`, `RosVisionMsgsDetection2dArray` (ojo: `2d` en minúscula), `RosDiagnosticMsgsDiagnosticArray` |
| `comprobar` de `main.tscn` con `fuente-visor` + `fuente-v2 avisos,marcadores,tf` | `ros_listo=true`, `tf=RosTfListener`, **15 displays con datos** (Robot, Mapa, Mapa3D, Plan, Scan, Odom, Batería, Temperatura, Presión, Diagnóstico, Consola, Trazador, Inspector, Marcadores, Marcadores2D), sin `SCRIPT ERROR` |
| `comprobar` de `main_pc.tscn` + `fuente-v14` + `fuente-v2 …,percepcion` | 26 displays, 20 con datos: además **NubePuntos** (`/points` 10 Hz), **ImagenPC** 16UC1, **Octomap** (858 vóxeles), **GridMap**, y **marcadores interactivos por el servicio**: `con_servicio=true estados_pedidos=1 marcadores=["caja"] seq=1` |
| `comprobar` de `main_percepcion.tscn` | 19 con datos: Nube, Imagen (JPEG), Cajas2D, Cajas3D, … |
| `comprobar` de `main_viz.tscn` | `ros_listo=true`, 15 con datos |
| `comprobar` de `banco_v5.tscn` + `ros2 topic pub` de 4 tipos | Punto, Imu, Marcador y Covarianza reciben a 5 Hz |
| Explorador de topics (V12, rama del PC con grafo) | `tiene_grafo=true desde_grafo=true topics=34` (el `get_topic_names_and_types()` de rclgd, nunca probado antes) |
| **Ventana real** (`main_pc.tscn`, 8 s, `--write-movie`) | `OpenGL API 3.3.0 NVIDIA 620.70.06 - Compatibility - NVIDIA GeForce RTX 5060 Ti`; el fotograma 239 muestra mapa, scan, plan, marcadores, esfera del Octomap, malla del GridMap y HUD (batería, meta, temperatura, presión) |
| **Editor** con ventana (`--editor`, 400 fotogramas) | abre el puente sin errores de script (solo el aviso de audio, §5.2) |
| Demo `roomba_rclgd` migrada, `--headless` | `ros2 topic list` desde otro contenedor: `/odom`, `/lidar/scan`, `/imu/data`, `/camera/image_raw`, `/tf`, `/house/markers`…; `ros2 topic hz /odom` = 60 Hz; `ros2 rclgd doctor`: «all checks passed» |
| Demo `rclgd_sensors` migrada | importa sin errores; sin pantalla el LIDAR por GPU falla (`RenderingDevice` nulo, esperado en `--headless`) → **[usuario] verificar en pantalla** |

---

## 2. Paso 1 — Contenedor jazzy con rclgd y la pantalla del PC

### 2.1 Una vez

```fish
docker/vita-ros.sh build            # solo si no existe psvita-ros-station:jazzy (docker images | grep station)
tools/rclgd-gui.sh imagen           # psvita-ros-rclgd:jazzy (1-2 min)
tools/rclgd-gui.sh doctor           # todo en [✓] salvo, la primera vez, «sin puente»
tools/rclgd-gui.sh puente           # ~/Proyectos/rclgd-estudio/visor-rclgd
```

`doctor` debe mostrar `DISPLAY=:0 (X11/XWayland)`, la `Xauthority`, `/dev/dri`, `runtime NVIDIA`, `Godot 4.7.1` y la
imagen. Si `RCLGD_WS` no es `~/Proyectos/rclgd-estudio/ws-jazzy`: `set -x RCLGD_WS /otra/ruta` antes (fish).

### 2.2 Cómo lanza el script el contenedor

`docker run --rm --net=host --ipc=host --user (id -u):(id -g)` con:

- **Pantalla:** `-e DISPLAY -v /tmp/.X11-unix` y la `Xauthority` de KDE (`/run/user/1000/xauth_*`) montada en
  `/tmp/.Xauthority`; además `xhost +local:` (lo mismo que `gui()` de `docker/vita-ros.sh`). Godot 4.7 usa X11 por
  defecto: en Plasma Wayland va por **XWayland** (`DISPLAY=:0`). No hace falta reenviar el socket Wayland.
- **GPU:** `--device /dev/dri` + grupos `video` y `render`, y `--runtime nvidia` con
  `NVIDIA_DRIVER_CAPABILITIES=all` (el runtime está en el PC: `docker info | grep Runtimes`).
- **ROS:** misma red e IPC que la estación, `ROS_DOMAIN_ID` (0 por defecto) y `ROS_AUTOMATIC_DISCOVERY_RANGE=SUBNET`
  como `docker/docker-compose.yml`. **Fast DDS solo por UDP** (`FASTDDS_BUILTIN_TRANSPORTS=UDPv4`): ver §5.3.
- **Tu usuario** y `HOME=~/Proyectos/rclgd-estudio/.home-godot` (ajustes del editor, `~/.ros/log`): los archivos que
  cree Godot son tuyos, no de root. Se monta `~/Proyectos` en la misma ruta (el puente, las demos y el repo).

### 2.3 Abrir el editor

```fish
tools/rclgd-gui.sh editor                                          # el puente del visor
tools/rclgd-gui.sh editor ~/Proyectos/rclgd-estudio/migrados/roomba_rclgd
```

**[usuario] verificar en pantalla:** se abre la ventana del editor «Godot Engine v4.7.1.stable», el panel de salida
no tiene errores rojos de script y en la terminal sale `OpenGL API 3.3.0 NVIDIA … RTX 5060 Ti` (el visor usa
Compatibility). Cerrar la ventana termina el contenedor.

Otras órdenes útiles: `tools/rclgd-gui.sh shell` (bash con ROS y rclgd cargados; ahí funcionan `ros2 rclgd doctor`,
`ros2 rclgd editor`, …) y `tools/rclgd-gui.sh ros2 topic list` (un `ros2` suelto en la misma imagen y red).

---

## 3. Paso 2 — Prueba de humo con una demo de rclgd

Las demos de `rclgd-estudio` usan todavía el **plugin de clases sombra** (`addons/rclgd/{plugin.cfg,rclgd.gd,gen/}`),
que rclgd 3.0.0 ya no tiene (`rclgd.gd` llama a `RosMsg.gen_editor_support`, eliminado, y los `class_name` de `gen/`
chocan con las clases nativas). `migrar` hace una copia y aplica los pasos de migración de
`skills/rclgd/references/mensajes-y-tipos.md` §2 (y, si el `package.xml` no declara paquetes de mensajes, añade
`std/geometry/sensor/nav_msgs`: a `rclgd_sensors` @ `420d4d4` le falta `sensor_msgs` y sus scripts no compilan).

```fish
tools/rclgd-gui.sh migrar ~/Proyectos/rclgd-estudio/roomba_ws/src/roomba_rclgd
tools/rclgd-gui.sh migrar ~/Proyectos/rclgd-estudio/rclgd_sensors
```

### 3.1 Roomba (recomendada: la más completa)

Terminal 1:

```fish
tools/rclgd-gui.sh jugar ~/Proyectos/rclgd-estudio/migrados/roomba_rclgd
```

Terminal 2 (cualquiera de las dos vías ve el mismo grafo):

```fish
tools/rclgd-gui.sh ros2 topic list                  # o: docker/vita-ros.sh topics
tools/rclgd-gui.sh ros2 topic hz /odom              # ≈ 60 Hz
tools/rclgd-gui.sh ros2 topic echo /lidar/scan --once --field ranges
docker/vita-ros.sh teleop                           # mueve el Roomba con el teclado (/cmd_vel)
docker/vita-ros.sh rviz                             # opcional: Fixed Frame «map», añadir LaserScan /lidar/scan y TF
```

Verde: `ros2 topic list` muestra `/odom`, `/lidar/scan`, `/imu/data`, `/camera/image_raw`, `/tf`, `/house/markers`,
`/roomba/marker` y `/bumper` [V, sin pantalla]; **[usuario] verificar en pantalla:** la casa y el Roomba se ven en la
ventana y el robot se mueve con `teleop`.

### 3.2 rclgd_sensors (LIDAR por GPU, cámara, IMU, GPS)

```fish
tools/rclgd-gui.sh jugar ~/Proyectos/rclgd-estudio/migrados/rclgd_sensors
tools/rclgd-gui.sh ros2 topic list -t               # en otra terminal
```

**[usuario] verificar en pantalla:** la escena `sensors.tscn` se abre (Forward+: usa Vulkan) y aparecen los topics
de los sensores. Sin pantalla no se puede comprobar: el LIDAR usa un *compute shader* y en `--headless` no hay
`RenderingDevice` [V]. Si con ventana tampoco publica, revisar Vulkan (§5.2).

---

## 4. Paso 3 — El visor con rclgd

### 4.1 Fuentes de datos (estación)

Cada fuente en su terminal (Ctrl+C para pararla). La estación tiene que estar arriba (`docker/vita-ros.sh up`).

| Terminal | Orden | Publica |
|---|---|---|
| T1 | `docker/vita-ros.sh fuente-visor` | `/map` (latched), `/scan`, `/odom`, `/joint_states`, `/plan`, `/battery_state`, `/barometer`, `/temperature` |
| T2 | `docker/vita-ros.sh fuente-v2 avisos,marcadores,tf` | `/rosout`, `/diagnostics`, `/visualization_marker_array` (31 sólidos + línea + texto), **`/tf` y `/tf_static`** |
| T3 | `docker/vita-ros.sh fuente-v2 percepcion` (o añadir `,percepcion` a T2) | `/camera/color/image_raw/compressed`, `/detections`, `/detections_3d`, `/points` |
| T4 | `tools/rclgd-gui.sh fuente-v14` | `/octomap_binary`, `/elevation_map`, `/basic_controls/*` (marcador interactivo «caja»), `/camera/depth/image_raw` |
| T5 | `docker/vita-ros.sh fuente-costmap` | `/global_costmap/costmap` + parches (V11) |

**Importante (TF):** con rclgd el visor usa el `RosTfListener` real (`visor_ros.gd:216-220`). `fuente-visor` sola
no publica `/tf`: los displays en `odom`/`base_scan`/`base_link` quedan en «sin TF odom→map» y no se dibujan
[V]. Lanza siempre **T2 con `tf`** (map → odom → base_link → base_scan…). Con `ros2_vita` + TfLigero esto no se
notaba.

Sin relay: el relay (`docker/vita-ros.sh relay`) es para la Vita; con rclgd el visor se suscribe a los topics
directos (`compacto=false`).

### 4.2 Lanzar las escenas

```fish
tools/rclgd-gui.sh puente                                          # tras cada cambio del repo
tools/rclgd-gui.sh jugar ~/Proyectos/rclgd-estudio/visor-rclgd res://main_pc.tscn
```

o desde el editor (`tools/rclgd-gui.sh editor`): abrir la escena y **F6** (escena actual). Escenas:

| Escena | Qué es | Fuentes |
|---|---|---|
| `res://main.tscn` | visor de ejemplo, perfil HMI | T1 + T2 |
| `res://main_pc.tscn` | `main.tscn` + extras solo PC (V14): nube en GPU, marcadores interactivos, Octomap, GridMap, profundidad | T1 + T2 + T3 + T4 |
| `res://main_viz.tscn` | `main.tscn` con perfil VIZ | T1 + T2 (+ T5) |
| `res://main_percepcion.tscn` | `main.tscn` + pestaña Cámara, nube 2D y cajas 3D (V10) | T1 + T2 + T3 |
| `res://banco_v5.tscn` | displays directos de V5 | `ros2 topic pub` (§4.4) |

Comprobación sin pantalla de cualquiera (útil antes de mirar, o si algo no se ve):

```fish
tools/rclgd-gui.sh comprobar res://main_pc.tscn 8
```

Verde: `[visor] ros_listo=true … tf=RosTfListener`, ningún `SCRIPT ERROR` y `recibidos > 0` en los displays cuyos
topics publican las fuentes lanzadas; para los marcadores interactivos, la línea `[im] con_servicio=true …
marcadores=["caja"]`; para el explorador, `[explorador] tiene_grafo=true`.

Controles en el PC (README de `godot/plantillas/visor/`, V7): **Tab** recorre herramientas (ninguna → Teleop → Meta →
Pose inicial → Punto → Interactuar en `main_pc`); **Re Pág / Av Pág** cambian de pestaña del HUD; **F9** cambia de
escena (selector de la Vita, guarda la elección en `user://`); **B** activa el banco de 80 primitivas; Teleop:
**Mayús mantenida + flechas**; Meta / Pose inicial: pulsar, arrastrar el rumbo y soltar (Esc descarta).

### 4.3 Qué debe verse (criterio de verde por display)

Todo **[usuario] verificar en pantalla**; entre corchetes, lo ya comprobado sin pantalla.

**`main.tscn` (T1 + T2):**

| Display | Verde |
|---|---|
| Mapa / Mapa3D | rectángulo 5 × 4 m con borde negro (ocupado) en gris (libre), en planta 2D y en 3D [recibido, 1 msg latched] |
| Scan | puntos que ondulan alrededor del robot, sobre el robot y no desplazados [20 Hz; dibujo 10 Hz con el aviso D8 «fijar el ritmo en origen», esperado] |
| Odom / Robot | flecha que da vueltas en un círculo de 1 m; las dos ruedas giran (JointState) |
| Plan | línea de 100 poses |
| TF | ejes de los 8 marcos (odom, rueda_izq … camara) moviéndose con el robot |
| Marcadores / Marcadores2D | 31 sólidos + línea + texto que se animan a 10 Hz, sin «fantasmas» al borrar |
| HUD | barra superior: batería que baja, «Meta: sin meta»; pestañas: Temperatura 10–50 °C (oscila) y Presión ≈ 1010–1016 hPa con sus barras, Consola (20 avisos/s de `/rosout`), Diagnóstico (cambia de color cada 5 s), Gráficas (Trazador, `/odom`), Inspector (campos de `/odom` actualizándose) |
| Herramientas | Teleop publica `/cmd_vel` (`tools/rclgd-gui.sh ros2 topic echo /cmd_vel`); Meta → `/goal_pose`; Pose inicial → `/initialpose` (covarianza como RViz); Punto → `/clicked_point` |

**Teleop de verdad:** para T1 usa la tortuga en vez de `fuente-visor` (las dos publican `/odom`):
`docker/vita-ros.sh sim` → Tab hasta Teleop, Mayús + flechas: la tortuga de turtlesim se mueve y la flecha de Odom
la sigue.

**`main_pc.tscn` (lo nunca probado con rclgd, doc 36 §13.4):**

| Display | Verde |
|---|---|
| **Marcadores interactivos** (`/basic_controls`) | caja azul en (1, −1, 0,5) con flechas (mover) y anillos (girar) en x, y, z [estado inicial por el servicio `get_interactive_markers`: comprobado]. Tab hasta **Interactuar**, agarrar un asa y arrastrar: la caja se mueve y T4 imprime `[feedback] tipo=… control=move_x pos=(…)` (MOUSE_DOWN, POSE_UPDATE ≤ 20 Hz, MOUSE_UP) |
| **Octomap** (`/octomap_binary`) | esfera hueca de vóxeles de 10 cm, radio 0,8 m, en (−1,5, 1,5, 1), coloreada por altura (arcoíris) [858 vóxeles decodificados; visto en la captura] |
| **GridMap** (`/elevation_map`) | malla 4 × 4 m en (2,5, −2,5) con una onda que avanza cada segundo, color turbo por altura [visto en la captura] |
| **NubePuntos** (`/points`, T3) | nube 3D en GPU coloreada por campo |
| **ImagenPC** (pestaña Profundidad, `/camera/depth/image_raw`) | degradado horizontal que se desplaza, mapa turbo (16UC1 en mm) [recibido a 5 Hz] |
| Explorador de topics | sin UI propia: `comprobar` lista los topics del grafo (`[explorador] … topics=N`) [comprobado: 34] |

**`main_percepcion.tscn` (T3):** pestaña Cámara con la imagen JPEG sintética y las cajas 2D encima; nube 2D en la
planta y cajas 3D [los cuatro reciben].

**`main_viz.tscn`:** lo de `main.tscn` con el perfil VIZ (más cupo de marcadores, poses, costmap con T5).

### 4.4 `banco_v5.tscn` (displays directos)

En fish, la función de `docs/ia/workshops/posts/V3-revision.md:174`:

```fish
function pub; docker exec -d vita_station bash -lc "source /opt/ros/jazzy/setup.bash; ros2 topic pub -r 5 $argv"; end
pub /clicked_point geometry_msgs/msg/PointStamped "'{header: {frame_id: map}, point: {x: 1.0, y: 0.5, z: 0.2}}'"
pub /imu sensor_msgs/msg/Imu "'{header: {frame_id: map}, orientation: {w: 1.0}, linear_acceleration: {z: 9.81}, angular_velocity: {z: 0.5}}'"
pub /marcador visualization_msgs/msg/Marker "'{header: {frame_id: map}, ns: v5, id: 1, type: 1, pose: {position: {x: -1.0, y: 1.0, z: 0.25}, orientation: {w: 1.0}}, scale: {x: 0.5, y: 0.5, z: 0.5}, color: {r: 1.0, g: 0.5, a: 1.0}}'"
pub /amcl_pose geometry_msgs/msg/PoseWithCovarianceStamped "'{header: {frame_id: map}, pose: {pose: {position: {x: 2.0}, orientation: {w: 1.0}}, covariance: [0.25,0,0,0,0,0, 0,0.1,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0, 0,0,0,0,0,0.07]}}'"
tools/rclgd-gui.sh jugar ~/Proyectos/rclgd-estudio/visor-rclgd res://banco_v5.tscn
# … los otros 6 tipos (/vector, /orientacion, /ft_sensor, /sonar, /footprint, /fix): V3-revision.md:176-185
docker exec vita_station pkill -f "ros2 topic pub"           # al acabar
```

Verde: cada tipo publicado se ve en su sitio (punto, flecha de la IMU, cubo naranja, elipse de covarianza…) [los
cuatro de arriba reciben a 5 Hz].

### 4.5 TfLigero frente a RosTfListener [?]

Con rclgd el visor **siempre** usa `RosTfListener` (sin `get_transport_info`, `visor_ros.gd:216-220`); TfLigero solo
corre con `ros2_vita`. Comparación propuesta (opcional; criterio de V9: mismo resultado ± 1 mm): misma fuente
(T1 + T2) y, a la vez, la ventana rclgd y el editor de host de `ros2_vita` por XRCE contra el agente:

```fish
set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
docker/vita-ros.sh relay hmi,tf /vita "" odom,rueda_izq,rueda_der,torre,brazo,pinza,antena,camara
$GH --path godot/visor-ros -- transporte=xrce compacto=1
```

**[usuario] verificar en pantalla:** los ejes de los 8 marcos coinciden en las dos ventanas (y con
`docker/vita-ros.sh rviz`, Fixed Frame «map»). Sin cambiar código no hay un modo de comparar los dos TF en la misma
ventana (§7).

### 4.6 El visor con el Roomba (opcional)

Con `jugar …/migrados/roomba_rclgd` en marcha (sin T1), `main.tscn` recibe `/odom` y `/tf` del Roomba; el Scan del
visor escucha `/scan` y el Roomba publica `/lidar/scan` (no se ve sin cambiar el `topic` del display en el
inspector del puente). El explorador lista los topics del Roomba (`comprobar`).

---

## 5. Problemas frecuentes

### 5.1 La ventana no aparece

- `Authorization required` / `cannot open display`: `tools/rclgd-gui.sh doctor`; desde una terminal del escritorio
  (no SSH), `echo $DISPLAY` = `:0`. Si la `xauth` cambió tras reiniciar sesión no hay que hacer nada: el script la
  busca en cada arranque (`/run/user/1000/xauth_*`); como último recurso `xhost +local:`.
- No se reenvía Wayland nativo: Godot 4.7 en Linux arranca con X11 (`--display-driver x11` por defecto) y en Plasma
  Wayland lo sirve XWayland. Para probar Wayland habría que montar `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` y pasar
  `--display-driver wayland` [?, no probado].

### 5.2 GPU y audio

- La terminal debe decir `OpenGL API 3.3.0 NVIDIA … RTX 5060 Ti` (Compatibility) [V]. Si sale `llvmpipe`, el runtime
  NVIDIA no se aplicó: `docker info | grep Runtimes`. Forward+ (rclgd_sensors) usa **Vulkan** del driver NVIDIA vía
  `NVIDIA_DRIVER_CAPABILITIES=all` **[usuario] verificar en pantalla**; si falla, probar
  `tools/rclgd-gui.sh godot --path <proyecto> --rendering-driver opengl3` (el LIDAR por GPU no irá; lo que va
  tras `--` en `jugar` son argumentos del juego, no del motor).
- `ALSA lib … Unknown PCM default` y `All audio drivers failed, falling back to the dummy driver`: esperado (el
  contenedor no tiene audio); no afecta.

### 5.3 Los topics se ven pero no llegan datos

- **Memoria compartida de Fast DDS:** la estación corre como root y Godot como tu usuario; con SHM el descubrimiento
  funciona pero **no llega ningún mensaje** [V: `RCLGD_SHM=1 … comprobar` → 0 recibidos; sin él, todo llega]. Por
  eso el script pone `FASTDDS_BUILTIN_TRANSPORTS=UDPv4`. Si lanzas Godot de otra forma, exporta esa variable.
- **Dominio:** `ROS_DOMAIN_ID` igual en todos (0 por defecto en la estación y en el script); `echo $ROS_DOMAIN_ID`
  vacío = 0.
- **QoS:** `/map` y `/octomap_binary` son FIABLE + TRANSIENT_LOCAL (llegan aunque la fuente arrancara antes); los
  displays de sensores piden BEST_EFFORT (aceptan publicadores fiables). Un publicador BEST_EFFORT con un display
  FIABLE no casa: `tools/rclgd-gui.sh ros2 topic info -v <topic>` enseña las dos QoS.
- Varias fuentes del mismo topic (p. ej. `fuente-visor` y `sim` publican `/odom`) se mezclan; para y vuelve a lanzar.
  Los `docker/vita-ros.sh fuente-*` siguen vivos en la estación si se corta la terminal de golpe:
  `docker exec vita_station pkill -f fuente_prueba`.

### 5.4 Clases tipadas y `package.xml`

- `Could not find type "RosSensorMsgsImage"`: el paquete no está en el `package.xml` del proyecto (le pasa a
  `rclgd_sensors`; `migrar` lo arregla en la copia). Tras cambiar `package.xml`: **Proyecto → Recargar proyecto
  actual** (las clases se fijan al cargar la extensión).
- Nombres: `Detection2DArray` → `RosVisionMsgsDetection2dArray` (`2d` en minúscula) [V].
- `Static function "gen_editor_support()" not found` o choques de `class_name` en `addons/rclgd/gen/`: proyecto con
  el plugin viejo → `tools/rclgd-gui.sh migrar`. `ros2 rclgd doctor` (en `tools/rclgd-gui.sh shell`, dentro del
  proyecto) lo confirma.
- Un mensaje de un paquete que no está en la imagen (`package '…' not found`): añadir el `ros-jazzy-…` a
  `construir_imagen()` de `tools/rclgd-gui.sh` y `tools/rclgd-gui.sh imagen`.

---

## 6. Hallazgos de esta prueba (para las próximas sesiones)

| # | Hallazgo | Dónde | Estado |
|---|---|---|---|
| **P1** | `rclgd.init()` devuelve `void` en rclgd y `Error` en `ros2_vita`: `var err := rclgd.init(args)` **no compila con rclgd** («Cannot get return value of call to "init()" because it returns "void"»). Rompe todo el visor y cualquier app de plantillas en el PC con rclgd. `API_PARITY.md:17` lo da por ✅ | `godot/plantillas/ros/contexto_ros.gd:16`; también `g1-unitree/main.gd:281`, `g4-smoke`, `g5-xrce`, `g6-hmi`, `g7-imu`, `g7b-imu3d` | **parcheado solo en el puente** (`parchear_puente()` de `tools/rclgd-gui.sh`: `rclgd.call("init", args)` + `rclgd.ok()`). Arreglo en el repo pendiente; el parche deja de aplicarse solo cuando cambie esa línea |
| P2 | Con rclgd el visor usa `RosTfListener`: sin `/tf` (solo `fuente-visor`) los displays en `odom`/`base_scan` quedan «sin TF» | `visor_ros.gd:216-220` | documentado (§4.1); con `ros2_vita` + TfLigero no pasaba |
| P3 | `godot/plantillas/pruebas/visor*.gd` usan API solo de `ros2_vita` (`RosMsg.load_schema_file`, `has_schema`, `list_types`, `rclgd.get_transport_info`, transporte `loopback`): no compilan con rclgd. `visor.gd` sí corre: **56/57** (falla «el último gana: llegan los 3», que depende del *loopback*) | `godot/plantillas/pruebas/` | el puente no copia `pruebas/`; doc 36 §13.4 pedía correrlas con rclgd: haría falta una variante |
| P4 | Fast DDS SHM entre la estación (root) y Godot (usuario) no entrega datos | §5.3 | resuelto en el script (UDPv4) |
| P5 | Demos de `rclgd-estudio` con el plugin de clases sombra; `rclgd_sensors` sin `sensor_msgs` en `package.xml` | §3 | `migrar` (copias) |

Lo de doc 36 §13.4 que queda **comprobado sin pantalla** con rclgd: clases tipadas aceptadas por los displays
(reciben sin errores), descubrimiento del explorador por el grafo, servicio `get_interactive_markers`
(`create_client`/`async_send_request`), `InteractiveMarkerUpdate`/`Octomap`/`GridMap` resueltos por ament, `RosQoS`
real (FIABLE/latched de `/map` y `/octomap_binary`). Queda **sin probar**: el arrastre de marcadores interactivos y
lo visual de cada display ([usuario], §4.3), TfLigero frente a RosTfListener (§4.5), `get_member("reference")` en
una clase tipada y si `int8[]` llega como `PackedByteArray` o `Array` (el Octomap se decodificó, así que uno de los
dos caminos funciona; no se registró cuál).

## 7. Decisiones aplazadas

- **Modo «rclgd» permanente en `godot/visor-ros`** (en vez del puente): `package.xml` y `rclgd.gdextension` en el
  proyecto, `config/features` y plugin `psvita` según plataforma, exclusiones en el preset de la Vita.
- **Arreglo de P1 en el repo** (`contexto_ros.gd` y las apps G*): cambia código de plantillas compartido por todas las
  apps de la Vita → con las pruebas de host y en hardware.
- Variante de las pruebas `pruebas/visor*.gd` que corra con rclgd (P3).
- Selector en el visor para forzar TfLigero en el PC (comparación de §4.5 en una sola ventana).
