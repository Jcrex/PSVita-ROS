# 36a — Catálogo de displays por tipo (sección 4 del doc 36)

> Separado de `docs/36-visualizacion-topics-godot.md` el 2026-11-13 (ADR 0014 §4.3) **sin cambiar el texto**: conserva
> la numeración §4.x, y «doc 36 §4.x» significa este fichero. Arquitectura, primitivas, relay VC/1, QoS, presupuesto,
> trampas, gates y tareas V1–V15 siguen en [`36-visualizacion-topics-godot.md`](36-visualizacion-topics-godot.md)
> (sus §0–§3 y §5–§12). Marcas, convenciones de tamaños y estado: las de la cabecera del doc 36.
> Cuando exista el código (V1+), el código es la fuente y estas fichas se reducen a la tabla §4.0.

---

## 4. Catálogo por tipo

### 4.0 Tabla maestra

Columnas: **Display** = archivo bajo `visor/displays/` (o `visor/herramientas/`); **PC / Vita** = capa (3D orbital,
2D planta, 2D superpuesto, HUD, textura); **¿488?** = ¿cabe el mensaje estándar en un datagrama best effort de la
Vita? (B con rosbags); **Ruta Vita** = directo (tipo estándar, con su esquema en `TIPOS_VISOR`) o relay
`<p>/…` (§5); **Hz** = ritmo en la Vita; **Veredicto** = de `W13-revision.json` (V = VERIFICADO, D = DESAFÍO,
A = ALTERNATIVA, M = Por medir) y cómo entra aquí. «`solo_pc`» = el display se desactiva en la Vita.

| # | Tipo ROS | Display | PC | Vita | ¿488? | Ruta Vita | Hz | Veredicto |
|---|---|---|---|---|---|---|---:|---|
| 1 | cualquiera | `hud/inspector_arbol.gd` (`solo_pc`) | HUD `Tree` | — | — | — | — | V nucleo#6 |
| 2 | cualquiera | `hud/inspector_texto.gd` | HUD | HUD pestaña Inspector | según tipo | directo | 4 | M nucleo#7 → G-W13-H0; ⚖ 8 filas × 30 car. |
| 3 | campos numéricos | `hud/trazador.gd` | HUD | HUD pestaña Gráficas | según tipo | directo o `ritmo/<n>` | ≤ 15 | M nucleo#8 → gate de V12; ⚖ 3 × 64 puntos |
| 4 | `std_msgs` escalares (Bool…Float64, String, Empty) | `hud/valor.gd` | HUD | HUD | sí (≤ 12 B + cadena) | directo | 10 | V nucleo#12 (`Empty` [?]) |
| 5 | `std_msgs/*MultiArray` | `hud/multiarray.gd` | HUD (perfil / calor) | HUD | ≤ 118 f32 / 236 i16 | directo | 10 (calor ≤ 4) | V nucleo#13 |
| 6 | `std_msgs/ColorRGBA` | `hud/color.gd` + `PaletaViz.de_ros` | HUD | HUD | sí | directo | — | D nucleo#14 → ⚖ D2 |
| 7 | `std_msgs/Header`, `builtin_interfaces/{Time,Duration}` | `tiempo_ros.gd` (utilidad) | — | — | — | — | — | V nucleo#15 |
| 8 | tipo sin esquema (Vita) | `hud/desconocido.gd` | — | HUD | — | no suscribe | — | V nucleo#11 |
| 9 | (todos) monitor Hz/enlace | `hud/barra_estado.gd` | barra fija | barra fija | — | — | 2 | D nucleo#16 → ⚖ D6 |
| 10 | descubrimiento | `explorador_topics.gd` (`solo_pc`) | grafo cada 2 s | ninguno | — | `relay_info` | — | V nucleo#9; A nucleo#10 → ⚖ D9 |
| 11 | `geometry_msgs/Point(Stamped)` | `3d/punto.gd` | 3D esfera + historial | 3D (pool ≤ cupo) | sí (44) | directo | 10 | V geom#1 |
| 12 | `Vector3(Stamped)` | `3d/vector.gd` | 3D flecha | 3D | sí (52) | directo | 10 | V geom#2 |
| 13 | `Pose(Stamped)` | `3d/pose.gd` · `2d/pose.gd` | 3D flecha/ejes | 2D triángulo (3D opc.) | sí (76) | directo | 10 | V geom#3 |
| 14 | `PoseArray` | `3d/poses.gd` (`solo_pc`) · `2d/poses.gd` | 3D pool | 2D triángulos, 1 lote | n ≤ 8 (28+56n) | relay `poses` (n ≤ 36) | 2 | V geom#4; ⚖ D5 |
| 15 | `PoseWithCovariance(Stamped)` | `3d/covarianza.gd` · `2d/covarianza.gd` | 3D flecha + elipsoide | 2D elipse + abanico | sí (364) | directo o relay `pose_cov` | 2 | V geom#5; ⚖ D5.4 |
| 16 | `Twist`, `Accel`, `Wrench` (+`Stamped`, `WithCovariance`) | `3d/tornillo.gd` | 3D 2 flechas + anillo | 3D (o barras HUD) | sí (52–364) | directo | 10 | V geom#6–8 (código común) |
| 17 | `Quaternion(Stamped)` | `3d/orientacion.gd` | 3D ejes + RPY | igual | sí (60) | directo | 10 | V geom#9 |
| 18 | `Transform(Stamped)` | `3d/transformada.gd` | 3D ejes + flecha | igual | sí (100) | directo | 10 | V geom#10 |
| 19 | `Polygon(Stamped)` | `3d/poligono.gd` (`solo_pc`) · `2d/poligono.gd` | 3D cinta | 2D polilínea | n ≤ 38 (28+12n) | directo | 2 | V geom#11 |
| 20 | `Inertia(Stamped)` | `3d/inercia.gd` | 3D caja + CoM | igual (depuración) | sí (108) | directo | 1 | D geom#12 → `lados: Vector3` |
| 21 | `nav_msgs/Odometry` | `3d/odometria.gd` · `2d/odometria.gd` | 3D flechas (keep) | 2D rastro + triángulo | no (724) | relay `pose2d` | 30 | V geom#13; ⚖ D5.4 |
| 22 | `nav_msgs/Path` | `3d/path.gd` · `2d/path.gd` | 3D cinta | 2D polilínea | no (28+72n) | relay `path_compacto` | 2 | V geom#14 |
| 23 | `tf2_msgs/TFMessage` (display TF) | `3d/tf.gd` | 3D ejes + flechas + nombres | 3D ejes (flechas no) | n ≤ 4 (108·n) | `TfLigero` local; relay `tf` opc. | 10 | D geom#15 → ⚖ D3/D7 |
| 24 | TF en la Vita | `tf_ligero.gd` | — | — | — | local + `tf` opc. | — | A geom#16 → ⚖ D3 |
| 25 | `sensor_msgs/JointState` + URDF | `3d/robot_joints.gd` | 3D robot horneado | igual (LOD Vita) | no (1 668, G1) | relay `joints` + `joints_orden` | 25 | V geom#17 |
| 26 | `Imu` | `3d/imu.gd` | 3D ejes + 2 flechas | igual; 2D brújula | sí (316–324) | directo; `ritmo/imu` si > 30 Hz | 20 | V geom#18 |
| 27 | `MagneticField` | `3d/magnetico.gd` | 3D flecha + rumbo | igual | sí (124) | directo | 10 | V geom#19 |
| 28 | `NavSatFix` | `2d/gps.gd` | 2D rastro ENU (+teselas OSM) | 2D | sí (125) | directo | 5 | V geom#20 |
| 29 | `Range` | `3d/rango.gd` · `2d/rango.gd` | 3D cono α 0,5 | 3D cono opaco o sector 2D | sí (52) | directo | 10 | V geom#21 |
| 30 | `Temperature`, `FluidPressure`, `Illuminance`, `RelativeHumidity` | `hud/medidor.gd` | HUD | HUD pestaña Estado | sí (44) | directo | 4 | V hmi#3–6 |
| 31 | `BatteryState` | `hud/bateria.gd` | barra fija | barra fija | sí (89–133) | directo | ≤ 1 | V hmi#2 |
| 32 | `Joy` | `hud/joy.gd` (+ fuente `/vita/joy`) | HUD | HUD | sí (128) | directo | 20 | V hmi#1 |
| 33 | `LaserScan` | `3d/scan_puntos.gd` (`solo_pc`) · `2d/scan.gd` | 3D puntos | 2D 1 lote | ≤ 107 rayos | relay `scan_compacto` | 10 | V sens#0; D sens#1 → ⚖ D4 |
| 34 | `MultiEchoLaserScan` | `3d/scan_multieco.gd` (`solo_pc`) | aplanar a LaserScan | — | no | relay `scan_compacto` (eco elegido en el relay) | 10 | V sens#2 |
| 35 | `PointCloud2` | `3d/nube_puntos.gd` (`solo_pc`) · `2d/nube.gd` | 3D puntos (GPU si > 50 k) | 2D por bandas | no | relay `nube2d` (n ≤ 76 × 3) | 5 | V sens#3; A sens#4 → ⚖ D5 |
| 36 | `PointCloud` (obsoleto) | convertir fuera de Godot | — | — | no | relay | — | V sens#5 |
| 37 | `Image` 8 bit (rgb8, rgba8, bgr8, bgra8, mono8, 8UC1/3, bayer_*8) | `hud/imagen.gd` (`solo_pc`) | textura + *shader* | — | no | relay `camara/compressed` | 3 | V sens#6 |
| 38 | `Image` profundidad (16UC1, mono16, 32FC1) | `hud/imagen.gd` (`solo_pc`) | R16/RF + *shader* | — | no | relay `camara/compressed` | 3 | D sens#7 → sin código propio; 16SC1 por resolver |
| 39 | `Image` yuv422/uyvy/yuyv | `hud/imagen_yuv.gd` (`solo_pc`) | RGBA8 w/2 + *shader* | — | no | relay | 3 | V sens#8 |
| 40 | `Image` en la Vita | — | — | HUD pestaña Cámara | no | relay `camara/compressed` | 3 | D sens#9 → ⚖ D13 |
| 41 | `CompressedImage` jpeg/png | `hud/imagen_comprimida.gd` | HUD | HUD | solo JPEG ≤ 452 | relay `camara/compressed` (fiable) | 3 | V sens#10 |
| 42 | `CompressedImage` compressedDepth | republicar fuera de Godot | — | — | no | relay | — | V sens#11 |
| 43 | `CameraInfo` | `3d/camara_info.gd` | 3D frustum líneas | 3D prismas o 2D | sí (357–381) | directo | 1 | D sens#12 → corrección |
| 44 | «Camera» (imagen + escena) | `hud/camara.gd` (`solo_pc`) | SubViewport | «modo cámara» | — | — | — | M sens#13 |
| 45 | DepthCloud | `3d/nube_profundidad.gd` (`solo_pc`) | GPU (*vertex shader*) | — | no | relay `nube2d` | — | V sens#14 |
| 46 | `OccupancyGrid` «map» | `3d/mapa.gd` · `2d/mapa.gd` | 3D quad + *shader* | textura (planta o quad) | no | relay `mapa_meta` + `mapa_tesela` | ≤ 20 teselas/s | V mapas#0 |
| 47 | `OccupancyGrid` «costmap» | mismo, paleta costmap | 3D *shader* | compuesto sobre el mapa | no | relay `costmap_meta` + `costmap_tesela` | ≤ 10 | V mapas#1 (V11) |
| 48 | `OccupancyGrid` «raw» | mismo, paleta gris (`solo_pc`) | 3D | — | no | — | — | V mapas#2 |
| 49 | `map_msgs/OccupancyGridUpdate` | en `mapa.gd` | `blit_rect` | teselas sucias del relay | ≤ 21×21 | relay (época fija) | — | D mapas#3 → ⚖ D5.5 |
| 50 | `nav_msgs/GridCells` | `3d/celdas.gd` (`solo_pc`) · `2d/celdas.gd` | MultiMesh | 2D 1 lote | n ≤ 18 | directo | 2 | V mapas#4 |
| 51 | `nav_msgs/MapMetaData` | `hud/meta_mapa.gd` | HUD | HUD | sí (84) | directo F+TL | — | V mapas#5 |
| 52 | `nav2_msgs/Costmap` (raw) | en `mapa.gd` (`solo_pc`) | R8 + paleta | — | no | relay `costmap` | — | V mapas#6 |
| 53 | `nav2_msgs/VoxelGrid` | `3d/voxeles.gd` (`solo_pc`) | MultiMesh | — | no | relay `nube2d` | — | V mapas#7 |
| 54 | `grid_map_msgs/GridMap` | `3d/grid_map.gd` (`solo_pc`, V14) | malla de alturas | — | no | relay (por diseñar) | — | V mapas#8 |
| 55 | `octomap_msgs/Octomap` | `3d/octomap.gd` (`solo_pc`, V14) | MultiMesh | — | no | relay (por diseñar) | — | V mapas#9 |
| 56 | `visualization_msgs/Marker` (gestor) | `3d/marcadores.gd` | 3D/2D | 3D sólidos, 2D líneas | ≤ 10 puntos (229–469) | directo o relay `marcadores` | 5 | D mapas#10 → `var tf = null` |
| 57 | Marker ARROW (pose/puntos), CUBE, SPHERE, CYLINDER | `fabrica_marcadores.gd` | 3D instancia | 3D instancia + paleta | sí (229/277) | directo / `marcadores` | 5 | V mapas#11–15 |
| 58 | Marker LINE_STRIP / LINE_LIST | `2d/marcadores_2d.gd` (Vita) · cinta/prisma (PC) | 3D prismas | 2D superpuesto | ≤ 10 puntos | `marcador_puntos` | ≤ 4 trozos/s | V mapas#16–17 |
| 59 | Marker CUBE_LIST / SPHERE_LIST | PC MultiMesh (`solo_pc`); Vita horneado ≤ 64 o 2D | 3D | 3D horneado / 2D | ≤ 10 | `marcador_puntos` | ≤ 1 | V mapas#18–19 |
| 60 | Marker POINTS | `2d/marcadores_2d.gd` | 2D o MultiMesh | 2D 1 lote | ≤ 10 | `marcador_puntos` | — | V mapas#20 |
| 61 | Marker TEXT_VIEW_FACING | `TextoSuperpuesto` | `draw_string` (o `Label3D` `solo_pc`) | `draw_string` | sí (249) | `marcador_texto` | ≤ 2 | D mapas#21 → ⚖ D11 |
| 62 | Marker MESH_RESOURCE | `fabrica_marcadores.gd` | tabla `package://`→`res://`, GLTF en caliente | solo horneadas | sí (URI) | directo | — | V mapas#22 (gltf Vita [?]) |
| 63 | Marker TRIANGLE_LIST | `fabrica_marcadores.gd` | ArrayMesh | ArrayMesh + paleta | ≤ 3 tri | relay | ≤ 1 | V mapas#23 |
| 64 | Marker ARROW_STRIP (12, Jazzy) | `fabrica_marcadores.gd` | tira + punta | igual | — | — | — | V mapas#24 (semántica [?]) |
| 65 | `MarkerArray` | `3d/marcadores.gd` + cliente compacto | gestor | estado completo | no (50 CUBE = 11 605) | relay `marcadores` (≤ 33) | 5 | A mapas#25 → ⚖ D14 |
| 66 | `InteractiveMarker(Update)` | `3d/im_cliente.gd` (`solo_pc`, V14) | asas | aplazado | update 132 | — | — | D mapas#26 → preload + sin tipo |
| 67 | `InteractiveMarkerFeedback` | `herramientas/im_feedback.gd` (`solo_pc` hasta V14) | ratón | (aplazado) | sí (149–157) | directo **fiable** | ≤ 20 | D mapas#27 → `pulsado: bool` + ⚖ C9 |
| 68 | `ImageMarker` | `hud/marcas_imagen.gd` | HUD sobre imagen | igual | ≤ 15 puntos | directo | 5 | V mapas#28 |
| 69 | `shape_msgs/{SolidPrimitive,Mesh,Plane}` | `fabrica_marcadores.gd` | 3D | 3D estático | depende | relay / horneado | — | V mapas#29–31 |
| 70 | `diagnostic_msgs/DiagnosticArray` | `hud/diagnostico.gd` | HUD (o `Tree`) | pestaña Diagnóstico | 1–2 estados | relay `diagnostics` | ≤ 10 | M hmi#7 → G-W13-H0; ⚖ 8 filas |
| 71 | `rcl_interfaces/Log` | `hud/consola.gd` | HUD | pestaña Consola | casi siempre | relay `rosout` (fiable) | ≤ 10 | M hmi#8 → G-W13-H0; ⚖ 6 líneas × 40 |
| 72 | `lifecycle_msgs/TransitionEvent` | `hud/lifecycle.gd` | HUD | pestaña Estado | sí (65) | directo fiable | evento | V hmi#9 |
| 73 | `vision_msgs/Detection2DArray` | `hud/cajas_2d.gd` | HUD sobre imagen | pestaña Cámara | 1 det. (449–474) | relay `detecciones` (n ≤ 18) | 5 | D hmi#10 → ⚖ D12 |
| 74 | `vision_msgs/Detection3DArray` | `2d/cajas_3d.gd` (superpuesto) | 2D superpuesto | igual | no (485–505) | relay `detecciones3d` (n ≤ 12) | 5 | D hmi#11 → ⚖ D12 |
| 75 | `trajectory_msgs/JointTrajectory` | `3d/fantasma.gd` | 3D 2.º robot | robot oculto o brazo ≤ 8 | 1 punto (228) | puente `/vita/accion/trayectoria` | — | M hmi#12 → ⚖ D7 |
| 76 | `control_msgs/JointTrajectoryControllerState` | `hud/controlador.gd` | HUD | pestaña Controlador (14 juntas) | no (1 340–2 404) | directo fiable | ≤ 5 | V hmi#13 (`get_member("reference")`) |
| 77 | `nav_msgs/Path` plan frente a real | `2d/plan_real.gd` | 2D | 2D | no | relay `path_compacto` + `pose2d` | 2 / 30 | D hmi#14 → ⚖ D5.4 (+ marco por resolver) |
| 78 | `action_msgs/GoalStatusArray` + feedback Nav2 | `hud/estado_meta.gd` | barra fija | barra fija | sí (33–453 / 116) | nivel 0 directo o `/vita/accion/estado` | 5 | V hmi#15 |
| 79 | Nav2 Goal → `PoseStamped` `/goal_pose` | `herramientas/meta.gd` | ratón | táctil + ✕ | sí (76) | publica directo fiable | evento | V hmi#16 |
| 80 | 2D Pose Estimate → `PoseWithCovarianceStamped` `initialpose` | `herramientas/pose_inicial.gd` | ratón | táctil + ✕ | sí (364) | publica directo fiable | evento | V hmi#17 |
| 81 | Publish Point → `PointStamped` `/clicked_point` | `herramientas/punto.gd` | ratón | táctil | sí (44) | publica directo fiable | evento | V hmi#18 |
| 82 | Teleop → `Twist` `/cmd_vel` | `herramientas/teleop.gd` | teclado | stick + R | sí (52) | directo fiable; `/vita/mando` con robots reales | 20 | V hmi#19 |

Correcciones de cifras que aplica la tabla (⚖ D4/C6): «LaserScan: 106 rayos» y «Detection3DArray no cabe por 1 B»
eran artefactos de contar o no la encapsulación; da igual en la práctica porque los dos van por el relay. CameraInfo
plumb_bob = 357 B con frame `camera` (no 381; depende del frame). Detection2DArray de 1 detección = 449/465/474 B
según frame y clase (el post decía 481) (`W13-revision.md` §3.2) [V].

Plantilla de cada subsección: **Representación** · **Campos** (campo ROS → dato Godot) · **`@export` propios**
(además de los comunes, §2.3) · **Vita** · **Veredicto** · esqueleto. Los esqueletos solo muestran lo propio del
display (los `@export` comunes y la mecánica vienen de la base). Ruta de `extends`: `res://comun/visor/display_ros_3d.gd`
(3D), `…/display_ros_2d.gd` (2D), `…/display_ros_hud.gd` (HUD).

### 4.1 Genéricos y `std_msgs` (familia `nucleo-generico`)

#### 4.1.1 Introspección (`introspeccion_ros.gd`) — V nucleo#0

Representación: utilidad estática; lista de campos por tipo, calculada **una vez** sobre un prototipo vacío; lectura
de rutas con `get_member`. Coste por mensaje 0 (caché). Se copia de la ficha cambiando solo la ruta.

```gdscript
extends RefCounted
## Campos de un RosMsg, portable rclgd (dinámico o tipado) ↔ ros2_vita (dinámico).
const _OMITIR := {"script": true}
const _NO_CAMPO := PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP
static var _cache := {}

static func campos_de_tipo(tipo: String) -> PackedStringArray:
	if _cache.has(tipo):
		return _cache[tipo]
	var out := PackedStringArray()
	var proto = RosMsg.from_type(tipo)
	if proto == null:
		return out
	var clase: String = proto.get_class()
	var lista: Array = ClassDB.class_get_property_list(clase, true) if clase != "RosMsg" else proto.get_property_list()
	for p in lista:
		if p.usage & _NO_CAMPO or _OMITIR.has(p.name):
			continue
		out.append(p.name)
	_cache[tipo] = out
	return out

static func campos(msg) -> PackedStringArray:
	return campos_de_tipo(msg.get_ros_interface_name())

## Ruta troceada: ["twist", "twist", "linear", "x"] o ["poses", "3", "pose"].
static func leer_ruta(msg, ruta: PackedStringArray):
	var v = msg
	for paso in ruta:
		if v is RosMsg:
			v = v.get_member(StringName(paso))
		elif typeof(v) >= TYPE_ARRAY and paso.is_valid_int() and paso.to_int() < v.size():
			v = v[paso.to_int()]
		else:
			return null
	return v
```

#### 4.1.2 Inspector en árbol (`hud/inspector_arbol.gd`, `solo_pc`) — V nucleo#6

Representación: `Tree` de dos columnas (campo, valor), construido **perezosamente** (solo baja a lo desplegado),
actualizado en sitio por ruta a ≤ 5 Hz; arrays truncados a `limite_array` con fila «… N elementos»; `uint8[]` como
tamaño + primeros bytes. `@export`: `limite_array` (32), `hz` = 5. Vita: no (cada glifo es un *quad* recalculado cada
fotograma, H16; 20 filas × 30 car. ≈ 600 *quads* > HUD entero) [I]. El código de la ficha se usa tal cual con dos
cambios: `extends Tree` pasa a ser un `Tree` **hijo** de un `DisplayRosHud` con `solo_pc = true` (la base no puede
ser `Tree` y `Control` a la vez), y `mostrar(msg)` se llama desde `_pintar(datos)` con `datos = msg`. Limitación
conocida: si un array encoge, las filas sobrantes no se ocultan (barrer `_filas` por prefijo).

#### 4.1.3 Inspector de texto (`hud/inspector_texto.gd`) — M nucleo#7 → G-W13-H0

Representación: filas planas «sangría campo: valor» con `draw_string` en `_draw()`, solo si cambia el texto; cruceta
arriba/abajo = desplazar, derecha/izquierda = desplegar/plegar. ⚖ D6: en la Vita, **8 filas × 30 caracteres** a
4 Hz (pestaña Inspector), no 12 × 32 como proponía la ficha; los límites son de partida hasta G-W13-H0.

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## Inspector de texto (Vita y PC): filas planas con draw_string, ≤ 4 Hz, solo si cambian.
const Intro = preload("res://comun/visor/introspeccion_ros.gd")
@export var filas := 8
@export var ancho_max := 30
var desplegados := {}
var _lineas := PackedStringArray()
var _primera := 0

func _init() -> void:
	hz = 4.0
	hz_vita = 4.0
	caducidad_s = 0.0

func _procesar(msg):
	var out := PackedStringArray()
	_aplanar(msg, "", 0, out)
	return null if out == _lineas else out          # null = no redibujar

func _pintar(d) -> void:
	_lineas = d
	queue_redraw()

func _aplanar(m, ruta: String, nivel: int, out: PackedStringArray) -> void:
	for c in Intro.campos(m):
		var v = m.get_member(c)
		var r := ruta + "/" + c
		out.append(("  ".repeat(nivel) + "%s: %s" % [c, _corto(v)]).left(ancho_max))
		if v is RosMsg and desplegados.has(r):
			_aplanar(v, r, nivel + 1, out)

func _corto(v) -> String:
	if v is RosMsg:
		return "{…}"
	if typeof(v) >= TYPE_ARRAY:
		return "%s[%d] %s" % [type_string(typeof(v)), v.size(), str(v.slice(0, 4))]
	return "%.3f" % v if v is float else str(v)

func _draw() -> void:
	var f := get_theme_default_font()
	for i in mini(filas, _lineas.size() - _primera):
		draw_string(f, Vector2(4, 16 + 16 * i), _lineas[_primera + i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				color_estado(Color.WHITE))

func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": filas * ancho_max}   # 240 = una pestaña entera
```

`slice(0, 4)` evita convertir arrays grandes en GDScript (en rclgd el array ya se copió entero al hacer
`get_member`) [I].

#### 4.1.4 Trazador de series (`hud/trazador.gd`) — M nucleo#8 → gate de V12

Representación: hasta 3 series (rutas de campo del **mismo** topic) en búferes circulares `PackedVector2Array` de
(t, y) en unidades de datos; el dibujo no recorre puntos en GDScript: `draw_set_transform` hace el mapeo a píxeles en
el C++ del lienzo y cada serie es una `draw_polyline(..., -1)` = 1 comando (H17). ⚖ D6: **3 series × 64 puntos** en
la Vita (la ficha proponía 300). Rutas con la sintaxis de Foxglove (`/odom.twist.twist.linear.x`: el punto no
puede aparecer en un nombre de topic); la de rqt_plot (`/odom/twist/...`) solo en el PC resolviendo el prefijo más
largo con el grafo. Para series de varios topics: un trazador por topic, superpuestos en la pestaña.
Gate (ficha y V12): pestaña Gráficas con 3 series → `draws` +≤ 3 y `avg_canvas_us` +≤ 300; duda [I]: que la
polilínea fina siga siendo de 1 px con `draw_set_transform` escalado y que el port la dibuje en un lote.

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## Trazador (rqt_plot / Foxglove Plot). `campos` = rutas dentro del mensaje de `topic`. Sin bucles por punto al dibujar.
const Intro = preload("res://comun/visor/introspeccion_ros.gd")
@export var campos: PackedStringArray = ["twist.twist.linear.x"]
@export var ventana_s := 10.0
@export var capacidad := 64
@export var colores := PackedColorArray([Color.ORANGE, Color.CYAN, Color.LIME])
var _series := []                 # {ruta: PackedStringArray, pts: PackedVector2Array, cab: int, n: int}
var _y_min := INF
var _y_max := -INF

func conectar(v) -> void:
	canal.coalescer = false       # el trazador necesita todas las muestras
	for c in campos.slice(0, 3):
		var pts := PackedVector2Array()
		pts.resize(capacidad)
		_series.append({"ruta": c.replace("[", ".").replace("]", "").split("."), "pts": pts, "cab": 0, "n": 0})
	super.conectar(v)

func _procesar(msg):
	var t := Time.get_ticks_msec() * 0.001
	for s in _series:
		var v = Intro.leer_ruta(msg, s.ruta)
		if not (v is float or v is int or v is bool):
			continue
		var y := float(v)
		s.pts[s.cab] = Vector2(t, y)
		s.cab = (s.cab + 1) % capacidad
		s.n = mini(s.n + 1, capacidad)
		_y_min = minf(_y_min, y)
		_y_max = maxf(_y_max, y)
	return true

func _draw() -> void:
	var ahora := Time.get_ticks_msec() * 0.001
	var esc := Vector2(size.x / ventana_s, -size.y / maxf(_y_max - _y_min, 1e-6))
	draw_set_transform(Vector2(size.x - ahora * esc.x, size.y - _y_min * esc.y), 0.0, esc)
	for k in _series.size():
		var s = _series[k]
		var orden: PackedVector2Array = s.pts.slice(s.cab) + s.pts.slice(0, s.cab) if s.n == capacidad else s.pts.slice(0, s.n)
		if orden.size() > 1:
			draw_polyline(orden, color_estado(colores[k % colores.size()]), -1.0)

func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 3 * capacidad + 20}   # [I] hasta G-W13-H0
```

El tiempo relativo al arranque en `Vector2` (float32) tiene resolución ≈ 0,25 ms a 1 h [I].

#### 4.1.5 Escalares de `std_msgs` (`hud/valor.gd`) — V nucleo#12

Representación: texto «nombre: valor unidad»; `Bool` → cuadro verde/rojo; `Empty` → contador de eventos; `Char` →
número y carácter; `String` recortado a 64. Campos: `data` → bool/int/float/String; `std_msgs` no lleva unidades
(`@export unidad`). `@export`: `unidad`, `decimales` (3). Vita: ≤ 12 B + cadena; en `generar_esquemas.py:13-14` solo
están `Bool` y `String` [V]: el resto entra por `TIPOS_VISOR` (D10). `Empty` [?]: msg-schema rechaza tipos sin campos;
depende del miembro de relleno de rosbags → fuera de `TIPOS_VISOR` hasta probarlo (§9.3).

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## Valor escalar de std_msgs (Bool, Int*, UInt*, Float*, Byte, Char, String, Empty).
@export var unidad := ""
@export var decimales := 3
var _eventos := 0

func _procesar(msg):
	if tipo == "std_msgs/msg/Empty":
		_eventos += 1
		return ["%d eventos" % _eventos, null]
	var v = msg.data
	if v is bool:
		return ["", Paleta.OK if v else Paleta.ERROR]
	if v is float:
		return [String.num(v, decimales) + " " + unidad, null]
	if tipo == "std_msgs/msg/Char":
		return ["%d '%s'" % [v, String.chr(v)], null]
	return [str(v).left(64) + " " + unidad, null]

func _draw() -> void:
	if datos == null:
		return
	var x := 4.0
	if datos[1] != null:
		draw_rect(Rect2(2, 2, 12, 12), color_estado(datos[1]))
		x = 18.0
	draw_string(get_theme_default_font(), Vector2(x, 13), "%s: %s" % [topic.get_file(), datos[0]],
			HORIZONTAL_ALIGNMENT_LEFT, size.x - x, 12, color_estado(Color.WHITE))

func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 30}
```

#### 4.1.6 `*MultiArray` (`hud/multiarray.gd`) — V nucleo#13

Representación: 0–1 dimensiones → perfil (polilínea fina de `data` frente al índice, 1 comando, escala por
`draw_set_transform`); 2 dimensiones → mapa de calor como textura (`Image L8`, filtro POINT) a ≤ 4 Hz; ≥ 3 →
inspector. Si el topic es un formato del relay, el registro elige antes el display específico. Campos:
`layout.dim[k].size/stride/label`, `layout.data_offset`, `data` (Packed*); 2D fila-mayor:
`data[ofs + r·dim[1].stride + c]`. `@export`: `max_puntos` (128), `mapa: TextureRect`. Vita: formato base del relay,
el más barato de recibir (H25); convertir a puntos es un bucle GDScript acotado por `max_puntos` (≈ 0,8 ms [I]); el
calor reutiliza `ImageTexture.update` (H19), no crea textura por mensaje (corrección de la propia ficha). El esqueleto
de la ficha vale con `_procesar` devolviendo `[_pts, _min, _max]` (o el `Image` en 2D) y `_draw()` sin cambios.

#### 4.1.7 `ColorRGBA` (`hud/color.gd`) — D nucleo#14 → ⚖ D2

Muestra de color + `#rrggbbaa`. Las utilidades `color_ros`/`indice_paleta` de la ficha **no** van aquí: son
`PaletaViz.de_ros(c)` y `PaletaViz.indice(c)` (§3.3), que usan Marker, MarkerArray y todo lo 3D. En la Vita el
color 3D sale de la paleta (H3); en 2D el color por primitiva es gratis (H16).

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
func _procesar(msg): return Paleta.de_ros(msg)
func _draw() -> void:
	if datos == null: return
	draw_rect(Rect2(2, 2, size.y - 4, size.y - 4), datos)
	draw_string(get_theme_default_font(), Vector2(size.y + 2, 13), "#" + (datos as Color).to_html(true))
```

#### 4.1.8 `Header`, `Time`, `Duration` (`tiempo_ros.gd`) — V nucleo#15

Sin display propio: el `frame_id` lo consumen las bases (TF) y el `stamp`, la latencia de la barra fija. En la Vita
`now()` es la hora del agente tras `uxr_sync_session`; si falla, reloj local y la latencia no tiene sentido. Sin
`use_sim_time` (⏳): con `/clock` de simulación la latencia es basura → se oculta si |latencia| > 1 h [I].

```gdscript
extends RefCounted
## Tiempo ROS (builtin_interfaces/Time y Duration) y Header, portable rclgd ↔ ros2_vita.
static func segundos(t) -> float:
	return float(t.sec) + float(t.nanosec) * 1e-9

static func a_texto(t) -> String:
	return "%d.%09d" % [t.sec, t.nanosec]

## Latencia (now − header.stamp) en s; NAN si el sello es 0 o absurdo (sim_time, sin sincronía).
static func latencia(nodo, msg) -> float:
	if not ("header" in msg):
		return NAN
	var st = msg.header.stamp
	if st.sec == 0 and st.nanosec == 0:
		return NAN
	var l := segundos(nodo.now()) - segundos(st)
	return l if absf(l) < 3600.0 else NAN

static func escribir_tiempo(t, s: float) -> void:
	t.sec = int(floor(s))
	t.nanosec = int((s - floor(s)) * 1e9)
```

#### 4.1.9 Tipo sin esquema (`hud/desconocido.gd`) — V nucleo#11

La base ya no suscribe si `RosMsg.from_type(tipo) == null` (estado «sin esquema: …», §2.9.2). Este widget solo
pinta `topic`, `tipo` y el `estado` con la pista «añadir a `TIPOS_VISOR` en `generar_esquemas.py`». Coste 0 si no
suscribe; con suscripción y sin esquema, hoy sería un `ERR_FAIL_COND` por muestra (spam de log).

#### 4.1.10 Monitor de topics → barra fija (`hud/barra_estado.gd`) — D nucleo#16 → ⚖ D6

⚖ El monitor de nucleo#16 **no es una pieza aparte**: enlace y Hz van en la barra fija (≤ 120 *quads* con batería,
meta y herramienta activa); el detalle por display es una vista de la pestaña Estado. Fuentes: `canal.hz_medido` y
`estado` de cada display del grupo `display_ros`; `rclgd.get_transport_info()` (solo `ros2_vita`: `be_pending`,
`be_dropped`, reconexiones…) por `has_method` + `call`; `<p>/relay_bw` (existe) para los bytes del relay. Sin
contadores por suscripción hasta V13 (P2). Refresco 2 Hz.

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## Barra fija: enlace XRCE + Hz del display vigilado + herramienta activa (la batería y la meta son widgets hermanos).
@export var vigilado: Node                 # display cuyo Hz se muestra (p. ej. el scan)
var herramienta := ""
var _t := 0.0
var _texto := ""

func _process(dt: float) -> void:
	_t += dt
	if _t < 0.5 or visor == null:
		return
	_t = 0.0
	var enlace := "PC"
	if rclgd.has_method("get_transport_info"):
		var info: Dictionary = rclgd.call("get_transport_info")
		enlace = "XRCE perd %s" % str(info.get("be_dropped", "?"))
	var hz_txt := "" if vigilado == null else "%s %.0f Hz" % [vigilado.name, vigilado.canal.hz_medido]
	var nuevo := "%s · %s · %s" % [enlace, hz_txt, herramienta]
	if nuevo != _texto:
		_texto = nuevo
		queue_redraw()

func _draw() -> void:
	draw_string(get_theme_default_font(), Vector2(4, 16), _texto, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 12)

func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 50}
```

#### 4.1.11 Descubrimiento — V nucleo#9 (PC) · A nucleo#10 → ⚖ D9 (Vita)

PC: `explorador_topics.gd` (`solo_pc`) de la ficha nucleo#9 tal cual: sondea `get_topic_names_and_types()` cada 2 s
(con `RosTimer`), emite `topic_nuevo`/`topic_perdido`, y `RegistroDisplays.crear()` añade displays **sin guardarlos**.
Vita: ninguno. El cliente de `/vita/catalogo` de nucleo#10 se descarta (⚖ D9); `relay_info` (`VC/1.2;módulos`)
basta para distinguir «sin datos» de «módulo apagado».

### 4.2 `geometry_msgs` (familia `geometria-tf-robot`)

Representación común: un `Node3D` por display, visuales creados **una vez** en `conectar()` (pool del tamaño del
cupo), movidos por `transform`. La base ya coloca el nodo en el marco del mensaje (`transform = marco`), así que
los visuales llevan transformaciones **locales** al frame del header. Capa por defecto `"poses"` (cupo HMI 4 /
Viz 16) salvo que se diga. Lo que vive en el suelo tiene además versión 2D (planta), la de por defecto en la Vita.
Esquemas: `PointStamped`, `Vector3Stamped`, `PoseArray`, `PoseWithCovarianceStamped`, `WrenchStamped`,
`AccelStamped`, `QuaternionStamped`, `PolygonStamped` entran en `TIPOS_VISOR` (D10); `Pose(Stamped)`, `Twist(Stamped)`,
`TransformStamped`, `Imu`, `MagneticField`, `NavSatFix`, `Range`, `TFMessage` ya están en `generar_esquemas.py:12-40`
[V].

#### 4.2.1 `Point` / `PointStamped` (`3d/punto.gd`) — V geom#1

Esfera (octaedro en la Vita) por punto con historial circular (RViz *History Length*); `Point` sin header se pinta
en `frame_id`. Campos: `point.x/y/z` (m) → `ros_to_godot_vector`. `@export`: `radio` (0,1; RViz 0,2), `historial`
(10), `color`. 44 B; contraparte que publica: herramienta Publish Point (§4.8).

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var radio := 0.1
@export var historial := 10
@export var color := Color(1.0, 0.0, 1.0)
var _pool: Array[MeshInstance3D] = []
var _i := 0

func _init() -> void:
	capa = "poses"

func conectar(v) -> void:
	super.conectar(v)
	for k in cupo:
		var e := Prim.instancia(Prim.ESFERA, color)
		e.visible = false
		e.top_level = true                       # el historial se queda en el mundo aunque el marco se mueva
		add_child(e)
		_pool.append(e)

func _procesar(msg):
	var p = msg.point
	return rclgd.ros_to_godot_vector(Vector3(p.x, p.y, p.z))

func _pintar(pos) -> void:
	if _pool.is_empty():
		return
	var e := _pool[_i]
	_i = (_i + 1) % _pool.size()
	e.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * radio * 2.0), global_transform * (pos as Vector3))
	e.visible = true

func _coste() -> Dictionary: return {"instancias": historial, "triangulos": 8 * historial, "quads": 0}
```

#### 4.2.2 `Vector3` / `Vector3Stamped` (`3d/vector.gd`) — V geom#2

Flecha desde el origen del frame, largo = |v| × `escala`; oculta si |v| < umbral (`looking_at` con vector nulo da
error). Sin display en RViz de serie [V]. Serie temporal opcional con el trazador. `@export`: `escala`, `color`.
52 B, 24 tri, 1 *draw*.

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var escala := 1.0
@export var color := Color(0.2, 0.6, 1.0)
var _f: MeshInstance3D
func conectar(v) -> void:
	super.conectar(v)
	_f = Prim.instancia(Prim.FLECHA, color)
	add_child(_f)
func _procesar(msg):
	return rclgd.ros_to_godot_vector(Vector3(msg.vector.x, msg.vector.y, msg.vector.z)) * escala
func _pintar(v) -> void:
	var t = Prim.flecha_hacia(v)
	_f.visible = t != null
	if t != null:
		_f.transform = t
func _coste() -> Dictionary: return {"instancias": 1, "triangulos": 24, "quads": 0}
```

#### 4.2.3 `Pose` / `PoseStamped` (`3d/pose.gd`, `2d/pose.gd`) — V geom#3

3D: flecha (o ejes) en la pose, escalada por `largo` (RViz *Shaft Length* 1 + *Head* 0,3). 2D: triángulo orientado
por el yaw (`draw_colored_polygon`, patrón validado de `godot/g6-hmi/main.gd:182` y del minimapa). 76 B, 60 Hz posibles
(`docs/27:81`). La Vita también **publica** `PoseStamped` (meta, §4.8).

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export_enum("flecha", "ejes") var forma := "flecha"
@export var largo := 1.0
@export var color := Color(1.0, 0.1, 0.0)
var _vis: MeshInstance3D
func conectar(v) -> void:
	super.conectar(v)
	_vis = Prim.instancia(Prim.FLECHA if forma == "flecha" else Prim.EJES, color)
	add_child(_vis)
func _procesar(msg): return Prim.pose_godot(msg.pose)
func _pintar(t) -> void: _vis.transform = (t as Transform3D).scaled_local(Vector3.ONE * largo)
func _coste() -> Dictionary: return {"instancias": 1, "triangulos": 36, "quads": 0}
```

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## Pose en planta: triángulo orientado (g6-hmi/main.gd:182). datos = [Vector2 m, yaw].
@export var lado_px := 10.0
@export var color := Color(1.0, 0.1, 0.0)
var _p := Vector2.ZERO
var _yaw := 0.0
func _procesar(msg):
	var o = msg.pose.orientation
	var yaw := atan2(2.0 * (o.w * o.z + o.x * o.y), 1.0 - 2.0 * (o.y * o.y + o.z * o.z))   # util_ros.gd yaw_de_quat
	return [Vector2(msg.pose.position.x, msg.pose.position.y), yaw]
func _pintar(d) -> void:
	_p = px(d[0])
	_yaw = d[1]
	queue_redraw()
func _draw() -> void:
	var f := Vector2(cos(_yaw), -sin(_yaw))            # yaw ROS en la planta (y hacia abajo)
	var l := Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([_p + f * lado_px, _p - f * lado_px * 0.6 + l * lado_px * 0.6,
			_p - f * lado_px * 0.6 - l * lado_px * 0.6]), color)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 1}
```

#### 4.2.4 `PoseArray` (`3d/poses.gd` `solo_pc`, `2d/poses.gd`) — V geom#4 → relay `poses` (⚖ D5)

PC: pool de flechas reutilizado (las sobrantes se ocultan). Vita: 28 + 56·n B ⇒ n ≤ 8 en directo; ⚖ D5: lo normal es
el relay `<p>/poses` = cabecera común + `[x, y, yaw]·n`, **n ≤ 36** (464 B, diezmado; la ficha decía ≤ 39 sin
cabecera), 2 Hz, pintado en 2D como triángulos en **un** lote (H16–H17). Nota [I]: la nube de AMCL en Jazzy es
`nav2_msgs/ParticleCloud` (con pesos), no `PoseArray`: el módulo `poses` del relay acepta los dos.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## PoseArray en planta: un triángulo por pose en UNA llamada. datos = PackedVector3Array (x, y, yaw) en m.
@export var lado_px := 6.0
@export var color := Color(1.0, 0.1, 0.0)
var _v := PackedVector2Array()
var _c := PackedColorArray()
var _idx := PackedInt32Array()
func _init() -> void:
	capa = "sensores_2d"
func _procesar(msg):
	var out := PackedVector3Array()
	for p in msg.poses:
		var o = p.orientation
		out.append(Vector3(p.position.x, p.position.y, atan2(2.0 * (o.w * o.z + o.x * o.y), 1.0 - 2.0 * (o.y * o.y + o.z * o.z))))
	return out
func _procesar_compacto(msg):                       # <p>/poses: [seq, trozo, n_trozos, n, (x, y, yaw)·n]
	var d: PackedFloat32Array = msg.data
	var out := PackedVector3Array()
	if d.size() < 4:
		return null
	for i in mini(int(d[3]), (d.size() - 4) / 3):
		out.append(Vector3(d[4 + 3 * i], d[5 + 3 * i], d[6 + 3 * i]))
	return out                                      # n ≤ 36 cabe en un trozo: sin ensamblar
func _pintar(poses) -> void:
	_v.resize(0)
	_c.resize(0)
	for q in poses:
		var p := px(Vector2(q.x, q.y))
		var f := Vector2(cos(q.z), -sin(q.z)) * lado_px
		var l := Vector2(-f.y, f.x) * 0.5
		_v.append_array([p + f, p - f * 0.5 + l, p - f * 0.5 - l])
		_c.append_array([color, color, color])
	if _idx.size() != _v.size():
		_idx = PackedInt32Array(range(_v.size()))
	queue_redraw()
func _draw() -> void:
	if _v.size() > 0:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _v, _c)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 100}   # «poses y odometría ≤ 100»
```

La versión 3D del PC es el código de geom#4 (pool de `Prim.instancia(Prim.FLECHA, color)`, `transform =
Prim.pose_godot(poses[i]).scaled_local(Vector3.ONE * largo)`), con `@export maximo` (200).

#### 4.2.5 `PoseWithCovariance(Stamped)` (`3d/covarianza.gd`, `2d/covarianza.gd`) — V geom#5; relay `pose_cov` (⚖ D5.4)

Representación (algoritmo de `covariance_visual.cpp`): flecha de la pose + elipse/elipsoide de posición con semiejes
**2·√λ** (bloque 3×3; 2×2 si `c[14] ≤ 0` y `c[21] ≤ 0` y `c[28] ≤ 0`) + abanico de yaw ±2σ (`σ = √c[35]`). Campos:
`covariance` float64[36] por filas (x, y, z, rotX, rotY, rotZ) → `PackedFloat64Array`; bloque 2D `c[0], c[1], c[7]`;
la elipse vive en los ejes del `header.frame_id` y no gira con la pose [I]. `@export`: `escala_pos`, `escala_ori`,
`color`. Vita: 364 B, cabe en directo; **sin elipsoide translúcido** (sin orden de transparencias y profundidad
siempre escrita, `docs/31` §2.4): (a) planta 2D = elipse `draw_polyline` de 24 lados + abanico `draw_colored_polygon`
(dos comandos), por defecto; (b) orbital 3D = `DISCO` opaco escalado por `transform`. ⚖ D5.4: `/vita/pose2d` **no se
amplía** a 10 floats (rompería `godot/plantillas/vita_relay.gd:87-91`, contra geom#13); la covarianza de AMCL llega
por `<p>/pose_cov` = `[x, y, yaw, σxx, σxy, σyy, σyaw]` (7 floats, 44 B, 2 Hz). Autovalores 2D en forma cerrada:

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## Covarianza 2D en planta: elipse 2σ (24 lados) + abanico de yaw ±2σ. datos = [centro m, yaw, l1, l2, th, s_yaw].
@export var escala_pos := 1.0
@export var color := Color(1.0, 0.4, 1.0)
var _d = null
func _init() -> void:
	capa = "sensores_2d"
func _procesar(msg):
	var c: PackedFloat64Array = msg.pose.covariance
	var o = msg.pose.pose.orientation
	var yaw := atan2(2.0 * (o.w * o.z + o.x * o.y), 1.0 - 2.0 * (o.y * o.y + o.z * o.z))
	return _elipse(Vector2(msg.pose.pose.position.x, msg.pose.pose.position.y), yaw, c[0], c[1], c[7], c[35])
func _procesar_compacto(msg):                  # <p>/pose_cov = [x, y, yaw, σxx, σxy, σyy, σyaw]
	var d: PackedFloat32Array = msg.data
	return null if d.size() < 7 else _elipse(Vector2(d[0], d[1]), d[2], d[3], d[4], d[5], d[6])
func _elipse(p: Vector2, yaw: float, a: float, b: float, dd: float, var_yaw: float) -> Array:
	var h := sqrt(((a - dd) * 0.5) ** 2 + b * b)
	var l1 := maxf((a + dd) * 0.5 + h, 0.0)
	var l2 := maxf((a + dd) * 0.5 - h, 0.0)
	return [p, yaw, l1, l2, 0.5 * atan2(2.0 * b, a - dd), sqrt(maxf(var_yaw, 0.0))]
func _pintar(d) -> void:
	_d = d
	queue_redraw()
func _draw() -> void:
	if _d == null:
		return
	var pts := PackedVector2Array()
	var ejes := Vector2(2.0 * sqrt(_d[2]), 2.0 * sqrt(_d[3])) * escala_pos
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(px(_d[0] + Vector2(cos(a) * ejes.x, sin(a) * ejes.y).rotated(_d[4])))
	draw_polyline(pts, color, -1.0)
	var r := 0.5 * visor.px_por_m
	var c0 := px(_d[0])
	var abanico := PackedVector2Array([c0])
	for k in 7:
		var a: float = _d[1] - 2.0 * _d[5] + 4.0 * _d[5] * k / 6.0
		abanico.append(c0 + Vector2(cos(a), -sin(a)) * r)
	draw_colored_polygon(abanico, Color(color, 0.5))
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 30}
```

El 3D del PC (elipsoide `C·(V·diag(2√λ))·Cᵀ` + discos de orientación) es el de geom#5 con `Prim.instancia(Prim.DISCO,
…)` y `Prim.a_godot(b_ros)` en lugar de `C * b_ros * C.transposed()`.

#### 4.2.6 `Twist`, `Accel`, `Wrench` (+`Stamped`, `WithCovariance(Stamped)`) (`3d/tornillo.gd`) — V geom#6–8

Display «screw» de RViz (`TwistStamped`/`AccelStamped`/`Wrench`): flecha lineal (o fuerza, roja) + flecha angular
(o par, amarilla) con `ANILLO` abierto de 315° de radio L/4 a mitad del eje (`wrench_visual.cpp`). Las tres fichas
traían el mismo código (`W13-revision.md:70-72`): un único script con `tipo`. El angular es pseudovector: la flecha
va por el eje de giro (regla de la mano derecha; la conversión es una rotación propia, `transforms.rst:37-48`).
`Twist` sin header (p. ej. `/cmd_vel`) se pinta en `frame_id` (por defecto `base_link`). NaN → descartar (RViz
*Accept NaN* = false). `@export`: `escala_lineal`, `escala_angular` (RViz *Force/Torque Arrow Scale* 2),
`ocultar_pequenos` (RViz *Hide Small Values*). Coste: 3 instancias (24 + 24 + 56 tri). En la Vita el `Twist` típico
es el que **ella** publica (teleop); verlo = flecha de mando en la planta (`g6-hmi/main.gd:185`) y barras HUD.

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var escala_lineal := 1.0
@export var escala_angular := 1.0
@export var ocultar_pequenos := true
var _lin: MeshInstance3D
var _ang: MeshInstance3D
var _anillo: MeshInstance3D
func conectar(v) -> void:
	super.conectar(v)
	_lin = Prim.instancia(Prim.FLECHA, Color(0.8, 0.2, 0.2))
	_ang = Prim.instancia(Prim.FLECHA, Color(0.8, 0.8, 0.2))
	_anillo = Prim.instancia(Prim.ANILLO, Color(0.8, 0.8, 0.2))
	for n in [_lin, _ang, _anillo]:
		add_child(n)
func _procesar(msg):
	var t: String = msg.get_ros_interface_name()
	var w := t.contains("Wrench")
	var c = msg
	if "Stamped" in t:                      # TwistStamped.twist / AccelStamped.accel / WrenchStamped.wrench
		c = msg.get_member("wrench" if w else ("twist" if t.contains("Twist") else "accel"))
	if "WithCovariance" in t:               # …WithCovariance.twist / .accel
		c = c.get_member("twist" if t.contains("Twist") else "accel")
	var a = c.get_member("force" if w else "linear")
	var b = c.get_member("torque" if w else "angular")
	var vl := Vector3(a.x, a.y, a.z)
	var va := Vector3(b.x, b.y, b.z)
	if not (vl.is_finite() and va.is_finite()):
		return null
	return [rclgd.ros_to_godot_vector(vl) * escala_lineal, rclgd.ros_to_godot_vector(va) * escala_angular]
func _pintar(d) -> void:
	var umbral := 0.01 if ocultar_pequenos else 1e-6
	var tl = Prim.flecha_hacia(d[0]) if (d[0] as Vector3).length() > umbral else null
	var ta = Prim.flecha_hacia(d[1]) if (d[1] as Vector3).length() > umbral else null
	_lin.visible = tl != null
	_ang.visible = ta != null
	_anillo.visible = ta != null
	if tl != null:
		_lin.transform = tl
	if ta != null:
		_ang.transform = ta
		var largo: float = (d[1] as Vector3).length()
		var r := largo * 0.25
		_anillo.transform = (ta as Transform3D).translated_local(Vector3(0, 0, -0.5)).scaled_local(Vector3(r, r, 1.0 / largo))
func _coste() -> Dictionary: return {"instancias": 3, "triangulos": 104, "quads": 0}
```

Esquemas: `Twist` y `TwistStamped` ya están; `AccelStamped` y `WrenchStamped` entran por `TIPOS_VISOR`; las
variantes `WithCovariance` no (se añaden si una app las usa).

#### 4.2.7 `Quaternion(Stamped)` (`3d/orientacion.gd`) — V geom#9

`EJES` girados por el cuaternión en el origen del frame + RPY en grados para el HUD (a ≤ 10 Hz, O1 de G7c,
`docs/31:139`). Cuaternión nulo → se ignora; no unitario → normalizar. Sin display en RViz [V]. 60 B, 36 tri.

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var largo := 0.5
var rpy_grados := Vector3.ZERO
var _ejes: MeshInstance3D
func conectar(v) -> void:
	super.conectar(v)
	_ejes = Prim.instancia(Prim.EJES, Color.WHITE)
	add_child(_ejes)
func _procesar(msg):
	var o = msg.quaternion
	var q := Quaternion(o.x, o.y, o.z, o.w)
	if q.length_squared() < 1e-6:
		return null
	q = q.normalized()
	rpy_grados = Vector3(atan2(2.0 * (q.w * q.x + q.y * q.z), 1.0 - 2.0 * (q.x * q.x + q.y * q.y)),
			asin(clampf(2.0 * (q.w * q.y - q.z * q.x), -1.0, 1.0)),
			atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))) * (180.0 / PI)
	return rclgd.ros_to_godot_quat(q)
func _pintar(q) -> void:
	_ejes.transform = Transform3D(Basis(q as Quaternion).scaled(Vector3.ONE * largo), Vector3.ZERO)
func _coste() -> Dictionary: return {"instancias": 1, "triangulos": 36, "quads": 0}
```

#### 4.2.8 `Transform(Stamped)` (`3d/transformada.gd`) — V geom#10

Ejes del hijo (`child_frame_id`) en el marco del padre (`header.frame_id`) + flecha hijo → padre; nombre del hijo por
`visor.texto.poner(...)`. En el PC se puede reemitir con `RosTfBroadcaster.send_transform` si el topic no es `/tf`.
100 B; 60 tri, 2 *draws*. Esqueleto = el de geom#10 con `_procesar` → `Transform3D(Basis(ros_to_godot_quat(q)),
ros_to_godot_vector(t))` y `_pintar` que coloca `_ejes` (escala 0,3) y la flecha
`Prim.flecha_hacia(-hijo.origin)` en `hijo.origin` (el padre es el origen del nodo).

#### 4.2.9 `Polygon(Stamped)` (`2d/poligono.gd`; `3d/poligono.gd` `solo_pc`) — V geom#11

Contorno cerrado: planta 2D `draw_polyline` cerrada (+ relleno opcional `draw_colored_polygon`), 1 comando (H17), por
defecto en la Vita; en el PC, `Prim.cinta(pts, ancho, ic, true)` reconstruida **solo si cambia la forma** (la huella
de Nav2 es casi estática) y a ≤ 2 Hz. Campos: `polygon.points[i]` (Point32) → `Vector2(x, y)`; marco una vez por
mensaje. 28 + 12·n B ⇒ n ≤ 38. `@export`: `ancho` (0,02), `color`, `relleno`. Topic típico
`/local_costmap/published_footprint`.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
@export var color := Color(0.2, 0.9, 0.3)
@export var relleno := false
var _pts := PackedVector2Array()
func _procesar(msg):
	var out := PackedVector2Array()
	for p in msg.polygon.points:
		out.append(Vector2(p.x, p.y))
	return null if out == _pts else out           # sin cambio de forma: no redibujar
func _pintar(pts) -> void:
	_pts = pts
	queue_redraw()
func _draw() -> void:
	if _pts.size() < 2:
		return
	var p := PackedVector2Array()
	for q in _pts:
		p.append(px(q))
	if relleno and p.size() >= 3:
		draw_colored_polygon(p, Color(color, 0.3))
	p.append(p[0])
	draw_polyline(p, color, -1.0)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 40}
```

#### 4.2.10 `Inertia(Stamped)` (`3d/inercia.gd`) — D geom#12 → corrección aplicada

Caja de inercia equivalente (densidad uniforme) en el CoM, ejes principales por Jacobi cíclico 3×3; uso de
depuración del URDF horneado (raro en la Vita: Jacobi ≈ 1 ms [I] por mensaje). Campos: `m`, `com`, `ixx…izz` →
tensor → autovalores `I1..I3` → lados `a = √(6(I2+I3−I1)/m)`… **Corrección de check-only** (`W13-revision.md:57`):
`var lados := Vector3(...) * (6.0 / i.m)` no compila («Cannot infer the type of "lados"», `Vector3 * Variant`) →
`var lados: Vector3 = …`. El resto del código de geom#12 se conserva:

```gdscript
func _procesar(msg):
	var i = msg.inertia
	if i.m <= 0.0:
		return null
	var a := [[i.ixx, i.ixy, i.ixz], [i.ixy, i.iyy, i.iyz], [i.ixz, i.iyz, i.izz]]
	var v := Basis()                                  # columnas = autovectores (ejes ROS)
	for _barrido in 10:                               # Jacobi cíclico 3×3
		for pq in [[0, 1], [0, 2], [1, 2]]:
			var p: int = pq[0]
			var q: int = pq[1]
			if absf(a[p][q]) < 1e-12:
				continue
			var th := 0.5 * atan2(2.0 * a[p][q], a[q][q] - a[p][p])
			var c := cos(th)
			var s := sin(th)
			for k in 3:
				var akp: float = a[k][p]
				var akq: float = a[k][q]
				a[k][p] = c * akp - s * akq
				a[k][q] = s * akp + c * akq
			for k in 3:
				var apk: float = a[p][k]
				var aqk: float = a[q][k]
				a[p][k] = c * apk - s * aqk
				a[q][k] = s * apk + c * aqk
			var vp := v[p]
			var vq := v[q]
			v[p] = c * vp - s * vq
			v[q] = s * vp + c * vq
	var l := Vector3(a[0][0], a[1][1], a[2][2])
	var lados: Vector3 = Vector3(l.y + l.z - l.x, l.x + l.z - l.y, l.x + l.y - l.z) * (6.0 / i.m)   # ← corrección
	lados = Vector3(sqrt(maxf(lados.x, 0.0)), sqrt(maxf(lados.y, 0.0)), sqrt(maxf(lados.z, 0.0)))
	return Transform3D(Prim.a_godot(v.scaled_local(lados)), rclgd.ros_to_godot_vector(Vector3(i.com.x, i.com.y, i.com.z)))

func _pintar(t) -> void:
	_caja.transform = t                               # _caja = Prim.instancia(Prim.CUBO, …) creada en conectar()
```

Prueba de host pendiente: Jacobi contra una caja de inercia conocida (borrador de geom §4.6).

### 4.3 Odometría, Path, TF y robot

#### 4.3.1 `nav_msgs/Odometry` (`2d/odometria.gd`; `3d/odometria.gd`) — V geom#13

Representación (RViz): rastro de flechas; se añade una **solo si** la pose se aleja de la **última flecha dibujada**
más de `tol_pos` o `tol_ang` (`Quaternion.angle_to` ≈ `ogreQuaternionAngularDistance`); pool circular de `keep`,
nunca se crean nodos por mensaje. Covarianza opcional (§4.2.5). En la Vita: 724 B no cabe en best effort (fiable
llega en 2 fragmentos, G6 a 20–30 Hz, `docs/27:80`); se usa el relay `<p>/pose2d` = `[x, y, yaw, vx, vy, wz]`, 40 B,
30 Hz (`vita_relay.py:11`) y la **planta 2D** (rastro `draw_polyline` + triángulo, validado en G6 y en el minimapa
del G1). 3D en la Vita solo con cupo (`poses`: HMI 4, Viz 16 ⇒ `keep` ≤ cupo; la ficha decía ≤ 20). `@export`:
`tol_pos` (0,1 m), `tol_ang` (0,1 rad), `keep` (100 PC), `color`; `topic_vita = "pose2d"`, `tipo_vita =
"std_msgs/msg/Float32MultiArray"`. Marco fijo `odom`: sin TF. La velocidad (`twist.twist` en `child_frame_id`: vx,
wz) va a la barra o a un medidor.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## Odometry en planta: rastro + triángulo. datos = Vector3(x, y, yaw) en el marco del mensaje (odom).
@export var tol_pos := 0.1
@export var max_rastro := 300
@export var color := Color(0.3, 0.7, 1.0)
var _rastro := PackedVector2Array()
var _yaw := 0.0
func _init() -> void:
	capa = "sensores_2d"
	hz = 30.0
func _procesar(msg):
	var o = msg.pose.pose.orientation
	return Vector3(msg.pose.pose.position.x, msg.pose.pose.position.y,
			atan2(2.0 * (o.w * o.z + o.x * o.y), 1.0 - 2.0 * (o.y * o.y + o.z * o.z)))
func _procesar_compacto(msg):
	var d: Dictionary = VitaRelay.pose2d(msg)          # vita_relay.gd:87-92
	return null if d.is_empty() else Vector3(d.pos.x, d.pos.y, d.yaw)
func _pintar(p) -> void:
	var q := Vector2(p.x, p.y)
	_yaw = p.z
	if _rastro.is_empty() or _rastro[-1].distance_to(q) > tol_pos:
		_rastro.append(q)
		if _rastro.size() > max_rastro:
			_rastro.remove_at(0)
	queue_redraw()
func _draw() -> void:
	if _rastro.size() < 2:
		return
	var pts := PackedVector2Array()
	for q in _rastro:
		pts.append(px(q))
	draw_polyline(pts, color, -1.0)
	var f := Vector2(cos(_yaw), -sin(_yaw)) * 10.0
	var c := pts[-1]
	draw_colored_polygon(PackedVector2Array([c + f, c - f * 0.6 + Vector2(-f.y, f.x) * 0.6, c - f * 0.6 - Vector2(-f.y, f.x) * 0.6]), color)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 100}
```

(`const VitaRelay = preload("res://comun/vita_relay.gd")` en la cabecera de los displays que lo usan.) El 3D es el de
geom#13 con el pool creado en `conectar()` del tamaño de `cupo` y `_pintar(t)` aplicando la tolerancia.

#### 4.3.2 `nav_msgs/Path` (`2d/path.gd`; `3d/path.gd`) — V geom#14

Polilínea transformada al marco fijo **una vez por mensaje** (como RViz). PC: `Prim.cinta` (2 tri/segmento) o líneas;
Vita: `draw_polyline` 2D por defecto, o cinta 3D reconstruida a ≤ 2 Hz (≤ 112 tri, `docs/31:133`; ADR 0011 §4; cupo
`lento` 0 en HMI, 4 en Viz). Path de 100 poses = 7 228 B: no cabe ni en fiable de forma estable (`docs/27:67`) →
relay `<p>/path_compacto` = `[n, x0, y0, …]`, Douglas-Peucker ε 5 cm, ≤ 57 puntos, 476 B, 2 Hz
(`vita_relay.py:18,87-110`). `Path` no hace falta en el `.rsch` de la Vita. Dato intermedio común:
`PackedVector2Array` en metros del marco del mensaje.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
@export var color := Color(0.1, 1.0, 0.0)          # RViz Path por defecto
var _pts := PackedVector2Array()
func _init() -> void:
	hz = 2.0
func _procesar(msg):
	var out := PackedVector2Array()
	for ps in msg.poses:
		out.append(Vector2(ps.pose.position.x, ps.pose.position.y))
	return out
func _procesar_compacto(msg): return VitaRelay.path_puntos(msg)   # vita_relay.gd:112-121
func _pintar(pts) -> void:
	_pts.resize(0)
	for q in pts:
		_pts.append(px(q))
	queue_redraw()
func _draw() -> void:
	if _pts.size() > 1:
		draw_polyline(_pts, color, -1.0)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 112}
```

#### 4.3.3 Display TF (`3d/tf.gd`) — D geom#15 → ⚖ D3 y D7

Representación: **no se suscribe a `/tf`**: consulta `visor.tf` a 10 Hz (`RosTfListener` en el PC, `TfLigero` en la
Vita), dibuja `EJES` por marco en el marco fijo, una flecha de cada hijo a su padre y los nombres con
`TextoSuperpuesto` (nunca `Label3D`); oculta los marcos sin actualizar en `timeout_s` (los estáticos no caducan).
**Corrección de la revisión y ⚖ sentencia**: (1) el relay `/vita/tf` de la ficha (trozos de 4 transforms a 30 Hz,
32 marcos) son ≈ 104 KB/s, más que todo el presupuesto de red (`W13-revision.md:161-162`): en la Vita los marcos del
robot salen de la cinemática local (`/vita/joints`) y `map|odom → base` de `/vita/pose2d`; el módulo `tf` del relay
es opcional y con lista blanca de **≤ 8 marcos a 10 Hz** (288 B, 2,9 KB/s); (2) ejes + flechas de 32 marcos = 64
instancias, por encima de las 32 de TF: **flechas hijo → padre apagadas en la Vita** (o líneas 2D superpuestas) y
cupo `tf` = 8 (HMI) / 32 (Viz). `@export`: `escala` (0,3; RViz *Marker Scale*), `timeout_s` (15), `periodo` (0,1),
`mostrar_nombres`, `mostrar_flechas` (por defecto `not en_vita`), `filtro` (lista blanca). En el PC
`get_frame_latest_time` existe en `RosTfListener` [V geom#15]; `TfLigero` no guarda sello (último valor), así que en
la Vita no hay caducidad por marco [I].

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
## Display TF: ejes por marco (+ flecha al padre en el PC) consultando visor.tf; sin suscripción propia.
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var escala := 0.3
@export var periodo := 0.1
@export var mostrar_nombres := false
@export var mostrar_flechas := true
@export var filtro: PackedStringArray = []          # vacío = todos
var _ejes := {}
var _flechas := {}
var _t := 0.0
func _init() -> void:
	capa = "tf"
func conectar(v) -> void:
	super.conectar(v)                                 # topic = "": no suscribe; reserva el cupo
	if v.en_vita:
		mostrar_flechas = false
func _process(dt: float) -> void:
	_t += dt
	if visor == null or visor.tf == null or _t < periodo:
		return
	_t = 0.0
	for f in visor.tf.get_frame_names():
		if filtro.size() > 0 and not filtro.has(f):
			continue
		if not _ejes.has(f):
			if _ejes.size() >= cupo:
				continue                                  # sin cupo: no se crea (lo avisó reservar())
			_ejes[f] = Prim.instancia(Prim.EJES, Color.WHITE)
			add_child(_ejes[f])
			if mostrar_flechas:
				_flechas[f] = Prim.instancia(Prim.FLECHA, Color(1.0, 0.9, 0.2))
				add_child(_flechas[f])
		var t = visor.transformada(f)
		_ejes[f].visible = t != null
		if t == null:
			continue
		_ejes[f].transform = (t as Transform3D).scaled_local(Vector3.ONE * escala)
		if mostrar_nombres and visor.texto:
			visor.texto.poner("tf/" + f, (t as Transform3D).origin, f)
		if mostrar_flechas:
			var padre: String = visor.tf.get_frame_parent(f)
			var tp = visor.transformada(padre) if padre != "" else null
			var fl = Prim.flecha_hacia((tp as Transform3D).origin - (t as Transform3D).origin) if tp != null else null
			_flechas[f].visible = fl != null
			if fl != null:
				_flechas[f].transform = Transform3D((fl as Transform3D).basis, (t as Transform3D).origin)
func _coste() -> Dictionary: return {"instancias": 32, "triangulos": 32 * 36, "quads": 0}
```

#### 4.3.4 `TfLigero` — A geom#16 → ⚖ D3

Código en §2.9.6. Cambios frente a la ficha: fuentes locales por defecto (no `/tf` crudo); `can_transform` añadido;
`get_frame_latest_time` fuera (sin sellos). Riesgo asumido: dos implementaciones de TF (GDScript ahora, C en V13) →
prueba común con los casos de `modules/tf-tree/tests/parity_test.c`. Cuando se registre el `RosTfListener` nativo,
`VisorRos` lo elige por `has_method` y `TfLigero` queda de respaldo en el host.

#### 4.3.5 `JointState` + URDF = RobotModel (`3d/robot_joints.gd`) — V geom#17

Representación: escena horneada en el PC por `tools/urdf2godot` (ADR 0009) con nombres de link/junta; el display
aplica `set_joints(nombres, posiciones)` (cinemática local, sin TF de links; `godot/g1-unitree/robot/urdf_robot.gd:80`)
y coloca la base con TF (PC) o `/vita/pose2d` (Vita). Campos: `name[i]` ↔ `position[i]`; `velocity`/`effort`
opcionales; *mimic* lo resuelve `urdf_robot.gd`. Vita: JointState de 29 juntas = 1 668 B (pos+vel+eff) / 1 196 B
(solo pos), no cabe (`docs/27:76-77`) → relay `<p>/joints` (Float32 en el orden de `<p>/joints_orden`, String
F+TL), 25 Hz, ≤ 118 juntas (`vita_relay.py:12-13`); JointState pequeño (2 ruedas ≈ 120 B) cabe en directo. LOD Vita
~12 k tri; G1 a 60 FPS en hardware (ADR 0009). `/robot_description` descartado en la Vita (XML + STL, `docs/25` §5).
Cupo `robot` = 40 instancias. `@export`: `escena_robot` (LOD), `link_raiz` (`base_link`), `marco_mundo` (`odom`).
Al conectar registra los links en `TfLigero` (`registrar_robot`), que así resuelve los marcos del robot sin tráfico.
Pendiente de la ficha (sin código): *Effort display* (esfuerzo por junta en color/anillo) y modo «TF por link» del PC.

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
## RobotModel: escena horneada (ADR 0009) + JointState → set_joints. En la Vita: joints + joints_orden + pose2d.
@export var escena_robot: PackedScene
@export var link_raiz := "base_link"
@export var marco_mundo := "odom"
var robot                                             # urdf_robot.gd: set_joints(nombres, posiciones)
var _orden := PackedStringArray()
var _subs: Array = []
func _init() -> void:
	capa = "robot"
	hz = 25.0
	frame_id = "base_link"
func conectar(v) -> void:
	super.conectar(v)
	if cupo == 0:
		return
	robot = escena_robot.instantiate()
	add_child(robot)                                   # sin owner: no se guarda en la escena (doc 35)
	if v.tf != null and v.tf.has_method("registrar_robot"):
		v.tf.registrar_robot(robot, link_raiz)       # TfLigero: marcos de los links sin tráfico (D3)
	if canal.compacto:                                 # suscripciones auxiliares del relay
		var n = v.contexto.nodo
		_subs.append(n.create_subscription(v.prefijo_compacto + "/joints_orden", "std_msgs/msg/String",
				func(m): _orden = String(m.data).split(","), v.contexto.qos(false, 1, true)))
		_subs.append(n.create_subscription(v.prefijo_compacto + "/pose2d", "std_msgs/msg/Float32MultiArray",
				func(m): v.tf.desde_pose2d(m.data, marco_mundo, link_raiz), v.contexto.qos(true, 1, false)))
func _procesar(msg): return [PackedStringArray(msg.name), msg.position]
func _procesar_compacto(msg): return null if _orden.is_empty() else [_orden, msg.data]
func _pintar(d) -> void:
	robot.set_joints(d[0], d[1])
func _coste() -> Dictionary: return {"instancias": 40, "triangulos": 12000, "quads": 0}
```

`frame_id = "base_link"`: la base del robot se coloca con `visor.transformada("base_link")` (TF del PC o, en la Vita,
`TfLigero` alimentado por `pose2d`). [I] `Callable` lambda como callback de `create_subscription` en `ros2_vita`:
comprobar en V1 (la ficha geom#16 ya lo marcaba con `Callable.bind`).

### 4.4 Sensores pequeños, HUD de estado y mando

#### 4.4.1 `Imu` (`3d/imu.gd`) — V geom#18

`EJES` con la orientación **absoluta** en la posición del IMU (no se compone con TF, como `rviz_imu_plugin`) [I] +
flecha de aceleración lineal (amarilla, m/s² × `escala_acel`; en reposo +9,81 en Z) + flecha de velocidad angular
(cian). `orientation_covariance[0] == -1` ⇒ sin orientación (Imu.msg) → ejes ocultos. Planta 2D: brújula de yaw +
burbuja. Vita: 316–324 B, cabe a 30–60 Hz (`docs/27:83`); si el IMU publica a 100 Hz → `<p>/ritmo/imu` a 20 Hz
(módulo `ritmo`, D8). La Vita es sobre todo **publicadora** de su Imu (`godot/plantillas/sensores/imu.gd`).
`@export`: `escala_acel` (0,05 m por m/s²), `escala_giro` (0,5 m por rad/s). 3 instancias ≈ 84 tri.

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var escala_acel := 0.05
@export var escala_giro := 0.5
var _ejes: MeshInstance3D
var _acel: MeshInstance3D
var _giro: MeshInstance3D
func conectar(v) -> void:
	super.conectar(v)
	_ejes = Prim.instancia(Prim.EJES, Color.WHITE)
	_acel = Prim.instancia(Prim.FLECHA, Color(1, 0.8, 0))
	_giro = Prim.instancia(Prim.FLECHA, Color(0, 0.8, 1))
	for n in [_ejes, _acel, _giro]:
		add_child(n)
func _procesar(msg):
	var o = msg.orientation
	var q = null
	if msg.orientation_covariance[0] != -1.0:
		q = rclgd.ros_to_godot_quat(Quaternion(o.x, o.y, o.z, o.w).normalized())
	var a = msg.linear_acceleration
	var w = msg.angular_velocity
	return [q, rclgd.ros_to_godot_vector(Vector3(a.x, a.y, a.z)) * escala_acel,
			rclgd.ros_to_godot_vector(Vector3(w.x, w.y, w.z)) * escala_giro]
func _pintar(d) -> void:
	_ejes.visible = d[0] != null
	if d[0] != null:                                   # orientación absoluta: se anula la rotación del marco
		_ejes.transform = Transform3D(transform.basis.inverse() * Basis(d[0] as Quaternion), Vector3.ZERO)
	for par in [[_acel, d[1]], [_giro, d[2]]]:
		var t = Prim.flecha_hacia(par[1])
		par[0].visible = t != null
		if t != null:
			par[0].transform = t
func _coste() -> Dictionary: return {"instancias": 3, "triangulos": 84, "quads": 0}
```

#### 4.4.2 `MagneticField` (`3d/magnetico.gd`) — V geom#19

Flecha del campo en µT × `escala` (m por µT) en el marco del sensor + rumbo para una brújula 2D: `atan2(−By, Bx)` en
sensor nivelado, ENU [I: signos según montaje]; |B| (25–65 µT en la Tierra) como validez. Campos: `magnetic_field`
(T) ×1e6 → µT; `magnetic_field_covariance[0] = 0` ⇒ desconocida. 124 B. Magnetómetro de la Vita no accesible por la
API usada en G7 [?]. Esqueleto = el de vector (§4.2.2) con `_procesar` que además guarda `rumbo_grados` y
`modulo_ut`; `@export declinacion_grados` para rumbo verdadero.

#### 4.4.3 `NavSatFix` (`2d/gps.gd`) — V geom#20

Planta 2D: rastro ENU local (plano tangente desde el primer fix) con `draw_polyline` + círculo de 2σ coloreado por
estado (rojo `NO_FIX`, verde `FIX`, azul SBAS/GBAS). PC: fondo opcional de teselas OSM por `HTTPRequest` y caché
(respetar la política de uso de OSM [I]); Vita: teselas prehorneadas en el `.pck` (≤ 9 a la vez: ≥ 256 KiB de CDRAM
cada una y ≤ 48 texturas, H19) o ninguna. **Trampa**: no guardar grados en `Vector2` (float32: 1e-5° ≈ 1 m); origen
en dos `float` de GDScript (64 bit) y conversión a metros antes del `Vector2`. Campos: `latitude/longitude` (°,
WGS84), `status.status` (−1…2), `position_covariance` (ENU, m²) y `position_covariance_type`. 125 B.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
const R_TIERRA := 6378137.0
@export var max_puntos := 300
var _lat0 := NAN                                       # float de GDScript = 64 bit; NO Vector2
var _lon0 := 0.0
var _rastro := PackedVector2Array()                   # metros ENU (este, norte)
var _sigma := 0.0
var _estado := -1
func _init() -> void:
	hz = 5.0
func _procesar(msg):
	_estado = int(msg.status.status)
	if _estado < 0 or is_nan(msg.latitude):
		return null
	if is_nan(_lat0):
		_lat0 = msg.latitude
		_lon0 = msg.longitude
	var este: float = deg_to_rad(msg.longitude - _lon0) * R_TIERRA * cos(deg_to_rad(_lat0))
	var norte: float = deg_to_rad(msg.latitude - _lat0) * R_TIERRA
	var c: PackedFloat64Array = msg.position_covariance
	_sigma = sqrt(maxf(c[0], c[4])) if int(msg.position_covariance_type) > 0 else 0.0
	return Vector2(este, norte)
func _pintar(p) -> void:
	_rastro.append(p)
	if _rastro.size() > max_puntos:
		_rastro.remove_at(0)
	queue_redraw()
func _draw() -> void:
	if _rastro.is_empty():
		return
	var pts := PackedVector2Array()
	for q in _rastro:
		pts.append(px(q))
	if pts.size() >= 2:
		draw_polyline(pts, Color(0.2, 0.8, 1.0), -1.0)
	var col := Paleta.ERROR if _estado < 0 else (Paleta.OK if _estado == 0 else Color.DODGER_BLUE)
	draw_arc(pts[-1], maxf(2.0 * _sigma * visor.px_por_m, 3.0), 0.0, TAU, 24, col, -1.0)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 60}
```

(`const Paleta = preload("res://comun/visor/paleta_viz.gd")` en la cabecera.) El marco del display es el fijo
(`frame_id = visor.marco_fijo`): el GPS no tiene TF a `map` salvo `navsat_transform` [I].

#### 4.4.4 `Range` (`3d/rango.gd`, `2d/rango.gd`) — V geom#21

`CONO` unidad (vértice en el origen, base en z = −1, radio 0,5) escalado por `transform` a (ancho, ancho, r) con
`ancho = 2·r·tan(fov/2)`; r fuera de `[min_range, max_range]` ⇒ oculto, salvo `−Inf` en sensor de distancia fija
(`min = max`) ⇒ `min_range` (`range_display.cpp getDisplayedRange`). **Filtro con NaN** (§8): `r >= min and r <= max`.
Vita: cono opaco (sin orden de transparencias) de 16 tri o sector 2D `draw_colored_polygon` (3–6 vértices). 52 B a
60 Hz. Color por `radiation_type` (0 ultrasonido, 1 infrarrojo).

```gdscript
func _procesar(msg):
	var r: float = msg.range
	if r >= msg.min_range and r <= msg.max_range:
		pass
	elif msg.min_range == msg.max_range and is_inf(r) and r < 0.0:
		r = msg.min_range
	else:
		return 0.0                                        # fuera de rango: ocultar
	return Vector2(r, 2.0 * r * tan(msg.field_of_view * 0.5))
func _pintar(d) -> void:                                # d = 0.0 o Vector2(largo, ancho)
	_cono.visible = d is Vector2
	if d is Vector2:
		_cono.transform = Transform3D(Basis.from_scale(Vector3(d.y, d.y, d.x)), Vector3.ZERO)
```

#### 4.4.5 Medidores ambientales (`hud/medidor.gd`): `Temperature`, `FluidPressure`, `Illuminance`, `RelativeHumidity` — V hmi#3–6

Barra con umbrales verde/amarillo/rojo (colores de rqt_robot_monitor), valor con unidades y *sparkline* (una
polilínea fina = 1 comando). Un solo script; cada tipo es configuración:

| Tipo | `campo` | `escala` | `unidad` | `minimo`–`maximo` (`aviso`) | Fuente de prueba |
|---|---|---:|---|---|---|
| `Temperature` | `temperature` | 1 | °C | −10–60 (45) | — |
| `FluidPressure` | `fluid_pressure` | 0,01 | hPa | 950–1 050 (1 040) | `plantillas/sensores/barometro.gd` (5 Hz XRCE, `:14-20`) |
| `Illuminance` | `illuminance` | 1 | lx | 0–2 000 (1 500) | `ros2 topic pub` |
| `RelativeHumidity` | `relative_humidity` | 100 | % | 0–100 (80) | `ros2 topic pub` |

44 B cada uno; `FluidPressure` ya está en `generar_esquemas.py:32`, los otros tres entran por `TIPOS_VISOR` [V].

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
@export var campo := "temperature"
@export var escala := 1.0
@export var unidad := "°C"
@export var minimo := -10.0
@export var maximo := 60.0
@export var aviso := 45.0
@export var muestras := 60
var _serie := PackedFloat32Array()
func _procesar(msg):
	var v := float(msg.get_member(campo)) * escala
	_serie.append(v)
	if _serie.size() > muestras:
		_serie.remove_at(0)
	return v
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.12))
	if datos == null:
		return
	var v: float = datos
	var c := color_estado(Paleta.OK if v < aviso else (Paleta.WARN if v < maximo else Paleta.ERROR))
	draw_rect(Rect2(0, size.y - 6, size.x * clampf(inverse_lerp(minimo, maximo, v), 0.0, 1.0), 6), c)
	draw_string(get_theme_default_font(), Vector2(4, 14), "%.1f %s" % [v, unidad], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
	var pts := PackedVector2Array()
	for i in _serie.size():
		var f := clampf(inverse_lerp(minimo, maximo, _serie[i]), 0.0, 1.0)
		pts.append(Vector2(size.x * i / maxf(1.0, muestras - 1), 18.0 + (size.y - 26.0) * (1.0 - f)))
	if pts.size() > 1:
		draw_polyline(pts, c, -1.0)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 30}
```

#### 4.4.6 `BatteryState` (`hud/bateria.gd`, barra fija) — V hmi#2

Icono con relleno = `percentage` (NaN = no medido → `charge/capacity`), rojo si la salud es mala
(`power_supply_health` 2–8) o < `umbral_bajo` (0,2); texto «V A estado». Hz bajo (0,2–1 Hz,
`plantillas/sensores/bateria.gd:15-16`) ⇒ `caducidad_s = 15`. 89 B (sin celdas) / 133 B (6 celdas); esquema ya en
`generar_esquemas.py:30`. ≈ 40 *quads*. El esqueleto de hmi#2 vale cambiando `extends` a `display_ros_hud.gd`,
`_recibir(m)` por `_procesar(msg)` que **devuelve** `[pct, texto, alarma]`, y `caducado()` por `gris`.

#### 4.4.7 `Joy` (`hud/joy.gd`) y fuente `/vita/joy` — V hmi#1

Visor: dos sticks (arco + punto) y fila de botones; ≈ 70 *quads*; 128 B (8 ejes, 17 botones) a 20 Hz. Fuente: la Vita
publica `/vita/joy` (best effort, 20 Hz, 128 B; ⚖ §6) desde `Input.get_joy_axis` / `is_joy_button_pressed` **negando X
e Y** (en Godot el eje Y del stick es positivo hacia abajo, `godot/g6-hmi/main.gd:85-86`; en `joy`, arriba e
izquierda = +1 [I]). Esqueleto de hmi#1 con el mismo cambio de `extends`/`_procesar`; `@export pares_sticks`,
`invertir_x`.

### 4.5 Sensores densos (familia `sensores-densos`)

Regla de corte (`docs/31` §4.1): relay si el CDR pasa de 488 B → C++ del motor (JPEG/PNG, `blit_rect`) → GDScript si
≤ 2 ms por mensaje → C en `viz-decode` (V13). **Ningún bucle por píxel en GDScript** (14–35 ms por 640×480 en el
host de pruebas [V]: inviable incluso en el PC a 30 Hz). Código de sensores probado en headless con mensajes reales
(esquema `godot/g1-sensores/ros/schema.rsch`, ida y vuelta `serialize()`/`deserialize()`); tiempos en un Ryzen 7
5800X; la Vita, 20–40× más lenta en GDScript [I] (1,5 µs/instrucción, `docs/31:162`).

#### 4.5.1 `LaserScan` (`2d/scan.gd`; `3d/scan_puntos.gd` `solo_pc`) — V sens#0; D sens#1 → ⚖ D4

Vita (y planta en el PC): **un** triángulo por punto en **una** llamada `canvas_item_add_triangle_array`, redibujado
solo al llegar mensaje (H16–H17). Tabla de direcciones cos/sin recalculada solo si cambian `angle_min`,
`angle_increment` o n (`docs/31:210`; 720 rayos: 711 → 263–340 µs en host [V]). **Filtro REP-117 con NaN** (§8):
`if not (r >= range_min and r <= range_max): continue`. Cifra corregida (D4): un LaserScan con frame `base_scan` y sin
intensidades cabe hasta 107 rayos (488 B con rosbags = 484 B de carga), no 106; da igual: los escáneres reales
(360–720 rayos, 1 504–5 824 B) van por `<p>/scan_compacto` (Int16 cm, ≤ 180 rayos, 384 B, 10 Hz; `docs/27:61-64,98`).
El simulador de plantillas publica 60 rayos (`plantillas/sensores/lidar_2d.gd:6`), que sí caben en directo. Cupo
2D: scan ≤ 360 *quads*. `@export`: `lado_px` (3), `color`; `frame_id` del sensor (p. ej. `base_scan`) para el
compacto, que no trae header.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## LaserScan en planta: UN lote por mensaje. datos = PackedVector2Array (m, marco del sensor).
const VitaRelay = preload("res://comun/vita_relay.gd")
@export var lado_px := 3.0
@export var color := Color(1, 0.2, 0.2)
var _dirs := PackedVector2Array()
var _clave := Vector3.INF
var _v := PackedVector2Array()
var _c := PackedColorArray()
var _idx := PackedInt32Array()
func _init() -> void:
	hz = 10.0
func _procesar(msg):
	var r: PackedFloat32Array = msg.ranges
	var clave := Vector3(msg.angle_min, msg.angle_increment, r.size())
	if clave != _clave:                                   # cos/sin solo si cambia la geometría
		_clave = clave
		_dirs.resize(r.size())
		for i in r.size():
			_dirs[i] = Vector2.from_angle(msg.angle_min + i * msg.angle_increment)
	var out := PackedVector2Array()
	for i in r.size():
		if not (r[i] >= msg.range_min and r[i] <= msg.range_max):   # ±Inf y NaN fuera (REP-117)
			continue
		out.append(_dirs[i] * r[i])
	return out
func _procesar_compacto(msg): return VitaRelay.scan_puntos(msg)   # vita_relay.gd:95-109 (0 = sin dato)
func _pintar(puntos) -> void:
	var n: int = mini(puntos.size(), cupo)               # cupo en quads = puntos
	_v.resize(n * 3)
	_c.resize(n * 3)
	for i in n:
		var p := px(puntos[i])
		_v[3 * i] = p + Vector2(0, -lado_px)
		_v[3 * i + 1] = p + Vector2(lado_px, lado_px)
		_v[3 * i + 2] = p + Vector2(-lado_px, lado_px)
		_c[3 * i] = color
		_c[3 * i + 1] = color
		_c[3 * i + 2] = color
	if _idx.size() != n * 3:
		_idx = PackedInt32Array(range(n * 3))
	queue_redraw()
func _draw() -> void:
	if _v.size() > 0:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _v, _c)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 360}
```

`VitaRelay.scan_puntos` tiene su propio bucle cos/sin por rayo (`vita_relay.gd:95-109`); el arreglo de
`docs/31` §4.4 (tabla de direcciones) entra en V3. PC (`3d/scan_puntos.gd`, `solo_pc`): `ArrayMesh`
`PRIMITIVE_POINTS` con color por intensidad (LUT arcoíris de 256, `Color.from_hsv(0.8333·(1 − k/255), 1, 1)`),
`use_point_size`; *decay* (`persistencia_s`) = una `MeshInstance3D` congelada (`top_level`) por barrido liberada con
un temporizador. Código de sens#0 cambiando `iniciar(nodo, topic)` por la base y `decay_s` por `persistencia_s`.

#### 4.5.2 `MultiEchoLaserScan` — V sens#2

Aplanar a LaserScan eligiendo eco (`primero` / `ultimo` / `mas_fuerte` / `todos`) y reutilizar el display de scan
(PC). 360 haces × 3 ecos + intensidades = 11 584 B: no cabe ni en fiable; en la Vita el relay elige el eco y emite
`scan_compacto`. Coste PC dominado por envolver 2·N `RosMsg` (`LaserEcho`, camino lento de arrays compuestos;
360 haces ≈ 1–2 ms [I]). Esqueleto de sens#2 con `_procesar` que devuelve el `PackedVector2Array`; con `todos`, los
ecos de un haz comparten ángulo (mejor que repartir el incremento, hueco anotado en la ficha).

#### 4.5.3 `PointCloud2` (`2d/nube.gd`; `3d/nube_puntos.gd` `solo_pc`) — V sens#3; A sens#4 → ⚖ D5

PC: decodificador genérico por `fields[].name/offset/datatype` con `decode_float(i·point_step + off)` sobre el
`PackedByteArray`, diezmado uniforme hasta `max_puntos`, color por campo (LUT arcoíris), `rgb` empaquetado
(`decode_u32` → `Color8`), NaN fuera con `Vector3.is_finite()`; `ArrayMesh PRIMITIVE_POINTS` bajo un nodo con
`basis = C` (sin conversión por punto). `is_bigendian` → `data.bswap32()` **solo si todos los campos son de 4 B**
(RViz no lo trata). Coste ≈ 0,2 µs/punto en GDScript (10 k = 1,9 ms) [V host]; ruta rápida si xyz(i) float32
contiguos: `to_vector3_array()`/`to_vector4_array()` (36–48 µs/10 k, Godot ≥ 4.7) [V]; > 50 k puntos a 10 Hz →
textura + *vertex shader* con `VERTEX_ID` (hueco V14).
Vita: no cabe (20 puntos xyzi = 461 B; 100 = 1 741 B). ⚖ D5: relay `<p>/nube2d` = Int16 **cabecera común**
`[seq, trozo, n_trozos, n]` + xyz en cm·n, **n ≤ 76** (480 B; la ficha proponía 78 con cabecera de 3, 486/492 B según
convención), vóxel 10 cm, ≤ 228 puntos (3 trozos), 5 Hz. Planta 2D con un lote por trozo y color por banda de altura
(paleta de 16, como el «Axis color» de RViz). Cupo: nube ≤ 228 *quads*. GDScript ≈ 1,7 ms por trozo en la Vita [I]
(`docs/31:184`); `vizd_cloud_cm` en C cuando exista (V13). Recomendado [I]: que el relay transforme la nube a `map`
(la Vita no tiene `/tf` completo) y la mande con el marco fijo.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## PointCloud2 en la Vita: <p>/nube2d (Int16, cm). datos = [trozo, PackedVector2Array px, PackedColorArray].
const Vc1 = preload("res://comun/ros/vc1.gd")
@export var alturas := Vector2(-0.2, 2.0)
@export var lado_px := 2.0
var _trozos := {}
var _seq := -1
var _lut := PackedColorArray(range(16).map(func(k): return Color.from_hsv(0.66 * (1.0 - k / 15.0), 1, 1)))
func _init() -> void:
	hz = 0.0                                            # todos los trozos: no coalescer por tiempo
	topic_vita = "nube2d"
	tipo_vita = "std_msgs/msg/Int16MultiArray"
func conectar(v) -> void:
	canal.coalescer = false                             # cada trozo cuenta
	super.conectar(v)
func _procesar_compacto(msg):
	var d: PackedInt32Array = msg.data                  # int16[] llega como PackedInt32Array (H25)
	var cab: Dictionary = Vc1.cabecera(d)               # {seq, trozo, n_trozos, n} (§5.3)
	if cab.is_empty():
		return null
	if cab.seq != _seq:
		_seq = cab.seq
		_trozos.clear()                                 # nueva nube
	var v := PackedVector2Array()
	var c := PackedColorArray()
	var esc := 15.0 / (alturas.y - alturas.x)
	for i in cab.n:
		var b := 4 + 3 * i
		var p := px(Vector2(d[b], d[b + 1]) / 100.0)
		var col := _lut[clampi(int((d[b + 2] / 100.0 - alturas.x) * esc), 0, 15)]
		v.append_array([p + Vector2(0, -lado_px), p + Vector2(lado_px, lado_px), p + Vector2(-lado_px, lado_px)])
		c.append_array([col, col, col])
	return [cab.trozo, v, c]
func _pintar(t) -> void:
	_trozos[t[0]] = [t[1], t[2]]
	queue_redraw()
func _draw() -> void:                                  # un lote por trozo (≤ 3); color plano → se funde (H16)
	for t in _trozos.values():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(range(t[0].size())), t[0], t[1])
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 228}
```

El esqueleto PC (`3d/nube_puntos.gd`) es el de sens#3 con `_procesar` devolviendo `[pts, col]` y `_pintar` creando
la `ArrayMesh`; `@export campo_color` («» | `intensity` | `z` | `rgb`), `rango_color`, `max_puntos` (60 000),
`tam_px` (3). Orden exacto del arcoíris de RViz (`getRainbowColor`) [?] → `@export invertir_arcoiris`.

#### 4.5.4 `PointCloud` (obsoleto) — V sens#5

Como RViz: convertir a PointCloud2 **fuera de Godot** (`point_cloud_converter` o el relay). Respaldo GDScript en sens#5
(un `RosMsg` por `Point32`: ≈ 1–3 µs por punto [I], solo nubes pequeñas). Sin esquema en la Vita.

#### 4.5.5 `Image` (`hud/imagen.gd`, `solo_pc`) — V sens#6, V sens#8, D sens#7

PC: `Image.create_from_data` con el formato equivalente (cero conversión) + `ImageTexture.update` reutilizando la
textura; intercambio de canales y profundidad en un *shader* `canvas_item`:

| `encoding` | `Image.Format` | Modo del *shader* | Nota |
|---|---|---|---|
| `rgb8`, `8UC3` | `FORMAT_RGB8` | 0 directo | |
| `rgba8` | `FORMAT_RGBA8` | 0 | |
| `bgr8` / `bgra8` | `RGB8` / `RGBA8` | 1 (`.bgr`) | |
| `mono8`, `8UC1`, `bayer_*8` | `FORMAT_L8` | 0 | bayer en gris, como RViz (sin demosaico) |
| `mono16`, `16UC1` | `FORMAT_R16` (unorm) | 2: `z = r·65,535` m | 16UC1 en mm (REP-118) [I] |
| `32FC1` | `FORMAT_RF` | 3: `z = r` m | 0/NaN/Inf transparentes |
| `yuv422`(=uyvy), `uyvy`, `yuyv`, `yuv422_yuy2` | `RGBA8` de ancho/2 | YUV→RGB (BT.601 completo [I]) | script aparte `imagen_yuv.gd` (sens#8) |

Profundidad (D sens#7): la ficha no traía código propio — el bloque es el de sens#6, que **sí** cubre R16 y RF con
los modos 2 y 3 del *shader*; lo que queda sin código va a «Por resolver» (§9.3): `16SC1` (`FORMAT_R16I` +
`usampler` [?]), `64FC1`, `nv21`/`nv24`, codificaciones de color de 16 bit, filas con relleno (`step ≠ w·bpp`: hoy se
rechazan), auto-rango (Normalize Range + mediana de 5 fotogramas). `FORMAT_R16`, `to_vector*_array` y `bswap*`
existen en Godot 4.7 (rclgd) y 4.8-dev7 (Vita), **no en 4.4** [V]. `Image.convert(R16→L8)` existe pero escala
0–65 535 → 0–255 (5 m = 0,08 → casi negro) [V medido]. El esqueleto es el de sens#6 tal cual (constantes `FMT`,
`SH`) con `_procesar` → `[img, modo]` y `_pintar` que hace `create_from_image` la primera vez o `update` si coinciden
tamaño y formato.

#### 4.5.6 Imagen en la Vita y `CompressedImage` (`hud/imagen_comprimida.gd`) — V sens#10; D sens#9 → ⚖ D13

⚖ D13: la Vita **nunca** recibe imagen cruda. Relay `<p>/camara/compressed` = `sensor_msgs/msg/CompressedImage`
JPEG **160×120 q40** (≤ 3 KB), **fiable**, **3 Hz** por defecto (parámetro `camara_hz`, máximo 5 y solo si el relay entero sigue ≤ 40 KB/s nominales: con el perfil `percepcion` se queda en 3, `V3-juez-fable.md` F3; la ficha decía 5).
Mismo script en PC y Vita (el tipo estándar ya está en `generar_esquemas.py:25`): decodifica el motor
(`Image.load_jpg_from_buffer`/`load_png_from_buffer`, H22; libjpeg sin SIMD en la Vita). La recepción fiable no
bloquea el hilo principal (la que bloquea es la emisión, `docs/27:13-15`). Coste Vita [I]: 1–2 ms decodificar +
1–3 ms `update` ≈ 3–6 ms por imagen (`docs/31:183`) → gate **E-W8-5** (≤ 6 ms). Profundidad: el relay la entrega ya
coloreada en JPEG. Descartados: miniaturas `mono8` (80×60 = 4 848 B, más grande y peor) y trocear en best effort.
`format` de image_transport: `"rgb8; jpeg compressed bgr8"` → Godot ya da RGB tras decodificar. PNG de 16 bit:
el cargador de Godot lo baja a 8 bit (`png_driver_common.cpp:72-106`) [V] → `compressedDepth` se descarta aquí.

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## CompressedImage jpeg/png (PC y Vita: decodifica el motor, H22). Pestaña Cámara.
@export var rect: TextureRect                         # en la escena; stretch KEEP_ASPECT_CENTERED
var _tex: ImageTexture
var _img := Image.new()
func _init() -> void:
	topic_vita = "camara/compressed"
	tipo = "sensor_msgs/msg/CompressedImage"
	tipo_vita = "sensor_msgs/msg/CompressedImage"
	fiabilidad = 2                                      # FIABLE: ≈ 3 KB no cabe en 488 B (§6)
	profundidad = 1
	hz = 15.0
	hz_vita = 3.0
	caducidad_s = 2.0
func _procesar(msg):
	var f := String(msg.format)
	if "compressedDepth" in f:
		return null                                     # PNG de 16 bit: se perdería precisión (§8)
	var data: PackedByteArray = msg.data
	var err := _img.load_png_from_buffer(data) if "png" in f else _img.load_jpg_from_buffer(data)
	return _img if err == OK else null
func _pintar(img) -> void:
	if _tex == null or _tex.get_size() != Vector2(img.get_size()):
		_tex = ImageTexture.create_from_image(img)
		rect.texture = _tex
	else:
		_tex.update(img)                                # mismo tamaño y formato: sin realojar (H19)
func _caducar() -> void:
	rect.modulate = Color(1, 1, 1, 0.4) if gris else Color.WHITE
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 1}
```

`compressedDepth` (V sens#11): no se decodifica en Godot; `ros2 run image_transport republish compressedDepth raw`
(PC) o el relay, y se usa §4.5.5. Formato: `ConfigHeader` (12 B [I]) + PNG 16 bit o RVL; 32FC1 cuantizado como
inversa `D = A/(v − B)`.

#### 4.5.7 `CameraInfo` (`3d/camara_info.gd`) — D sens#12 → corrección

Frustum desde K, `width`, `height` (rehecho solo si cambia K) y, opcionalmente, óptica aplicada a una `Camera3D` con
`set_frustum` (tamaño y desplazamiento del plano cercano desde fy, cx, cy). Marco óptico (x der, y abajo, z delante)
→ Godot local (x, −y, −z). **Correcciones**: (1) tamaño 357 B con frame `camera` (no 381; depende del frame), cabe
igual; (2) `ImmediateMesh`/`PRIMITIVE_LINES` **solo vale en el PC** (H1): en la Vita, 4 prismas finos
(6 tri/segmento, `docs/31` §2.2, cupo `reserva`) o el frustum en 2D superpuesto; no hay SubViewport 3D en el port
(G7c). Pendiente [I]: usar P (`p[0], p[5], p[2], p[6]`) en vez de K para imágenes rectificadas, como el display Camera
de RViz; signo del desplazamiento (convención de centro de píxel) por comparar con una imagen real. El esqueleto de
sens#12 vale en el PC con `_procesar` → `[k, w, h]` (o `null` si no cambia).

#### 4.5.8 Display «Camera» (`hud/camara.gd`, `solo_pc`) — M sens#13

PC: `SubViewport` con fondo transparente y `world_3d` compartido, `Camera3D` en el frame óptico con la óptica de
`camara_info.gd`, superpuesto con alfa a la imagen. Vita: sin SubViewport 3D → «modo cámara»: la cámara principal
se mueve al frame óptico, `set_frustum`, y la imagen va como `TextureRect` HUD semitransparente encima (fondo
transparente por defecto [?]); coste = el del 3D principal. **Por medir** (sin ejecutar [I]); sincronizar imagen y
TF por `stamp` necesita `lookup_transform` con tiempo (en la Vita no hay) → §9.3. Esqueleto de sens#13 sin cambios
salvo `extends` de un `DisplayRosHud` contenedor con `solo_pc = true`.

#### 4.5.9 DepthCloud (`3d/nube_profundidad.gd`, `solo_pc`) — V sens#14

Todo en GPU: profundidad como textura R16/RF y una malla de w×h puntos (creada una vez) desproyectada en el *vertex
shader* con fx, fy, cx, cy (`VERTEX_ID` → píxel): cero bucles GDScript (RViz lo hace en CPU). Vita: no (sin
*shaders*); el relay desproyecta y reduce a `nube2d`. Esqueleto de sens#14 tal cual (dos suscripciones: `CameraInfo`
y `Image`; la segunda es la del canal, la primera auxiliar con `contexto.qos(true, 1, false)`).

### 4.6 Mapas y rejillas (familia `mapas-marcadores`, primera mitad)

#### 4.6.1 `OccupancyGrid` «map», «costmap», «raw» (`2d/mapa.gd`; `3d/mapa.gd`) — V mapas#0–2

PC (`3d/mapa.gd`): *quad* en el suelo con dos texturas — datos crudos (`m.data.to_byte_array()` → `RGBA8` con el byte
en R, **sin bucles GDScript**) y paleta 256×1 — y un *shader* de tres líneas que busca el color (`texelFetch`), como
RViz. Paletas = ports literales de `palette_builder.cpp:87-152` (map: gris invertido; costmap: 0 transparente,
1–98 azul→rojo, 99 cian inscrito, 100 magenta letal, −1 `0x708986`; raw: gris lineal), en `PaletaViz.rampa_mapa()`
(§3.3). Campos: `info.resolution`, `info.width/height`, `info.origin` (pose de la **esquina** de la celda (0,0), no
del centro) → `Transform3D`; celda (i,j) = `data[j·width + i]`, fila 0 en el origen. `@export`: `esquema`
(map|costmap|raw), `alfa`, `binaria` + `umbral`; QoS *latched* (fiable + TRANSIENT_LOCAL); `update_topic` = `topic +
"_updates"` (`map_display.cpp:222-225`).
Vita: un mapa no cabe (384² = 147 560 B, `docs/27:65`): relay VC/1 `<p>/mapa_meta` (F+TL) + `<p>/mapa_tesela`
(32×32 a 2 bit, best effort, ≤ 20/s), que ya consume `godot/plantillas/vita_relay.gd`. **Arreglo de V3**
(`docs/31` §4.4): decodificar cada tesela con LUT de 256 entradas (byte → 4 celdas RGBA) + `Image.create_from_data` +
`blit_rect` en vez de los 1 024 `set_pixel` actuales (`vita_relay.gd:56-67`): ≈ 1–1,5 ms por tesela frente a ≈ 20 ms
[I]; textura troceada en sub-texturas de 128² y subida de **una sucia por fotograma** a ≤ 4 Hz (`HZ_TEXTURA`,
`vita_relay.gd:16`; H19). Sin *shaders* la paleta «map» se reduce a 3 colores (2 bit). Capa: textura en la planta
(por defecto) o 2–18 tri / 1–9 *draws* en 3D (cupo `mundo` = 12). Gate **G-W13-M4** (mapa 384² por relay con
LUT + `blit_rect`: `process` ≤ 4 ms, textura estable 5 min).

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## Mapa en planta (Vita y PC). Estándar: OccupancyGrid entero; compacto: teselas VC/1 vía vita_relay.gd.
const VitaRelay = preload("res://comun/vita_relay.gd")
var relay = VitaRelay.new()                           # mantiene mapa_img/mapa_tex y la época
var _sub_meta
func _init() -> void:
	latched = true
	topic_vita = "mapa_tesela"
	tipo_vita = "std_msgs/msg/UInt8MultiArray"
	hz = 0.0                                          # teselas: entregar todas
func conectar(v) -> void:
	canal.coalescer = false
	super.conectar(v)
	if canal.compacto:                                # la meta es latched aparte (F+TL)
		_sub_meta = v.contexto.nodo.create_subscription(v.prefijo_compacto + "/mapa_meta",
				"std_msgs/msg/Float32MultiArray", relay.on_mapa_meta, v.contexto.qos(false, 1, true))
func _procesar(msg):                                  # PC/planta: el OccupancyGrid entero (latched)
	return msg                                        # _pintar lo pasa a textura con la LUT (sin set_pixel)
func _procesar_compacto(msg):
	relay.on_mapa_tesela(msg)                         # V3: LUT + blit_rect dentro de vita_relay.gd
	return true
func _process(dt: float) -> void:
	super._process(dt)
	relay.actualizar_textura()                        # ≤ HZ_TEXTURA
	queue_redraw()                                    # [I] solo si cambió la textura: señal mapa_cambiado
func _draw() -> void:
	if relay.mapa_tex == null:
		return
	var o := px(relay.origen)
	var tam := Vector2(relay.ancho, relay.alto) * relay.resolucion * visor.px_por_m
	draw_texture_rect(relay.mapa_tex, Rect2(o - Vector2(0, tam.y), tam), false)   # norte arriba
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 1}
```

`_pintar` del camino estándar (no mostrado): `Image.create_from_data(w, h, false, FORMAT_RGBA8, data.to_byte_array())`
y, en planta sin *shader*, paso por la LUT de la paleta; en 3D (PC), el material de mapas#0 tal cual.

#### 4.6.2 Costmap en la Vita — V mapas#1 → módulo `costmap` (V11)

Sin *shaders* ni orden de transparencias (`docs/31` §2.4): el costmap se **compone en CPU sobre la imagen del mapa**
(una textura). El 2 bit de VC/1 pierde el degradado → formato nuevo ⚖ D5: `<p>/costmap_tesela` = `UInt8MultiArray`
`[ver_lo, ver_hi, tx, ty]` + tesela **32×16 a 4 bit** (0 desconocido, 1 libre = transparente, 2–13 degradado, 14
inscrito, 15 letal), 260 B (276 con rosbags), BE ≤ 10/s; `<p>/costmap_meta` como `mapa_meta`. El relay baja la
resolución por máximo a ≥ 10 cm. LUT de 16 colores sacada de la misma paleta (`PaletaViz.lut16_costmap()`, índices
`[255, 0, 8, 16, …, 88, 98, 99, 100]` de mapas#1). Costmap global de 10 cm 200×200 = 91 teselas ≈ 24 KB por repaso [I].
Gate **G-W13-M5**: costmap 4 bit (Nav2 + TB3), repaso completo ≤ 3 s, ≥ 30 FPS. Riesgo [?]: el costmap **local**
rodante (origen que se mueve con el robot) genera meta y teselas nuevas continuamente → §9.3.

#### 4.6.3 `map_msgs/OccupancyGridUpdate` — D mapas#3 → ⚖ D5.5

PC: parche con `Image.blit_rect` sobre la `Image` persistente y subida limitada a ≤ 10 Hz (`hz_subida`); se ignoran
updates sin mapa o fuera de límites (`map_display.cpp:353-410`). Código de mapas#3 tal cual (QoS
`contexto.qos(false, 5)`, como `rclcpp::QoS(5)` de RViz). `map_msgs` no está en el *typestore* de rosbags (habría que
registrar el `.msg`); 40 B + w·h ⇒ solo parches ≤ 21×21 caben. **Corrección del contrato** (⚖ D5.5): hoy el relay
sube `version` con cada `OccupancyGrid` (`vita_relay.py:235`), así que un costmap a 1–5 Hz invalidaría todas las
teselas cada vez: `version` pasa a ser **época de geometría** (solo sube si cambian resolución, tamaño u origen) y
los updates marcan teselas sucias sin tocarla.

#### 4.6.4 `GridCells` (`2d/celdas.gd`; `3d/celdas.gd` `solo_pc`) — V mapas#4

Celdas planas del mismo color. PC: `MultiMeshInstance3D` de losas (código de mapas#4). Vita: 36 + 24·n B ⇒ ≤ 18
celdas en directo (`TIPOS_VISOR`); planta 2D con `canvas_item_add_triangle_array` (1 llamada, 1 *quad* por celda,
cupo `resto_2d`), o fundidas en la tesela del costmap por el relay. Campos: `cell_width/height` (m), `cells[]`
(centros).

#### 4.6.5 `MapMetaData` (`hud/meta_mapa.gd`) — V mapas#5

Solo HUD: resolución, tamaño, origen, hora de carga; sirve para pre-dimensionar la imagen. 84 B: directo con
TRANSIENT_LOCAL (`TIPOS_VISOR`). Equivale a `<p>/mapa_meta`. Esqueleto de mapas#5 con `_procesar` → texto.

#### 4.6.6 `nav2_msgs/Costmap`, `VoxelGrid`; `grid_map_msgs/GridMap`; `octomap_msgs/Octomap` — V mapas#6–9 (`solo_pc`)

- **Costmap raw** (`<costmap>_raw`): preferir el `OccupancyGrid` `costmap` + `costmap_updates`. Si hace falta el coste
  exacto: textura `R8` directa (`uint8[]` → `PackedByteArray`) y paleta con la tabla de traducción de Nav2 ya aplicada
  (0→0, 1–252→1–98, 253→99, 254→100, 255→−1; `costmap_2d_publisher.cpp:101-109`). Código de mapas#6.
- **VoxelGrid**: solo vóxeles **marcados** (`(col >> (16+z)) & 1`, `voxel_grid.hpp:95-150`) a MultiMesh; mejor
  suscribir la PointCloud2 que ya genera Nav2. 200×200 columnas = 40 000 iteraciones GDScript ≈ 5–15 ms [I] → ≤ 2 Hz.
  `data` es `uint32[]` → `PackedInt64Array` en la Vita; en rclgd [?] (§9.3). Vita: relay → `nube2d`.
- **GridMap** (V14): malla de alturas (2 tri por celda) de una capa coloreada por otra; matriz *column-major* con búfer
  circular (`outer/inner_start_index`); `info.pose` = **centro** del mapa; índice (0,0) en la esquina +x,+y [I]. 100×100
  ≈ 30–60 ms en GDScript [I] → ≤ 1 Hz. Vita: relay a raster 2D (reutilizando el formato de `costmap_tesela` como
  rampa de altura); malla 3D ≤ 64×64 solo tras verde de E-W8-2.
- **Octomap** (V14): decodificador binario (2 B por nodo, 2 bit por hijo: 01 ocupado, 11 con hijos; raíz de lado
  `res·2^16`) viable en GDScript en el PC (mapa de habitación a 5 cm ≈ 25–100 k nodos ≈ 50–300 ms [I] → hilo o
  ≤ 0,2 Hz). Vita: relay → lista de vóxeles ocupados a `nube2d`. Código de mapas#9.

Ninguno de `map_msgs`, `nav2_msgs`, `grid_map_msgs`, `octomap_msgs` entra en `TIPOS_VISOR` (⚖ D10): en la Vita
llegan compactados y en el PC rclgd los resuelve por ament.

### 4.7 Marcadores (familia `mapas-marcadores`, segunda mitad)

Regla de capa en la Vita (ADR 0011, `docs/31` §0): **sólido rígido → 3D por instancia** (mover = cambiar
`transform`, 0 B de arena); **líneas, puntos, texto → 2D** en un comando por display (H16–H17); **raster →
textura**. Cupo `marcadores`: HMI 12 / Viz 32 (⚖ D7; la ficha proponía 48).

#### 4.7.1 Gestor de `Marker` (`3d/marcadores.gd`) — D mapas#10 → corrección aplicada

Semántica de RViz2 Jazzy (`marker_common.cpp:205-310`, `marker_base.cpp:84-115`):

- **Clave** ns → {id → entrada}; DELETEALL con `ns` no vacío borra solo ese ns (`marker_common.cpp:224-229`) [V].
- **Acciones**: 0 ADD = MODIFY; 2 DELETE; 3 DELETEALL. Si cambia `type`, se recrea (`:282-287`). NaN/Inf ⇒ se rechaza
  (`:195-213`).
- **Caducidad**: si `lifetime` > 100 µs, `expira = ahora + lifetime` con el reloj **de recepción** (`:305`,
  `marker_base.cpp:84`) → `Time.get_ticks_msec()`, barrido a 4 Hz.
- **frame_locked**: sin él, el marco se resuelve una vez; con él, cada fotograma (`marker_base.cpp:100-115`).
- **Reciclado**: los nodos borrados se ocultan y vuelven a un pool por tipo; nunca `queue_free` en régimen estable.
  Tope = `cupo`.
- **Corrección de check-only** (`W13-revision.md:58`): `var tf: RosTfListener` **no compila en `ros2_vita`** («Could
  not find type "RosTfListener"») → sin anotar; además el marco ya lo resuelve la base / `visor.transformada()`.
- API extra para otros displays: `poner_compacto(clave, tipo, t, escala, color)` y `retener_solo(claves)` (cliente del
  relay), `mover_ns(ns, t)` y `borrar_ns(ns)` (marcadores interactivos, PC).

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
## Gestor de Marker/MarkerArray (marker_common.cpp:205-310). Directo (PC) o estado completo del relay (Vita).
const Fab = preload("res://comun/visor/fabrica_marcadores.gd")
const Prim = preload("res://comun/visor/primitivas_viz.gd")
var _ns := {}                                   # ns → {id → {n, tipo, expira, frame, pose, locked}}
var _pool := {}                                 # tipo → Array de nodos ocultos
var _total := 0
var _t_barrido := 0
func _init() -> void:
	capa = "marcadores"
	hz = 0.0                                    # cada mensaje cuenta (acciones)
	topic_vita = "marcadores"
	tipo_vita = "std_msgs/msg/Float32MultiArray"
func conectar(v) -> void:
	canal.coalescer = false
	super.conectar(v)
func _procesar(msg):                            # Marker o MarkerArray
	var lista: Array = msg.markers if "markers" in msg else [msg]
	for m in lista:
		match int(m.action):
			0: _add(m)
			2: _borrar(m.ns, m.id)
			3:
				for ns in ([m.ns] if m.ns != "" else _ns.keys()):
					for id in _ns.get(ns, {}).keys():
						_borrar(ns, id)
	return null                                 # el gestor pinta él mismo; la base no mueve el nodo raíz
func _add(m) -> void:
	var tabla: Dictionary = _ns.get_or_add(m.ns, {})
	var e = tabla.get(m.id)
	if e != null and e.tipo != m.type:
		_borrar(m.ns, m.id)
		e = null
	if e == null:
		if _total >= cupo:
			return
		var libres: Array = _pool.get_or_add(m.type, [])
		e = {"n": libres.pop_back() if libres.size() > 0 else Fab.crear(m.type), "tipo": m.type}
		if e.n.get_parent() == null:
			add_child(e.n)
		tabla[m.id] = e
		_total += 1
	var vida: float = m.lifetime.sec + m.lifetime.nanosec * 1e-9
	e.expira = Time.get_ticks_msec() + int(vida * 1000.0) if vida > 1e-4 else -1
	e.frame = String(m.header.frame_id).trim_prefix("/")
	e.locked = m.frame_locked
	e.pose = Prim.pose_godot(m.pose)
	var t = visor.transformada(e.frame)
	e.n.visible = t != null and Fab.aplicar(e.n, m, visor)     # Fab fija malla, color y escala; false = no dibujar
	if t != null:
		e.n.transform = (t as Transform3D) * (e.pose as Transform3D)
func _borrar(ns: String, id: int) -> void:
	var e = _ns.get(ns, {}).get(id)
	if e != null:
		e.n.visible = false
		_pool.get_or_add(e.tipo, []).append(e.n)
		_ns[ns].erase(id)
		_total -= 1
func _process(dt: float) -> void:
	super._process(dt)
	var ahora := Time.get_ticks_msec()
	if ahora - _t_barrido < 250:                # caducidad y frame_locked a 4 Hz
		return
	_t_barrido = ahora
	for ns in _ns.keys():
		for id in _ns[ns].keys():
			var e = _ns[ns][id]
			if e.expira >= 0 and ahora > e.expira:
				_borrar(ns, id)
			elif e.locked:
				var t = visor.transformada(e.frame)
				if t != null:
					e.n.transform = (t as Transform3D) * (e.pose as Transform3D)
func _coste() -> Dictionary: return {"instancias": 32, "triangulos": 32 * 24, "quads": 0}
```

Detalle: `_procesar` devuelve `null`, así que la base no recoloca el nodo raíz (cada marcador lleva su marco). El
cliente compacto (§4.7.4) sobreescribe `_procesar_compacto`. En la Vita un `Marker` suelto cabe en directo hasta 10
puntos (229 B sin puntos, 469 con 10, 493 con 11 [V recalculado]); `visualization_msgs/Marker` entra en
`TIPOS_VISOR`.

#### 4.7.2 `FabricaMarcadores` (`fabrica_marcadores.gd`) y tipos de Marker — V mapas#11–24, D mapas#21

⚖ D2: la fábrica **solo traduce** `Marker.type` / `shape_msgs` → `PrimitivasViz`; no define mallas ni colores.

| `type` | Representación | Campos | Vita | Tri / *draws* |
|---|---|---|---|---|
| 0 ARROW (pose) | `FLECHA` escalada por `scale` (largo, ancho, alto); x·y·z = 0 ⇒ oculto | `pose`, `scale`, `color` | 3D instancia | 24 / 1 |
| 0 ARROW (2 `points`) | `CILINDRO` (cuerpo) + `CONO` (cabeza 0,23·d o `scale.z`) orientados con `looking_at`; 1 punto ⇒ error | `points[0..1]`, `scale.x/y/z` | 3D, 2 instancias | ≈ 48 / 2 |
| 1 CUBE · 2 SPHERE · 3 CYLINDER | malla unidad + `escala_ros(scale)` (SPHERE: diámetros; CYLINDER: diámetros x,y y altura z) | `pose`, `scale`, `color` | 3D instancia + paleta | 12 / 8 / 32 |
| 4 LINE_STRIP · 5 LINE_LIST | Vita: superposición 2D `draw_polyline_colors` / `draw_multiline_colors` reproyectada ≤ 20 Hz; PC: prismas de 3 caras (6 tri/seg) con color por vértice | `points`, `colors` (si `size == points.size`), `scale.x` = ancho | 2D (`2d/marcadores_2d.gd`) | 1 comando |
| 6 CUBE_LIST · 7 SPHERE_LIST | PC: MultiMesh con color por instancia (`solo_pc`); Vita: **una** malla horneada con UV a paleta (12 tri/cubo, octaedro 8 tri/esfera) si ≤ 64 y ≤ 1 Hz; si no, 2D | `points`, `scale`, `colors` | horneado o 2D | 768 / 1 (64 cubos) |
| 8 POINTS | 2D: un *quad* por punto en **una** `canvas_item_add_triangle_array`, tamaño en px por la focal (522 px con fov 55°, `docs/31` §2.2) | `points`, `scale.x/y`, `colors` | 2D | 1 comando |
| 9 TEXT_VIEW_FACING | ⚖ D11: `visor.texto.poner(clave, pos, text, color)`; `Label3D` solo `solo_pc` | `pose.position`, `text`, `scale.z` (alto) | 2D `draw_string` | ≤ 40 glifos |
| 10 MESH_RESOURCE | tabla `package://` → `res://` de mallas horneadas (como el URDF, ADR 0009); PC: `GLTFDocument` en caliente; si falta, cubo + aviso | `mesh_resource`, `mesh_use_embedded_materials`, `scale` | solo horneadas | ≤ 1 000 tri (H5) |
| 11 TRIANGLE_LIST | `ArrayMesh`; Vita con UV a paleta por triángulo; reconstruir solo si cambia el *hash*; ≤ 1 000 tri | `points` (×3), `colors` | 3D estático | 60 B/tri (H9) |
| 12 ARROW_STRIP (Jazzy) | LINE_STRIP + punta ARROW en el último segmento; `marker_factory.cpp:71-103` no lo dibuja [V] | `points ≥ 2` | 2D + 3D | semántica [?] |

**Corrección D mapas#21** (⚖ D11): el post usaba un `Label` del HUD por texto; un `Label` por texto multiplica
elementos y lotes del lienzo (doc 34: 222 *draws* con 305 *quads*) → `TextoSuperpuesto`. Esqueleto de la fábrica:

```gdscript
extends RefCounted
## FabricaMarcadores (ADR 0013 §1): Marker / shape_msgs → instancias de PrimitivasViz. No define mallas.
const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
const ARROW := 0
const TEXT := 9

static func crear(tipo: int) -> Node3D:
	var n := MeshInstance3D.new()
	if tipo == ARROW:                                # cuerpo y cabeza para el modo «2 puntos»
		for h in ["cuerpo", "cabeza"]:
			var c := MeshInstance3D.new()
			c.name = h
			n.add_child(c)
	return n

## Devuelve false si el marcador no se dibuja (escala nula, puntos inválidos…).
static func aplicar(n: Node3D, m, visor) -> bool:
	var col := Paleta.indice(Paleta.de_ros(m.color))
	match int(m.type):
		0:
			if m.points.size() == 2:
				return _flecha_puntos(n, m, col)
			n.mesh = Prim.malla(Prim.FLECHA, col)
			n.scale = Vector3(m.scale.y, m.scale.z, m.scale.x)
			return m.scale.x * m.scale.y * m.scale.z != 0.0
		1, 2, 3:
			n.mesh = Prim.malla(int(m.type), col)
			n.scale = Prim.escala_ros(m.scale)
			return m.scale.x * m.scale.y * m.scale.z != 0.0
		TEXT:
			if visor.texto:
				visor.texto.poner("%s/%d" % [m.ns, m.id], n.global_position, String(m.text), Paleta.de_ros(m.color))
			return false                                  # nada 3D que dibujar
	return false                                          # 4–8, 10–12: ver la tabla (2D, horneado, recursos)

static func _flecha_puntos(n: Node3D, m, col: int) -> bool:   # arrow_marker.cpp:108-152
	var a := rclgd.ros_to_godot_vector(Vector3(m.points[0].x, m.points[0].y, m.points[0].z))
	var b := rclgd.ros_to_godot_vector(Vector3(m.points[1].x, m.points[1].y, m.points[1].z))
	var d := b - a
	var dist := d.length()
	if dist < 1e-6 or m.scale.x + m.scale.y == 0.0:
		return false
	var cabeza: float = clampf(m.scale.z, 0.0, dist) if m.scale.z != 0.0 else 0.23 * dist
	var arriba := Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT
	var base := Basis.looking_at(d, arriba)
	var c := n.get_node("cuerpo") as MeshInstance3D
	var h := n.get_node("cabeza") as MeshInstance3D
	c.mesh = Prim.malla(Prim.CILINDRO, col)
	h.mesh = Prim.malla(Prim.CONO, col)
	c.transform = Transform3D(base.scaled_local(Vector3(m.scale.x, m.scale.x, dist - cabeza)), a)
	h.transform = Transform3D(base.scaled_local(Vector3(m.scale.y, m.scale.y, cabeza)), a + d.normalized() * (dist - cabeza))
	return true
```

[I] El `CILINDRO` de `PrimitivasViz` va sobre +Y (eje Z de ROS, para `CYLINDER`); para el cuerpo de la flecha hace
falta la variante sobre −Z (`CILINDRO_Z` de mapas#12): añadir la forma o rotar 90° en `_flecha_puntos` (decidir en
V8). El horneado de listas (`hornear_lista`, tablas `OCTA_CARAS`/`CUBO_CARAS`), `lineas_3d` (prismas, PC),
`malla_triangulos`, `resolver`/`cargar_malla` (MESH_RESOURCE) y `aplicar_arrow_strip` se copian de mapas#17, #19,
#22, #23 y #24 cambiando `Paleta.uv(color)` por `Paleta.uv(Paleta.indice(color))` y `material()` por
`Paleta.material()`.

Superposición 2D de LINE_STRIP / LINE_LIST / POINTS (`2d/marcadores_2d.gd`, `en_pantalla = true`, capa `resto_2d`
≤ 150): el `_draw()` de mapas#16 (líneas) y mapas#20 (puntos) tal cual, con `cam = visor.camara`; reproyección ≤ 20 Hz
(≈ 10–15 µs por punto en GDScript [I], `docs/31` §3). Gate **G-W13-M7**: LINE_STRIP 50 puntos y POINTS 180 en 2D con
la cámara orbitando, `process + canvas` ≤ 2–3 ms.

#### 4.7.3 `shape_msgs` — V mapas#29–31

`SolidPrimitive` → (malla unidad, escala Godot); **SPHERE = radio** (Marker usa diámetro); CYLINDER/CONE
`[altura, radio]` sobre Z; PRISM = extrusión ±altura/2 de un polígono CCW (`4n − 4` tri). `Mesh` → `ArrayMesh`
indexada en el PC (la Vita la aplana sola, H3: 60 B/tri; solo estáticas ≤ 1 000 tri); sentido de las caras no fijado
por ROS (invertir 1-2 si se ve por dentro). `Plane` → `PlaneMesh` de 4×4 m en el punto `−d·n/|n|²` (2 tri). Código de
mapas#29–31 dentro de `fabrica_marcadores.gd` (`primitiva(sp)`, `prisma`, `malla_shape`, `plano`), con mallas de
`PrimitivasViz` y material de `PaletaViz`.

#### 4.7.4 `MarkerArray` en la Vita — A mapas#25 → ⚖ D14

50 CUBE = 11 605 B (`docs/27:79`): nunca directo. ⚖ D14: el relay aplica él la semántica (ADD/DELETE/DELETEALL/
lifetime) y publica a 5 Hz el **estado completo** en trozos best effort de `<p>/marcadores` = cabecera común
`[seq, trozo, n_trozos, n]` + **10 floats** por marcador `[clave, tipo, x, y, z, yaw, sx, sy, sz, color]`, **n ≤ 11**
por datagrama (114 floats = 472 B), tope de **33** marcadores (3 trozos) por ciclo. `clave = (id ⊕ hash(ns)) & 0xFFFFFF`
(exacta en float32); `color = índice de paleta + 256·alfa(0–15)`. Al completar un `seq`, la Vita **recicla lo que no
llegó** (un DELETE perdido en best effort no deja fantasmas). Se pierde alabeo y cabeceo (solo `yaw`). Se descartan
los 8 floats de `docs/27:105` (con el tope de 33 también necesitan 3 trozos: no se ahorra ningún datagrama) y enviar
acciones. Puntos de líneas/listas: `<p>/marcador_puntos` = cabecera + `[clave, tipo, color, ancho]` + xyz·n, n ≤ 36
(480 B), ≤ 4 trozos/s; textos: `<p>/marcador_texto` = String `clave|x|y|z|texto` (≤ 80 car.), **fiable**, ≤ 2 Hz.
Gates **G-W13-M1** (pool lleno a 10 Hz: `drawn` +cupo, `avg_submit_us` ≤ 9 000, ≥ 30 FPS) y **G-W13-M3** (10 % de
pérdida con netem: sin fantasmas > 0,4 s, `process` ≤ 4 ms, ≤ 15 KB/s).

```gdscript
## En 3d/marcadores.gd: cliente de <p>/marcadores (estado completo por trozos).
const POR_MARCADOR := 10
var _seq := -1
var _vistos := {}
var _trozos := 0

func _procesar_compacto(msg):
	var d: PackedFloat32Array = msg.data
	var cab: Dictionary = Vc1.cabecera(d)           # {seq, trozo, n_trozos, n}
	if cab.is_empty():
		return null
	if cab.seq != _seq:
		_seq = cab.seq
		_vistos.clear()
		_trozos = 0
	_trozos += 1
	for i in cab.n:
		var b := 4 + i * POR_MARCADOR
		if b + POR_MARCADOR > d.size():
			break
		var clave := int(d[b])
		var col := int(d[b + 9])
		_vistos[clave] = true
		poner_compacto(clave, int(d[b + 1]),
				Transform3D(Basis(Vector3.UP, d[b + 5]), rclgd.ros_to_godot_vector(Vector3(d[b + 2], d[b + 3], d[b + 4]))),
				Vector3(d[b + 7], d[b + 8], d[b + 6]),               # escala en ejes Godot (sy, sz, sx)
				col & 0xFF)
	if _trozos == cab.n_trozos:
		retener_solo(_vistos)                       # estado completo: lo no visto vuelve al pool
	return null
```

(`poner_compacto` crea o reutiliza la entrada `_ns[""][clave]` con `Prim.malla(tipo, indice)` y `retener_solo` borra
las claves ausentes; `const Vc1 = preload("res://comun/ros/vc1.gd")`.) El yaw ROS alrededor de +Z es un giro
alrededor de +Y en Godot con el mismo signo (rotación propia) [I: comprobar con un marcador girado en V8].

#### 4.7.5 Marcadores interactivos — D mapas#26, D mapas#27 → correcciones; Vita aplazado (V14)

- **Cliente** (`3d/im_cliente.gd`, `solo_pc`): estado inicial por el servicio `<ns>/get_interactive_markers`, luego
  `<ns>/update` con `seq_num` (hueco ⇒ pedir el estado otra vez); cada control se dibuja con sus Marker (gestor) y un
  asa `Area3D` según `interaction_mode`. **Corrección de check-only** (`W13-revision.md:59`): `RosClient` no existe en
  `ros2_vita` y faltaba el `preload` de la fábrica → `const Fab = preload("res://comun/visor/fabrica_marcadores.gd")`,
  `var _cli` **sin anotar** y el script marcado `solo_pc`. En la Vita los servicios cliente están ⏳
  (`API_PARITY.md:31`): ⚖ los marcadores interactivos en la Vita (`im_poses`, relay como cliente) quedan **aplazados**
  a V14 / T-W4-9.
- **Feedback** (`herramientas/im_feedback.gd`): arrastre con ratón (PC) o táctil frontal (Vita, cuando se active):
  rayo de cámara ∩ plano del control → pose; POSE_UPDATE limitado a 20 Hz entre MOUSE_DOWN y MOUSE_UP. 149 B
  (157 con nombres reales). **Dos correcciones**: (1) check-only (`W13-revision.md:60`): `var pulsado := (… or …)`
  no compila («Cannot infer the type», operandos `Variant`) → `var pulsado: bool = …`; (2) ⚖ C9: el servidor IM
  suscribe el feedback con `rclcpp::QoS(1)` = **fiable** (`interactive_marker_server.hpp:87-88`, jazzy) y un
  publicador best effort no casa → **fiable**, profundidad 1.

```gdscript
extends "res://comun/visor/herramienta_visor.gd"
## Feedback de marcador interactivo (MOVE_PLANE). Publica FIABLE (C9): el servidor suscribe con rclcpp::QoS(1).
@export var hz_feedback := 20.0
var im_nombre := ""
var control := ""
var objetivo: Node3D                                  # nodo del control que se arrastra
var _plano: Plane
var _activo := false
var _t := 0
func _init() -> void:
	tipo = "visualization_msgs/msg/InteractiveMarkerFeedback"
	fiabilidad = 0                                    # FIABLE (antes BE en mapas#27)
func _unhandled_input(ev: InputEvent) -> void:
	var pulsado: bool = (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT) or ev is InputEventScreenTouch   # ← corrección
	if pulsado and ev.pressed and not _activo:
		_activo = true
		_plano = Plane(objetivo.global_basis.x, objetivo.global_position)
		_enviar(4)                                    # MOUSE_DOWN
	elif pulsado and not ev.pressed and _activo:
		_activo = false
		_enviar(5)                                    # MOUSE_UP
	elif _activo and (ev is InputEventMouseMotion or ev is InputEventScreenDrag):
		var cam: Camera3D = visor.camara
		var p = _plano.intersects_ray(cam.project_ray_origin(ev.position), cam.project_ray_normal(ev.position))
		if p != null:
			objetivo.global_position = p
			if Time.get_ticks_msec() - _t >= int(1000.0 / hz_feedback):
				_t = Time.get_ticks_msec()
				_enviar(1)                            # POSE_UPDATE
func _enviar(evento: int) -> void:
	var f := RosMsg.from_type(tipo)
	f.header.frame_id = visor.marco_fijo
	f.header.stamp = visor.contexto.nodo.now()
	f.client_id = "/vita" if OS.has_feature("vita") else "/godot"
	f.marker_name = im_nombre
	f.control_name = control
	f.event_type = evento
	var p := rclgd.godot_to_ros_vector(objetivo.global_position)
	var q := rclgd.godot_to_ros_quat(objetivo.global_basis.get_rotation_quaternion())
	f.pose.position.x = p.x
	f.pose.position.y = p.y
	f.pose.position.z = p.z
	f.pose.orientation.x = q.x
	f.pose.orientation.y = q.y
	f.pose.orientation.z = q.z
	f.pose.orientation.w = q.w
	publicar(f)
```

`topic` = `<ns>/feedback`. La HerramientaVisor usa profundidad 1 en la Vita y 5 en el PC; ⚖ la tabla de C9 pide 1 para
el feedback IM en los dos: fijarlo en V14.

#### 4.7.6 `ImageMarker` (`hud/marcas_imagen.gd`) — V mapas#28

Superposición 2D sobre la imagen de cámara (pestaña Cámara): un `Control` con `_draw` que escala de píxeles de la
imagen **original** a píxeles de pantalla (si el relay reduce la imagen a 160×120, escalar con el ancho real de
`CameraInfo`); mismo gestor ns+id+lifetime, en 2D (círculo, LINE_STRIP, LINE_LIST, POLYGON, POINTS). 124 B + 24 por
punto ⇒ ≤ 15 puntos directo (`TIPOS_VISOR`). Esqueleto de mapas#28 con `extends display_ros_hud.gd` y
`_procesar` → actualizar `_m` y devolver `true`.

### 4.8 HMI, percepción, acciones y herramientas (familia `hmi-percepcion-acciones`)

Kit común: todos los widgets son `DisplayRosHud` (⚖ D1: `widget_hud.gd` desaparece), dibujan en su `_draw()` con
`draw_string`/`draw_rect`/polilíneas finas, usan los colores de estado de `PaletaViz` (rqt_robot_monitor) y viven en
una pestaña de `GestorHud` o en la barra fija. Caducidad por widget: 2 s por defecto, 15 s batería, 10 s por fila en
diagnósticos (`timeline.py:161-163`) [V]; los widgets de eventos (lifecycle, estado de acción, `/rosout`) no caducan.

#### 4.8.1 `DiagnosticArray` (`hud/diagnostico.gd`) — M hmi#7 → G-W13-H0

Tabla tipo rqt_robot_monitor: cuadro de color + nivel + nombre + mensaje, de peor a mejor, STALE por fila a 10 s,
filtro «solo problemas»; detalle de `KeyValue` al tocar una fila. Campos: `status[].level` (byte: 0 OK, 1 WARN,
2 ERROR, 3 STALE; llega como entero [I] → `int(...)` defensivo), `name`, `message`, `values[]`. ⚖ D6: pestaña
Diagnóstico de **8 filas × 30 caracteres**, «solo problemas» por defecto en la Vita (la ficha: 12 filas ≈ 500 *quads*
[I] > 400 del HUD entero). Vita: 1 estado = 76 B; 1×3 KV = 157; 5×3 = 685 ⇒ con > 2 estados ya no cabe en BE →
relay `<p>/diagnostics` = `DiagnosticArray` de **1 estado** por mensaje, ≤ 3 pares, textos ≤ 40 car. (≈ 160 B [I]),
solo los que cambian + repaso 1 Hz, BE, ≤ 10 Hz (el tipo estándar se conserva: el widget no cambia, solo el topic).
Diagnósticos pequeños (≤ 7,5 KiB a 1 Hz) pueden ir directos en fiable. Gate **G-W13-H0** antes de fijar filas.

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
const TEXTO := ["OK", "WARN", "ERROR", "STALE"]
@export var max_filas := 8
@export var ancho_max := 30
@export var caducidad_fila_s := 10.0
@export var solo_problemas := false
var _filas := {}                                      # nombre -> [nivel, mensaje, t_ms]
func _init() -> void:
	topic = "/diagnostics_agg"
	tipo = "diagnostic_msgs/msg/DiagnosticArray"
	topic_vita = "diagnostics"
	tipo_vita = tipo
	caducidad_s = 0.0
func conectar(v) -> void:
	canal.coalescer = false                           # cada estado del relay llega en su mensaje
	if v.en_vita:
		solo_problemas = true
	super.conectar(v)
func _procesar(msg):
	var ahora := Time.get_ticks_msec()
	for st in msg.status:
		_filas[String(st.name)] = [int(st.level), String(st.message), ahora]
	return true
func _draw() -> void:
	var fuente := get_theme_default_font()
	var ahora := Time.get_ticks_msec()
	var claves := _filas.keys()
	claves.sort_custom(func(a, b): return _filas[a][0] > _filas[b][0])
	var y := 14.0
	var n := 0
	for k in claves:
		var nivel: int = 3 if ahora - _filas[k][2] > caducidad_fila_s * 1000.0 else clampi(_filas[k][0], 0, 3)
		if (solo_problemas and nivel == 0) or n >= max_filas:
			continue
		draw_rect(Rect2(2, y - 10, 10, 10), [Paleta.OK, Paleta.WARN, Paleta.ERROR, Paleta.STALE][nivel])
		draw_string(fuente, Vector2(16, y), ("%s %s: %s" % [TEXTO[nivel], k, _filas[k][1]]).left(ancho_max),
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 18, 12)
		y += 14.0
		n += 1
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": max_filas * (ancho_max + 1)}
```

#### 4.8.2 `rcl_interfaces/Log` = `/rosout` (`hud/consola.gd`) — M hmi#8 → G-W13-H0

Consola de N líneas coloreadas por nivel (10 D, 20 I, 30 W, 40 E, 50 F), filtro por nivel mínimo y subcadena de
nodo, pausa. ⚖ D6: **6 líneas × 40 caracteres** en la Vita (la ficha: 10 líneas ≈ 600 *quads*). Vita: relay
`<p>/rosout` = **mismo tipo `Log`**, solo nivel ≥ WARN, `file`/`function` vaciados, `msg` ≤ 200 car. (≈ 270 B [I]),
≤ 10 msg/s; ⚖ QoS **fiable** (la ficha decía best effort: un aviso perdido no se repite). En el PC: `/rosout` es
RELIABLE + TRANSIENT_LOCAL en el emisor; aquí VOLATILE (sin historial). Escribir desde la Vita: `RosLogger` ❌ (§1.4);
un publicador propio de `Log` sería posible añadiendo el esquema. Esqueleto de hmi#8 con el cambio de base, `_init`
con `fiabilidad = 2`, `topic_vita = "rosout"`, `tipo_vita = tipo`, `caducidad_s = 0`, `canal.coalescer = false` y
`max_lineas = 6 if en_vita`; `_procesar` añade la línea y devuelve `true`. Prueba de hardware (V6): 20 avisos/s durante
5 min, FPS sin bajar de escalón, `reliable_dropped` = 0.

#### 4.8.3 `lifecycle_msgs/TransitionEvent` (`hud/lifecycle.gd`) — V hmi#9

Fila por nodo gestionado: verde activo, amarillo inactivo/transitorio, rojo error, gris desconocido. Campos:
`goal_state.id` (1 sin configurar, 2 inactivo, 3 activo, 4 finalizado; 10–15 transitorios, 15 error),
`transition.label`. 65 B; **fiable** (solo hay mensaje al cambiar). `topic = <nodo>/transition_event`. Sin servicios en
la Vita: estado inicial «desconocido» hasta la primera transición o por el proxy `srv` del puente (`docs/32` §12).
`caducidad_s = 0` (evento). Esqueleto de hmi#9 con el cambio de base y `fiabilidad = 2`.

#### 4.8.4 `Detection2DArray` (`hud/cajas_2d.gd`) — D hmi#10 → ⚖ D12

Rectángulos con etiqueta y % de score sobre el `TextureRect` de la cámara, escalados de píxeles de la imagen
**original** al widget. Campos: `detections[].bbox` (`center` Pose2D + `size_x/y` px; `theta` se ignora [I]),
`results[0].hypothesis.class_id/score`. ⚖ D12: una detección ya ocupa 449–474 B (la covarianza 6×6 de
`ObjectHypothesisWithPose` son 288 B) → relay `<p>/detecciones` = Float32 cabecera común + `[ancho, alto]` +
`[clase, score, cx, cy, w, h]·n`, **n ≤ 18** (472 B; la ficha daba n ≤ 19 con otra cabecera) + `<p>/det_clases`
(String F+TL con los nombres), 5 Hz. Se pierden `id` e hipótesis múltiples (se envía la mejor clase). Cupo
`resto_2d`: detecciones ≤ 150 *quads*. `vision_msgs` no entra en `TIPOS_VISOR` (D10).

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## Cajas 2D sobre la imagen. datos = [Vector2 tamaño imagen, Array de [Rect2 px imagen, etiqueta, score]].
@export var ancho_imagen := 640.0
@export var alto_imagen := 480.0
@export var umbral_score := 0.3
var clases := PackedStringArray()                     # de <p>/det_clases
func _init() -> void:
	tipo = "vision_msgs/msg/Detection2DArray"
	topic_vita = "detecciones"
	tipo_vita = "std_msgs/msg/Float32MultiArray"
	fiabilidad = 2                                    # en el PC: 1 det. ≈ 470 B, 3 = 1 377 B
	hz_vita = 5.0
func _procesar(msg):
	var cajas := []
	for d in msg.detections:
		var etiqueta := String(d.id)
		var score := 1.0
		if d.results.size() > 0:
			etiqueta = String(d.results[0].hypothesis.class_id)
			score = float(d.results[0].hypothesis.score)
		if score >= umbral_score:
			var s := Vector2(d.bbox.size_x, d.bbox.size_y)
			cajas.append([Rect2(Vector2(d.bbox.center.position.x, d.bbox.center.position.y) - s * 0.5, s), etiqueta, score])
	return [Vector2(ancho_imagen, alto_imagen), cajas]
func _procesar_compacto(msg):                         # [seq, trozo, n_trozos, n, ancho, alto, (clase, score, cx, cy, w, h)·n]
	var d: PackedFloat32Array = msg.data
	if d.size() < 6:
		return null
	var cajas := []
	for i in mini(int(d[3]), (d.size() - 6) / 6):
		var b := 6 + 6 * i
		var k := int(d[b])
		if d[b + 1] >= umbral_score:
			var s := Vector2(d[b + 4], d[b + 5])
			cajas.append([Rect2(Vector2(d[b + 2], d[b + 3]) - s * 0.5, s), clases[k] if k < clases.size() else str(k), d[b + 1]])
	return [Vector2(d[4], d[5]), cajas]
func _draw() -> void:
	if datos == null:
		return
	var k: Vector2 = size / (datos[0] as Vector2)
	var fuente := get_theme_default_font()
	for c in datos[1]:
		var r: Rect2 = c[0]
		var col := color_estado(Color.from_hsv(float(absi(hash(c[1])) % 360) / 360.0, 0.8, 1.0))
		draw_rect(Rect2(r.position * k, r.size * k), col, false, -1.0)
		draw_string(fuente, r.position * k + Vector2(2, -2), "%s %d%%" % [c[1], roundi(c[2] * 100.0)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 150}
```

(`det_clases` se suscribe en `conectar()` como suscripción auxiliar *latched*, igual que `joints_orden` en §4.3.5.)

#### 4.8.5 `Detection3DArray` (`2d/cajas_3d.gd`, superpuesto) — D hmi#11 → ⚖ D12

Cajas de alambre: 12 aristas por caja proyectadas al lienzo con **una** `draw_multiline` (H17), idéntico en PC y Vita
(no hay líneas 3D sin *shaders*; precio: no se ocultan tras el robot, `docs/31` §3); etiqueta en el centro con
`TextoSuperpuesto`. Alternativa con oclusión: `CUBO` de la paleta (12 tri) del cupo de marcadores. Campos:
`bbox.center` (Pose) y `bbox.size` (m) en `header.frame_id`. ⚖ D12: «1 detección = 489 B, no cabe por 1 B» era un
artefacto de convención (485 B de carga), pero con nombres reales son 505 B → relay `<p>/detecciones3d` = cabecera
común + `[clase, score, x, y, z, yaw, sx, sy, sz]·n`, **n ≤ 12** (464 B; la ficha daba 13), 5 Hz. Coste: 12 cajas × 8
`unproject` ≈ 1–1,5 ms por fotograma de reproyección [I] → reproyectar a ≤ 20 Hz, no cada fotograma. Base
`DisplayRos2D` con `en_pantalla = true`; `_procesar`/`_procesar_compacto` → `Array` de 8 esquinas (Godot, marco del
mensaje) por caja; `_draw()` = el de hmi#11 multiplicando por `marco` (Transform3D de la base) en vez de
`marco_fijo.global_transform`.

#### 4.8.6 `JointTrajectory` → fantasma (`3d/fantasma.gd`) — M hmi#12 → ⚖ D7

Segunda instancia del robot horneado que recorre los puntos en bucle según `time_from_start` (interpolación lineal,
pausa final 0,5 s), con `set_joints`. ⚖ D7: en la Vita **solo con el robot oculto** (sustituye al robot en el cupo
`robot`) **o solo la cadena del brazo (≤ 8 instancias, de la reserva)**; color plano distinto (sin transparencia fiable
en 3D, `docs/31` §2.4). 6 juntas × 1 punto = 228 B (cabe, patrón *fire-and-forget*); planes de MoveIt por el puente
`/vita/accion/trayectoria` (Int16MultiArray ≤ 32 puntos, 476 B, `docs/32:81`). Por medir: `[gxm3d] drawn=` con el
fantasma del brazo junto al robot. Esqueleto de hmi#12 con `_procesar` → `[nombres, tiempos, posiciones]` y el
bucle en `_process`; `capa = "reserva"` y `_coste().instancias = 8`.

#### 4.8.7 `JointTrajectoryControllerState` (`hud/controlador.gd`) — V hmi#13

Barras por junta: real (azul), referencia (marca naranja), |error| en rojo si pasa `tolerancia` (0,05 rad). 7 juntas =
1 340 B, 14 = 2 404 B → **fiable** a ≤ 5 Hz (la plantilla ya lo publica fiable a 2 Hz con XRCE,
`plantillas/sensores/estado_controlador.gd:9-13`); esquema propio en `plantillas/ros/msg/control_msgs`. Pestaña
Controlador: 14 juntas, solo barras. **Trampa** (verificada con check-only): `m.reference` resuelve a
`RefCounted.reference()` → `m.get_member("reference").positions` (como `estado_controlador.gd:36-41`). Esqueleto de
hmi#13 con el cambio de base (`_procesar` → `[nombres, ref, real, err]`).

#### 4.8.8 Plan frente a real (`2d/plan_real.gd`) — D hmi#14 → corrección parcial

Dos polilíneas en planta: plan (verde) y rastro real (azul), mismo script en PC (`Path` + `Odometry`) y Vita
(`path_compacto` + `pose2d`). ⚖ D5.4: se usa `/vita/pose2d` de **6 floats** (no la ampliación a 10 de geom#13). Ojo
marcos: el plan va en `map` y la odometría en `odom` [V]; en la Vita `TfLigero` solo conoce `map → odom` si se activa
el módulo `tf` del relay con ese marco en la lista blanca; si no, se dibujan los dos en el marco fijo suponiendo
`map ≈ odom` (deriva visible) [I] → §9.3. Implementación: **dos displays** del contrato (el `2d/path.gd` de §4.3.2 y
el `2d/odometria.gd` de §4.3.1, con `frame_id` = `map` y `odom`), no un script con dos suscripciones; la base resuelve
cada marco con `visor.transformada()`.

#### 4.8.9 `GoalStatusArray` + feedback de `NavigateToPose` (`hud/estado_meta.gd`, barra fija) — V hmi#15

Línea «Meta: fase · distancia · ETA · recuperaciones» con color por fase (0 sin meta … 4 LLEGÓ, 6 ABORTADA). Nivel 0
de ADR 0012 (topics ocultos `<acción>/_action/status` y `/_action/feedback`): status 33–453 B (**fiable**, profundidad
1, TRANSIENT_LOCAL [I]: el servidor lo publica *latched*), feedback 116 B; pero el feedback puede llegar a ~100 msg/s
(bt_loop 10 ms) → en la Vita mejor nivel 1, `/vita/accion/estado` 112 B a 5 Hz (`docs/32:51`). La Vita no conoce el
UUID de su meta: se elige la de `goal_info.stamp` más reciente. Cancelar: solo por el puente (nivel 1) o, en el PC,
con `RosActionClient`. [?] Que rclgd y `ros2_vita` acepten `nav2_msgs/action/NavigateToPose_FeedbackMessage` por texto
en una suscripción normal → §9.3. Esqueleto de hmi#15 con el cambio de base (`latched = true`, suscripción auxiliar
del feedback en `conectar()`).

#### 4.8.10 Herramientas que publican (`herramientas/*.gd`) — V hmi#16–19

RViz publica con `rclcpp::QoS(5)` (KEEP_LAST 5, fiable, volátil), `header.frame_id` = marco fijo y sello
`clock->now()` (`goal_tool.cpp:67,78`) [V]. Aquí: **fiable**, profundidad 5 (PC) / 1 (Vita), un mensaje por
confirmación, sello `nodo.now()` (hora del agente en la Vita). Todo ≤ 364 B: en la Vita no fragmenta y la emisión
fiable no bloquea el hilo principal (`docs/27:13-15,34`).

| Herramienta | Mensaje → topic | Gesto PC | Gesto Vita | Detalles |
|---|---|---|---|---|
| Nav2 Goal (`meta.gd`) | `PoseStamped` → `goal_pose` (relativo, 76 B) | pulsar = posición, arrastrar = rumbo, soltar = publicar | táctil delantero (como ratón); meta «pendiente» naranja hasta **✕** | rumbo `atan2(Δy, Δx)` (`pose_tool.cpp:151`) → `(0, 0, sin θ/2, cos θ/2)` (`:154-161`); umbral de arrastre 5 cm |
| 2D Pose Estimate (`pose_inicial.gd`) | `PoseWithCovarianceStamped` → `initialpose` (364 B) | igual | igual + ✕ | cov[0] = cov[7] = 0,25, cov[35] = (π/12)² = 0,0685 (`initial_pose_tool.cpp:62-70`); asignar el array entero |
| Publish Point (`punto.gd`) | `PointStamped` → `/clicked_point` (44 B) | al **soltar**: rayo de física contra las colisiones del mundo editable (doc 35), si no, el suelo | toque | «Single click»: se desactiva tras publicar (`point_tool.cpp:65-68,111-114`); el robot horneado no tiene colisiones (`urdf_robot.gd:2`) |
| Teleop (`teleop.gd`) | `Twist` → `/cmd_vel` (52 B), 20 Hz | flechas + Mayús (hombre muerto) | stick izq. + **R mantenido**; △/✕ escala | fiable por defecto (validado en G6, `godot/g6-hmi/main.gd:65`); al soltar, **un** Twist cero y silencio; con robots reales `/vita/mando` best effort 20 Hz + puerta en el PC (ADR 0012 §3); con el G1, best effort (`humanoide_g1.gd:163-164`) |

Mapeo de controles de la Vita (decisión de diseño de hmi, sin cambio en la sentencia): SELECT recorre Teleop → Meta →
Pose inicial → Punto (nombre en la barra fija); START abre/cierra el panel; L + cruceta o toque cambian de pestaña;
el panel trasero **no** está disponible (`docs/28:59`): giro de la cámara orbital en el stick derecho; sin táctil,
cursor con el stick derecho, rumbo con L/R y ✕. [I] Emulación de ratón desde táctil: comprobar que un toque produce un
solo evento (§9.3).

```gdscript
extends "res://comun/visor/herramienta_visor.gd"
## Nav2 Goal (goal_tool.cpp): pulsar = posición, arrastrar = rumbo, soltar = publicar (Vita: ✕ confirma).
var _inicio = null                                    # Vector3 ROS o null
var _yaw := 0.0
var _pendiente = null                                 # [Vector3, yaw] en la Vita hasta ✕
func _init() -> void:
	topic = "goal_pose"
	tipo = "geometry_msgs/msg/PoseStamped"
func _unhandled_input(e: InputEvent) -> void:
	if not activa:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_inicio = suelo_ros(e.position)
		elif _inicio != null:
			if visor.en_vita and confirmar_en_vita:
				_pendiente = [_inicio, _yaw]          # flecha naranja en el HUD
			else:
				_publicar(_inicio, _yaw)
			_inicio = null
	elif e is InputEventMouseMotion and _inicio != null:
		var p = suelo_ros(e.position)
		if p != null and Vector2(p.x - _inicio.x, p.y - _inicio.y).length() > 0.05:
			_yaw = atan2(p.y - _inicio.y, p.x - _inicio.x)
	elif e.is_action_pressed("ui_accept") and _pendiente != null:   # ✕ en la Vita
		_publicar(_pendiente[0], _pendiente[1])
		_pendiente = null
func _publicar(p: Vector3, yaw: float) -> void:
	var m := RosMsg.from_type(tipo)
	m.header.frame_id = visor.marco_fijo
	m.header.stamp = visor.contexto.nodo.now()
	m.pose.position.x = p.x
	m.pose.position.y = p.y
	m.pose.orientation.z = sin(yaw * 0.5)
	m.pose.orientation.w = cos(yaw * 0.5)
	publicar(m)
```

`pose_inicial.gd` hereda de `meta.gd` y solo cambia `topic`, `tipo` y `_publicar` (código de hmi#17, con
`m.pose.covariance = cov` asignando el `PackedFloat64Array` entero, `API_PARITY.md:49`). `punto.gd` y `teleop.gd` son
los de hmi#18 y hmi#19 con `extends herramienta_visor.gd`, `conectar(n)` → la base y `_pub.publish` → `publicar`;
en teleop, `+ 0.0` evita publicar `-0.0` (`g6-hmi/main.gd:98`) y el `RosTimer` de 0,05 s se crea en `conectar()`
tras `super.conectar(v)`.
