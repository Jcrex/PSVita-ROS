# Unitree G1 — plantilla completa de sensores ROS 2

Reutiliza el URDF y las mallas de `godot/g1-unitree/`: 29 articulaciones, 12 633 triángulos en Vita y 60 633 en PC. La marcha usa los clips grabados de la política oficial de Unitree; las colisiones y el movimiento son cinemáticos.

## g1_sim **o** g1-sensores: espacio de nombres `g1s`

`docker/g1/g1_sim.py` (MuJoCo + política oficial) ya publica `/g1/estado`, `/odom`, `/joint_states` y `/tf odom→pelvis`.
Si los dos productores usaran los mismos nombres, la pose saltaría entre ambos (revisión R4, P0). Por eso este
proyecto publica **todo lo suyo con el prefijo `g1s`**:

| Qué | g1_sim | g1-sensores |
|---|---|---|
| Estado compacto (19 floats) | `/g1/estado` | `/g1s/estado` |
| Odometría | `/odom` | `/g1s/odom` |
| Juntas | `/joint_states` | `/g1s/joint_states` |
| TF base | `odom → pelvis` | `g1s/odom → g1s/pelvis` |
| Compactos VC/1 | — (los da `vita_relay`) | `/vita/g1s/{pose2d, joints, joints_orden, scan_compacto, mapa_meta, mapa_tesela}` |

Pueden correr a la vez sin pisarse. `/cmd_vel` es una **entrada** compartida: si los dos están vivos, los dos se
mueven. `g1-unitree` en modo ros puede ver este G1 cambiando su suscripción de `/g1/estado` a `/g1s/estado`
(mismo formato; `z` es ahora la altura real de la pelvis, como en g1_sim). Para el TF completo de las 29 juntas,
`robot_state_publisher` con `frame_prefix:=g1s/` y `joint_states` remapeado a `/g1s/joint_states` [I].

## Sensores montados en el URDF

Cada sensor se cuelga de su link con el campo `"link"` de `robot.json` (revisión R2-A3), con los ejes del link:

- IMU de pelvis y torso (`imu_in_pelvis`, `imu_in_torso`; marcos `g1s/imu_in_*`).
- D435 RGB-D en `d435_link` (mira hacia delante y abajo, como el URDF), con RGB, JPEG, CameraInfo y profundidad 32FC1
  en PC. Los datos van en `g1s/d435_optical_frame`, que este proyecto publica en `/tf_static` (no está en el URDF).
- Livox Mid-360 en `mid360_link` (~1,40 m): PointCloud2, IMU y proyección LaserScan; marco `g1s/mid360_link`.
- Odometría con la pose real de la pelvis (~0,94 m sobre el origen del cuerpo; R2-A5), 29 `JointState`, batería y TF base.
- Estado propietario `unitree_hg/LowState`, `/secondary_imu` (`unitree_hg/IMUState`, IMU del torso como en el G1 real),
  `unitree_go/SportModeState` y `LidarState` (**formatos de Go2/B2**; el G1 real publica `rt/odommodestate`) y
  `WirelessController`. La columna `origen` de `ros/topics.json` dice qué es de Unitree G1, de Go2 o del proyecto.
- Entrada `LowCmd` (mientras llegan, la marcha deja libres las piernas; 0,5 s sin LowCmd y vuelve la marcha) y
  API `sport` del LocoClient (`unitree_api/Request` + `Response`): 7105 SetVelocity (respeta `duration`), 7101
  SetFsmId, 7102 SetBalanceMode y los GET 7001/7003; el resto responde **3203** (API no implementada).

Los mensajes grandes propietarios se publican en PC; los compactos funcionan en ambas plataformas. Todos los topics
y exclusiones están en `ros/topics.json`.

## Uso

```fish
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
docker/vita-ros.sh up
$G --path godot/g1-sensores
$G --path godot/g1-sensores -- lod=vita
```

Stick izquierdo: andar/girar; L/R o Q/E: paso lateral; ○/C: cenital; △/R: reiniciar. Al soltar el mando el robot
se para (hombre muerto local). Para control bajo nivel, publica `unitree_hg/msg/LowCmd` en `/lowcmd`; para locomoción
de alto nivel usa `/cmd_vel` o `api_id=7105` en `/api/sport/request`.

## Exportar

```fish
tools/export-vita-vpk.sh godot/g1-sensores build/g1-sensores.vpk
tools/deploy-vpk-ftp.sh build/g1-sensores.vpk 192.168.1.94
```

TITLE_ID `RVGD40022`. D435 y PointCloud2 solo se generan en PC; **no hay relay de imagen ni de nube** hacia la Vita
(pendiente). El TF completo del URDF debe generarlo `robot_state_publisher` en PC. Las manos dexterous y `/arm_sdk`
(`rt/arm_sdk`) no se emulan porque este URDF tiene `rubber_hand` y `ros2_vita` no implementa acciones.
