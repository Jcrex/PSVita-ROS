# Unitree G1 — plantilla completa de sensores ROS 2

Reutiliza el URDF y las mallas de `godot/g1-unitree/`: 29 articulaciones, 12 633 triángulos en Vita y 60 633 en PC. La marcha usa los clips grabados de la política oficial de Unitree; las colisiones y el movimiento son cinemáticos.

## Sensores montados en el URDF

- IMU de pelvis y torso (`imu_in_pelvis`, `imu_in_torso`).
- D435 RGB-D en `d435_link`, con RGB, JPEG, CameraInfo y profundidad 32FC1 en PC.
- Livox Mid-360 en `mid360_link`: PointCloud2, IMU y proyección LaserScan para navegación.
- Odometría, 29 `JointState`, batería y TF base.
- Estado propietario `unitree_hg/LowState`, `unitree_go/SportModeState`, `LidarState` y `WirelessController`.
- Entrada `LowCmd` y API de deporte `unitree_api/Request` + `Response`.

`/g1/estado` conserva el contrato del proyecto anterior: 19 floats (pose + 12 joints de piernas) a 25 Hz, apto para Vita. Los mensajes grandes propietarios se publican en PC; los compactos funcionan en ambas plataformas. Todos los topics y exclusiones están en `ros/topics.json`.

## Uso

```fish
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
docker/vita-ros.sh up
$G --path godot/g1-sensores
$G --path godot/g1-sensores -- lod=vita
```

Stick izquierdo: andar/girar; L/R o Q/E: paso lateral; ○/C: cenital; △/R: reiniciar. Para control bajo nivel, publica `unitree_hg/msg/LowCmd` en `/lowcmd`; para locomoción de alto nivel usa `/cmd_vel` o `api_id=7105` en `/api/sport/request`.

## Exportar

```fish
tools/export-vita-vpk.sh godot/g1-sensores build/g1-sensores.vpk
tools/deploy-vpk-ftp.sh build/g1-sensores.vpk 192.168.1.94
```

TITLE_ID `RVGD40022`. D435 y PointCloud2 requieren PC; en Vita usa el relay. El TF completo del URDF debe generarlo `robot_state_publisher` en PC. Las manos dexterous y `/armsdk` no se emulan porque este URDF tiene `rubber_hand` y `ros2_vita` no implementa acciones.
