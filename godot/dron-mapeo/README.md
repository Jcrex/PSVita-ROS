# Dron de mapeo — plantilla prioritaria de sensores

Dron genérico propio de 552 triángulos, diseñado en Blender. El movimiento 6DOF es cinemático: no pretende sustituir un modelo aerodinámico ni un controlador PX4/ArduPilot.

## Suite de percepción

- IMU, GNSS, barómetro, magnetómetro, batería y odometría.
- Cámara RGB-D frontal y cenital, cada una con RGB, JPEG y CameraInfo en PC.
- LiDAR 3D de 16 anillos y proyección 2D de 360 rayos en PC.
- Sonar inferior y frontal (`sensor_msgs/Range`).
- Rotores, flujo óptico, parada de emergencia y TF.
- Mapa 2D con pose conocida; `slam_toolbox` puede consumir `/drone/scan` y `/drone/odom` para SLAM completo.

En Vita se conservan los sensores pequeños y un scan estándar de 60 rayos; imágenes y nubes se degradan mediante relay. Todos los nombres, tipos, frecuencias y plataformas están en `ros/topics.json`.

## Uso

```fish
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
docker/vita-ros.sh up
$G --path godot/dron-mapeo
```

Stick izquierdo: avance/retroceso y yaw; stick derecho: lateral/altitud; W/S y A/D en teclado; Q/E: altitud; flechas izquierda/derecha: yaw. `/drone/cmd_vel` usa `linear.z` para altitud y `angular.z` para yaw.

## Exportar

```fish
tools/export-vita-vpk.sh godot/dron-mapeo build/dron-mapeo.vpk
tools/deploy-vpk-ftp.sh build/dron-mapeo.vpk 192.168.1.94
```

TITLE_ID `RVGD40023`. El mapa local no afirma cierre de bucles ni estimación de pose; para SLAM real usa un nodo ROS 2 en PC. La medición de FPS y pérdidas en hardware queda como gate pendiente.
