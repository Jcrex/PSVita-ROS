# Tooling de rclgd: instalar, crear, editar, ejecutar, probar

## Instalar
- **apt (Ubuntu con repos de ROS 2):** `sudo apt install ros-jazzy-rclgd` → trae `rclgd`,
  `colcon_rclgd`, `rclgd_cli` **y el editor Godot fijado** (4.7.1). Verificar:
  `source /opt/ros/jazzy/setup.bash && ros2 rclgd doctor`.
- **Desde fuente:** en `~/ros2_ws/src`: `git clone --recurse-submodules https://github.com/Ozuba/rclgd.git`
  (usar `-b jazzy`), `rosdep install --from-paths src --ignore-src -y -r`,
  `colcon build --packages-up-to rclgd rclgd_cli colcon_rclgd`, `source install/setup.bash`.
- **El binario de Godot lo descarga la compilación** (SHA-512 fijado) y lo instala en
  `install/rclgd/lib/rclgd/godot-bin`; la versión queda en `share/rclgd/godot_version`.
  **No instales Godot aparte.** Cambiar de versión = cambiar el submódulo `godot-cpp` +
  `GODOT_VERSION`/`GODOT_SHA512_*` en `rclgd/CMakeLists.txt` y recompilar (solo versiones *stable*).
- **En el proyecto PSVita-ROS (CachyOS/Arch, sin apt):** ROS 2 Jazzy vive en el contenedor docker
  `robotnik_dev` (Ubuntu). Instalar rclgd **dentro** del contenedor (apt o fuente) y, para el editor
  gráfico, reenviar X11/Wayland al contenedor. *Sin verificar en este entorno: validar en el PC.*

## CLI `ros2 rclgd`
| Orden | Qué hace |
|---|---|
| `ros2 rclgd create <pkg> [--dependencies geometry_msgs sensor_msgs] [--renderer gl_compatibility] [--dry-run]` | paquete completo: `package.xml` (`build_type: rclgd`), `project.godot`, `main.tscn/.gd` demo, `addons/rclgd` |
| `ros2 rclgd editor [pkg]` | abre el **proyecto fuente** del paquete (nunca la copia instalada); sin args: dir actual o gestor de proyectos; `--import-only` importa en headless y sale |
| `ros2 rclgd list [--names-only]` | paquetes rclgd construidos |
| `ros2 rclgd doctor` | entorno ROS, `librclgd.so`, lanzador, versión fijada, binario, cableado del proyecto |
| `ros2 run rclgd godot` | el binario de Godot sin lógica de proyecto |

Nombres de paquete en `lower_snake_case`.

## colcon (`build_type: rclgd`)
`package.xml` mínimo: `<buildtool_depend>rclgd</buildtool_depend>`, `<depend>` por cada paquete de
mensajes, `<export><build_type>rclgd</build_type></export>`. `colcon build` sincroniza el proyecto a
`install/` (mejor `--symlink-install`), lo registra en el índice ament, crea el lanzador
`install/lib/<pkg>/<pkg>` y hace la importación headless de recursos.

## Ejecutar
```bash
ros2 run <pkg> <pkg>
ros2 run <pkg> <pkg> --ros-args -r __ns:=/robot1 -p use_sim_time:=true --log-level <nodo>:=debug
```
Funciona desde *launch files* como cualquier ejecutable. Sin línea de órdenes, el autoload `ROS`
lee `ros/parameters/<clave>` de los ajustes del proyecto (la línea de órdenes gana).

## Estructura de un proyecto creado
```
<pkg>/package.xml  project.godot  main.tscn  main.gd  .gitignore(.godot/)
<pkg>/addons/rclgd/{plugin.cfg, rclgd.gd (genera clases sombra), ros_init.gd (autoload ROS), bin/rclgd.gdextension}
```
`project.godot` incluye `[autoload] ROS="*res://addons/rclgd/ros_init.gd"` y el plugin en `[editor_plugins]`
(desaparece con las clases nativas; ver `versiones.md`).

## Pruebas headless (patrón oficial, `rclgd/test/`)
```bash
rclgd/test/run_tests.sh <godot-bin> <librclgd.so> rclgd/test/project [--filter=texto] [--junit=f.xml]
```
- Copia el proyecto a un dir temporal, enlaza la librería, escribe `.godot/extension_list.cfg`, usa
  `ROS_DOMAIN_ID` aleatorio y `ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST`, y ejecuta
  `godot --headless --path <dir> --script res://runner.gd`.
- `runner.gd` (extends `SceneTree`) ejecuta cada `test_*` de `res://tests/test_*.gd`, captura errores del
  motor con un `Logger` propio y sale con código ≠ 0 si algo falla. **Cópialo** para tus proyectos.
- Los tests son el mejor catálogo de ejemplos: `rclgd-docs.sh ejemplos <método>`.
