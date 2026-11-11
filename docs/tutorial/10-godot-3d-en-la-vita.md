# 10 — El modelo 3D en la propia Vita (G7c)

**Hito:** G7c · **Proyecto:** `godot/g7-imu/` · **Antes:** lecciones 08 y 09.

La app de la Vita publica `/vita/imu` **y** dibuja su propio modelo 3D girando con su IMU, sin pasar por ROS.

## Paso 1 — Qué cambió

| Cambio | Dónde | Por qué |
|---|---|---|
| O1 | HUD cada 0,1 s (`HUD_PERIODO`) | rehacer 12 líneas 60 veces/s es trabajo tirado |
| O2 | `ejes` es una `Basis` | convertir = **una** multiplicación (`ejes * v`) |
| O3 | `msg_imu` creado una vez | antes, un `Imu` nuevo cada 33 ms |
| O4 | nivel con aceleración suavizada; `@tool` | la bola ya no salta; el círculo se ve en el editor |
| 3D | `Marco3D` + `Escena` | la Vita **no** dibuja 3D en SubViewport (`rasterizer_scene_gxm_vita.inc:840`): el 3D va a pantalla completa y la cámara se encuadra en `Marco3D` |
| Textos de muestra | `Estado`, `Datos` | ves en el editor cuánto ocupan |

Círculo (botón) = reiniciar la orientación. Línea nueva en el HUD: **FPS**.

## Paso 2 — Compón la interfaz (editor)

```fish
set G toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
$G.gui --editor --path godot/g7-imu
```

Mueve o agranda `Marco3D` (borde azul, solo en el editor): al ejecutar, el modelo se encuadra ahí.

## Reto — filtro F2 con matrices (lectura)

`actualizar()` en `godot/g7-imu/filtro.gd` lo escribió Claude: **explícalo** paso a paso. La idea es la de la lección 09, pero
la orientación es una **matriz** `Basis`, no tres ángulos:

1. **Giro:** `orientacion = orientacion * Basis(eje, angulo)` (por la derecha = en ejes de la Vita).
2. **Corrección:** gira una fracción `(1 − alfa)` desde «arriba medido» hacia «arriba creído».
3. `orthonormalized()` para limpiar el redondeo.

Ventaja: no se rompe con la Vita en vertical (pitch ±90°).

## Paso 3 — Prueba

```fish
$G.gui --path godot/g7-imu -- demo -p agent_ip:=127.0.0.1   # PC: el modelo cabecea
tools/export-vita-vpk.sh godot/g7-imu build/g7-imu.vpk
tools/deploy-vpk-ftp.sh build/g7-imu.vpk 192.168.1.94
```

En la Vita apunta los **FPS** y, en el PC, `docker/vita-ros.sh shell` → `ros2 topic hz /vita/imu`
(debe seguir ≈ 30). Es el primer 3D de Godot en la Vita: es experimental.

## Comprueba que lo entiendes

1. ¿Por qué el giro se multiplica por la **derecha** y no por la izquierda?
2. ¿Por qué la corrección del paso 2 no arregla el yaw?
3. ¿Por qué es seguro reutilizar `msg_imu` (pista: `ros_runtime.cpp:106`)?
4. ¿Qué ventaja tiene `1 − exp(−dt/τ)` frente a un 0,1 fijo?

| Paso | Hecho |
|---|---|
| Componer la interfaz | ☑ |
| Reto F2 (lectura) | ☐ |
| Probar en el PC | ☑ |
| Probar en la Vita (FPS, Hz) | ☑ 59 FPS, 30 Hz |
