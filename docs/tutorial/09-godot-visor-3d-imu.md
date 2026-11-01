# 09 — Visor 3D de la IMU: tu primer suscriptor y un filtro

**Hito:** G7b · **Proyecto:** `godot/g7b-imu3d/` · **Antes:** lección 08.

Un modelo 3D de la Vita, en el PC, gira como la consola real. Aprendes tres cosas: **suscribirte** a un topic,
**cambiar de ejes** (ROS ↔ Godot) y **fusionar sensores** (el reto lo escribes tú).

## Paso 1 — Las piezas

| Archivo | Qué hace |
|---|---|
| `main.tscn` | cámara, luz, suelo y el nodo `Vita` (modelo `assets/PSVita` + ejes rojo/verde/azul) |
| `main.gd` | `create_subscription` a `/vita/imu`, calcula `dt` y gira `Vita` |
| `filtro.gd` | **tu reto:** de aceleración + giro a roll/pitch/yaw |

Claves de `main.gd`:

| Código | Por qué |
|---|---|
| `qos.set_reliability(RosQoS.BEST_EFFORT)` | g7-imu publica *best effort*; un suscriptor *reliable* no recibe nada (y no da error) |
| `_on_imu(m: RosMsg)` | se llama con cada mensaje |
| `dt` con `header.stamp` | reloj de la Vita: la WiFi no lo deforma |
| `ROS_A_GODOT * b_ros * ROS_A_GODOT.transposed()` | la misma rotación en ejes de Godot |

## Paso 2 — Pruébalo (fish, PC)

```fish
docker/vita-ros.sh up
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
$G --headless --path godot/g7-imu -- demo -p agent_ip:=127.0.0.1    # terminal 1: publica falsos
$G.gui --path godot/g7b-imu3d -- -p agent_ip:=127.0.0.1             # terminal 2: el visor
```

- `.gui` es el editor con ventana (el visor necesita pantalla, no `--headless`).
- Con la Vita real: abre g7-imu en la Vita y omite la terminal 1.
- Debe poner «a 30 Hz».
- El modelo `.blend` necesita Blender (Ajustes del editor → Import → Blender) y que el aviso de Blender no desactive la importación.

## Reto (trabajo real)

1. **Filtro complementario** en `filtro.gd → actualizar()`. Las pistas están en el archivo.
   Con el demo, el modelo debe **cabecear** ±29° (rojo sube y baja).
2. **Experimenta con `alfa`:** 1.0 (solo giro), 0.0 (solo acelerómetro), 0.98. Anota qué ves.
3. **Con la Vita:** deja la consola quieta 1 min. ¿Se desvía el yaw? ¿Y roll/pitch? ¿Por qué?

## Comprueba que lo entiendes

1. ¿Qué pasa si quitas la línea de `BEST_EFFORT`? ¿Por qué no sale error?
2. ¿Por qué `dt` se calcula con `header.stamp` y no con `delta` de `_process`?
3. ¿Por qué el acelerómetro no puede dar el yaw?
4. Columna 1 de `ROS_A_GODOT`: ¿por qué `(0, 0, -1)`?

## Para saber más

- REP-103 (ejes) y REP-145 (IMU): <https://www.ros.org/reps/rep-0103.html>
- QoS en ROS 2: <https://docs.ros.org/en/jazzy/Concepts/Intermediate/About-Quality-of-Service-Settings.html>

| Paso | Hecho |
|---|---|
| Leer `main.gd` | ☑ |
| Probar con el demo | ☑ |
| Reto 1 / 2 / 3 | ☑ ☐ ☐ |
| Probar con la Vita | ☑ (2026-11-01) |
