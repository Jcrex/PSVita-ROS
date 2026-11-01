# 08 — La IMU de la Vita en ROS 2 (G7a)

**Qué haces:** publicar el acelerómetro y el giroscopio de la Vita en `/vita/imu`.
Proyecto: `godot/g7-imu/`.

## Idea en 4 líneas

- `Input.get_accelerometer()` y `get_gyroscope()` leen el sensor en cada fotograma.
- Se convierten a m/s² y rad/s y se reordenan los ejes (x delante, y izquierda, z arriba).
- Un timer los publica a 30 Hz como `sensor_msgs/Imu`, en modo *best effort*.
- Sin orientación: `orientation_covariance[0] = -1` (convención de ROS).

## Paso 1 — Ábrelo en Godot

```bash
toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64.gui --editor --path godot/g7-imu
```

Mira el árbol `Main` → `Estado`, `Datos`, `Nivel`. Abre `main.gd`.

## Paso 2 — Lee `main.gd` (las 5 piezas clave)

| Código | Qué significa |
|---|---|
| `@onready var x = $Estado` | coge el nodo hijo «Estado» |
| `var pub_imu` fuera de funciones | si fuera local, Godot lo borraría y no publicaría |
| `declare_parameter("hz", 30.0)` | se cambia al arrancar: `-p hz:=50` |
| `create_timer(1.0 / hz, _publicar)` | llama a `_publicar` periódicamente |
| `m.orientation_covariance = PackedFloat64Array(...)` | los arrays se asignan enteros |

## Paso 3 — Pruébalo en el PC

```bash
docker/vita-ros.sh up                                   # agente + ROS 2
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64   # fish (en zsh: G=...)
$G --headless --path godot/g7-imu -- demo -p agent_ip:=127.0.0.1
```

En otra terminal, `docker/vita-ros.sh shell` y luego:

```bash
ros2 topic list -t                  # ¿aparece /vita/imu?
ros2 topic hz /vita/imu             # ≈30
ros2 topic echo /vita/imu --once
```

`demo` inventa datos; todo lo que va tras `--` es para el juego.

## Paso 4 — Llévalo a la Vita

```bash
tools/export-vita-vpk.sh godot/g7-imu build/g7-imu.vpk
tools/deploy-vpk-ftp.sh build/g7-imu.vpk 192.168.1.94
```

Instala con VitaShell, ábrelo y en el PC: `docker/vita-ros.sh echo /vita/imu`.

## Retos (trabajo real pendiente)

1. **Unidades.** Vita quieta: si `|a|` ≈ 1,0, el sensor da g (está bien). Si ≈ 9,8, usa `-p escala_acel:=1.0`.
2. **Ejes.** Plana con la pantalla arriba: `z` ≈ +9,8. Levanta el borde delantero: `x` ≈ +9,8. Si no, prueba `-p ejes:=-y,x,z` hasta acertar.
3. **Código tuyo.** Publica los botones en `/vita/joy` (`sensor_msgs/Joy`).

## Comprueba que lo entiendes

1. ¿Por qué `pub_imu` no puede ser una variable local?
2. ¿Por qué *best effort* para un sensor?
3. ¿Qué tres cosas miras si `/vita/imu` no aparece?

| Paso | Hecho |
|---|---|
| Abrir en el editor | ☑ |
| Probar en el PC | ☑ |
| Probar en la Vita | ☑ (2026-10-31) |
| Retos 1 / 2 / 3 | ☐ ☐ ☐ |
