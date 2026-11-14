extends SceneTree
## Prueba de host de los displays V3 (doc 36 §10): scan, path, pose y mapa en planta; robot_joints, pose y mapa
## en 3D; arreglos del relay de docs/31 §4.4 (LUT + blit_rect de teselas, tabla de direcciones del scan).
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_displays.gd
##
## Mensajes REALES: se construyen con RosMsg, se serializan y se deserializan en otro RosMsg (lo que hace el
## transporte), y además se publican por `loopback`. El camino compacto usa bytes VC/1 hechos con las funciones de
## `ros/vc1.gd` (las mismas huellas que `docker/scripts/vita_relay.py`, comprobadas en `pruebas/runner.gd`).
## La Vita se simula con `en_vita = true` (perfil HMI): camino compacto, cupos (D7) y planta 2D por defecto.

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const Registro = preload("res://comun/visor/registro_displays.gd")
const VitaRelay = preload("res://comun/vita_relay.gd")
const VC1 = preload("res://comun/ros/vc1.gd")
const D := "res://comun/visor/displays/"

var fallos := 0
var pruebas := 0
var _escena_robot: PackedScene


func check(condicion: bool, nombre: String) -> void:
	pruebas += 1
	if not condicion:
		fallos += 1
		push_error(nombre)
	else:
		print("OK ", nombre)


func _init() -> void:
	_correr.call_deferred()


func _correr() -> void:
	RosMsg.load_schema_file(String(ProjectSettings.get_setting("ros/schema_path", "res://ros/schema.rsch")))
	_escena_robot = _robot_falso()
	_probar_relay()
	_probar_tamanos()
	_probar_registro()
	await _probar_pc()
	await _probar_vita()
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


# ---------------------------------------------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------------------------------------------
## Serializa y deserializa en un RosMsg nuevo (ida y vuelta CDR, como en el transporte).
func _ida_vuelta(m, tipo: String):
	var bytes: PackedByteArray = m.serialize()
	var r = RosMsg.from_type(tipo)
	check(r.deserialize(bytes) == OK, "CDR ida y vuelta de %s (%d B)" % [tipo, bytes.size()])
	return r


func _arr(tipo: String, datos):
	var m = RosMsg.from_type(tipo)
	m.data = datos
	return m


func _robot_falso() -> PackedScene:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar ultimo := []\nvar veces := 0\nfunc set_joints(n, p) -> void:\n\tultimo = [n, p]\n\tveces += 1\n"
	check(s.reload() == OK, "robot falso compila")
	var raiz := Node3D.new()
	raiz.name = "RobotFalso"
	raiz.set_script(s)
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = "Malla%d" % i
		raiz.add_child(mi)
		mi.owner = raiz
	var ps := PackedScene.new()
	check(ps.pack(raiz) == OK, "robot falso empaquetado")
	raiz.free()
	return ps


func _display(ruta: String, nombre: String, props: Dictionary) -> Node:
	var d: Node = load(ruta).new()
	d.name = nombre
	for k in props:
		d.set(k, props[k])
	return d


## Visor con los displays: 3D colgando del visor y 2D de una Planta (CanvasLayer), como en main.tscn.
func _visor(en_vita: bool, d3: Array, d2: Array) -> Node:
	var v: Node = VisorRos.new()
	v.name = "VisorPrueba"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = en_vita
	for d in d3:
		v.add_child(d)
	var planta := CanvasLayer.new()
	planta.name = "Planta"
	v.add_child(planta)
	for d in d2:
		planta.add_child(d)
	var raiz := Node3D.new()
	raiz.name = "Escena"
	raiz.add_child(v)
	root.add_child(raiz)
	return v


func _esperar(v: Node) -> void:
	for _i in 60:
		if v.estado != "sin conectar":
			return
		await process_frame


func _fotogramas(n: int) -> void:
	for _i in n:
		await process_frame


func _cerrar(v: Node) -> void:
	v.get_parent().queue_free()
	await _fotogramas(2)


func _rejilla(w: int, h: int) -> PackedInt32Array:
	var r := PackedInt32Array()
	for y in h:
		for x in w:
			r.append((x * 7 + y * 13) % 103 - 2)        # −2 … 100: desconocido, libre, gris y ocupado
	return r


# ---------------------------------------------------------------------------------------------------------------
# Relay: LUT + blit_rect = set_pixel (imagen idéntica) y tabla de direcciones = cos/sin por rayo
# ---------------------------------------------------------------------------------------------------------------
func _probar_relay() -> void:
	var w := 70
	var h := 37                                          # bordes parciales en x y en y
	var rej := _rejilla(w, h)
	var relay = VitaRelay.new()
	var meta = _arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array([0.05, w, h, -1.0, -2.0, 3, 2, 1]))
	relay.on_mapa_meta(meta)
	var ref := Image.create(w, h, false, Image.FORMAT_RGBA8)
	ref.fill(VitaRelay.COLORES[0])
	var us_lut := 0
	var us_ref := 0
	for ty in 2:
		for tx in 3:
			var b: PackedByteArray = VC1.empaquetar_tesela(rej, w, h, tx, ty, 513)
			var m = _ida_vuelta(_arr("std_msgs/msg/UInt8MultiArray", b), "std_msgs/msg/UInt8MultiArray")
			check(m.data == b, "VC/1 tesela (%d,%d): bytes intactos tras CDR" % [tx, ty])
			var t := Time.get_ticks_usec()
			relay.on_mapa_tesela(m)
			us_lut += Time.get_ticks_usec() - t
			t = Time.get_ticks_usec()
			_tesela_set_pixel(ref, b, w, h)
			us_ref += Time.get_ticks_usec() - t
	check(relay.mapa_img.get_data() == ref.get_data(), "tesela: LUT + blit_rect = 1 024 set_pixel (imagen idéntica)")
	check(relay.teselas_recibidas == 6, "tesela: 6 recibidas")
	print("  tesela en host: LUT %d µs, set_pixel %d µs (media de 6)" % [us_lut / 6, us_ref / 6])
	# En el host la diferencia es pequeña (C++ rápido); la ganancia que importa es en la Vita (gate de V3).
	check(us_lut / 6 < 1500, "tesela: LUT ≤ 1,5 ms por tesela en el host (%d µs)" % (us_lut / 6))
	check(relay.actualizar_textura() == true and relay.actualizar_textura() == false,
			"actualizar_textura(): true al subir, false sin cambios")
	# Tesela fuera del mapa: se ignora sin error.
	relay.on_mapa_tesela(_arr("std_msgs/msg/UInt8MultiArray", VC1.empaquetar_tesela(rej, w, h, 0, 0, 1).duplicate()))
	var fuera: PackedByteArray = VC1.empaquetar_tesela(rej, w, h, 0, 0, 1)
	fuera[2] = 9
	relay.on_mapa_tesela(_arr("std_msgs/msg/UInt8MultiArray", fuera))
	check(relay.teselas_recibidas == 7, "tesela fuera del mapa: se ignora")

	# Scan: tabla de direcciones frente a cos/sin por rayo (código anterior).
	var rangos := PackedFloat32Array()
	for i in 400:
		rangos.append([INF, NAN, 0.01, 25.0, 1.5 + i * 0.01][i % 5])
	var sc: PackedInt32Array = VC1.empaquetar_scan(rangos, -PI, TAU / 400.0, 0.05, 20.0, 7)
	var ms = _ida_vuelta(_arr("std_msgs/msg/Int16MultiArray", sc), "std_msgs/msg/Int16MultiArray")
	check(ms.data == sc, "VC/1 scan: valores intactos tras CDR")
	var nuevo: PackedVector2Array = VitaRelay.scan_puntos(ms)
	var viejo := _scan_viejo(ms)
	check(nuevo == viejo and nuevo.size() > 0, "scan: tabla de direcciones = cos/sin por rayo (%d puntos)" % nuevo.size())
	check(VitaRelay.scan_puntos(ms) == viejo, "scan: segunda llamada con la tabla cacheada, mismo resultado")


## Código de vita_relay.gd antes de V3 (referencia: 1 024 set_pixel por tesela).
func _tesela_set_pixel(img: Image, b: PackedByteArray, ancho: int, alto: int) -> void:
	var tx := b[2]
	var ty := b[3]
	for j in 32:
		var y := ty * 32 + j
		if y >= alto:
			break
		var fila := alto - 1 - y
		for i in 32:
			var x := tx * 32 + i
			if x >= ancho:
				break
			var k := j * 32 + i
			var c := (b[4 + (k >> 2)] >> ((k & 3) * 2)) & 3
			img.set_pixel(x, fila, VitaRelay.COLORES[mini(c, 2)])


func _scan_viejo(m) -> PackedVector2Array:
	var d = m.data
	var r := PackedVector2Array()
	var a0 := deg_to_rad(d[1] / 100.0)
	var inc := deg_to_rad(d[2] / 100.0)
	var n: int = mini(d[3], d.size() - 4)
	for i in n:
		var dist: float = d[4 + i] / 100.0
		if dist > 0.0:
			var a := a0 + i * inc
			r.append(Vector2(cos(a), sin(a)) * dist)
	return r


# ---------------------------------------------------------------------------------------------------------------
# Tamaños VC/1 con rosbags (≤ 488 B: carga ≤ 484 + 4 de encapsulación; doc 36 §5.1)
# ---------------------------------------------------------------------------------------------------------------
func _probar_tamanos() -> void:
	var rangos := PackedFloat32Array()
	rangos.resize(720)
	rangos.fill(3.0)
	var sc: PackedInt32Array = VC1.empaquetar_scan(rangos, -PI, TAU / 720.0, 0.1, 20.0, 1)
	var casos := {
		"scan_compacto 180": _arr("std_msgs/msg/Int16MultiArray", sc),
		"pose2d": _arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array([1, 2, 0.5, 0.1, 0, 0.2])),
		"joints 118": _arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array(range(118))),
		"path_compacto 57": _arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array(range(115))),
		"mapa_tesela": _arr("std_msgs/msg/UInt8MultiArray", VC1.empaquetar_tesela(_rejilla(32, 32), 32, 32, 0, 0, 1)),
	}
	for k in casos:
		var n: int = casos[k].serialize().size() + 4
		check(n <= 488, "tamaño VC/1 %s: %d B ≤ 488" % [k, n])


# ---------------------------------------------------------------------------------------------------------------
# Registro: el 3D es el defecto del PC y la planta 2D el de la Vita (D7)
# ---------------------------------------------------------------------------------------------------------------
func _probar_registro() -> void:
	var casos := [
		["/map", "nav_msgs/msg/OccupancyGrid", "3d/mapa.gd", "2d/mapa.gd"],
		["/goal_pose", "geometry_msgs/msg/PoseStamped", "3d/pose.gd", "2d/pose.gd"],
		["/odom", "nav_msgs/msg/Odometry", "2d/pose.gd", "2d/pose.gd"],
		["/scan", "sensor_msgs/msg/LaserScan", "2d/scan.gd", "2d/scan.gd"],
		["/plan", "nav_msgs/msg/Path", "2d/path.gd", "2d/path.gd"],
		["/joint_states", "sensor_msgs/msg/JointState", "3d/robot_joints.gd", "3d/robot_joints.gd"],
		["/vita/pose2d", "std_msgs/msg/Float32MultiArray", "2d/pose.gd", "2d/pose.gd"],
		["/vita/joints", "std_msgs/msg/Float32MultiArray", "3d/robot_joints.gd", "3d/robot_joints.gd"],
		["/vita/path_compacto", "std_msgs/msg/Float32MultiArray", "2d/path.gd", "2d/path.gd"],
		["/vita/mapa_tesela", "std_msgs/msg/UInt8MultiArray", "2d/mapa.gd", "2d/mapa.gd"],
		["/vita/scan_compacto", "std_msgs/msg/Int16MultiArray", "2d/scan.gd", "2d/scan.gd"],
	]
	for c in casos:
		var pc: String = Registro.regla(c[0], c[1], false).get("script", "")
		var vita: String = Registro.regla(c[0], c[1], true).get("script", "")
		check(pc == D + c[2] and vita == D + c[3], "registro %s: PC %s, Vita %s" % [c[0], c[2], c[3]])
	var d: Node = Registro.crear("/map", "nav_msgs/msg/OccupancyGrid", true)
	check(d != null and d.get_script().resource_path.ends_with("2d/mapa.gd"), "registro: crear() en la Vita da la planta")
	d.free()
	for r in ["2d/scan.gd", "2d/path.gd", "2d/pose.gd", "2d/mapa.gd", "3d/robot_joints.gd", "3d/pose.gd", "3d/mapa.gd"]:
		var s = load(D + r)
		check(s != null and s.nombre_display() != "" and s.tipos_ros().size() > 0, "display %s: identidad" % r)


# ---------------------------------------------------------------------------------------------------------------
# PC: camino estándar con mensajes reales (ida y vuelta CDR) y por loopback
# ---------------------------------------------------------------------------------------------------------------
func _displays() -> Dictionary:
	return {
		"robot": _display(D + "3d/robot_joints.gd", "Robot", {"topic": "/joint_states", "tipo": "sensor_msgs/msg/JointState",
				"escena_robot": _escena_robot, "frame_id": "", "hz": 0.0}),
		"pose3": _display(D + "3d/pose.gd", "Pose3D", {"topic": "/goal_pose", "tipo": "geometry_msgs/msg/PoseStamped", "hz": 0.0}),
		"mapa3": _display(D + "3d/mapa.gd", "Mapa3D", {"topic": "/map", "tipo": "nav_msgs/msg/OccupancyGrid"}),
		"mapa": _display(D + "2d/mapa.gd", "Mapa", {"topic": "/map", "tipo": "nav_msgs/msg/OccupancyGrid"}),
		"scan": _display(D + "2d/scan.gd", "Scan", {"topic": "/scan", "tipo": "sensor_msgs/msg/LaserScan", "hz": 0.0}),
		"pose": _display(D + "2d/pose.gd", "Odom", {"topic": "/odom", "tipo": "nav_msgs/msg/Odometry", "hz": 0.0}),
		"path": _display(D + "2d/path.gd", "Plan", {"topic": "/plan", "tipo": "nav_msgs/msg/Path", "hz": 0.0}),
	}


func _probar_pc() -> void:
	var ds := _displays()
	var v := _visor(false, [ds.robot, ds.pose3, ds.mapa3], [ds.mapa, ds.scan, ds.pose, ds.path])
	await _esperar(v)
	check(v.ros_listo and not v.usa_compactos(), "PC: loopback, camino estándar")
	for k in ["robot", "pose3", "mapa3", "mapa", "scan", "pose"]:
		check(ds[k].estado == "ok" and not ds[k].canal.compacto, "PC: %s ok por el topic estándar (%s)" % [k, ds[k].canal.topic_abierto])
	var hay_path: bool = RosMsg.from_type("nav_msgs/msg/Path") != null
	check(ds.path.estado == ("ok" if hay_path else "sin esquema: nav_msgs/msg/Path"),
			"PC: path «%s» (Path no está en el esquema de visor-ros: V5)" % ds.path.estado)

	# LaserScan: NaN, ±Inf y fuera de rango se descartan (T2).
	var scan = RosMsg.from_type("sensor_msgs/msg/LaserScan")
	scan.header.frame_id = "base_scan"
	scan.angle_min = -PI / 2
	scan.angle_increment = PI / 59.0
	scan.range_min = 0.1
	scan.range_max = 10.0
	var r := PackedFloat32Array()
	for i in 60:
		r.append([2.0, NAN, INF, -INF, 0.05, 11.0][i % 6] if i % 6 != 0 else 2.0)
	scan.ranges = r
	ds.scan._al_mensaje(_ida_vuelta(scan, "sensor_msgs/msg/LaserScan"))
	check(ds.scan.puntos_dibujados == 10, "scan PC: 10 de 60 rayos válidos (NaN/Inf/fuera fuera)")
	check(ds.scan._v.size() == 30 and ds.scan._idx.size() == 30, "scan PC: un triángulo por punto en un lote")
	var p0: Vector2 = ds.scan._v[0] - Vector2(0, -ds.scan.lado_px)
	check(p0.distance_to(Vector2(0, 2.0) * v.px_por_m) < 0.01, "scan PC: rayo −90° a 2 m = (0, +2 m·px) en planta")

	# Odometry → pose 2D (pose.pose) con yaw 90°.
	var od = RosMsg.from_type("nav_msgs/msg/Odometry")
	od.header.frame_id = "odom"
	od.pose.pose.position.x = 1.5
	od.pose.pose.position.y = -0.5
	od.pose.pose.orientation.z = sin(PI / 4)
	od.pose.pose.orientation.w = cos(PI / 4)
	ds.pose._al_mensaje(_ida_vuelta(od, "nav_msgs/msg/Odometry"))
	check(ds.pose.pose.is_equal_approx(Vector3(1.5, -0.5, PI / 2)), "pose 2D PC: Odometry → (1,5, −0,5, 90°)")
	check(ds.pose.visible and ds.pose._rastro.size() == 1, "pose 2D PC: visible y rastro iniciado")

	# PoseStamped → flecha 3D.
	var ps = RosMsg.from_type("geometry_msgs/msg/PoseStamped")
	ps.header.frame_id = "map"
	ps.pose.position.x = 2.0
	ps.pose.orientation.w = 1.0
	ds.pose3._al_mensaje(_ida_vuelta(ps, "geometry_msgs/msg/PoseStamped"))
	var t: Transform3D = ds.pose3._vis.transform
	check(ds.pose3._vis.visible and t.origin.is_equal_approx(Vector3(0, 0, -2)), "pose 3D PC: x ROS = −Z Godot")
	check(ds.pose3.cupo == 1 and ds.pose3.get_child_count() == 1, "pose 3D PC: una instancia")

	# OccupancyGrid → 2D y 3D (rampa «map» de RViz).
	var g = RosMsg.from_type("nav_msgs/msg/OccupancyGrid")
	g.header.frame_id = "map"
	g.info.resolution = 0.1
	g.info.width = 40
	g.info.height = 30
	g.info.origin.position.x = -2.0
	g.info.origin.position.y = -1.5
	g.info.origin.orientation.w = 1.0
	var datos := _rejilla(40, 30)
	datos[0] = -1                                       # celda (0,0): desconocido
	datos[40 * 30 - 1] = 100                            # última celda: ocupado
	g.data = datos
	var gm = _ida_vuelta(g, "nav_msgs/msg/OccupancyGrid")
	ds.mapa._al_mensaje(gm)
	ds.mapa3._al_mensaje(gm)
	var tex: ImageTexture = ds.mapa.mapa.textura
	check(tex != null and tex.get_width() == 40 and tex.get_height() == 30, "mapa 2D PC: textura 40×30")
	var img := tex.get_image()
	check(img.get_pixel(0, 29).to_rgba32() == Color8(0x70, 0x89, 0x86).to_rgba32(), "mapa 2D PC: (0,0) desconocido abajo a la izquierda")
	check(img.get_pixel(39, 0).to_rgba32() == Color8(0, 0, 0).to_rgba32(), "mapa 2D PC: última celda ocupada arriba a la derecha")
	check(ds.mapa.mapa.origen == Vector2(-2.0, -1.5) and is_equal_approx(ds.mapa.mapa.res, 0.1), "mapa 2D PC: origen y resolución")
	var quad: MeshInstance3D = ds.mapa3._vis
	check(quad.visible and quad.mesh.get_faces().size() == 6, "mapa 3D PC: un quad de 2 triángulos")
	check(ds.mapa3._mat.albedo_texture == ds.mapa3.mapa.textura, "mapa 3D PC: textura en el material")

	# JointState → set_joints (por loopback, de punta a punta).
	var js = RosMsg.from_type("sensor_msgs/msg/JointState")
	js.name = PackedStringArray(["a", "b"])
	js.position = PackedFloat64Array([0.25, -0.5])
	var pub = v.contexto.nodo.create_publisher("/joint_states", "sensor_msgs/msg/JointState", v.contexto.qos(true, 1, false))
	pub.publish(js)
	await _fotogramas(3)
	var rob = ds.robot.robot
	check(rob != null and rob.veces == 1 and rob.ultimo[0] == PackedStringArray(["a", "b"]) and rob.ultimo[1][1] == -0.5,
			"robot PC: JointState por loopback → set_joints")
	check(ds.robot.cupo == 40, "robot PC: 40 instancias pedidas")

	# Path: el camino estándar con poses reales (sin esquema de Path, envoltorio Dictionary con PoseStamped).
	var poses := []
	for i in 5:
		var q = RosMsg.from_type("geometry_msgs/msg/PoseStamped")
		q.pose.position.x = i * 0.5
		q.pose.position.y = 1.0
		poses.append(_ida_vuelta(q, "geometry_msgs/msg/PoseStamped") if i == 0 else q)
	var pts: PackedVector2Array = ds.path._procesar({"poses": poses})
	ds.path.visor = v
	ds.path._pintar(pts)
	check(ds.path.puntos_dibujados == 5 and ds.path._pts[4] == Vector2(2.0, -1.0) * v.px_por_m, "path PC: polilínea de 5 puntos")
	pub = null
	await _cerrar(v)


# ---------------------------------------------------------------------------------------------------------------
# Vita simulada: camino compacto VC/1 por loopback, cupos D7
# ---------------------------------------------------------------------------------------------------------------
func _probar_vita() -> void:
	var ds := _displays()
	var v := _visor(true, [ds.robot, ds.pose3, ds.mapa3], [ds.mapa, ds.scan, ds.pose, ds.path])
	await _esperar(v)
	check(v.usa_compactos(), "Vita: camino compacto")
	var topics := {"robot": "/vita/joints", "pose3": "/vita/pose2d", "mapa3": "/vita/mapa_tesela", "mapa": "/vita/mapa_tesela",
			"scan": "/vita/scan_compacto", "pose": "/vita/pose2d", "path": "/vita/path_compacto"}
	for k in topics:
		check(ds[k].estado == "ok" and ds[k].canal.compacto and ds[k].canal.topic_abierto == topics[k],
				"Vita: %s suscrito a %s" % [k, topics[k]])
	# Cupos (perfil HMI): robot 40, poses 4, mundo 12; 2D sensores 800.
	check(ds.robot.cupo == 40 and v.usado("robot") == 40, "cupo Vita: robot 40 de 40")
	check(ds.pose3.cupo == 1 and v.usado("poses") <= 4, "cupo Vita: pose 3D 1 de 4")
	check(ds.mapa3.cupo == 1 and v.usado("mundo") <= 12, "cupo Vita: mapa 3D 1 de 12")
	check(v.usado("sensores_2d") == 360 + 112 + 100 + 1 and v.usado("sensores_2d") <= 800,
			"cupo Vita: sensores 2D %d ≤ 800" % v.usado("sensores_2d"))
	check(not ds.mapa.latched and not ds.mapa3.latched, "Vita: la tesela se suscribe best effort")

	var nodo = v.contexto.nodo
	var be = v.contexto.qos(true, 1, false)
	var fiable = v.contexto.qos(false, 1, true)
	var p_meta = nodo.create_publisher("/vita/mapa_meta", "std_msgs/msg/Float32MultiArray", fiable)
	var p_tes = nodo.create_publisher("/vita/mapa_tesela", "std_msgs/msg/UInt8MultiArray", be)
	var p_scan = nodo.create_publisher("/vita/scan_compacto", "std_msgs/msg/Int16MultiArray", be)
	var p_pose = nodo.create_publisher("/vita/pose2d", "std_msgs/msg/Float32MultiArray", be)
	var p_path = nodo.create_publisher("/vita/path_compacto", "std_msgs/msg/Float32MultiArray", be)
	var p_js = nodo.create_publisher("/vita/joints", "std_msgs/msg/Float32MultiArray", be)
	var p_orden = nodo.create_publisher("/vita/joints_orden", "std_msgs/msg/String", fiable)

	# Mapa: meta + 6 teselas (todas se entregan: coalescer apagado).
	var w := 70
	var h := 37
	var rej := _rejilla(w, h)
	p_meta.publish(_arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array([0.05, w, h, -1.0, -2.0, 3, 2, 1])))
	await _fotogramas(2)
	for ty in 2:
		for tx in 3:
			p_tes.publish(_arr("std_msgs/msg/UInt8MultiArray", VC1.empaquetar_tesela(rej, w, h, tx, ty, 1)))
	# Scan de 720 rayos que el relay diezma a 180 (paso 4); 1 de cada 4 elegidos es NaN → 0 = sin dato.
	var rangos := PackedFloat32Array()
	for i in 720:
		rangos.append(NAN if i % 16 == 0 else 2.0)
	p_scan.publish(_arr("std_msgs/msg/Int16MultiArray", VC1.empaquetar_scan(rangos, -PI, TAU / 720.0, 0.1, 20.0, 3)))
	p_pose.publish(_arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array([1.0, 2.0, PI / 2, 0.3, 0.0, 0.1])))
	var ruta := PackedFloat32Array([57.0])                  # [n, x0, y0, …] como empaquetar_path
	for i in 57:
		ruta.append_array(PackedFloat32Array([i * 0.1, sin(i * 0.1)]))
	p_path.publish(_arr("std_msgs/msg/Float32MultiArray", ruta))
	p_js.publish(_arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array([0.1, 0.2])))   # antes del orden: se ignora
	await _fotogramas(3)
	check(ds.robot.robot.veces == 0, "robot Vita: sin joints_orden, los valores se ignoran")
	p_orden.publish(_arr("std_msgs/msg/String", "cadera,rodilla"))
	await _fotogramas(2)
	p_js.publish(_arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array([0.1, 0.2])))
	await _fotogramas(3)

	check(ds.mapa.mapa.teselas == 6 and ds.mapa3.mapa.teselas == 6, "mapa Vita: 6 teselas en 2D y 3D")
	var ref := VitaRelay.new()
	ref.on_mapa_meta(_arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array([0.05, w, h, -1.0, -2.0, 3, 2, 1])))
	for ty in 2:
		for tx in 3:
			_tesela_set_pixel(ref.mapa_img, VC1.empaquetar_tesela(rej, w, h, tx, ty, 1), w, h)
	check(ds.mapa.mapa.relay.mapa_img.get_data() == ref.mapa_img.get_data(), "mapa Vita: imagen = decodificación de referencia")
	check(ds.mapa.mapa.origen == Vector2(-1.0, -2.0) and ds.mapa.mapa.ancho == 70, "mapa Vita: geometría de mapa_meta")
	await create_timer(0.3).timeout                         # HZ_TEXTURA = 4
	await _fotogramas(2)
	check(ds.mapa.mapa.textura != null and ds.mapa.mapa.textura == ds.mapa.mapa.relay.mapa_tex, "mapa Vita: textura del relay")
	check(ds.mapa3._vis.visible and ds.mapa3._mat.albedo_texture == ds.mapa3.mapa.textura, "mapa 3D Vita: quad con la textura")
	print("  tesela en el display (host): última %d µs, máx %d µs" % [ds.mapa.mapa.us_ultima, ds.mapa.mapa.us_max])

	check(ds.scan.puntos_dibujados == 135 and ds.scan.puntos_dibujados <= ds.scan.cupo,
			"scan Vita: 135 de 180 rayos (los NaN = 0 fuera), ≤ cupo %d" % ds.scan.cupo)
	check(ds.pose.pose.is_equal_approx(Vector3(1.0, 2.0, PI / 2)), "pose 2D Vita: pose2d → (1, 2, 90°)")
	var nan_msg = _arr("std_msgs/msg/Float32MultiArray", PackedFloat32Array([NAN, 0, 0, 0, 0, 0]))
	check(ds.pose._procesar_compacto(nan_msg) == null and ds.pose3._procesar_compacto(nan_msg) == null,
			"pose Vita: pose2d con NaN se ignora en 2D y 3D (T2, revisión V1)")
	var t: Transform3D = ds.pose3._vis.transform
	check(t.origin.is_equal_approx(Vector3(-2, 0, -1)), "pose 3D Vita: pose2d → (x ROS = −Z, y ROS = −X)")
	check(ds.path.puntos_dibujados == 57 and ds.path.puntos_dibujados <= ds.path.cupo, "path Vita: 57 puntos ≤ cupo 112")
	check(ds.robot.robot.veces == 1 and ds.robot.robot.ultimo[0] == PackedStringArray(["cadera", "rodilla"]),
			"robot Vita: joints en el orden de joints_orden")
	check(ds.robot.poses_base >= 1 and ds.robot.robot.transform.origin.is_equal_approx(Vector3(-2, 0, -1)),
			"robot Vita: base colocada con pose2d (sin TF)")

	# Cupo 2D lleno: un segundo scan no cabe entero (800 − 573 = 227; revisión V3: Odom pide 100 < 360) y dibuja como mucho lo concedido.
	var scan2 = _display(D + "2d/scan.gd", "Scan2", {"hz": 0.0})
	v.get_node("Planta").add_child(scan2)
	scan2.conectar(v)
	check(scan2.cupo == 227 and v.usado("sensores_2d") == 800, "cupo Vita: segundo scan recibe 227 (zona llena)")
	var mucho := PackedVector2Array()
	for i in 300:
		mucho.append(Vector2(1, 0))
	scan2._pintar(mucho)
	check(scan2.puntos_dibujados == 227, "cupo Vita: el scan dibuja ≤ su cupo")
	scan2.desconectar()
	var otra_pose = _display(D + "3d/pose.gd", "Pose3D_b", {})
	v.add_child(otra_pose)
	for i in 4:
		v.reservar("poses", 1, "relleno")
	otra_pose.conectar(v)
	check(otra_pose.estado == "sin cupo" and otra_pose._vis == null, "cupo Vita: pose 3D sin cupo no crea instancia")
	p_meta = null
	p_tes = null
	p_scan = null
	p_pose = null
	p_path = null
	p_js = null
	p_orden = null
	await _cerrar(v)
