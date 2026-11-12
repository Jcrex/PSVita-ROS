# Dron de mapeo — plantilla prioritaria de sensores

Dron genérico propio de 552 triángulos, diseñado en Blender. El movimiento 6DOF es cinemático: no pretende sustituir un modelo aerodinámico ni un controlador PX4/ArduPilot.

## Suite de percepción

- IMU, GNSS, barómetro, magnetómetro, batería y odometría.
- Cámara RGB-D frontal y cenital, cada una con RGB, JPEG y CameraInfo en PC.
- LiDAR 3D de 16 anillos y proyección 2D de 360 rayos en PC.
- Sonar inferior y frontal (`sensor_msgs/Range`).
- Rotores, flujo óptico, parada de emergencia y TF: `/tf` fiable `odom → drone_base_link` y, como el dron no tiene
  URDF, `/tf_static` con `drone_base_link →` cada sensor y los marcos ópticos de las cámaras (`"tf_estatico_sensores":
  true` en `robot.json`). Los sonares orientan el eje x de su marco al haz, como pide `sensor_msgs/Range`.
- Mapa 2D con pose conocida en el marco `odom`, centrado en el despegue; `slam_toolbox` puede consumir `/drone/scan`,
  `/drone/odom` y `/tf` para SLAM completo.
- Magnetómetro en ENU (norte = +y, como el GNSS) y barómetro con la misma altitud de origen que el GNSS (450 m).

En Vita se conservan los sensores pequeños, un scan estándar de 60 rayos y los compactos VC/1
`/vita/drone/{pose2d, scan_compacto, mapa_meta, mapa_tesela}`. Las imágenes y nubes **no** llegan a la Vita: no existe
relay de imagen ni de nube (pendiente). Todos los nombres, tipos, frecuencias y plataformas están en `ros/topics.json`.

## Uso

```fish
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
docker/vita-ros.sh up
$G --path godot/dron-mapeo
```

Stick izquierdo: avance/retroceso y yaw; stick derecho: lateral (izquierda = +y, REP-103) y altitud; W/S y A/D en
teclado (A = izquierda); E/Q o R/L: subir/bajar; flechas izquierda/derecha: yaw. `/drone/cmd_vel` usa `linear.z` para
altitud y `angular.z` para yaw; el yaw obedece también con la teleop local activa y se para con el timeout de 0,5 s,
al soltar el mando y con la parada de emergencia.

## Exportar

```fish
tools/export-vita-vpk.sh godot/dron-mapeo build/dron-mapeo.vpk
tools/deploy-vpk-ftp.sh build/dron-mapeo.vpk 192.168.1.94
```

TITLE_ID `RVGD40023`. El mapa local no afirma cierre de bucles ni estimación de pose; para SLAM real usa un nodo ROS 2 en PC. La medición de FPS y pérdidas en hardware queda como gate pendiente.
