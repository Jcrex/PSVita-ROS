# R2 — Revisión de sensores, robots y convenciones ROS 2 (commit 909e6ab)

> Revisión de solo lectura del GDScript de `godot/plantillas/{ros,sensores,robots}/*.gd` y
> `godot/plantillas/aplicacion_robot.gd`, escrito por Kimi K3.1 Pro, contrastado con lo que afirman
> `docs/29-plantillas-robots-sensores.md`, `docs/30-rendimiento-xrce-plantillas.md` y `godot/plantillas/README.md`.
> Fecha: 2026-11-12. Revisor: Claude (Opus 5.5). No se ha modificado código.
> Marcas: **[V]** verificado (ejecución o derivación cerrada), **[I]** inferencia, **[?]** sin confirmar.

## 0. Cómo se verificó

- Suite del repo: `godot.linuxbsd.editor.x86_64 --headless --path godot/g1-sensores --script res://comun/pruebas/runner.gd`
  → `RESULTADO: 7/7` [V].
- Sondas propias (en el scratchpad, fuera del repo) ejecutadas en headless con `-- transporte=loopback`:
  posiciones de sensores, teleop, conteos por sensor en 10 s, imagen de profundidad, yaw del dron, orden de motores G1.
- Prueba DDS real: agente `microros/micro-ros-agent:jazzy` aislado (UDP 8889, `--ipc=host`) + `ros/domain_id=77` para
  no tocar la estación del usuario; suscriptor `rclpy` y `tf2_echo` en `psvita-ros-station:jazzy` [V].
  Nota: sin `--ipc=host` en ambos contenedores no llega ningún dato (FastDDS anuncia SHM); la receta del doc 30 sí lo pone.

## 1. Resumen

| Sev. | Nº | Hallazgo | Estado |
|---|---|---|---|
| CRÍTICO | C1 | `sensor_base.gd` publica al **doble** de la frecuencia nominal en 10/5/2 Hz (y 60 en vez de 50) — causa de la discrepancia abierta del doc 30 | [V] |
| CRÍTICO | C2 | `/tf` se publica **best effort**: tf2 (fiable) lo rechaza por QoS incompatible; ningún consumidor TF recibe `odom→base` | [V] |
| CRÍTICO | C3 | Teleop local: al soltar el mando el robot **sigue a la última velocidad para siempre** (hombre muerto desactivado) | [V] |
| ALTO | A1 | LaserScan sellado en la publicación pero medido un periodo antes (≈0,48 s de retraso a 2 Hz XRCE) | [V] |
| ALTO | A2 | Profundidad 32FC1 **invertida verticalmente** respecto a RGB/CameraInfo | [V] |
| ALTO | A3 | G1: `mid360_scan` e `imu_mid360` no se montan en `mid360_link`; el scan se lanza a ras de suelo (z≈0,16 m) y el mapa del G1 sale de ahí | [V] |
| ALTO | A4 | `frame_id` que no existen en ningún árbol TF (G1: `d435_color`, `d435_color_optical_frame`, `utlidar_lidar`; dron: no hay URDF ni TF estático de ningún sensor) | [V] |
| ALTO | A5 | G1: `odom→pelvis` publica la pelvis a z≈0,16 m (pies) cuando está a ≈0,8 m | [V] |
| ALTO | A6 | Dron: `angular.z` de `/cmd_vel` se ignora con teleop local (defecto) y, sin él, el yaw **sigue girando** tras el timeout y tras la parada de emergencia | [V] |
| ALTO | A7 | `mapeo_2d.gd`: espejo con láseres montados boca abajo (RB-KAIROS+), mapa que no cubre el spawn (y=−17 m) y `frame_id="map"` sin `map→odom` | [V] |
| MEDIO | M1–M9 | dt de la IMU, magnetómetro vs GNSS (ENU), barómetro sin altitud de origen, lateral del dron invertido, LowCmd pisado por la marcha, re-integración del mismo scan, sellos sin sincronizar en Vita, rangos fuera de límite, ida y vuelta del scan en Vita | ver §4 |
| BAJO | B1–B14 | detalles REP/cosmética | ver §5 |

Lo que está **bien** (verificado) se lista en §6 para no repetir la revisión.

## 2. Críticos

### C1 — Frecuencias al doble por `fmod` + tolerancia (`godot/plantillas/ros/sensor_base.gd:53-57`) [V]

```gdscript
_acumulado += dt
var periodo := 1.0 / hz
if _acumulado + 0.00001 < periodo:
    return
_acumulado = fmod(_acumulado, periodo)
```

Cuando el acumulado queda **justo por debajo** del periodo (error de coma flotante al sumar k·(1/60)), la tolerancia deja
publicar, pero `fmod(x, periodo)` con `x < periodo` devuelve `x` entero: el acumulador conserva casi un periodo y en el
tick siguiente se publica otra vez. Simulación con dt = 1/60 durante 10 s (600 ticks):

| hz nominal | esperado | real | huecos entre publicaciones (ticks) |
|---:|---:|---:|---|
| 50 | 500 | **599** | 1 |
| 30 | 300 | 300 | 2 |
| 25 | 250 | **299** | 1,2,3 |
| 20 | 200 | 200 | 3 |
| 15 | 150 | 150 | 4 |
| 10 | 100 | **199** | 1,5 |
| 5 | 50 | **99** | 1,11 |
| 2 | 20 | **39** | 1,29 |

Confirmado en Godot (loopback, G1, 10 s): `imu_* hz=50 → 600`, `mid360_scan hz=10 → 200`, `d435/mid360 hz=5 → 100`,
`unitree_estado hz=25 → 300` [V]. Confirmado por DDS (dron, perfil XRCE, 10 s): IMU 10 Hz → **200**, magnetómetro 5 Hz → **100**,
LaserScan 2 Hz → **40**, GNSS 2 Hz → **40** [V].

Consecuencias: explica la "discrepancia temporal no aislada" del doc 30 §6 y probablemente buena parte de los
`be_dropped` de G1 y dron (el perfil XRCE real duplica el presupuesto BE); falsea `scan_time`/`time_increment` y la `dt`
de la IMU (M1). La tabla del doc 29 §3 (50 Hz IMU, etc.) no es lo que sale.

Arreglo (comprobado en la misma simulación: 500/300/250/200/150/100/50/20/10 exactos):

```gdscript
if _acumulado + 0.00001 < periodo:
    return
_acumulado -= periodo
if _acumulado > periodo:   # tras un hipo, no ráfagas
    _acumulado = 0.0
```

Mejor aún (doc 30 §8.2): planificador con reloj absoluto (`Time.get_ticks_usec()`) y siguiente instante objetivo.
`mapeo_2d.gd:66-70` usa otro esquema (`_acumulado = 0.0`) que pierde el resto y deriva hacia abajo; unificarlo.

### C2 — `/tf` best effort: tf2 no lo recibe (`godot/plantillas/sensores/odometria.gd:39`) [V]

`contexto.publicador("/tf", "tf2_msgs/msg/TFMessage", true)` crea el publicador **BEST_EFFORT**. `tf2_ros::TransformListener`
se suscribe a `/tf` con `DynamicListenerQoS` (fiable, profundidad 100), y un suscriptor RELIABLE es incompatible con un
publicador BEST_EFFORT (tabla de compatibilidad QoS de ROS 2). Prueba real:

```
[transform_listener_impl]: New publisher discovered on topic '/tf', offering incompatible QoS.
No messages will be sent to it. Last incompatible policy: RELIABILITY_QOS_POLICY
[tf2_echo]: Waiting for transform odom -> drone_base_link: Invalid frame ID "odom" ... frame does not exist
```

RViz, Nav2, `slam_toolbox` y `robot_localization` no ven nunca `odom→base`. El doc 29 §3 y §10 ("Godot publica odom→base",
"se alimenta slam_toolbox con /scan, /odom y /tf") y los `topics.json` ("best effort, odom->base") afirman algo que no
funciona; la verificación del doc 29 §9 nunca probó un listener TF.

Arreglo: `/tf` fiable (`best_effort=false`, profundidad ≥ 10) en PC. En Vita, el mensaje TF (~100 B) cabe en el stream
fiable; si se quiere BE por rendimiento, hay que republicarlo fiable en el PC (`vita_relay.py`). Añadir un test con
`ros2 run tf2_ros tf2_echo` al gate.

### C3 — Teleop local sin hombre muerto (`godot/plantillas/robots/robot_ros.gd:85-89`) [V]

```gdscript
if aceptar_teleop_local and not emergencia:
    var local := leer_teleop()
    if local != Vector3.ZERO:
        orden_objetivo = local
        _desde_cmd = -1.0
```

`_desde_cmd = -1` desactiva el timeout; cuando se suelta el stick/tecla, `leer_teleop()` devuelve cero, la rama no se
ejecuta y `orden_objetivo` **conserva el último valor indefinidamente**. Sonda G1: pulsar W 1 s, soltar y esperar 2 s →
`orden_obj=(1.0, 0, 0) actual=(1.0, 0, 0) key=false` [V]. Afecta a los tres robots (y al stick de la Vita: al soltar
despacio, el último valor por encima de la zona muerta 0,2 queda fijado). Contradice "timeout de 0,5 s" (doc 29 §2).

Arreglo: recordar si el último origen fue local y, si `local == ZERO` y lo era, poner `orden_objetivo = ZERO`; o bien
tratar el teleop local igual que un `/cmd_vel` (`_desde_cmd = 0.0`) para que caiga en el mismo hombre muerto.

## 3. Altos

### A1 — LaserScan con datos de hace un periodo (`godot/plantillas/sensores/lidar_2d.gd:59-104`) [V]

Orden en `sensor_base._physics_process`: primero `_actualizar_sensor` y luego, si toca, `_publicar`. En el tick de
publicación `_scan_listo` sigue a `true` (scan viejo) y se publica; en el tick siguiente se lanza el scan nuevo entero
(PC: 4 096 rayos/fotograma) y queda esperando **un periodo completo**. `header.stamp` se pone en `_publicar`
(`_sellar_y_fijar_frame`), así que los datos tienen ≈ periodo − 1 tick de antigüedad: 15 Hz → ~50 ms, 10 Hz → ~83 ms,
**2 Hz (XRCE) → ~480 ms**. A 1 m/s o 1,5 rad/s eso son 0,5 m o 0,7 rad de error en `slam_toolbox`/costmap, y
`mapeo_2d` lo hereda.

Arreglo: guardar el sello cuando el scan termina (`_stamp_scan = contexto.nodo.now()` en `_actualizar_sensor`) o,
mejor, iniciar el barrido `ceil(n/presupuesto)` ticks antes del instante de publicación.

### A2 — Profundidad invertida verticalmente (`godot/plantillas/sensores/camara.gd:153`) [V]

`local = ((x+0.5-w/2)/fy, (y+0.5-h/2)/fy, -1)`: en la cámara de Godot +Y es arriba, pero la fila `y` de la imagen crece
hacia abajo. Sonda (dron a 3 m, cámara frontal horizontal, 80×60): fila 0 = `[6.61, 8.62, 8.62]` m (suelo),
filas 54–59 = `0.0` (cielo) — el suelo aparece **arriba** [V]. RGB (`get_image()`, origen arriba-izquierda) y CameraInfo
no están invertidos, así que `depth_image_proc` registra nubes reflejadas y RGB-D no casa.

Arreglo: `-(y + 0.5 - h * 0.5) / fy` en la componente Y.

### A3 — Sensores del G1 sin montar (`godot/plantillas/robots/humanoide_g1.gd:88` + `godot/g1-sensores/robot.json`) [V]

`sensores_listos` solo reparenta `d435`, `mid360`, `imu_pelvis` e `imu_torso`. `mid360_scan` (LaserScan, `frame_id`
`utlidar_lidar`) e `imu_mid360` (`frame_id mid360_link`) se quedan en la raíz del `CharacterBody3D`: sonda →
`mid360_scan padre=Robot pos_ros=(9.0, -17.0, 0.1606)`, frente a `mid360 padre=mid360_link pos_ros=(…, 1.40)` [V].
El LaserScan del G1 se traza a 0,16 m del suelo (rayos rasantes, ve bordillos y no paredes a 1,4 m) y `mapeo`
(`"padre":"mid360_scan"`) mapea desde ahí.

Arreglo: añadir `"mid360_scan": "mid360_link"` e `"imu_mid360": "mid360_link"` al diccionario `montajes`, o un campo
`"link"` genérico en `robot.json` que resuelva `aplicacion_robot.gd`.

### A4 — `frame_id` inexistentes en el árbol TF [V]

- G1: el URDF horneado (`godot/g1-sensores/robot/g1_vita.tscn`) solo tiene `d435_link`, `mid360_link`, `imu_in_pelvis`,
  `imu_in_torso`. `robot.json` usa `d435_color`, `d435_color_optical_frame` y `utlidar_lidar`, que **no aparecen en
  ningún fichero del repo** salvo `robot.json` (grep) [V]. `robot_state_publisher` no los publicará: nube, scan,
  imagen y profundidad son intransformables.
- Dron: no hay URDF ni publicador TF estático (`grep static_transform|tf_static|robot_state_publisher` en `docker/` y en
  los tres proyectos: nada) [V]. `drone_imu_link`, `drone_lidar_link`, `drone_front_camera_optical_frame`, etc. no
  existen para tf2. Sumado a C2, el dron no tiene ningún TF utilizable.
- RB-KAIROS+: los nombres son los del Xacro de Robotnik [I]; no comprobado contra el URDF expandido.

Arreglo: usar los links reales (o publicar los estáticos que falten desde Godot en `/tf_static`, fiable y
TRANSIENT_LOCAL, a partir de `pos_ros`/`rpy_ros` y la rotación óptica `rpy=(-π/2, 0, -π/2)`).

### A5 — `odom→pelvis` a la altura de los pies (`godot/plantillas/robots/robot_ros.gd:118-119`, `odometria.gd:71`) [V]

`posicion_ros()` devuelve el origen del `CharacterBody3D` (base de la cápsula, z=0,1606 en la sonda) y el G1 lo publica
como `odom→pelvis`. La pelvis real está a ~0,79 m (la sonda da `imu_in_pelvis` a z=0,857). El propio código lo sabe:
`unitree_estado.gd:83` suma `+0.78` "a mano" solo al formato compacto. Con `robot_state_publisher` el modelo y todo
sensor transformado vía TF quedan ~0,7 m hundidos respecto al mundo de Godot.

Arreglo: un `base_frame_offset` en `robot.json` (o leer la pose del link `pelvis` del modelo) usado por odometría/TF;
quitar el `+0.78` duplicado.

### A6 — Yaw del dron: ignorado o desbocado (`godot/plantillas/robots/dron.gd:14-18,33-44`) [V]

- `leer_teleop()` pone `yaw_objetivo = 0.0` **cada tick** y se llama siempre que `aceptar_teleop_local` (por defecto
  `true`): el `angular.z` de `/drone/cmd_vel` se borra en el tick siguiente. Sonda: 1 s de `angular.z=1` → yaw 0,0 [V].
- Con `aceptar_teleop_local=false` (modo `demo`), el hombre muerto (`robot_ros.gd:81-84`) solo pone a cero
  `orden_objetivo`; `yaw_objetivo` no se toca: 2 s después de dejar de enviar, el dron ha girado 2,0 rad más
  (`yaw_objetivo=1.0`) [V]. `fijar_emergencia(true)` tampoco lo para: −5,28 rad (= +1 rad envuelto) en 1 s de
  emergencia [V].

Arreglo: guardar el yaw como cuarta componente de la orden (p. ej. `orden_objetivo` como `Vector4` o un campo aparte
gestionado por el mismo timeout/emergencia), y que `leer_teleop` solo escriba yaw si hay entrada local.

### A7 — `mapeo_2d.gd`: espejo, cobertura y frame (`godot/plantillas/sensores/mapeo_2d.gd`) [V]

1. **Espejo con láseres invertidos** (`:100,109`): el ángulo de mundo se calcula como `yaw_de_quat(sensor) + a`,
   válido solo si el láser tiene z hacia arriba. Los SICK del RB-KAIROS+ llevan `rpy_ros=[0, −π, …]`
   (`godot/rbkairos-plus/robot.json`): con pitch π el rayo `a` va a `yaw_x + π − a` pero el código usa
   `yaw_x + a` (con `yaw_x = yaw+π` extraído del eje x) → el mapa del RB-KAIROS+ sale reflejado [V, derivación].
   Arreglo: transformar el punto final con la base 3D completa (`global_basis * dir_local`) y proyectar a XY.
2. **El mapa no cubre el spawn** (`:53-54,86-87`): 128×0,25 m = 32 m centrados en el origen → x,y ∈ [−16, 16]. RB-KAIROS+
   y G1 nacen en `(9, −17)`: `_celda` da y = −4 y `_marcar` descarta; buena parte del entorno queda fuera de un mundo de
   52×52 m [V, cálculo]. Arreglo: origen del mapa en el spawn, o `tamano`/`resolucion` que cubran el mundo.
3. **`frame_id = "map"`** (`:142`) con coordenadas del mundo de Godot (= `odom`) y sin nadie que publique `map→odom`:
   RViz no puede situarlo. Arreglo: `frame_id = odom_frame` o publicar `map→odom` identidad.

## 4. Medios

- **M1** `imu.gd:32,42` — `dt = 1.0/hz` en lugar del tiempo real transcurrido. Con C1 los huecos reales son 1 y 5 ticks
  para 10 Hz: la componente dinámica de la aceleración sale ×1/6 o ×0,83, y a 50 Hz (publica cada tick) ×0,83 [V].
  Arreglo: acumular el `dt` real desde la última publicación (o derivar en cada tick de física). Además la aceleración
  es la del `CharacterBody` y no incluye brazo de palanca ω×r ni el balanceo de la pelvis/torso del G1 [I, bajo].
- **M2** `magnetometro.gd:3` vs `gps.gd:46-53` — el GNSS trata x_ROS como **Este** (ENU, REP-103/105), pero el campo
  `(21, 0, −43) µT` pone el norte magnético en +x. Por DDS: `MAG x=2.09e-05, y≈0` con el dron mirando a +x [V].
  `robot_localization`/`navsat_transform` verían 90° de discrepancia. Arreglo ENU: `Vector3(0, 21, −43)` µT (y
  documentar declinación) o, si se quiere x=Norte, cambiar el GNSS.
- **M3** `barometro.gd:27-29` — altitud tomada desde z=0 al nivel del mar, mientras el GNSS usa `origen_altitud=450`:
  el barómetro dice ~0 m y el GNSS ~451 m [V, DDS: `altitude 451.58`]. Arreglo: sumar la misma altitud de origen.
- **M4** `dron.gd:35,38-39` — lateral invertido respecto a REP-103 y a `robot_ros.gd:64-68`: stick derecho a la derecha
  y tecla D dan `+y` (izquierda); A da derecha [V, lectura]. Arreglo: `y = -get_joy_axis(RIGHT_X)`, A → +1, D → −1.
- **M5** `humanoide_g1.gd:57-62` vs `unitree_control.gd:18-20` — `/lowcmd` escribe `_posiciones`, pero la marcha
  sobrescribe las 12 articulaciones de pierna en cada tick: `fijar_motor(3, 1.2)` → `left_knee` = 0,43 al tick siguiente
  [V]. El doc 29 dice que LowCmd "funciona"; solo funciona para cintura/brazos. Arreglo: modo "low-level" que suspenda
  la marcha mientras lleguen LowCmd (con su propio hombre muerto). (El orden de motores sí coincide: 29/29 [V].)
- **M6** `mapeo_2d.gd:62-72` — `_scan` nunca se vacía: si no llega scan nuevo (pérdida BE) se vuelve a integrar el mismo
  con la pose actual (log-odds duplicados y desplazados). Y la pose usada es la del instante de integración, no la del
  `header.stamp` del scan (se suma a A1). Arreglo: `_scan = null` tras integrar; guardar la pose al recibirlo.
- **M7** `contexto_ros.gd:50` → `RosNode::now()` (`godot/ros2_vita/ros_runtime.cpp:291-298`) usa el reloj Unix local.
  En la Vita ese RTC no está sincronizado con el PC (no hay `uxr_sync_session` en `ros2_vita`) → sellos desplazados,
  `message_filters`/tf2 descartan por extrapolación [I]. Arreglo: sincronizar con el agente (`uxr_sync_session` +
  `uxr_epoch_nanos`) o re-sellar en el relay.
- **M8** `lidar_2d.gd:73-75`, `rango.gd:40` — sin impacto → `range_max` (LaserScan) y lecturas < `range_min` se
  **recortan a `range_min`** (dato válido falso de obstáculo pegado). REP-117 pide `+Inf` sin retorno y `−Inf` demasiado
  cerca; `laser_geometry` descarta `r >= range_max`, por lo que el costmap no limpia sin `inf_is_valid` [V lectura,
  REP-117]. En Range, `rango_max + 1.0` funciona pero `+Inf` es la convención del mensaje en Jazzy.
- **M9** `mapeo_2d.gd:46` en Vita — el mapeador se suscribe por XRCE al `/scan` que publica la propia Vita: cada scan
  sale y vuelve por el agente (doble consumo de la cola BE y del enlace) [I]. Arreglo: pasar el array de rangos en
  memoria (señal o referencia al nodo `lidar_2d`).

## 5. Bajos

- **B1** `lidar_2d.gd:48` + `robot.json` (G1/dron): barrido de 360° con `angle_min=−π`, `angle_max=+π` e
  `increment=(max−min)/(n−1)` → primer y último rayo en la misma dirección. Convención: `angle_max = π − increment`.
- **B2** `camara.gd:130-131` — `cx = w/2`, `cy = h/2`; en convención OpenCV/ROS (centro de píxel en enteros) el
  centro es `(w−1)/2`. 0,5 px.
- **B3** `camara.gd:158` — profundidad sin impacto = 0.0; REP-118 usa NaN (no medida) en 32FC1. `depth_image_proc`
  acepta ambos [?].
- **B4** `imu.gd:41-43` — la primera muestra publica aceleración 0 (sin gravedad).
- **B5** `robot_ros.gd:112-115` — el reset con R/Y (`aplicacion_robot.gd:244-253`) teletransporta y genera un pico de
  velocidad (Odometry.twist) y de aceleración IMU de decenas de m/s²; reiniciar `_ultima_posicion` / `_yaw_anterior`.
- **B6** `robot_ros.gd:104-105` — `velocity` se reconstruye cada tick, así que la gravedad nunca se acumula (caída
  constante de 0,16 m/s).
- **B7** `dron.gd:57-58` — `rpm * dt / 60` son revoluciones, no radianes (falta ×2π); solo visual.
- **B8** `lidar_2d.gd:96,102` — `_secuencia` en `Int16MultiArray` desborda a los 32 767 scans (~1,8 h a 5 Hz).
- **B9** `bateria.gd:39` — mezcla m/s y rad/s en `orden.length()`; `_segundos` sin uso.
- **B10** `estado_controlador.gd:36-42` — `reference = feedback`, `error = 0`, `output = posición`; aceptable como
  stub, pero no es un estado de controlador. Comprobar que `speed_scaling_factor` existe en el `control_msgs` de
  Jazzy (5.x) [?].
- **B11** `brazo_trajectory.gd:18-19` — usa solo el último punto e ignora `time_from_start`; el brazo va a 1,5 rad/s
  fijos (`rbkairos.gd:65`).
- **B12** `estop.gd:16`, `unitree_control.gd:20,31` — sin comprobar `robot != null`.
- **B13** `dron_estado.gd` — `frame_id` por defecto `"sensor"` si el JSON no lo da (el dron sí lo da); el "flujo óptico"
  es la velocidad real, no flujo.
- **B14** `contexto_ros.gd:34-40` — la caché `topic|tipo` ignora la QoS: un segundo publicador con otra QoS recibe la
  del primero en silencio. Y el nodo aparece en DDS como `ros2_vita`, no con `config.nodo` [V, `ros2 topic info -v`].
- **B15** doc 29 §2/§9: "LaserScan 60 = 296 B" se midió con `frame_id="laser"`; con `robot_front_laser_link` son ~313 B.
  Sigue < 488 B.

## 6. Verificado correcto (no tocar)

- Conversión Godot↔ROS: `ros2_vita/ros_runtime.h:198-200` → `ros=(−g.z, −g.x, g.y)`, cuaternión
  `(−z, −x, y, w)` = conjugación por una rotación propia (det = +1); `aplicacion_robot.gd:160-163` construye la base
  ROS→Godot con las mismas columnas [V].
- Direcciones REP-103: LaserScan `(−sin a, 0, −cos a)` = `ros_to_godot(cos a, sin a, 0)`; LiDAR 3D; `rotation.y` de
  Godot = yaw ROS (CCW) [V].
- Mecanum (`base_mecanum.gd:15-19`, FL/FR/BL/BR, `a = lx+ly`): signos estándar de la configuración en X [V]; el signo
  del eje de cada joint depende del URDF [?]. Las ruedas usan la orden, no la velocidad real (cosmético).
- IMU: `+9,79 m/s²` en z en reposo (gravedad incluida, REP-145) [V DDS]; orientación dada con covarianza ≠ −1;
  covarianzas σ² en diagonal.
- `covarianza_6d`: índices 0,7,14 / 21,28,35 correctos. Odometry: pose en `odom`, twist en `child_frame_id` [V].
- NavSatFix: `STATUS_FIX`, `SERVICE_GPS`, `COVARIANCE_TYPE_DIAGONAL_KNOWN`, radios M y N de WGS-84 correctos; error
  AR(1) con varianza estacionaria correcta.
- MagneticField en tesla, covarianza en T² [V]. FluidPressure en Pa con la fórmula barométrica estándar.
- Range: `ULTRASOUND=0`, `INFRARED=1`. BatteryState: `DISCHARGING=2`, `GOOD=1`, `LIPO=3`, Ah, porcentaje 0–1,
  corriente negativa al descargar.
- PointCloud2: `FLOAT32=7`, offsets 0/4/8/12, `point_step=16`, `row_step=16·n`, `height=1`, `is_dense` con solo puntos
  válidos, little-endian. CameraInfo: `K`, `P` (3×4, fx=fy con `KEEP_HEIGHT`), `R=I`, `D` de 5 con `plumb_bob`.
- OccupancyGrid: fila 0 = y mínima, índice `y·width + x`, −1 desconocido, 0–100.
- Hombre muerto por `/cmd_vel`: 0,5 s correcto para x/y/z de la base (el fallo es solo teleop local, C3, y yaw del
  dron, A6).
- G1: orden de `nombres_joints()` = orden de motores Unitree (29/29) [V]; `imu.quaternion` en orden wxyz de Unitree.
- Restricciones Vita (W7): `SubViewport` solo en `camara.gd` con `solo_pc=true` (se desactiva antes de crearlo);
  `lidar_3d` también `solo_pc`; ningún `MultiMesh`, `ImmediateMesh`, líneas, puntos, partículas, `Label3D`/`Sprite3D` ni
  hilos en `godot/plantillas` [V grep]. Mensajes BE en Vita por debajo de 488 B (IMU, scan 60, teselas 260 B + cabecera,
  compactos).

## 7. Respuesta a la pregunta abierta del doc 30 §6

Los conteos superiores a la nominal **no** son del transporte ni de escenas duplicadas: es C1. Con `dt = 1/60`, toda
frecuencia cuyo periodo sea múltiplo entero de `dt` y cuya suma flotante quede por debajo (10, 5, 2 Hz…) publica dos
veces seguidas; 50 y 25 Hz suben a 60 y 30. Esto duplica el tráfico BE real del perfil XRCE de G1 y dron y es la
primera hipótesis para sus `be_dropped` restantes [I: no se re-midió el descarte con el arreglo].

## 8. Orden de arreglo recomendado

1. C1 (una línea, cambia todas las tasas) → re-medir `be_dropped` del doc 30.
2. C2 + A4 (TF fiable, frames reales/estáticos) → gate con `tf2_echo` y RViz.
3. C3 + A6 (seguridad de mando).
4. A1, A2, A3, A5, A7 (calidad de datos para SLAM/RGB-D).
5. Medios y bajos.
