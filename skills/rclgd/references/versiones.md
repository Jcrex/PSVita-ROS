# Versiones, ramas y cómo detectar cambios

| Fecha de estudio | Rama | Commit | rclgd | Godot fijado | Notas |
|---|---|---|---|---|---|
| 2026-11-14 | **`jazzy`** | **`d8221d3`** | **3.0.0 (2026-11-04)** | 4.7.1 | **mismo código que `fb12a65`**: solo cambia el CHANGELOG («Forthcoming» se publica como 3.0.0). Compilado desde fuente en el PC y probado: **45/45** pruebas del propio rclgd (§Compilar) |
| 2026-10-29 | `jazzy` | `fb12a65` | 3.0.0 + Forthcoming | 4.7.1 | base de la API de esta skill: incluye las **clases tipadas nativas** (`d31b4f1`) y la doc revisada (`bfbda5c`) |
| 2026-10-29 | `rolling` (por defecto) | `bfbda5c` | 3.0.0 + Forthcoming | 4.7.1 | mismo contenido que `jazzy` (jazzy = merge de rolling) |
| 2026-10-29 | `feature/native-msg-classes` | — | — | — | **ya no existe**: fusionada en `rolling`/`jazzy` |
| 2026-10-27 | `rolling` | `4d0a8b3` | 3.0.0 | 4.7.1 | base anterior (clases sombra) |
| 2026-10-27 | `jazzy` | `aeb82b3` | 3.0.0 | 4.7.1 | base anterior (clases sombra) |
| 2026-10-27 | `main` | `a773912` | — | — | docs iguales salvo `version.py` (histórica) |
| — | `kilted`, `lyrical` | — | — | — | otras distros |

**Cambios de 3.0.0 (2026-11-04; antes «Forthcoming»; CHANGELOG de `rclgd` y `rclgd_cli`):**
- **Clases tipadas nativas** registradas al cargar desde `res://package.xml` (msg, srv Request/Response,
  action Goal/Result/Feedback y anidados); `from_type` y todo lo recibido devuelven la clase tipada;
  `create_*` aceptan nombre, clase o instancia. Detalle: `mensajes-y-tipos.md` §2.
- **Incompatibles:** desaparecen las clases sombra, el plugin del editor (`plugin.cfg`, `rclgd.gd`) y
  `RosMsg.gen_editor_support`; el conjunto de tipos se fija al cargar (recargar tras cambiar
  dependencias); los juegos exportados necesitan `package.xml` en el filtro de no-recursos; un script
  pasado como tipo ya no se resuelve por `ROS_TYPE_NAME`.
- Campos que chocan con miembros de `RosMsg`/palabras clave no son propiedades (`get_member`).
- La plantilla de `ros2 rclgd create` ya no trae el plugin; `ros2 rclgd doctor` avisa de restos.
- API regenerada (`git diff` de `references/api`): cambian solo `RosMsg` (sin `gen_editor_support`;
  `from_type`/`init`/`get_type_name` redefinidos), `RosNode.create_publisher/subscription` (tipo =
  nombre, clase o instancia) y la descripción de `rclgd` (hilos de servicios/goal).

**Paquete apt `ros-jazzy-rclgd` (comprobado el 2026-11-14 con `apt-cache policy` en una imagen jazzy):** solo hay
**2.1.0** (`2.1.0-3noble.20261006`): **sin clases tipadas nativas ni RosLogger**. Para la API de esta skill hay que
**compilar desde fuente** (receta abajo). El `docker/` de `Ozuba/roomba_ws` instala ese paquete apt: no vale tal cual.

### Compilar rclgd jazzy desde fuente (PC, probado el 2026-11-14)
Clon en `~/Proyectos/rclgd-estudio/rclgd` (rama `jazzy`); `git submodule update --init --depth 1` (trae `godot-cpp`).
Contenedor jazzy de la estación (`psvita-ros-station:jazzy`), fuente en solo lectura, salida en `ws-jazzy/`:
```bash
docker run --rm -v ~/Proyectos/rclgd-estudio/rclgd:/ws/src/rclgd:ro -v ~/Proyectos/rclgd-estudio/ws-jazzy:/ws/out \
  --entrypoint bash psvita-ros-station:jazzy -c 'apt-get update -qq && apt-get install -y -qq build-essential cmake \
  python3-colcon-common-extensions ros-jazzy-ros-babel-fish ros-jazzy-tf2-ros ros-jazzy-rclcpp-action ros-jazzy-ros2launch
  source /opt/ros/jazzy/setup.bash && cd /ws && colcon --log-base out/log build --build-base out/build \
  --install-base out/install --packages-up-to rclgd'          # colcon_rclgd + rclgd_cli + rclgd, ~1 min 20 s
```
CMake descarga Godot **4.7.1** a `ws-jazzy/build/rclgd/godot-engine/`. Pruebas del propio rclgd (45/45):
`bash src/rclgd/rclgd/test/run_tests.sh <godot-4.7.1> out/install/rclgd/lib/rclgd/librclgd.so src/rclgd/rclgd/test/project`
dentro del mismo contenedor con `source out/install/setup.bash` (y `ros-jazzy-ros-babel-fish` instalado).

Cambios relevantes de 3.0.0 (CHANGELOG): `RosLogger` con API de rclpy; clases de fábrica abstractas
(`.new()` falla); corregidos `STATUS_CANCELED=5`/`STATUS_ABORTED=6` de `RosGoalHandle`.

## Procedimiento para actualizar esta skill
```bash
S=skills/rclgd/scripts
$S/rclgd-docs.sh ramas                 # ¿commits nuevos?
$S/rclgd-docs.sh sync jazzy && $S/rclgd-docs.sh version && $S/rclgd-docs.sh cambios 80
$S/rclgd-docs.sh api skills/rclgd/references/api
git diff --stat skills/rclgd/references/api    # qué cambió en la API
```
Luego: actualizar esta tabla, `mensajes-y-tipos.md` si cambian los tipos, `SKILL.md` §1–§3 si cambian
reglas, y en PSVita-ROS `godot/ros2_vita/API_PARITY.md` (paridad con la Vita).
