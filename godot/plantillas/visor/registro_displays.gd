extends RefCounted
## RegistroDisplays (ADR 0013 §1; doc 36 §2.6 y §2.9.8): (tipo, patrón de topic) → script del display y capa
## (≈ `<message_type>` de plugins_description.xml de RViz; contrato de gdviz). Estático:
## `const Registro = preload("res://comun/visor/registro_displays.gd")`.
##
## Lo usan el ExploradorTopics del PC («añadir por topic», sin guardar; V12) y las pruebas de presupuesto. NO crea
## los displays de la escena: esos son nodos del `.tscn` (doc 35). El coste de cada display lo da su `_coste()`.
##
## Orden = prioridad: primero las reglas con topic (el relay reutiliza `*MultiArray` con significado por topic,
## `docker/scripts/vita_relay.py:10-19`), después las genéricas y al final el comodín (= `ros2 topic echo`).
## Los scripts de `displays/` llegan con V3–V12; hasta entonces `crear()` devuelve null si el script no existe.
## Al añadir un display, su regla sale de la tabla maestra (doc 36a §4.0).

const D := "res://comun/visor/displays/"
## Claves: `tipo`, `topic` (patrón; "" = cualquiera), `script`, `capa`, y opcionales `solo_pc` (el display no
## existe en la Vita) y `orbital` (vista 3D: es el defecto del PC, pero en la Vita se salta para que gane la
## planta 2D de la regla siguiente, D7; el script 3D sigue funcionando en la Vita si la escena lo pone).
## V5 (2026-11-13): reglas de los displays directos pequeños (punto, vector, ejes, fuerza, imu, rango, marcador
## simple, polígono, covarianza y gps).
## V3 (2026-11-13): reglas de robot_joints, pose (2D y 3D) y mapa 3D; `2d/pose.gd` hace de odometría hasta que
## exista `2d/odometria.gd` (`regla()` toma la primera cuyo script exista).
const REGLAS := [
	{"tipo": "std_msgs/msg/Int16MultiArray", "topic": "*/scan_compacto", "script": D + "2d/scan.gd", "capa": "sensores_2d"},
	{"tipo": "std_msgs/msg/Int16MultiArray", "topic": "*/nube2d", "script": D + "2d/nube.gd", "capa": "sensores_2d"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/pose2d", "script": D + "2d/odometria.gd", "capa": "sensores_2d"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/pose2d", "script": D + "2d/pose.gd", "capa": "sensores_2d"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/joints", "script": D + "3d/robot_joints.gd", "capa": "robot"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/path_compacto", "script": D + "2d/path.gd", "capa": "sensores_2d"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/marcadores", "script": D + "3d/marcadores.gd", "capa": "marcadores"},
	{"tipo": "std_msgs/msg/UInt8MultiArray", "topic": "*/mapa_tesela", "script": D + "2d/mapa.gd", "capa": "sensores_2d"},
	{"tipo": "sensor_msgs/msg/LaserScan", "script": D + "2d/scan.gd", "capa": "sensores_2d"},
	{"tipo": "sensor_msgs/msg/JointState", "script": D + "3d/robot_joints.gd", "capa": "robot"},
	{"tipo": "nav_msgs/msg/Odometry", "script": D + "2d/odometria.gd", "capa": "sensores_2d"},
	{"tipo": "nav_msgs/msg/Odometry", "script": D + "2d/pose.gd", "capa": "sensores_2d"},
	{"tipo": "nav_msgs/msg/Path", "script": D + "2d/path.gd", "capa": "sensores_2d"},
	{"tipo": "nav_msgs/msg/OccupancyGrid", "script": D + "3d/mapa.gd", "capa": "mundo", "orbital": true},
	{"tipo": "nav_msgs/msg/OccupancyGrid", "script": D + "2d/mapa.gd", "capa": "sensores_2d"},
	{"tipo": "geometry_msgs/msg/PoseStamped", "script": D + "3d/pose.gd", "capa": "poses", "orbital": true},
	{"tipo": "geometry_msgs/msg/PoseStamped", "script": D + "2d/pose.gd", "capa": "sensores_2d"},
	# V5: tipos directos pequeños (caben en 488 B; esquema en TIPOS_VISOR). Marker: el gestor (V8) si existe y si no,
	# el marcador simple.
	{"tipo": "geometry_msgs/msg/PointStamped", "script": D + "3d/punto.gd", "capa": "poses"},
	{"tipo": "geometry_msgs/msg/Vector3Stamped", "script": D + "3d/vector.gd", "capa": "poses"},
	{"tipo": "geometry_msgs/msg/QuaternionStamped", "script": D + "3d/ejes.gd", "capa": "poses"},
	{"tipo": "geometry_msgs/msg/TransformStamped", "script": D + "3d/ejes.gd", "capa": "poses"},
	{"tipo": "geometry_msgs/msg/WrenchStamped", "script": D + "3d/fuerza.gd", "capa": "poses"},
	{"tipo": "geometry_msgs/msg/AccelStamped", "script": D + "3d/fuerza.gd", "capa": "poses"},
	{"tipo": "geometry_msgs/msg/TwistStamped", "script": D + "3d/fuerza.gd", "capa": "poses"},
	{"tipo": "geometry_msgs/msg/Twist", "script": D + "3d/fuerza.gd", "capa": "poses"},
	{"tipo": "sensor_msgs/msg/Imu", "script": D + "3d/imu.gd", "capa": "poses"},
	{"tipo": "sensor_msgs/msg/Range", "script": D + "3d/rango.gd", "capa": "poses"},
	{"tipo": "visualization_msgs/msg/Marker", "script": D + "3d/marcadores.gd", "capa": "marcadores"},
	{"tipo": "visualization_msgs/msg/Marker", "script": D + "3d/marcador_simple.gd", "capa": "marcadores"},
	# V8: gestor de MarkerArray (3D; las líneas, puntos y textos los pinta además 2d/marcadores_2d.gd en la misma escena)
	# y los puntos del relay (<p>/marcador_puntos).
	{"tipo": "visualization_msgs/msg/MarkerArray", "script": D + "3d/marcadores.gd", "capa": "marcadores"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/marcador_puntos", "script": D + "2d/marcadores_2d.gd", "capa": "resto_2d"},
	{"tipo": "geometry_msgs/msg/PolygonStamped", "script": D + "2d/poligono.gd", "capa": "sensores_2d"},
	{"tipo": "geometry_msgs/msg/PoseWithCovarianceStamped", "script": D + "2d/covarianza.gd", "capa": "sensores_2d"},
	{"tipo": "sensor_msgs/msg/NavSatFix", "script": D + "2d/gps.gd", "capa": "sensores_2d"},
	# V9: TF y poses. Relay `<p>/poses` y `<p>/pose_cov` (antes que el `*MultiArray` genérico); `<p>/tf` lo consume
	# VisorRos (TfLigero), no un display; TFMessage → display TF (consulta visor.tf, sin suscribirse a /tf).
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/poses", "script": D + "2d/poses.gd", "capa": "sensores_2d"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/pose_cov", "script": D + "2d/covarianza.gd", "capa": "sensores_2d"},
	{"tipo": "geometry_msgs/msg/PoseArray", "script": D + "2d/poses.gd", "capa": "sensores_2d"},
	{"tipo": "nav2_msgs/msg/ParticleCloud", "script": D + "2d/poses.gd", "capa": "sensores_2d"},
	{"tipo": "tf2_msgs/msg/TFMessage", "script": D + "3d/tf.gd", "capa": "tf"},
	# V10: percepción. Relay `<p>/detecciones` y `<p>/detecciones3d` (antes del `*MultiArray` genérico; `<p>/nube2d`
	# ya tiene su regla arriba); imagen comprimida en PC y Vita, cruda solo en el PC (D13); vision_msgs solo directo
	# en el PC (no está en TIPOS_VISOR, D10 y D12).
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/detecciones", "script": D + "hud/cajas_2d.gd", "capa": "hud"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/detecciones3d", "script": D + "2d/cajas_3d.gd", "capa": "resto_2d"},
	{"tipo": "sensor_msgs/msg/CompressedImage", "script": D + "hud/imagen.gd", "capa": "hud"},
	{"tipo": "sensor_msgs/msg/Image", "script": D + "hud/imagen.gd", "capa": "hud", "solo_pc": true},
	{"tipo": "sensor_msgs/msg/PointCloud2", "script": D + "2d/nube.gd", "capa": "sensores_2d"},
	{"tipo": "vision_msgs/msg/Detection2DArray", "script": D + "hud/cajas_2d.gd", "capa": "hud", "solo_pc": true},
	{"tipo": "vision_msgs/msg/Detection3DArray", "script": D + "2d/cajas_3d.gd", "capa": "resto_2d", "solo_pc": true},
	# V6: widgets HUD de eventos y estado (tipos estándar; en la Vita llegan por el relay `<p>/rosout` y `<p>/diagnostics`).
	{"tipo": "rcl_interfaces/msg/Log", "script": D + "hud/consola.gd", "capa": "hud"},
	{"tipo": "diagnostic_msgs/msg/DiagnosticArray", "script": D + "hud/diagnostico.gd", "capa": "hud"},
	{"tipo": "std_msgs/msg/*MultiArray", "script": D + "hud/multiarray.gd", "capa": "hud"},
	{"tipo": "*", "script": D + "hud/inspector_texto.gd", "capa": "hud"},
]


## Reglas que casan con (topic, tipo), en orden de prioridad. En la Vita se saltan las `solo_pc` y las
## `orbital` (planta 2D por defecto, D7).
static func candidatos(topic: String, tipo: String, en_vita: bool) -> Array:
	var out := []
	for r in REGLAS:
		if en_vita and (r.get("solo_pc", false) or r.get("orbital", false)):
			continue
		var patron_tipo: String = r["tipo"]
		var patron_topic: String = r.get("topic", "")
		if tipo.match(patron_tipo) and (patron_topic == "" or topic.match(patron_topic)):
			out.append(r)
	return out


## Primera regla cuyo script existe ya; {} si ninguna.
static func regla(topic: String, tipo: String, en_vita: bool) -> Dictionary:
	for r in candidatos(topic, tipo, en_vita):
		if ResourceLoader.exists(r["script"]):
			return r
	return {}


## Crea el display (sin añadirlo a la escena ni guardarlo). Solo para ExploradorTopics (PC). null si no hay.
static func crear(topic: String, tipo: String, en_vita: bool) -> Node:
	var r := regla(topic, tipo, en_vita)
	if r.is_empty():
		return null
	var d: Node = load(r["script"]).new()
	d.topic = topic
	d.tipo = tipo
	return d
