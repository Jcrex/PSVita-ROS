# RB-KAIROS+ en Godot 4 — PC y PS Vita

Robot omnidireccional con UR10e generado del Xacro oficial. No es un modelo aproximado: conserva 40 links, 39 joints, los nombres ROS y 10 articulaciones móviles (cuatro ruedas + seis del brazo).

## Sensores y control

- Base mecanum: `/robot/robotnik_base_control/cmd_vel_unstamped` (`Twist`) y `cmd_vel` (`TwistStamped`), odometría y cuatro ruedas.
- UR10e: `/robot/joint_trajectory_controller/joint_trajectory`, `/joint_states` y `controller_state` Jazzy (`reference/feedback/error/output`).
- Físicos del `rbkairos_plus.urdf.xacro`: VectorNav IMU, dos SICK S300 (270 rayos en PC) y D435 frontal RGB-D.
- Sensores que el lanzador oficial `spawn_robot.launch.py` también puentea: GPS, cámaras rear/top PTZ y LiDAR 3D superior. Se incluyen como perfil de simulación, no como afirmación de equipamiento físico de serie.
- Batería, parada de emergencia, TF base y mapa de ocupación.

El catálogo exacto, QoS y disponibilidad PC/Vita está en `ros/topics.json`. La configuración editable está en `robot.json`.

## Modelos y mundo

- Vita: 11 620 triángulos; el chasis se limitó a 3 000 para evitar la ruta lenta de mallas grandes de GXM.
- PC: 67 246 triángulos.
- Mundo común: bosque, ciudad, parque y casa de 12×10 m con cocina, muebles, personas, animales, coches, juguetes, comida, plantas y obstáculos. Con el robot Vita, la escena queda por debajo del presupuesto de 60 000 triángulos.

Fuentes y commits en `ros/topics.json`; licencias en `CREDITOS.md` y `ros/LICENSE*`.

## Uso en el PC (fish)

```fish
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui
docker/vita-ros.sh up
$G --path godot/rbkairos-plus
# Sin agente, solo escena:
$G --path godot/rbkairos-plus -- sin_ros
# Forzar los mismos triángulos de la Vita:
$G --path godot/rbkairos-plus -- lod=vita
```

Stick izquierdo: avance/lateral; L/R o Q/E: giro. Stick derecho o ratón: cámara; cruceta: zoom; ○/C: cenital; △/R: reiniciar.

## Exportar

```fish
tools/export-vita-vpk.sh godot/rbkairos-plus build/rbkairos-plus.vpk
tools/deploy-vpk-ftp.sh build/rbkairos-plus.vpk 192.168.1.94
```

TITLE_ID `RVGD40021`. Antes de exportar una plantilla nueva de `ros2_vita`, recompila con `tools/build-godot-template.sh`. La prueba en hardware debe medir FPS, `be_dropped` y frecuencia real compartida de los sensores BE; no se afirma rendimiento Vita hasta ejecutar ese gate.

## Regenerar el chasis Vita reducido

```fish
toolchains/rosbags-venv/bin/python tools/diezmar-malla.py toolchains/robotnik_description/meshes/bases/rbkairos/rbkairos_chassis.stl godot/rbkairos-plus/robot/mallas_rbkairos_vita/robot_base_link_0.obj --tris 3000
```

El venv usa `trimesh` y `fast-simplification`; el resto del robot se genera con `tools/urdf2godot/`. Los hashes de los repositorios fuente están en `ros/fuentes.json`.
