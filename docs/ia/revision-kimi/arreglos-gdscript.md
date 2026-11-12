# Arreglos GDScript de las plantillas tras la revisión (R2, R3, R4)

> 2026-11-12. Ámbito: `godot/plantillas/{ros,sensores,robots,pruebas}/*.gd`, `aplicacion_robot.gd`, `robot.json`,
> `ros/topics.json` y README de `g1-sensores`, `rbkairos-plus` y `dron-mapeo`, y `docs/29`. No se tocó
> `ros2_vita/`, `docker/`, `godot/comun/`, `godot/g1-unitree/` ni `plantillas/vita_relay.gd`. No se compiló el motor.
> Ya estaban arreglados antes (no se tocaron): R2-C1 (`sensor_base.gd`), R2-C2 (`/tf` fiable) y R2-C3 (hombre muerto
> local). Cada cambio lleva en el código un comentario que cita el hallazgo.
> Marcas: [V] verificado con ejecución, [I] inferencia.

## 1. Verificación ejecutada

| Prueba | Resultado |
|---|---|
| `runner.gd` (G1 / RB-KAIROS+ / dron) | **14/14 · 12/12 · 12/12** [V]. Incluye 6 pruebas nuevas de paridad VC/1 y el LaserScan de 60 rayos con `robot_front_laser_link` (312 B). |
| Paridad VC/1 | `vc1.gd` da las mismas huellas MD5 que `empaquetar_scan` / `empaquetar_tesela` de `docker/scripts/vita_relay.py` (vectores con Inf, NaN, fuera de rango, diezmado ×3, `seq` = 40000, versión > 16 bit, rejilla 40×37 que no es múltiplo de 32) [V]. |
| `escena.gd` `lod=vita`, `fisica.gd`, `rendimiento.gd` (loopback, 4 s) | Sin errores; triángulos sin cambios (37 277 / 36 276 / 25 196); el robot se apoya igual; tasas nominales (p. ej. `front_laser` 58 en ~4 s a 15 Hz), `be_dropped` 0 [V]. |
| Las tres escenas en loopback, PC y `lod=vita` | 0 líneas de error o aviso [V]. |
| Sondas en loopback (scratchpad, fuera del repo) | ver la columna «Verificación» de §2 [V]. |
| Agente micro-ROS aislado (`rev-agent`, UDP **8889**, dominio **77**, `--ipc=host`) + `ros2` en `psvita-ros-station:jazzy` | `tf2_echo g1s/odom g1s/pelvis` → z = 0,936 m; `tf2_echo g1s/d435_link g1s/d435_optical_frame`; `tf2_echo odom drone_sonar_down` → RPY (0°, 90°, 0°); `tf2_echo drone_base_link drone_front_camera_optical_frame` → (−90°, 0°, −90°); `tf2_echo robot_odom robot_base_footprint`; `/tf_static` de los tres robots; `joints_orden` y `mapa_meta` latched; `scan_compacto` `[seq, −18000, 200, 180, …]`; `/utlidar/scan` y `/drone/scan` a **1,99 Hz** (perfil XRCE, 2 Hz nominal); `/drone/sonar/front` = `inf`. `get_transport_info`: `write_errors` 0, `be_dropped` 0. El agente se paró al acabar [V]. |

## 2. Hallazgo → cambio → verificación

| Hallazgo | Cambio (`archivo:línea`) | Verificación |
|---|---|---|
| **R2-A1** scan con un periodo de antigüedad | El barrido empieza cuando faltan `ceil(n/presupuesto)` fotogramas para publicar y se sella con el instante del primer rayo: `sensores/lidar_2d.gd:79-120`, `:134` | Sonda G1 a 2 Hz: antigüedad 1–20 ms (antes ≈ 480 ms) [V] |
| **R2-A2** profundidad invertida | Signo de la componente Y del rayo: `sensores/camara.gd:155-157` | Sonda G1 (D435 inclinada): fila 2 = 2,25 m, fila h−3 = 1,28 m (suelo abajo) [V] |
| **R2-A3** sensores del G1 sin montar | Campo `"link"` genérico en `robot.json`, resuelto en `aplicacion_robot.gd:151-176`; base `Util.base_sensor_en_link` (`ros/util_ros.gd:66-69`) que alinea los ejes Godot del sensor con los ROS del link. Se quitó el diccionario fijo de `robots/humanoide_g1.gd` | `mid360_scan`, `imu_mid360` y `mid360` en `mid360_link` a z = 1,40 m; scan delante = +x, arriba = +z; IMU pelvis = (−0,26, 0,19, **9,81**) [V]. Hallazgo nuevo: el montaje antiguo con base identidad también giraba 90° la D435 y la nube (ejes Godot sobre ejes ROS) |
| **R2-A4** frames sin TF | `/tf_static` fiable + TRANSIENT_LOCAL: `aplicacion_robot.gd:182-247` (lista `tf_estatico`, `"tf_estatico": true` por sensor o `tf_estatico_sensores`; óptico −π/2,0,−π/2; sonar con x en el haz). G1: marcos reales `g1s/<link>` y `g1s/d435_optical_frame`; RB-KAIROS+: solo los sensores que no están en el URDF (rear/PTZ, LiDAR superior, GPS, batería; la frontal pasa a `robot_front_rgbd_camera_color_frame`, que sí está); dron: todos | `tf2_echo` por DDS de los tres robots [V] |
| **R2-A5** `odom→pelvis` a ras de suelo | `posicion_base_ros()`/`orientacion_base_ros()` en `robots/robot_ros.gd:155-163`, sobrescritas por la pelvis real en `robots/humanoide_g1.gd:76-91`; usadas por `sensores/odometria.gd:64-80` y por `/g1s/estado` (`sensores/unitree_estado.gd:94-99`, sin el `+0.78`) | `tf2_echo` z = 0,936 m; `/g1s/estado` z = 0,941 (pelvis real con balanceo) [V] |
| **R2-A6** yaw del dron | `_parar_orden()` único en `robots/robot_ros.gd:53-59` (timeout, emergencia, soltar) + `_aplicar_teleop_local()` `:95-100`; el dron añade el yaw en ambos (`robots/dron.gd:34-66`) y `leer_teleop` ya no borra `yaw_objetivo` | Sonda: 1 s de `angular.z=1` con teleop local ON → 0,74 rad (antes 0); 2 s tras el timeout → 0,000; 1 s en emergencia → 0,000 [V] |
| **R2-A7.1** mapa en espejo | Rayo proyectado con la base 3D completa del láser: `sensores/mapeo_2d.gd:149-185` | Por construcción usa la misma dirección que el raycast del láser (`lidar_2d.gd:100`) [V lectura]; no se comparó con un mapa de referencia |
| **R2-A7.2** el mapa no cubre el spawn | `centrar_en_spawn` (defecto) y `centro_ros`: `sensores/mapeo_2d.gd:16-19`, `:56-60` | Meta G1: origen (−7, −33) para spawn (9, −17); dron (−21, −21) [V] |
| **R2-A7.3** `frame_id="map"` sin `map→odom` | `frame_id` exportado, por defecto `odom`; `robot.json`: `g1s/odom`, `robot_odom`, `odom`: `sensores/mapeo_2d.gd:14-15`, `:189` | — |
| R2-M1 / B4 IMU | `dt` real acumulado y gravedad en la 1.ª muestra: `sensores/imu.gd:33-48` | IMU pelvis 9,81 en reposo [V] |
| R2-M2 magnetómetro | Campo ENU `(0, 21, −43)` µT: `sensores/magnetometro.gd:3-6` | Sonda: dron con yaw 1,97 → `(19,2, −8,1)` µT = norte girado [V] |
| R2-M3 barómetro | `origen_altitud = 450`: `sensores/barometro.gd:7-9`, `:31` | 96 000 Pa ≈ 453 m [V] |
| R2-M4 lateral del dron | `y = −RIGHT_X`, A = +y: `robots/dron.gd:43-48` | lectura |
| R2-M5 LowCmd pisado | Pausa de la marcha mientras llegan LowCmd (0,5 s): `robots/humanoide_g1.gd:18-19`, `:61-67`, `:112` | no probado con LowCmd real [I] |
| R2-M6 / R4-C9 / R2-M9 | `lidar_2d.ultimo_scan()` (`:123-126`); `mapeo_2d` lee el padre en memoria, una vez por `seq`, con la pose del barrido (`:69-74`, `:117-128`); respaldo por ROS si el padre no es un lidar | Teselas y meta recibidas por DDS [V] |
| R2-M8 REP-117 | LaserScan +Inf / −Inf (`sensores/lidar_2d.gd:104-112`); Range +Inf / −Inf (`sensores/rango.gd:40-46`); `mapeo_2d` trata +Inf como libre hasta el alcance | `/drone/sonar/front` = `inf` [V] |
| R2-B1 360° | `increment = 2π/n`, `angle_max = min + (n−1)·inc`: `sensores/lidar_2d.gd:57-62` | compacto G1 `inc = 200 cdeg` con 180 rayos [V] |
| R2-B2 `cx, cy` | `(w−1)/2`: `sensores/camara.gd:129-133` | — |
| R2-B5 / B6 / B7 / B9 / B12 / B13 / B14 | `reiniciar_estado()` (`robot_ros.gd:166-175`, `aplicacion_robot.gd:99,330,337`); caída acumulada (`robot_ros.gd:133-135`); rotores ×2π (`dron.gd:79-80`); batería (`bateria.gd:37-38`); `robot != null` (`estop.gd:16`, `unitree_control.gd:36`); `frame_id` del dron_estado (`dron_estado.gd:15`); clave con QoS (`ros/contexto_ros.gd:35-37`) | `fisica.gd` sin cambios en el apoyo [V] |
| **VC/1** (R4 §1.6) | `ros/vc1.gd` (nuevo): `empaquetar_scan` (máscara `0x7FFF`, 0 = sin dato/sin impacto/fuera de rango, diezmado ≤ 180, siempre BE), `celda_2bit` (libre 0–25, ocupada ≥ 65, resto desconocido), `empaquetar_tesela` (`fill(0)`); usados en `lidar_2d.gd:137-141` y `mapeo_2d.gd:209-214`. `version` = época (`mapeo_2d.gd:65`, `reiniciar_mapa()` `:93-98`); meta solo al cambiar (`:113-114`); `joints_orden` String fiable + latched en `joint_state.gd:8-11`, `:31-35`, `:58-64`. Nombres `/vita/<robot>/{scan_compacto, pose2d, joints, joints_orden, mapa_meta, mapa_tesela}` en los tres `robot.json` (`prefijo_compacto` documenta el prefijo) | Paridad MD5 en `runner.gd` [V]; DDS [V] |
| **R4 P0** productor único del G1 | `g1-sensores/robot.json`: `/g1s/estado`, `/g1s/odom`, `/g1s/joint_states`, `/g1s/map`, `/vita/g1s/…` y marcos `g1s/…` (por eso convive con `g1_sim`, que usa `/g1/estado`, `/odom`, `/tf odom→pelvis`); README «g1_sim **o** g1-sensores» con tabla | `ros2 topic list` por DDS: ningún `/g1/estado` ni `/odom` [V] |
| **R3-2.5** 3401 | `ERR_API_NO_IMPLEMENTADA = 3203` y `ERR_PARAMETRO = 3204`: `sensores/unitree_control.gd:6-8` | Sonda: 7104 y 9999 → 3203 [V] |
| **R3-2.6** 7101–7107 | 7105 SetVelocity con `duration` (`robot_ros.gd:72-77`); 7101 SetFsmId (guarda; 0–3 paran la marcha); 7102 SetBalanceMode (guarda); GET 7001/7003 con `data`; el resto 3203: `unitree_control.gd:42-90` | 7101 → 0, 7001 → `{"data":500}` [V] |
| **R3-2.7** Go2 | `topics.json` del G1 con columna `origen` (Unitree G1 / Go2-B2 / proyecto / ROS); comentario en `unitree_estado.gd:111-114` | — |
| **R3-2.8** IMU del torso | `/secondary_imu` (`unitree_hg/IMUState`) en PC: `unitree_estado.gd:9-11`, `:51-53`, `:66-68`; `/imu/torso` queda como nombre del proyecto | 117 mensajes en la sonda [V] |
| R3-2.9 `/arm_sdk` | READMEs, `topics.json` y doc 29 | — |
| R4-C4 publicadores sin uso | `_usa_publicador_estandar()` en `ros/sensor_base.gd:35-49`; lo sobrescriben odometría, joint_state y lidar_2d | — (la Vita solo se ve en hardware) |
| R4 §2 `yaw_de_quat` | Una sola fórmula en `ros/util_ros.gd:50-58` (+ `yaw_de_xyzw` para arrays como `/g1/estado`) | — |
| **R4-C5** doc 29 promete relay de cámara/nube | doc 29 §3 y §10, `topics.json` («no existe relay de imagen ni de nube») y README | — |
| Hallazgo nuevo | `topics.json` del G1: `SportModeState`/`WirelessController` salen a 6,25 Hz (cada 4 muestras de 25 Hz), no 12,5 | lectura |

## 3. Lo que no se hizo y por qué

- **R2-M7** (sellos sin sincronizar en la Vita): requiere `uxr_sync_session` en `godot/ros2_vita/`, fuera de ámbito.
  Anotado en doc 29 §10.
- **R2-B3** (NaN en lugar de 0 en profundidad sin impacto): REP-118 sin confirmar [?]; `depth_image_proc` acepta 0.
- **R2-B10** (`estado_controlador` como stub) y **R2-B11** (`JointTrajectory`: último punto, sin `time_from_start`): no son
  correcciones claras sino funcionalidad nueva.
- **Unificar `yaw_de_quat`** con `godot/g1-unitree/main.gd:312` y `plantillas/vita_relay.gd`: fuera de ámbito; ambos
  pueden llamar ya a `Util.yaw_de_xyzw`.
- **`/sportmodestate` → `/odommodestate`**: solo se marcó como Go2; el tipo exacto de `rt/odommodestate` en el G1
  viene de un espejo no oficial [?] (R3 fuentes).
- **Umbral de «libre»**: se aplicó el de VC/1 (≤ 25). Con −0,4 log-odds por pasada, una celda necesita ~3
  integraciones (3 s a 1 Hz) para verse libre en las teselas; el `OccupancyGrid` de PC no cambia [I].
- **Teselas por ciclo**: siguen siendo 1 por segundo (16 s para refrescar 4×4); no se subió para no cargar la cola BE
  de la Vita.
- `godot/plantillas/README.md` (fuera de la lista de ámbito) aún habla de «296 B», de la cola BE antigua y del relay;
  conviene alinearlo con doc 29.
- Hardware: sin probar en la Vita (FPS, `be_dropped` con las tasas ya correctas, `/tf` fiable a 20 Hz por el stream
  fiable, TF estático de ~1,3 KB en el dron).
