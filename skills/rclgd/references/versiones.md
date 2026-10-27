# Versiones, ramas y cómo detectar cambios

| Fecha de estudio | Rama | Commit | rclgd | Godot fijado | Notas |
|---|---|---|---|---|---|
| 2026-10-27 | `rolling` (por defecto) | `4d0a8b3` | 3.0.0 | 4.7.1 | base de esta skill |
| 2026-10-27 | `jazzy` | `aeb82b3` | 3.0.0 | 4.7.1 | docs y `doc_classes` idénticos a `rolling` |
| 2026-10-27 | `main` | `a773912` | — | — | docs iguales salvo `version.py` (histórica) |
| 2026-10-27 | `feature/native-msg-classes` | `92ef998` | futura | 4.7.1 | **cambio incompatible** (clases nativas) |
| — | `kilted`, `lyrical` | — | — | — | otras distros |

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
