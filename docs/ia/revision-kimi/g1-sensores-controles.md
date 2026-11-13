# g1-sensores: controles y movimiento iguales a g1-unitree (2026-11-13)

Encargo: el usuario observó que `godot/g1-sensores/` (plantillas: `comun/robots/humanoide_g1.gd` sobre
`comun/robots/robot_ros.gd`) no se maneja ni se mueve como `godot/g1-unitree/` (la referencia, validada en la Vita
a 60 FPS). Este documento recoge las diferencias que había (con `archivo:línea` de la versión de `HEAD` 688cc3c),
los cambios hechos y la verificación.

Estado: **hecho y verificado en PC** (local con `-- sin_ros demo`, g1_sim contra `docker/vita-ros.sh g1`).
**Validar en hardware** (Vita): mandos y 60 FPS en g1-sensores; no se ha probado aún en la Vita.

## 1. Diferencias encontradas (antes del cambio)

Referencias: `godot/g1-unitree/main.gd` (REF) y, para g1-sensores, `godot/plantillas/robots/robot_ros.gd` (RR),
`godot/plantillas/robots/humanoide_g1.gd` en `HEAD` (HG) y `godot/plantillas/aplicacion_robot.gd` en `HEAD` (AR).

| Aspecto | g1-unitree (referencia) | g1-sensores (antes) | Efecto |
|---|---|---|---|
| Teclado W/S | `ly = ±0.7` (REF `main.gd:180-181`); Mayús+W = 1,0 (`:184`) | `x = ±1.0` (RR `robot_ros.gd:81-82`) | W siempre pedía 1,0 → clip «correr» en vez de «andar» |
| A/D | **girar** (`lx`, REF `:182-183`) | paso **lateral** (`y`, RR `:83-84`) | mapeo cambiado |
| Q/E y L/R | paso lateral ±0,4 (REF `:186-187`) | **giro** ±1 (RR `:86-88`) | mapeo cambiado |
| Stick izq. ←→ | gira (`wz = lx`, REF `:196`) | paso lateral (`y = -LEFT_X`, RR `:81`) | mapeo cambiado |
| Zona muerta | por eje, 0,25 (REF `:31`, `:194-196`) | módulo del vector < 0,2 (RR `:90`) | deriva del stick sumada a otro eje |
| Atrás | `vx = ly·0,6` (REF `:195`) | `vx = ly` | velocidad atrás distinta |
| Selección de clip | `_clip_para(cmd)` con la orden **sin rampa**, umbrales `> 0` y `> 0,85` (REF `:201-209`, `:219`) | `_clip()` sobre `orden_actual` (orden **rampeada**, RR `:119-120`), umbrales ±0,05 (HG `:42-52`) | el clip cambiaba con retraso respecto al mando |
| Desplazamiento | **root motion**: `marcha.avanzar()` integra el avance grabado del clip y `marcha.pos/yaw` es la pose (REF `:219-224`, `marcha.gd:53-83`) | el avance de `marcha.avanzar()` **se descartaba** (HG `:59`); el cuerpo se movía con la velocidad pedida (`velocity = orden_actual`, `rotation.y += wz·dt`, RR `:125-136`) | pies que patinan: la velocidad del cuerpo no era la del clip (andar ≈ 0,57 m/s con orden 0,5 o 1,0) |
| Mezcla | 0,25 s entre clips (`marcha.gd:11`, `:97-100`) | igual (mismo `marcha.gd`) pero encima la rampa de `aceleracion_max` | doble suavizado |
| Colisión | 2D con la rejilla de la casa (`colision_casa.gd`, `marcha.avanzar(dt, colision.libre)`, REF `:220`) con deslizamiento por ejes (`marcha.gd:73-82`) | cápsula del `CharacterBody3D` con `move_and_slide()` (RR `:136`) | (se mantiene: es el mundo de las plantillas) |
| Cámara | objetivo = pelvis − 0,2 m, 3,2 m, cabeceo 0,45, zoom 1–14 m a 3 m/s, rueda 0,3, cabeceo mín. −0,1, guiñada suavizada τ = 0,6 s (REF `:42-46`, `:326-347`, `:374-379`) | objetivo = origen + `altura_objetivo`, 7 m, 0,5, zoom 2–25 m a 5 m/s, rueda 0,5, cabeceo mín. 0,1, guiñada **rígida** (AR `:39-40`, `:298`, `:302`) | cámara lejana y que se balancea con la marcha |
| Demo | se conduce sola sin ROS (REF `:188-192`) | solo con `ros_listo` (AR `:276`) | `-- sin_ros demo` no se movía |
| ✕ | cambia de modo (marcha/ros/…) (REF `:357-362`) | sin uso | — |

## 2. Cambios

Líneas de la versión nueva (sin commitear). Parte la empezó otro agente (que se paró a medias) y aquí se terminó,
corrigió y verificó.

### 2.1 `godot/plantillas/robots/humanoide_g1.gd`

- **Mapeo de mandos** = g1-unitree: `leer_teleop()` (`humanoide_g1.gd:98`) es copia de `_leer_orden` (REF `:177`),
  con `ZONA_MUERTA := 0.25` (`:28`). Devuelve `Vector3.ZERO` sin entrada, así que el **hombre muerto** de
  `robot_ros.gd:110-118` sigue funcionando.
- **Clip**: `static func _clip_para` (`:118`) es copia literal de REF `:201`, y se le pasa `orden_objetivo` (la orden
  sin rampa), como hace g1-unitree con `cmd`. La rampa de `aceleracion_max` solo la usan ya la batería y la
  telemetría; la suavidad la pone la mezcla de 0,25 s de `marcha.gd`.
- **Root motion + colisión** (`_marcha_local`, `:225`): `_sincronizar_marcha()` (`:244`) copia la pose real del
  cuerpo a `marcha.pos/yaw`; `marcha.avanzar(dt, siempre_libre)` integra el avance del clip; el incremento
  `paso` se convierte en `velocity = paso/dt` y `move_and_slide()` lo recorre y **desliza contra el mundo** de las
  plantillas (equivalente 3D de `colision_casa.libre` + deslizamiento por ejes de `marcha.gd:73-82`).
  `rotation.y = marcha.yaw`. `is_on_wall()` → «[pared]» en el HUD, como `marcha.bloqueado` en REF `:246`.
- **Modelo**: `_aplicar_marcha_al_modelo` (`:254`) le da la altura e inclinación del clip sin la guiñada (la guiñada
  la lleva el `CharacterBody3D`). Índices de piernas precalculados (`_indices_piernas`) en vez de `find()` por tick.
- **Fuente `g1_sim`** (`_preparar_g1_sim` `:163`, `_on_estado_sim` `:186`, `_seguir_g1_sim` `:274`): suscripción a
  `/g1/estado` y publicador de `/cmd_vel` en best effort (como `docker/g1/g1_sim.py`); el estado se aplica en el
  tick de física; `/cmd_vel` a 20 Hz solo mientras hay orden + 5 ceros al soltar (REF publica ceros siempre, lo que
  taparía Nav2 o teleop_twist_keyboard). Anclaje `relativo` (la primera pose cae donde está el G1) o `absoluto`.
  La altura del cuerpo sale de un rayo al suelo de Godot (`_altura_suelo`, `:317`; añadido aquí: sin él los pies
  quedaban hundidos 0,2 m en la tarima de la casa). Velocidades de odometría/IMU derivadas entre estados (25 Hz),
  no por tick (`_actualizar_estado`, `:331`), para no dar 0, 0, pico. En g1_sim se ignoran `/cmd_vel` entrante
  (`:172-183`, si no, se reenviaría a sí mismo) y `LowCmd` (`fijar_motor`, `:402`).
- **✕/Espacio** alterna local ↔ g1_sim (`_unhandled_input`, `:130`; `fijar_fuente`, `:137`, manda un cero a g1_sim al
  salir). Arreglado aquí un error de análisis que dejaba el script sin cargar (`var pulsado :=` con valor sin tipo
  → `var pulsado: bool =`).
- **△/R** (`reiniciar_estado`, `:349`): marcha al fotograma 0, clip «quieto» y re-anclaje de g1_sim.
- **HUD**: `linea_hud()` (`:360`) con la fuente, el clip y «[pared]», o el estado de `/g1/estado`.
- `load("res://marcha.gd")` (no `preload`): ese archivo solo existe en g1-sensores; rbkairos-plus y dron-mapeo
  comparten la carpeta `plantillas/` y con `preload` fallaría su análisis.

### 2.2 `godot/plantillas/aplicacion_robot.gd` (compartido; sin bloque `camara` todo queda igual)

- Bloque opcional `"camara"` de `robot.json` (`_configurar_camara`, `:288`): distancia, cabeceo, límites, zoom,
  rueda, nodo objetivo (p. ej. `pelvis`) con desfase y suavizado de guiñada (`:340`, misma fórmula que REF `:344`).
- `demo` ya no exige `ros_listo` (`:310`): `-- sin_ros demo` mueve el robot (también en rbkairos-plus y dron-mapeo).
- Línea extra del HUD si el robot tiene `linea_hud()` (`:362`).

### 2.3 `godot/g1-sensores/robot.json`, `README.md` y prueba

- `robot.json`: `fuente_movimiento`, `g1_sim_topic_estado`, `g1_sim_topic_cmd`, `g1_sim_anclaje` y
  `camara` = la de g1-unitree (pelvis − 0,2 m, 3,2 m, 0,45 rad, 1–14 m, 3 m/s, rueda 0,3, cabeceo mín. −0,1, τ 0,6 s).
- `README.md`: tabla de mandos, demo, sección «Fuente de movimiento» (local = Godot es la planta; g1_sim =
  `docker/vita-ros.sh g1` es la planta y g1-sensores añade sensores) y aviso de `/cmd_vel` con dos apps.
- `godot/g1-sensores/pruebas/movimiento_g1.gd` (nuevo): prueba headless de regresión.

### 2.4 Diferencias que se mantienen a propósito

- Colisión 3D con cápsula (`radio_colision` 0,28) en vez de la rejilla 2D de la casa: el mundo de las plantillas
  no tiene `colision_casa`. El G1 puede subir escalones bajos (la tarima de 0,2 m) por la forma de la cápsula.
- Tick de física (60 Hz) en vez de `_process`: el `CharacterBody3D` debe moverse en física.
- ○ cenital: vista del mundo de las plantillas, no de la casa de g1-unitree.
- En g1_sim el G1 atraviesa las paredes de Godot: la planta es MuJoCo, con su propia casa.
- Velocidades: `velocidad_max` [1,0, 0,4, 1,0] solo recorta órdenes externas; la velocidad real es la del clip
  (andar ≈ 0,57 m/s, igual que en g1-unitree), como en el robot real con la política de Unitree.

## 3. Verificación (PC CachyOS, 2026-11-13)

| Prueba | Resultado |
|---|---|
| `runner.gd` g1-sensores / rbkairos-plus / dron-mapeo | **14/14, 12/12, 12/12** (igual que antes) |
| `--script res://pruebas/movimiento_g1.gd -- sin_ros` (g1-sensores) | **0 fallos**: W=0,7, A/D giran, Q lateral 0,4, Mayús+W=1; `_clip_para`; 3 s de «andar» = 1,704 m frente a 1,693 m de `marcha.gd` de referencia; giro 2 s = +1,48 rad; emergencia → «quieto»; pared a 1,2 m → se queda a 0,72 m y «[pared]»; g1_sim simulado: anclaje, +1 m relativo al rumbo, yaw +0,5, rodilla |
| Captura `-- sin_ros demo fotograma=300` (PC) y `lod=vita fotograma=600` | G1 andando y girando, cámara detrás a 3,2 m, HUD «clip andar» / «clip girar_izq», 60 FPS |
| Capturas demo rbkairos-plus y dron-mapeo | sin errores; ahora la demo se mueve sin ROS |
| g1_sim real: `docker/vita-ros.sh g1` + `config=` con `"fuente_movimiento": "g1_sim"` + `demo` | sesión XRCE OK; `/g1/estado` a 25 Hz; Godot publica `/cmd_vel` (p. ej. `angular.z 0.5`) y g1_sim se mueve (x 5,30 → 4,70, yaw cambia); `/g1s/odom` publica la pose anclada (11,35, −17,27, 0,78 = pelvis); HUD «/g1/estado recibidos: 171», G1 sobre la tarima (z 0,2). Contenedor parado con `docker stop vita_g1sim` |

Pendiente: validar en la Vita (mandos físicos, ✕ y 60 FPS con la marcha en el tick de física).
