# W13 · Borrador de `hmi-percepcion-acciones` (ronda 1, 2026-11-13)

> Investigador: `hmi-percepcion-acciones` (Opus 5.5). Fichas completas (20) en
> `W13-hmi-percepcion-acciones.json`. Este borrador las resume y deja las decisiones de diseño razonadas.
> Leyenda: [V] verificado en código/docs · [I] inferencia · [?] sin comprobar.

## 0. Resumen y decisiones

1. **Un kit de widgets HUD.** Todos los tipos de estado (Joy, batería, ambientales, diagnósticos, `/rosout`,
   lifecycle, estado de controlador y metas de Nav2) se pintan con un `Control` y su `_draw()`. Heredan de una
   base común `widget_hud.gd`, que:
   - suscribe por texto,
   - redibuja solo si llegó algo, a ≤ 10 Hz,
   - pinta en gris lo caducado.

   El mismo `.gd` corre en el PC (rclgd) y en la Vita (ros2_vita). Usa tipos por texto y `RosMsg` dinámico
   (API_PARITY.md:67-69) [V].
2. **Texto siempre en 2D** (docs/31 §2.4) [V]. Las cajas 3D de `Detection3DArray` también van en 2D: 12 aristas
   proyectadas con una sola `draw_multiline` (H17). Así el código es idéntico en el PC y en la Vita, que no tiene
   líneas 3D sin shaders.
3. **HUD de la Vita = barra fija + un panel grande cada vez.** El presupuesto es de ≈ 1 500 quads 2D por
   fotograma, de los que el HUD tiene 400 (docs/31:255). En la Vita el lienzo vuelve a emitir todos los quads en
   cada fotograma (H16) [V]. Cuentas aproximadas:
   - la consola de 10 líneas cuesta ≈ 600 quads y la tabla de diagnósticos de 12 filas ≈ 500 [I];
   - por eso no pueden estar las dos a la vez;
   - se alternan con pestañas (SELECT o un toque en la pestaña).
4. **QoS: las herramientas que publican van fiables.** `/goal_pose`, `/initialpose`, `/clicked_point` y
   `/cmd_vel` usan la QoS por defecto, que es fiable. Los suscriptores de Nav2, AMCL y turtlesim son fiables, y
   un publicador best effort no casaría con ellos (tabla de compatibilidad de QoS de ROS 2). Los widgets
   suscriben en best effort cuando el mensaje cabe en 488 B, y en fiable cuando no cabe o se publica por eventos.
5. **Cuatro módulos nuevos para `vita_relay`** (propuestos, sin implementar) [I]: `rosout`, `diag`, `det2d` y
   `det3d` (§5). El resto de tipos de la familia cabe tal cual en la Vita.
6. **Acciones.** Se siguen los niveles de ADR 0012 sin cambios:
   - nivel 0 (topics ocultos `_action/status` y `_action/feedback`) para mostrar el estado;
   - nivel 1 (puente VAB/1) para cancelar y para robots reales;
   - en el PC, opcionalmente, `RosActionClient`.
7. **Hallazgo de la comprobación (`--check-only`).** `m.reference` en `JointTrajectoryControllerState` **no**
   devuelve el campo. GDScript lo resuelve como el método `RefCounted.reference()` y el analizador falla. Hay que
   usar `m.get_member("reference")` [V].
   - Es la regla de los campos que chocan con miembros (API_PARITY.md:63), pero aquí el choque es con
     `RefCounted`, no con `RosMsg`.
   - Conviene revisar la lista de choques en ambos runtimes (§7).

Los 20 bloques de `codigo` pasan `--check-only` con el editor 4.8-dev7 del repo
(`toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64`, que trae el módulo ros2_vita) [V]. La
comprobación es contra la API de ros2_vita. La de rclgd se ha cotejado con `skills/rclgd/references/api/` y no se
ha compilado contra rclgd.

## 1. Tamaños CDR medidos (rosbags, ROS2_JAZZY, contenido representativo) [V]

Calculados con `toolchains/rosbags-venv`. Los `.msg` de vision_msgs se bajaron de la rama `ros2` y se registraron
a mano, porque no están en el typestore. Los dos casos que ya estaban en el doc 32 coinciden: GoalStatusArray
(33 y 453 B) y PoseStamped (76 B).

| Mensaje | CDR (B) | ¿BE ≤ 488? |
|---|---:|:-:|
| Joy (8 ejes, 17 botones) | 128 | sí |
| BatteryState (sin celdas / 6 celdas) | 89 / 133 | sí |
| Temperature, FluidPressure, Illuminance, RelativeHumidity | 44 | sí |
| DiagnosticArray 1 estado / 1×3 KV / 5×3 / 20×4 | 76 / 157 / 685 / 3 225 | solo 1–2 estados |
| Log (msg de 40 / 120 / 300 car., con file y function) | 180 / 260 / 440 | casi siempre |
| Log de 40 car. sin file ni function | 108 | sí |
| TransitionEvent | 65 | sí |
| Detection2DArray 1 / 3 / 10 det. (1 hipótesis) | 481 / 1 377 / 4 513 | solo 1 (justo) |
| Detection3DArray 1 / 3 / 10 det. | 489 / 1 433 / 4 737 | **no** (1 B de más) |
| JointTrajectory 6 j × 1 p / 6×10 / 7×50 (pos+vel) | 228 / 1 380 / 7 308 | solo 1 punto |
| JointTrajectoryControllerState 7 / 14 juntas | 1 340 / 2 404 | no |
| GoalStatusArray 1 / 16 metas | 33 / 453 | sí |
| PoseWithCovarianceStamped (`initialpose`) | 364 | sí |
| PoseStamped (`goal_pose`) / PointStamped (`clicked_point`) | 76 / 44 | sí |

La sorpresa está en `vision_msgs`. Cada `ObjectHypothesisWithPose` arrastra una `PoseWithCovariance` (288 B), así
que una sola detección 2D ya roza el límite.

## 2. Tabla tipo → widget (PC / Vita)

| Tipo | Equivalente | Widget PC (rclgd) | Vita (ros2_vita) | Transporte a la Vita |
|---|---|---|---|---|
| `sensor_msgs/Joy` | Foxglove Teleop | `joy.gd`: 2 sticks + fila de botones (HUD) | igual; además **fuente** `/vita/joy` desde `Input` | BE directo, 20 Hz |
| `BatteryState` | Foxglove Gauge/Indicator | `bateria_hud.gd`: icono con relleno, rojo si la salud es mala o < 20 % | igual, en la barra fija | BE directo, ≤ 1 Hz |
| `Temperature` / `FluidPressure` / `Illuminance` / `RelativeHumidity` | Gauge + Plot | `medidor.gd`: barra con umbrales + valor + sparkline (1 polilínea) | igual | BE directo; añadir 3 esquemas |
| `DiagnosticArray` | rqt_robot_monitor, Foxglove Diagnostics | tabla con color por nivel, peores arriba, STALE a 10 s (PC: o `Tree`) | igual, en el panel de detalle | fiable 1 Hz (≤ 7,5 KiB) o relay `diag` |
| `rcl_interfaces/Log` | rqt_console, Foxglove Log | consola de N líneas, filtro por nivel y nodo, pausa (PC: o `RichTextLabel`) | igual, en el panel de detalle | relay `rosout` (≥ WARN, recortado) |
| `TransitionEvent` | Foxglove State Transitions | fila de estado por nodo gestionado | igual; sin estado inicial (no hay servicios) | fiable directo |
| `Detection2DArray` / `BoundingBox2D` | Foxglove Image + anotaciones | rectángulos sobre el `TextureRect` de la cámara | igual, leyendo el compacto | relay `det2d` (n ≤ 19) |
| `Detection3DArray` / `BoundingBox3D` | vision_msgs_rviz_plugins [I] | aristas proyectadas al HUD (o `ImmediateMesh` de líneas en PC) | aristas proyectadas | relay `det3d` (n ≤ 13) o fiable ≤ 5 Hz |
| `JointTrajectory` | MoveIt Planned Path | fantasma: 2.ª instancia del robot en bucle según `time_from_start` | igual, con color plano (sin orden de transparencias); en el G1 solo el brazo | 1 punto BE; plan por el puente `/vita/accion/trayectoria` (≤ 32 p) |
| `JointTrajectoryControllerState` | rqt_joint_trajectory_controller / Plot | barras: real, referencia, \|error\| | igual | fiable ≤ 5 Hz |
| `nav_msgs/Path` plan frente a ejecutado | RViz Path ×2 + rastro | 2 polilíneas en planta (plan verde, rastro azul) | igual con `/vita/path_compacto` + `/vita/pose2d` | relay ya existente |
| `GoalStatusArray` + feedback de `NavigateToPose` | panel Nav2 de nav2_rviz_plugins | línea de estado: fase, distancia, ETA, recuperaciones | igual (nivel 0) o `/vita/accion/estado` (nivel 1) | BE/fiable directo; feedback hasta ~100/s ⇒ mejor el nivel 1 |

Notas por tipo:

- **Joy.** El eje Y de Godot es positivo hacia abajo (`g6-hmi/main.gd:85-86`). Al publicar `/vita/joy` hay que
  negar los ejes para seguir la convención de `joy`, en la que arriba e izquierda son +1 [I].
- **Lifecycle.** En el PC, el estado inicial se pide con `create_client` sobre `<nodo>/get_state`. En la Vita
  sale del proxy `srv` del puente (docs/32 §12).
- **Path.** El plan va en `map` y `/odom` en `odom`. Para que el rastro case con el plan, debe venir de
  `/vita/pose2d` calculado con TF map→base, o de un listener TF en el PC.
- **Fantasma.** En la Vita duplica los *draws* del robot (≤ 40 + 40, docs/31 §3) [I]. En el G1 solo se dibuja la
  cadena del brazo, o un botón alterna entre el robot y el fantasma.

## 3. Kit de widgets HUD reutilizables

| Archivo propuesto (`plantillas/comun/hmi/`) | Base | Sirve para | Quads aprox. [I] |
|---|---|---|---|
| `widget_hud.gd` | `Control` | base: topic, tipo, QoS, `_recibir()`, caducidad, redibujo ≤ `hz_dibujo` | 0 |
| `medidor.gd` | widget_hud | cualquier float con unidades: los 4 ambientales, y también Range y voltajes | 15–70 |
| `bateria_hud.gd` | widget_hud | BatteryState | ≈ 40 |
| `joy.gd` | widget_hud | Joy (visor) | ≈ 70 |
| `tabla_diagnostico.gd` | widget_hud | DiagnosticArray, con filtro «solo problemas» | ≈ 500 (12 filas) |
| `consola_log.gd` | widget_hud | `/rosout` | ≈ 600 (10 líneas) |
| `fila_lifecycle.gd` | widget_hud | TransitionEvent (una fila por nodo) | ≈ 40 |
| `estado_meta.gd` | widget_hud | GoalStatusArray + feedback de Nav2 | ≈ 50 |
| `panel_controlador.gd` | widget_hud | JointTrajectoryControllerState | ≈ 320 (14 juntas) |
| `cajas_2d.gd` | widget_hud | Detection2DArray sobre la imagen | ≈ 14 por caja |
| `cajas_3d.gd` | widget_hud | Detection3DArray proyectado | 1 comando (`draw_multiline`) |
| `plan_vs_real.gd` | `Node2D` | Path + rastro en la vista de planta | 2 polilíneas |
| `fantasma_trayectoria.gd` | `Node3D` | JointTrajectory | 3D: robot ×2 |

Reglas comunes:

- Colores de estado de rqt_robot_monitor:
  - OK (85, 178, 76);
  - WARN (222, 213, 17);
  - ERROR (178, 23, 46);
  - STALE (40, 23, 176).

  Fuente: `util_robot_monitor.py:48-54` [V]. Se reutilizan en batería, medidores, lifecycle y metas para que el
  operador lea un único código de color.
- Caducidad por widget: 2 s por defecto, 15 s en la batería y 10 s por fila en diagnósticos (como rqt,
  `timeline.py:161-163`) [V]. Los widgets de eventos (lifecycle, status de acción, `/rosout`) no caducan.
- Líneas con ancho −1 (finas, un comando, H17). El texto con `draw_string` y `get_theme_default_font()`, en 2D.
- **Distribución en la Vita (960×544)**, como decisión de diseño:
  - barra superior fija de 24 px: batería, enlace (`get_transport_info`), estado de meta y herramienta activa;
    unos 150 quads;
  - panel de detalle a la derecha de 320×496 px, con una sola pestaña visible: Diagnóstico, Consola,
    Controlador o Sensores (medidores);
  - el resto de la pantalla es la vista 3D o la de planta.

  En el PC se puede mostrar todo a la vez.

## 4. Herramientas que publican y su mapeo a los controles de la Vita

RViz publica con `rclcpp::QoS(5)`, que es KEEP_LAST 5, fiable y volátil. Siempre pone `header.frame_id` igual al
frame fijo y el sello `clock->now()` (código de rviz_default_plugins, rama jazzy) [V].

| Herramienta RViz | Mensaje / topic | Gesto en RViz | PC (Godot) | Vita |
|---|---|---|---|---|
| **2D Pose Estimate** | `PoseWithCovarianceStamped` → `initialpose` (364 B); cov. x = y = 0,25, yaw = (π/12)² en [0], [7], [35] | pulsar = posición, arrastrar = rumbo, soltar = publicar | `herramienta_pose.gd` (subclase): rayo de cámara contra el plano del suelo de `marco_fijo` | toque delantero = ratón; flecha fantasma en el HUD; **✕ confirma** |
| **Nav2 Goal** | `PoseStamped` → `goal_pose` (relativo, 76 B) | igual | `herramienta_pose.gd` | igual; meta «pendiente» en naranja hasta ✕ |
| **Publish Point** | `PointStamped` → `/clicked_point` (44 B); «Single click» = true | clic sobre un objeto, publica al soltar | rayo de física contra las colisiones del mundo editable (docs/35); si falla, el suelo | toque; tras publicar vuelve a la herramienta anterior |
| **Teleop** (Foxglove Teleop / rqt_robot_steering) | `Twist` → `/cmd_vel` (52 B) | botones o arrastre | flechas + Mayús como hombre muerto | stick izq. + **R mantenido**; △/✕ escala (g6-hmi); en robots reales, `/vita/mando` + puerta en el PC (ADR 0012) |

Mapeo de controles de la Vita [decisión de diseño]:

- **SELECT** recorre las herramientas: Teleop → Meta → Pose inicial → Punto. El nombre de la activa se ve en la
  barra fija.
- **START** abre y cierra el panel de detalle. Las pestañas cambian con L + cruceta o tocándolas.
- **Táctil delantero.** Sirve para las herramientas de pose y punto. Llega como ratón por
  `emulate_mouse_from_touch` [I]: hay que comprobar en el arranque que un toque no produce dos eventos. Mientras
  no exista el panel trasero, el giro de la cámara orbital va en el stick derecho.
- **Panel trasero.** No está disponible: el port solo lee el táctil delantero, aunque `sceTouchPeek` ya está en el
  cargador (docs/28:59). Cuando exista, se usará para orbitar y hacer zoom, y el táctil delantero quedará libre
  para las herramientas.
- **Sin táctil** (por ejemplo, con mando externo): un cursor en el plano movido con el stick derecho, rumbo con
  L/R y ✕ para publicar.
- **Confirmación con ✕ en la Vita** para la meta y la pose inicial. Una consola de mano se roza con facilidad, y
  una meta de Nav2 mueve el robot.

Sello de tiempo: `nodo.now()` en ambos runtimes, porque en la Vita ya es la hora del agente (API_PARITY.md:31)
[V]. Si `uxr_sync_session` fallara, el sello 0 significa «último» en tf2 (docs/32:41) [I].

## 5. Módulos propuestos para `vita_relay` (contrato ≤ 488 B) [I]

| Módulo | Entrada | Salida | Formato | Hz |
|---|---|---|---|---|
| `rosout` | `/rosout` (Log) | `/vita/rosout` (**mismo tipo Log**, BE) | solo nivel ≥ WARN; `file` y `function` vacíos; `msg` recortado a 200 caracteres (≈ 270 B como máximo) | ≤ 20 msg/s |
| `diag` | `/diagnostics_agg` | `/vita/diagnostics` (DiagnosticArray de **1 estado**, BE) | 3 KV como máximo, textos ≤ 40 car. (≈ 160 B); solo los que cambian + refresco 1 Hz por estado | ≤ 20 msg/s |
| `det2d` | Detection2DArray | `/vita/detecciones` Float32MultiArray | `[seq, ancho_img, alto_img, n, (clase, score, cx, cy, w, h)×n]`, n ≤ 19; nombres en `/vita/det_clases` (String fiable + TRANSIENT_LOCAL) | 5 |
| `det3d` | Detection3DArray | `/vita/detecciones3d` Float32MultiArray | `[seq, n, (clase, score, x, y, z, yaw, sx, sy, sz)×n]`, n ≤ 13 | 5 |

En `rosout` y `diag` se conserva el tipo estándar a propósito: así el widget no cambia y solo cambia el topic.
Los diagnósticos pequeños (≤ 7,5 KiB a 1 Hz) pueden ir directos en fiable sin relay.

## 6. Coste y medida en hardware (resumen)

Lo que hay que leer en los logs:

- `[gxm2d-canvas] avg_canvas_us` (H18);
- `[gxm2d-perf] quads=`;
- los FPS;
- `get_transport_info()`: `be_dropped`, `reliable_dropped` y `read_packets`.

Criterio general de verde: FPS ≥ 55 con el perfil ligero (docs/34) y `avg_canvas_us` ≤ 3 000 (docs/31 E-W8-6).
Pruebas concretas por ficha en el JSON. Las de más riesgo:

1. Consola o tabla de diagnósticos en la pestaña visible con 20 msg/s: comprobar los quads y los FPS.
2. `Detection3DArray` con 13 cajas y la cámara orbitando: la reproyección cuesta ≈ 1–1,5 ms por fotograma [I].
3. Fantasma del brazo junto al robot: anotar `[gxm3d] drawn=`.
4. Feedback de Nav2 en el nivel 0: comprobar que `read_packets` < 200/s (docs/32 §3).

Comandos (PC, fish): `docker/vita-ros.sh up`, `tools/deploy-vpk-ftp.sh`, y `docker/vita-ros.sh relay rosout,diag`
cuando existan esos módulos.

## 7. Huecos

| Hueco | Impacto | Salida propuesta |
|---|---|---|
| `RosLogger` / `get_logger` sin registrar en ros2_vita (API_PARITY.md:20, 39, 85) | la Vita no escribe en `/rosout`; los scripts con `get_logger()` no compilan en la Vita | implementarlo sobre un publicador `rcl_interfaces/msg/Log` (BE, ≤ 488 B, recortando el texto) + `print`; esquema de Log |
| Servicios (`create_client`) ⏳ | sin estado inicial de lifecycle, sin `get_state`, sin `ServoCommandType` | proxy `srv` del puente (docs/32 §12); nivel 2 aplazado |
| Acciones ⏳ (ADR 0012) | sin cancelar ni ver el resultado y el `error_code` de Nav2 en el nivel 0 | puente `accion_nav` (VAB/1) |
| Panel trasero sin parche (docs/28:59) | el táctil delantero se reparte entre herramientas y cámara | parche `display_server_vita.cpp` (T1.4.2) |
| Esquemas `.rsch` que faltan | Temperature, Illuminance, RelativeHumidity, DiagnosticArray, Log, TransitionEvent, GoalStatusArray, PointStamped, PoseWithCovarianceStamped, `vision_msgs/*` (registrar los `.msg` como control_msgs) y `NavigateToPose_FeedbackMessage` | ampliar `TIPOS` en `godot/plantillas/generar_esquemas.py:12-39` |
| Tipo `pkg/action/X_FeedbackMessage` por texto | [?] no se sabe si rclgd y ros2_vita resuelven ese nombre en una suscripción normal | probarlo en el host con `transport:=loopback` y en el PC con rclgd |
| Choques de nombres con `Object`/`RefCounted` (`reference`, y posiblemente otros como `free`, `notification`, `get`, `set`) | `m.reference` falla en el análisis (comprobado) | documentar la lista en la skill rclgd y en API_PARITY; usar siempre `get_member` en esos campos |
| Conversión de `byte` escalar (DiagnosticStatus.level) | [I] llega como int en ambos runtimes | `int(...)` defensivo en el widget (ya hecho); test de host |
| Emulación de ratón desde táctil en el port | [I] posibles eventos duplicados o ausentes | prueba G: un toque = un `InputEventMouseButton` |
| Joy desde la Vita (`/vita/joy`) | pendiente desde G7c | publicador sencillo; negar los ejes de Godot |

## 8. Fuentes principales

- RViz2 (jazzy): `rviz_default_plugins/src/rviz_default_plugins/tools/{goal_pose/goal_tool.cpp,
  pose_estimate/initial_pose_tool.cpp, point/point_tool.cpp, pose/pose_tool.cpp}`.
- rcl: `rcl/include/rcl/logging_rosout.h:37-48` (QoS de `/rosout`).
- rqt_robot_monitor (ros2): `util_robot_monitor.py:48-54`, `timeline.py:161-163`.
- Definiciones de mensajes:
  - `ros2/common_interfaces` (jazzy): Joy, BatteryState, Temperature, Illuminance, RelativeHumidity,
    DiagnosticStatus;
  - `ros2/rcl_interfaces` (jazzy): Log, State, TransitionEvent, GoalStatus;
  - `ros-perception/vision_msgs` (ros2);
  - `navigation2` (jazzy): `NavigateToPose.action`.
- Foxglove: lista de paneles (Diagnostics, Gauge, Indicator, Log, Teleop, Image, State Transitions…) en
  docs.foxglove.dev.
- Repositorio:
  - `godot/ros2_vita/API_PARITY.md`;
  - `docs/27`, `docs/28:59`, `docs/31` (H16–H18, §3, §5.3), `docs/32` §3–§12, ADR 0012;
  - `godot/g6-hmi/main.gd`;
  - `godot/plantillas/sensores/{bateria,barometro,estado_controlador}.gd`;
  - `godot/plantillas/generar_esquemas.py`;
  - `godot/g1-unitree/robot/urdf_robot.gd:80`;
  - `docker/scripts/vita_relay.py:10-23`;
  - `skills/rclgd/references/api/{RosNode,RosActionClient,RosGoalHandle,RosLogger,RosQoS}.md`.
