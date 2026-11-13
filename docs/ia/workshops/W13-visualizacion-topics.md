# W13 — Visualizar todos los tipos de topic en Godot (PC con rclgd, Vita con ros2_vita)

> Registro del workshop (método en `README.md` de esta carpeta). Abierto el 2026-11-13 por petición del usuario:
> «investigaciones exhaustivas de mejora y optimización del entorno […] cómo visualizar todos los tipos de topics en
> Godot, para luego poder traducirlo a código; toma como referencia la documentación de rclgd […]; con múltiples
> subagentes explorar en paralelo todos los casos posibles».

## Pregunta

Para **cada tipo de mensaje ROS 2 que un usuario puede querer ver** (el catálogo de displays de RViz2, rqt y
Foxglove, más los que ya usan nuestras plantillas), ¿cómo se representa en Godot 4, qué nodo/clase lo implementa,
cómo se leen sus campos con la API de rclgd (`RosMsg`), y qué cambia en la PS Vita (`ros2_vita`: XRCE ≤ 488 B por
mensaje sin fragmentar, sin API de grafo, render sin shaders con los hechos H1–H25 del doc 31)? El resultado debe
poder **traducirse directamente a código**: fichas por tipo con esqueleto GDScript y una arquitectura común
(registro tipo → visualizador, al estilo de los *display plugins* de RViz).

## Material de partida (leer antes de investigar)

| Qué | Dónde |
|---|---|
| rclgd: código y docs oficiales (RST) | `godot/rclgd/` (`docs/classes/class_rosmsg.rst`, `docs/concepts/transforms.rst`, `rclgd/src/`, `rclgd/test/`) |
| Skill rclgd (resumen verificado) | `skills/rclgd/SKILL.md`, `skills/rclgd/references/*.md`, `references/api/` |
| Skills Godot/ROS/Vita | `skills/godot4-ros-scripting/`, `skills/ros2-vita-godot/` |
| Paridad rclgd ↔ ros2_vita | `godot/ros2_vita/API_PARITY.md`, `godot/ros2_vita/ros_msg.cpp`, `ros_runtime.cpp` |
| Esquemas de mensaje en la Vita | `modules/msg-schema/README.md`, `godot/plantillas/generar_esquemas.py`, `godot/plantillas/ros/msg/` |
| Código de plantillas que ya visualiza | `godot/plantillas/sensores/*.gd`, `godot/plantillas/ros/*.gd`, `godot/g6-hmi`, `godot/g7b-imu3d` |
| Render en la Vita (decisión) | `docs/31-render-visualizacion-vita.md` (H1–H25), `docs/adr/0011-presupuesto-render-vita.md` |
| Límites XRCE y relay del PC | `docs/27-xrce-limites-y-relay.md`, `docs/32-acciones-puente-pc.md`, `docs/adr/0012-*.md` |
| Sensores y visión | `docs/28-sensores-y-vision-vita.md`, `docs/29-plantillas-robots-sensores.md` |
| URDF / RobotModel | `docs/25-urdf-godot.md`, `docs/adr/0009-urdf-horneado-en-pc.md` |
| Mini-rviz histórico | `archivo/docs/11-diseno-mini-rviz.md`, `docs/04-investigacion-portabilidad-rviz2.md` |
| Rendimiento real medido | `docs/30-rendimiento-xrce-plantillas.md`, `docs/34-perfil-vita-ligero.md` |
| Regla de escenas editables | `docs/35-regla-escenas-editables.md` |

Fuentes externas útiles: código de RViz2 (`ros2/rviz`, rama jazzy: `rviz_default_plugins`), Foxglove (paneles),
`ros2/common_interfaces` (definiciones de mensaje), docs de Godot 4 (`docs.godotengine.org/en/stable`).

## Equipo y reparto (ronda divergente, en paralelo)

| Papel | Modelo | Familia de tipos |
|---|---|---|
| `nucleo-generico` | Opus 5.5 | API de introspección de `RosMsg` en rclgd/ros2_vita; inspector genérico (árbol) para **cualquier** tipo; trazador de series (tipo rqt_plot); `std_msgs`, `builtin_interfaces`; descubrimiento de tipos (PC con grafo, Vita sin grafo); **arquitectura del registro tipo → visualizador** |
| `geometria-tf-robot` | Opus 5.5 | `geometry_msgs` (todos), `nav_msgs/Odometry`, `nav_msgs/Path`, `tf2_msgs/TFMessage` (árbol TF y ejes), covarianzas, `sensor_msgs/JointState` + URDF (RobotModel), `Imu`, `MagneticField`, `NavSatFix`, `Range` |
| `sensores-densos` | Opus 5.5 | `LaserScan`, `MultiEchoLaserScan`, `PointCloud2` (campos, mapas de color, diezmado), `PointCloud`, `Image` (todas las codificaciones), `CompressedImage` (+ `compressedDepth`), `CameraInfo` (frustum, superposición), DepthCloud |
| `mapas-marcadores` | Opus 5.5 | `OccupancyGrid`, `map_msgs/OccupancyGridUpdate`, `GridCells`, costmaps de Nav2, `grid_map_msgs`, `octomap_msgs`; `visualization_msgs/Marker` (los 12 tipos y acciones), `MarkerArray`, `InteractiveMarker` (+ feedback), `ImageMarker`, `shape_msgs` |
| `hmi-percepcion-acciones` | Opus 5.5 | `Joy`, `BatteryState`, `Temperature`, `FluidPressure`, `Illuminance`, `RelativeHumidity`, `diagnostic_msgs`, `rcl_interfaces/Log` (`/rosout`), `vision_msgs` (Detection2D/3D), `trajectory_msgs`/`control_msgs` (fantasma de trayectoria), estado/feedback de acciones (Nav2), `lifecycle_msgs`; **herramientas de RViz que publican** (2D Pose Estimate, Nav Goal, Publish Point) |
| `esceptico-revisor` | Opus 5.5 | Ronda 2: lee los cinco posts, comprueba citas al azar, busca fallos y alternativas, emite veredictos |

## Ficha por tipo (esquema de post de W13 = esquema §4.2 + campos de visualización)

Cada post es un objeto JSON del array `posts/W13-<papel>.json`:

```json
{ "workshop": "W13", "autor": "<papel> (opus)",
  "tipo": "sensor_msgs/msg/LaserScan",
  "equivalente": "RViz2 LaserScan display (rviz_default_plugins/...)",
  "candidato": "representación elegida en una frase",
  "pc_rclgd": "nodos Godot, capa (3D/2D/HUD/textura) y API rclgd usada",
  "vita_ros2_vita": "qué cambia en la Vita: capa según ADR 0011, decodificación, ¿cabe en 488 B?, relay, Hz",
  "campos": "campo ROS → dato Godot (conversión de ejes ros_to_godot_*, unidades, frame_id/TF)",
  "codigo": "esqueleto GDScript (≤ 40 líneas) del visualizador, con la API real",
  "parametros": ["propiedades @export del display (color, tamaño, decay, alfa…)"],
  "evidencia": "…", "fuentes": ["ruta:línea o URL"], "confianza": "[V]|[I]|[?]",
  "coste_estimado": "CPU/draws/triángulos/bytes por mensaje",
  "como_se_mediria_en_hardware": "prueba y criterio de verde" }
```

## Condición de parada

Cada tipo del reparto tiene ficha (o una justificación de por qué no aplica); el escéptico ha emitido veredicto
sobre todas; las fichas VERIFICADO pasan al doc final `docs/36-visualizacion-topics-godot.md` y, si hay decisión
de arquitectura, a un ADR nuevo.

## Rondas

- **Ronda 1 (divergente, 2026-11-13): cerrada.** Cinco investigadores en paralelo (tres cortados por el límite de
  uso y reanudados sin repetir trabajo). Fichas: núcleo 18, geometría 22, sensores densos 15, mapas/marcadores 32,
  HMI 20 (≈107). `check-only` con el editor de host: HMI 20/20; sensores densos ejecutado con mensajes reales
  (serialize → deserialize); el resto sin ejecutar.
- **Ronda 2 (escéptico, 2026-11-13): cerrada** → `posts/W13-revision.{json,md}`: 76 VERIFICADO, 18 DESAFÍO,
  7 ALTERNATIVA, 6 Por medir; `check-only` 101 PASA / 4 FALLA (corregidas) / 2 NO APLICA; 10 contradicciones y
  15 decisiones abiertas. Alternativa no citada en la ronda 1: **gdviz** (Ozuba, `docs/24`).
- **Decisiones:** por regla del usuario (2026-11-13) no se le preguntan; las tomó el juez **Fable 5.2** →
  `posts/W13-juez-fable.md` y [`docs/adr/0013-visualizacion-topics-godot.md`](../../adr/0013-visualizacion-topics-godot.md)
  (arquitectura propia en `godot/plantillas/visor/`, gdviz solo como modelo; relay VC/1 rev. 2; tareas V1–V15).
- **Integración:** `docs/36-visualizacion-topics-godot.md`.
