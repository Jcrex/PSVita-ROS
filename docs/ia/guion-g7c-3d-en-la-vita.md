# Guion (para Claude): G7c — modelo 3D y animación en la propia Vita

Preparado el 2026-11-01 al cerrar G7a/G7b (commits `34a25d9`, `3ddb572`). Lección para el usuario a
escribir al hacerlo: `docs/tutorial/10-…` (≤ 500 palabras). Seguir el modo aprendizaje (CLAUDE.md).

## Punto de partida (verificado)

- `godot/g7-imu/` corre en la Vita y publica `/vita/imu` **calibrado**: `escala_acel = -G`,
  `ejes = "y,-x,z"` (ejes de Sony x derecha / y gatillos / z fuera de pantalla; el acelerómetro da la
  gravedad). Demo en ejes de Sony (`main.gd`, `_process`).
- `godot/g7b-imu3d/` (PC) dibuja `assets/PSVita/PSVita.blend` (escala 0,2, rot X −90°) girando con
  `filtro.gd` (complementario, escrito por el usuario). Conversión ROS→Godot: `ROS_A_GODOT`
  (`g7b-imu3d/main.gd:27`) y `vita.basis = ROS_A_GODOT * b_ros * ROS_A_GODOT.transposed()`.
- El `.blend` se importa con Blender (`/usr/bin/blender`, ajuste del editor). El export a `.vpk` corre en el
  PC, donde está Blender; el `.vpk` lleva la escena ya importada (Blender no hace falta en la Vita).

## Objetivo

La app de la Vita (`g7-imu`) muestra, **además** de publicar, el modelo 3D girando con su propia IMU
(sin pasar por ROS: filtro local), y el nivel de burbuja pasa abajo a la izquierda y más pequeño.

## Riesgo principal: primer 3D de Godot 4 en la Vita

`docs/18-migracion-a-godot4.md:51`: el 3D GXM del port es **experimental** (iluminación por vértice,
sin sombras/niebla/post-proceso/shaders propios, ~30 FPS en OVERBURDEN). Riesgo R1 (§9) aconsejaba «solo
la ruta GXM 2D». G7c es la primera escena 3D nuestra en hardware ⇒ tratarlo como **puerta**: medir FPS
(`Engine.get_frames_per_second()` en el HUD) y que `/vita/imu` siga a ~30 Hz (`ros2 topic hz`).
Plan B si no rinde: dibujar el modelo «falso 3D» en 2D (proyección propia en `_draw`) o una caja simple.

## Decisiones para el usuario (explicar antes de programar)

| # | Decisión | Recomendación | Por qué |
|---|---|---|---|
| D1 | ¿En `g7-imu` o proyecto nuevo `g7c`? | `g7-imu` | una sola app en la Vita; `g7-imu` ya publica |
| D2 | `filtro.gd`: ¿copia? | copiar a `g7-imu/` | `res://` no sale del proyecto; anotar en ambos «copia de …» |
| D3 | Modelo: ¿copiar `assets/PSVita` (1,5 MB)? | copiar solo `.blend` + `.import` + licencia (+ PNG si el `.blend` los referencia) | el `.scn` importado no referencia PNG (verificado con `strings`) |
| D4 | Cómo repartir pantalla | 3D a pantalla completa con `Camera3D.h_offset` para desplazar el modelo a la derecha; HUD en `CanvasLayer` | evita un `SubViewport` (otra pasada de render en una GPU débil; hipótesis de coste) |
| D5 | Bola del nivel «a saltos» (`basicOrientation` vale −1/0/1) | dar al nivel `acel_ros` filtrada en vez de `grav_cruda` | reto pendiente de la lección 08 (`guion-leccion-08-imu.md`) |

## Maquetación propuesta (960×544)

| Elemento | Ahora (`g7-imu/main.tscn`) | Propuesta |
|---|---|---|
| `Estado` | 16,10 → 944,62 | igual |
| `Datos` | 16,72 → 600,500 (fuente 16) | 16,72 → 440,340 (fuente 14) |
| `Nivel` | 620,110 → 940,430 (320 px) | **16,352 → 166,502 (150 px)**, abajo a la izquierda |
| Modelo 3D | — | mitad derecha (cámara con `h_offset`) |
| `Ayuda` | 16,512 → 944,540 | igual; añadir «R/△: reiniciar orientación» si se usa otro botón (△ ya es la tara) |

`nivel.gd` dibuja con `size`, así que encoger el `Control` basta (radio = min(size)/2 − 4); bajar el
radio de la bola (14 px) a ~8 px y el texto (14) a ~11.

## Pasos (orden)

1. D1–D5 con el usuario. 2. Escena: raíz sigue siendo `Control` → mejor raíz `Node3D` con `CanvasLayer`
para el HUD actual (mover `Estado/Datos/Nivel/Ayuda` dentro) — **lo compone el usuario en el editor** y
Claude revisa el `.tscn`. 3. `main.gd`: instanciar `Filtro`, llamar `filtro.actualizar(acel_ros,
giro_ros, delta)` en `_process` (dt = `delta`, aquí no hay red) y girar el nodo `Vita` como en
`g7b-imu3d/main.gd:107-115` (reto del usuario: copiar y entender). 4. Probar en el PC con `-- demo`.
5. Exportar/desplegar (`tools/export-vita-vpk.sh godot/g7-imu build/g7-imu.vpk`,
`tools/deploy-vpk-ftp.sh build/g7-imu.vpk 192.168.1.94`). 6. Medir FPS y Hz; anotar en docs/18 §8 (G7).

## Ideas después

- Publicar `SceMotionState.deviceQuat` (`psp2/motion.h:46`) en `orientation` y comparar con el filtro
  (requiere tocar `display_server_vita.cpp` o exponerlo desde el módulo).
- Zona muerta del giroscopio (`sceMotionSetDeadband`, hipótesis).
- Reto 3 de la lección 08: `/vita/joy`; luego panel trasero y ADR de la cámara.
