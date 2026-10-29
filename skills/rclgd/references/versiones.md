# Versiones, ramas y cómo detectar cambios

| Fecha de estudio | Rama | Commit | rclgd | Godot fijado | Notas |
|---|---|---|---|---|---|
| 2026-10-29 | **`jazzy`** | **`fb12a65`** | 3.0.0 + Forthcoming | 4.7.1 | **base actual de esta skill**: incluye las **clases tipadas nativas** (`d31b4f1`) y la doc revisada (`bfbda5c`) |
| 2026-10-29 | `rolling` (por defecto) | `bfbda5c` | 3.0.0 + Forthcoming | 4.7.1 | mismo contenido que `jazzy` (jazzy = merge de rolling) |
| 2026-10-29 | `feature/native-msg-classes` | — | — | — | **ya no existe**: fusionada en `rolling`/`jazzy` |
| 2026-10-27 | `rolling` | `4d0a8b3` | 3.0.0 | 4.7.1 | base anterior (clases sombra) |
| 2026-10-27 | `jazzy` | `aeb82b3` | 3.0.0 | 4.7.1 | base anterior (clases sombra) |
| 2026-10-27 | `main` | `a773912` | — | — | docs iguales salvo `version.py` (histórica) |
| — | `kilted`, `lyrical` | — | — | — | otras distros |

**Cambios «Forthcoming» (en la fuente, aún sin versión publicada; CHANGELOG de `rclgd` y `rclgd_cli`):**
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

**Paquete apt `ros-jazzy-rclgd` 3.0.0:** sigue siendo el sistema de clases sombra hasta que salga una
versión nueva; comprobar qué hay instalado antes de aplicar §2 de `mensajes-y-tipos.md`.

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
