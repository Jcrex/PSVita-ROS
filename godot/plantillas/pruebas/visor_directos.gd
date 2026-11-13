extends SceneTree
## Prueba de host de V5 (doc 36 §10; sentencia W13 D10): esquema `TIPOS_VISOR` y displays directos pequeños.
##   - para cada tipo de `TIPOS_VISOR` (leído de `res://comun/generar_esquemas.py`, la misma lista que genera el
##     `.rsch`): `RosMsg.from_type` ≠ null, ida y vuelta `serialize`/`deserialize` con los mismos bytes y tamaño CDR
##     ≤ 488 B en el caso típico (convención del transporte: SIN los 4 B de encapsulación,
##     `godot/ros2_vita/xrce_transport.cpp:12-13,678`);
##   - cada display de V5 (`3d/{punto,vector,ejes,imu,fuerza,rango,marcador_simple}`, `2d/{poligono,covarianza,gps}`)
##     recibe su mensaje real (ida y vuelta CDR) y pinta sin errores de script (un `Logger` los cuenta); NaN (T2);
##   - tres tipos llegan de verdad por `loopback` (publicador → canal → display);
##   - RegistroDisplays y cupos de la Vita simulada (`en_vita = true`, perfil HMI).
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_directos.gd

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const Registro = preload("res://comun/visor/registro_displays.gd")
const Texto = preload("res://comun/visor/texto_superpuesto.gd")
const D := "res://comun/visor/displays/"
const MAX_BE := 488


## Cuenta los errores de script (Godot ≥ 4.5: `Logger`), como `pruebas/visor_hud.gd`.
class Vigia:
	extends Logger
	var errores := 0
	var ultimo := ""

	func _log_error(_f: String, file: String, _l: int, code: String, rationale: String, _e: bool, tipo: int,
			_b: Array[ScriptBacktrace]) -> void:
		if tipo == ERROR_TYPE_SCRIPT or (tipo == ERROR_TYPE_ERROR and file.contains("/visor/")):
			errores += 1
			ultimo = "%s: %s %s" % [file, code, rationale]

	func _log_message(_m: String, _e: bool) -> void:
		pass


var fallos := 0
var pruebas := 0
var vigia := Vigia.new()


func check(condicion: bool, nombre: String) -> void:
	pruebas += 1
	if not condicion:
		fallos += 1
		push_error(nombre)
	else:
		print("OK ", nombre)


func _init() -> void:
	OS.add_logger(vigia)
	_correr.call_deferred()


func _correr() -> void:
	RosMsg.load_schema_file(String(ProjectSettings.get_setting("ros/schema_path", "res://ros/schema.rsch")))
	_probar_esquema()
	_probar_registro()
	await _probar_pc()
	await _probar_vita()
	check(vigia.errores == 0, "sin errores de script en visor/ (%s)" % vigia.ultimo)
	OS.remove_logger(vigia)
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


# ---------------------------------------------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------------------------------------------
## `TIPOS_VISOR` tal como está en el generador (una sola fuente de verdad).
func _tipos_visor() -> PackedStringArray:
	var out := PackedStringArray()
	var texto := FileAccess.get_file_as_string("res://comun/generar_esquemas.py")
	var i := texto.find("TIPOS_VISOR = [")
	if i < 0:
		return out
	var fin := texto.find("\n]", i)
	for linea in texto.substr(i, fin - i).split("\n"):
		var l := linea.strip_edges()
		if l.begins_with("\"") and l.count("\"") >= 2:
			out.append(l.get_slice("\"", 1))
	return out


func _msg(tipo: String):
	return RosMsg.from_type(tipo)


func _ida_vuelta(m, tipo: String):
	var bytes: PackedByteArray = m.serialize()
	var r = RosMsg.from_type(tipo)
	check(r != null and r.deserialize(bytes) == OK and r.serialize() == bytes,
			"CDR ida y vuelta de %s (%d B)" % [tipo, bytes.size()])
	return r


func _pose(x: float, y: float, yaw: float):
	var p = _msg("geometry_msgs/msg/Pose")
	p.position.x = x
	p.position.y = y
	p.orientation.z = sin(yaw * 0.5)
	p.orientation.w = cos(yaw * 0.5)
	return p


func _uuid() -> PackedByteArray:
	var u := PackedByteArray()
	for i in 16:
		u.append(i * 13 % 256)
	return u


## Mensaje del «caso típico» de cada tipo (lo que un nodo real publica); los campos que no se tocan quedan a 0/"".
func _tipico(tipo: String):
	var m = _msg(tipo)
	if m == null:
		return null
	if "header" in m:
		m.header.frame_id = "base_link"
		m.header.stamp.sec = 1000
	match tipo:
		"std_msgs/msg/Float32", "std_msgs/msg/Float64":
			m.data = 1.5
		"std_msgs/msg/Int32", "std_msgs/msg/UInt8":
			m.data = 7
		"std_msgs/msg/ColorRGBA":
			m.r = 1.0
			m.a = 1.0
		"geometry_msgs/msg/PointStamped":
			m.point.x = 1.0
		"geometry_msgs/msg/Vector3Stamped":
			m.vector.z = 1.0
		"geometry_msgs/msg/PoseArray":
			m.header.frame_id = "map"
			m.poses = [_pose(0, 0, 0), _pose(1, 0, 0.5), _pose(2, 1, 1.0), _pose(3, 1, 1.5)]
		"geometry_msgs/msg/PoseWithCovarianceStamped":
			m.header.frame_id = "map"
			m.pose.pose = _pose(1, 2, 0.3)
			var c := PackedFloat64Array()
			c.resize(36)
			c[0] = 0.25
			c[7] = 0.04
			c[35] = 0.07
			m.pose.covariance = c
		"geometry_msgs/msg/WrenchStamped":
			m.wrench.force.x = 2.0
			m.wrench.torque.z = 0.5
		"geometry_msgs/msg/AccelStamped":
			m.accel.linear.x = 0.3
		"geometry_msgs/msg/QuaternionStamped":
			m.quaternion.w = 1.0
		"geometry_msgs/msg/PolygonStamped":
			var pts := []
			for q in [Vector2(0.3, 0.2), Vector2(0.3, -0.2), Vector2(-0.3, -0.2), Vector2(-0.3, 0.2)]:
				var p = _msg("geometry_msgs/msg/Point32")
				p.x = q.x
				p.y = q.y
				pts.append(p)
			m.polygon.points = pts
		"sensor_msgs/msg/Temperature":
			m.temperature = 23.5
		"sensor_msgs/msg/Illuminance":
			m.illuminance = 350.0
		"sensor_msgs/msg/RelativeHumidity":
			m.relative_humidity = 0.42
		"sensor_msgs/msg/Joy":
			m.axes = PackedFloat32Array([0.1, -0.2, 0.0, 1.0, 0.0, 0.0, 0.5, -0.5])
			m.buttons = PackedInt32Array([1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1])
		"nav_msgs/msg/Path":                                  # 28 + 72·n: 5 poses típicas de un plan corto
			m.header.frame_id = "map"
			var poses := []
			for i in 5:
				var ps = _msg("geometry_msgs/msg/PoseStamped")
				ps.header.frame_id = "map"
				ps.pose = _pose(i * 0.5, 0.0, 0.0)
				poses.append(ps)
			m.poses = poses
		"nav_msgs/msg/MapMetaData":
			m.resolution = 0.05
			m.width = 384
			m.height = 384
		"nav_msgs/msg/GridCells":
			m.header.frame_id = "map"
			m.cell_width = 0.05
			m.cell_height = 0.05
			var celdas := []
			for i in 10:
				var p = _msg("geometry_msgs/msg/Point")
				p.x = i * 0.05
				celdas.append(p)
			m.cells = celdas
		"visualization_msgs/msg/Marker":
			_marcador(m, "visor", 1, 1, Vector3(0.2, 0.2, 0.2))
		"visualization_msgs/msg/ImageMarker":
			m.ns = "cam"
			m.id = 1
			m.type = 0
			m.scale = 10.0
			m.position.x = 320.0
			m.position.y = 240.0
		"visualization_msgs/msg/InteractiveMarkerFeedback":
			m.client_id = "/rviz2/interactive_marker"
			m.marker_name = "meta"
			m.control_name = "mover_xy"
			m.event_type = 1
			m.pose = _pose(1, 1, 0)
		"diagnostic_msgs/msg/DiagnosticArray":
			var st = _msg("diagnostic_msgs/msg/DiagnosticStatus")
			st.level = 1
			st.name = "base: motor izquierdo"
			st.message = "Temperatura alta"
			st.hardware_id = "md49"
			var kvs := []
			for kv in [["temp", "61.5"], ["corriente", "1.2"]]:
				var k = _msg("diagnostic_msgs/msg/KeyValue")
				k.key = kv[0]
				k.value = kv[1]
				kvs.append(k)
			st.values = kvs
			m.status = [st]
		"rcl_interfaces/msg/Log":
			m.level = 30
			m.name = "bt_navigator"
			m.msg = "Goal failed: planner timed out after 5.0 s"
			m.file = "bt_navigator.cpp"
			m.function = "onGoalExit"
			m.line = 412
		"lifecycle_msgs/msg/TransitionEvent":
			m.timestamp = 1000
			m.transition.id = 1
			m.transition.label = "configure"
			m.start_state.id = 1
			m.start_state.label = "unconfigured"
			m.goal_state.id = 2
			m.goal_state.label = "inactive"
		"action_msgs/msg/GoalStatusArray":
			var gs = _msg("action_msgs/msg/GoalStatus")
			gs.goal_info.goal_id.uuid = _uuid()
			gs.goal_info.stamp.sec = 1000
			gs.status = 2
			m.status_list = [gs]
		"nav2_msgs/action/NavigateToPose_FeedbackMessage":
			m.goal_id.uuid = _uuid()
			m.feedback.current_pose.header.frame_id = "map"
			m.feedback.current_pose.pose = _pose(1, 2, 0.5)
			m.feedback.estimated_time_remaining.sec = 12
			m.feedback.number_of_recoveries = 1
			m.feedback.distance_remaining = 3.25
	return m


func _marcador(m, ns: String, id: int, tipo: int, s: Vector3, color := Color(0.1, 0.8, 0.2)) -> void:
	m.header.frame_id = "map"
	m.ns = ns
	m.id = id
	m.type = tipo
	m.action = 0
	m.pose = _pose(1, 0, 0)
	m.scale.x = s.x
	m.scale.y = s.y
	m.scale.z = s.z
	m.color.r = color.r
	m.color.g = color.g
	m.color.b = color.b
	m.color.a = 1.0


func _fotogramas(n: int) -> void:
	for _i in n:
		await process_frame


func _esperar(v: Node) -> void:
	for _i in 60:
		if v.estado != "sin conectar":
			return
		await process_frame


func _display(ruta: String, nombre: String, props: Dictionary) -> Node:
	var d: Node = load(ruta).new()
	d.name = nombre
	for k in props:
		d.set(k, props[k])
	return d


## Visor con displays 3D (hijos del visor) y 2D (bajo una Planta), cámara y TextoSuperpuesto, como en main.tscn.
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
	var hud := CanvasLayer.new()
	hud.name = "Hud"
	v.add_child(hud)
	var t: Control = Texto.new()
	t.name = "Texto"
	hud.add_child(t)
	v.texto = t
	var raiz := Node3D.new()
	raiz.name = "Escena"
	var cam := Camera3D.new()
	cam.position = Vector3(0, 5, 5)
	raiz.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO)
	raiz.add_child(v)
	root.add_child(raiz)
	cam.current = true
	return v


func _cerrar(v: Node) -> void:
	v.get_parent().queue_free()
	await _fotogramas(2)


# ---------------------------------------------------------------------------------------------------------------
# Esquema: cada tipo de TIPOS_VISOR existe, va y vuelve por CDR y cabe en 488 B en el caso típico
# ---------------------------------------------------------------------------------------------------------------
func _probar_esquema() -> void:
	var tipos := _tipos_visor()
	check(tipos.size() >= 28, "TIPOS_VISOR leído del generador: %d tipos" % tipos.size())
	# Tipos de TIPOS que también usan los displays V5 (ya estaban en el esquema).
	var usados := ["sensor_msgs/msg/Imu", "sensor_msgs/msg/Range", "sensor_msgs/msg/NavSatFix",
			"geometry_msgs/msg/Twist", "geometry_msgs/msg/TwistStamped", "geometry_msgs/msg/TransformStamped"]
	var tabla := []
	for t in Array(tipos) + usados:
		var m = _tipico(t)
		check(m != null, "esquema: RosMsg.from_type(%s) ≠ null" % t)
		if m == null:
			continue
		var r = _ida_vuelta(m, t)
		var n: int = m.serialize().size()
		tabla.append("%s=%d" % [t.get_file(), n])
		check(n <= MAX_BE, "tamaño típico de %s: %d B ≤ %d (sin encapsulación)" % [t, n, MAX_BE])
		if t == "nav2_msgs/action/NavigateToPose_FeedbackMessage":
			check(is_equal_approx(r.feedback.distance_remaining, 3.25) and r.feedback.number_of_recoveries == 1
					and r.feedback.estimated_time_remaining.sec == 12 and r.goal_id.uuid == _uuid(),
					"FeedbackMessage (registro manual): campos intactos tras CDR")
		elif t == "sensor_msgs/msg/Joy":
			check(r.axes.size() == 8 and r.buttons.size() == 12 and r.buttons[11] == 1, "Joy: ejes y botones intactos")
		elif t == "diagnostic_msgs/msg/DiagnosticArray":
			check(r.status.size() == 1 and r.status[0].values[1].value == "1.2", "DiagnosticArray: estado y valores intactos")
		elif t == "nav_msgs/msg/Path":
			check(r.poses.size() == 5 and is_equal_approx(r.poses[4].pose.position.x, 2.0), "Path: 5 poses intactas")
	print("  tamaños típicos (B, sin encapsulación): ", ", ".join(tabla))
	# Marker con 10 puntos aún cabe; con 11 ya no (doc 36a §4.7.1: 469 / 493 B con encapsulación).
	var mk = _tipico("visualization_msgs/msg/Marker")
	var pts := []
	for i in 10:
		pts.append(_msg("geometry_msgs/msg/Point"))
	mk.points = pts
	var n10: int = mk.serialize().size()
	pts.append(_msg("geometry_msgs/msg/Point"))
	mk.points = pts
	var n11: int = mk.serialize().size()
	check(n10 <= MAX_BE and n11 + 4 > MAX_BE, "Marker: 10 puntos caben (%d B), 11 no con encapsulación (%d + 4)" % [n10, n11])
	check(RosMsg.from_type("std_msgs/msg/Empty") == null, "std_msgs/Empty sigue fuera (D10, [?])")


# ---------------------------------------------------------------------------------------------------------------
# Registro: cada tipo directo tiene su display (PC y Vita: no hay alternativa orbital en V5)
# ---------------------------------------------------------------------------------------------------------------
func _probar_registro() -> void:
	var casos := [
		["/clicked_point", "geometry_msgs/msg/PointStamped", "3d/punto.gd"],
		["/vector", "geometry_msgs/msg/Vector3Stamped", "3d/vector.gd"],
		["/orientacion", "geometry_msgs/msg/QuaternionStamped", "3d/ejes.gd"],
		["/transformada", "geometry_msgs/msg/TransformStamped", "3d/ejes.gd"],
		["/ft_sensor", "geometry_msgs/msg/WrenchStamped", "3d/fuerza.gd"],
		["/accel", "geometry_msgs/msg/AccelStamped", "3d/fuerza.gd"],
		["/cmd_vel", "geometry_msgs/msg/Twist", "3d/fuerza.gd"],
		["/imu", "sensor_msgs/msg/Imu", "3d/imu.gd"],
		["/sonar", "sensor_msgs/msg/Range", "3d/rango.gd"],
		["/marcador", "visualization_msgs/msg/Marker", "3d/marcador_simple.gd"],
		["/local_costmap/published_footprint", "geometry_msgs/msg/PolygonStamped", "2d/poligono.gd"],
		["/amcl_pose", "geometry_msgs/msg/PoseWithCovarianceStamped", "2d/covarianza.gd"],
		["/fix", "sensor_msgs/msg/NavSatFix", "2d/gps.gd"],
	]
	for c in casos:
		var pc: String = Registro.regla(c[0], c[1], false).get("script", "")
		var vita: String = Registro.regla(c[0], c[1], true).get("script", "")
		check(pc == D + c[2] and vita == D + c[2], "registro %s (%s) → %s" % [c[0], c[1].get_file(), c[2]])
	for r in ["3d/punto.gd", "3d/vector.gd", "3d/ejes.gd", "3d/imu.gd", "3d/fuerza.gd", "3d/rango.gd",
			"3d/marcador_simple.gd", "2d/poligono.gd", "2d/covarianza.gd", "2d/gps.gd"]:
		var s = load(D + r)
		var ok: bool = s != null and s.nombre_display() != "" and s.tipos_ros().size() > 0
		if ok:
			for t in s.tipos_ros():
				ok = ok and RosMsg.from_type(t) != null
		check(ok, "display %s: identidad y todos sus tipos con esquema" % r)


# ---------------------------------------------------------------------------------------------------------------
# PC: cada display con su mensaje real (ida y vuelta CDR) y tres por loopback
# ---------------------------------------------------------------------------------------------------------------
func _displays() -> Dictionary:
	var h := {"hz": 0.0}
	return {
		"punto": _display(D + "3d/punto.gd", "Punto", _con(h, {"topic": "/clicked_point", "tipo": "geometry_msgs/msg/PointStamped", "historial": 3})),
		"vector": _display(D + "3d/vector.gd", "Vector", _con(h, {"topic": "/vector", "tipo": "geometry_msgs/msg/Vector3Stamped", "escala": 2.0})),
		"quat": _display(D + "3d/ejes.gd", "Orientacion", _con(h, {"topic": "/orientacion", "tipo": "geometry_msgs/msg/QuaternionStamped"})),
		"tf": _display(D + "3d/ejes.gd", "Transformada", _con(h, {"topic": "/transformada", "tipo": "geometry_msgs/msg/TransformStamped"})),
		"imu": _display(D + "3d/imu.gd", "Imu", _con(h, {"topic": "/imu", "tipo": "sensor_msgs/msg/Imu"})),
		"fuerza": _display(D + "3d/fuerza.gd", "Fuerza", _con(h, {"topic": "/ft_sensor", "tipo": "geometry_msgs/msg/WrenchStamped"})),
		"twist": _display(D + "3d/fuerza.gd", "Mando", _con(h, {"topic": "/cmd_vel", "tipo": "geometry_msgs/msg/Twist"})),
		"rango": _display(D + "3d/rango.gd", "Rango", _con(h, {"topic": "/sonar", "tipo": "sensor_msgs/msg/Range"})),
		"marcador": _display(D + "3d/marcador_simple.gd", "Marcador", {"topic": "/marcador", "tipo": "visualization_msgs/msg/Marker", "max_marcadores": 3}),
		"poligono": _display(D + "2d/poligono.gd", "Huella", _con(h, {"topic": "/footprint", "tipo": "geometry_msgs/msg/PolygonStamped", "relleno": true})),
		"cov": _display(D + "2d/covarianza.gd", "Covarianza", _con(h, {"topic": "/amcl_pose", "tipo": "geometry_msgs/msg/PoseWithCovarianceStamped"})),
		"gps": _display(D + "2d/gps.gd", "Gps", _con(h, {"topic": "/fix", "tipo": "sensor_msgs/msg/NavSatFix", "tol_pos": 0.1})),
	}


func _con(a: Dictionary, b: Dictionary) -> Dictionary:
	var r := a.duplicate()
	r.merge(b, true)
	return r


func _probar_pc() -> void:
	var ds := _displays()
	var d3 := [ds.punto, ds.vector, ds.quat, ds.tf, ds.imu, ds.fuerza, ds.twist, ds.rango, ds.marcador]
	var d2 := [ds.poligono, ds.cov, ds.gps]
	var v := _visor(false, d3, d2)
	await _esperar(v)
	check(v.ros_listo, "PC: el visor arranca en loopback")
	for k in ds:
		check(ds[k].estado == "ok" and ds[k].canal.abierto() and not ds[k].canal.compacto,
				"PC: %s suscrito en directo (%s)" % [k, ds[k].canal.topic_abierto])
	check(ds.twist.frame_id == "base_link" and ds.gps.frame_id == "map", "frames por defecto: Twist → base_link, GPS → marco fijo")

	# Punto: historial circular de 3 esferas en el marco fijo.
	for i in 4:
		var p = _tipico("geometry_msgs/msg/PointStamped")
		p.point.x = 1.0 + i
		ds.punto._al_mensaje(_ida_vuelta(p, "geometry_msgs/msg/PointStamped"))
	check(ds.punto._pool.size() == 3 and ds.punto._i == 1, "punto: pool de 3 y el 4.º reutiliza la primera esfera")
	check(ds.punto.ultimo.is_equal_approx(Vector3(0, 0, -4)), "punto: (4, 0, 0) ROS = (0, 0, −4) Godot")
	check(ds.punto._pool[0].global_position.is_equal_approx(Vector3(0, 0, -4)), "punto: esfera top_level en el mundo")
	var pn = _tipico("geometry_msgs/msg/PointStamped")
	pn.point.y = NAN
	ds.punto._al_mensaje(pn)
	check(ds.punto._i == 1, "punto: NaN se ignora (T2)")

	# Vector: flecha de |v|·escala; vector nulo = oculta.
	ds.vector._al_mensaje(_ida_vuelta(_tipico("geometry_msgs/msg/Vector3Stamped"), "geometry_msgs/msg/Vector3Stamped"))
	check(ds.vector._f.visible and ds.vector.ultimo.is_equal_approx(Vector3(0, 2, 0)), "vector: +Z ROS × 2 = (0, 2, 0) Godot")
	check(is_equal_approx(ds.vector._f.transform.basis.z.length(), 2.0), "vector: la flecha mide |v|")
	var v0 = _tipico("geometry_msgs/msg/Vector3Stamped")
	v0.vector.z = 0.0
	ds.vector._al_mensaje(v0)
	check(not ds.vector._f.visible, "vector: nulo = oculto (T13)")

	# Ejes: QuaternionStamped (yaw 90°) y TransformStamped (hijo con nombre y flecha al padre).
	var q = _tipico("geometry_msgs/msg/QuaternionStamped")
	q.quaternion.z = sin(PI / 4)
	q.quaternion.w = cos(PI / 4)
	ds.quat._al_mensaje(_ida_vuelta(q, "geometry_msgs/msg/QuaternionStamped"))
	check(ds.quat._ejes.visible and absf(ds.quat.rpy_grados.z - 90.0) < 0.01, "ejes: yaw 90° (rpy_grados)")
	check(ds.quat._flecha == null or not ds.quat._flecha.visible, "ejes: Quaternion sin flecha")
	var q0 = _tipico("geometry_msgs/msg/QuaternionStamped")
	q0.quaternion.w = 0.0
	ds.quat.rpy_grados = Vector3.ZERO
	ds.quat._al_mensaje(q0)
	check(ds.quat.rpy_grados == Vector3.ZERO, "ejes: cuaternión nulo se ignora (T14)")
	var ts = _tipico("geometry_msgs/msg/TransformStamped")
	ts.header.frame_id = "map"
	ts.child_frame_id = "camara"
	ts.transform.translation.x = 1.0
	ts.transform.rotation.w = 1.0
	ds.tf._al_mensaje(_ida_vuelta(ts, "geometry_msgs/msg/TransformStamped"))
	check(ds.tf.hijo == "camara" and ds.tf._ejes.transform.origin.is_equal_approx(Vector3(0, 0, -1)),
			"ejes: TransformStamped coloca el hijo en (1, 0, 0) ROS")
	check(ds.tf._flecha.visible and v.texto.cuantos() == 1, "ejes: flecha hijo → padre y nombre en el texto superpuesto")

	# IMU: en reposo, aceleración +9,81 en Z (arriba en Godot); sin orientación (cov[0] = −1) = ejes ocultos.
	var imu = _tipico("sensor_msgs/msg/Imu")
	imu.orientation.w = 1.0
	imu.linear_acceleration.z = 9.81
	imu.angular_velocity.z = 0.5
	ds.imu._al_mensaje(_ida_vuelta(imu, "sensor_msgs/msg/Imu"))
	check(ds.imu._ejes.visible and ds.imu._acel.visible and ds.imu._giro.visible, "imu: ejes y dos flechas visibles")
	check(ds.imu._acel.transform.basis.z.normalized().is_equal_approx(Vector3(0, -1, 0)),
			"imu: la flecha de aceleración apunta arriba (−Z local = +Y Godot)")
	var cov := PackedFloat64Array()
	cov.resize(9)
	cov[0] = -1.0
	imu.orientation_covariance = cov
	ds.imu._al_mensaje(_ida_vuelta(imu, "sensor_msgs/msg/Imu"))
	check(not ds.imu._ejes.visible and not ds.imu.con_orientacion, "imu: orientation_covariance[0] = −1 → sin ejes")

	# Fuerza: WrenchStamped (fuerza + par con anillo) y Twist sin cabecera.
	ds.fuerza._al_mensaje(_ida_vuelta(_tipico("geometry_msgs/msg/WrenchStamped"), "geometry_msgs/msg/WrenchStamped"))
	check(ds.fuerza._lin.visible and ds.fuerza._ang.visible and ds.fuerza._anillo.visible, "fuerza: fuerza, par y anillo")
	check(ds.fuerza._anillo.transform.basis.y.normalized().is_equal_approx(Vector3(0, 1, 0))
			and ds.fuerza._anillo.transform.origin.is_equal_approx(Vector3(0, 0.25, 0)),
			"fuerza: anillo perpendicular al par (+Z ROS) a mitad de la flecha")
	var tw = _tipico("geometry_msgs/msg/Twist")
	tw.linear.x = 0.5
	ds.twist._al_mensaje(_ida_vuelta(tw, "geometry_msgs/msg/Twist"))
	check(ds.twist._lin.visible and not ds.twist._ang.visible and not ds.twist._anillo.visible,
			"fuerza: Twist /cmd_vel solo con lineal")
	tw.angular.z = NAN
	ds.twist._lin.visible = false
	ds.twist._al_mensaje(tw)
	check(not ds.twist._lin.visible, "fuerza: NaN se descarta (T2)")

	# Rango: dentro, fuera, NaN y −Inf con distancia fija.
	var rg = _tipico("sensor_msgs/msg/Range")
	rg.radiation_type = 1
	rg.field_of_view = 0.5
	rg.min_range = 0.02
	rg.max_range = 4.0
	rg.range = 1.0
	ds.rango._al_mensaje(_ida_vuelta(rg, "sensor_msgs/msg/Range"))
	check(ds.rango._cono.visible and is_equal_approx(ds.rango.largo, 1.0), "rango: 1 m visible")
	check(is_equal_approx(ds.rango._cono.transform.basis.x.length(), 2.0 * tan(0.25)), "rango: ancho = 2·r·tan(fov/2)")
	for r in [5.0, NAN]:
		rg.range = r
		ds.rango._al_mensaje(rg)
		check(not ds.rango._cono.visible, "rango: %s fuera = oculto (T2)" % str(r))
	rg.min_range = 0.3
	rg.max_range = 0.3
	rg.range = -INF
	ds.rango._al_mensaje(rg)
	check(ds.rango._cono.visible and is_equal_approx(ds.rango.largo, 0.3), "rango: −Inf con min = max → min_range")

	# Marcador simple: ADD de 3 formas, texto, cupo, MODIFY, DELETE, DELETEALL por ns, lifetime y tipos ajenos.
	var mk = _tipico("visualization_msgs/msg/Marker")
	var tipos_m := [1, 2, 3]
	for i in 3:
		_marcador(mk, "a", i, tipos_m[i], Vector3(0.5, 0.5, 0.5))
		ds.marcador._al_mensaje(_ida_vuelta(mk, "visualization_msgs/msg/Marker"))
	check(ds.marcador.cuantos() == 3, "marcador: 3 vivos (CUBE, SPHERE, CYLINDER)")
	_marcador(mk, "b", 9, 2, Vector3.ONE)
	ds.marcador._al_mensaje(mk)
	check(ds.marcador.cuantos() == 3, "marcador: el 4.º no cabe (max_marcadores = 3)")
	var n0: MeshInstance3D = ds.marcador._vivos["a/0"]["n"]
	check(n0.visible and n0.global_position.is_equal_approx(Vector3(0, 0, -1)), "marcador: CUBE en (1, 0, 0) ROS")
	_marcador(mk, "a", 0, 0, Vector3(1.0, 0.1, 0.1))                    # MODIFY: mismo id, ahora ARROW
	ds.marcador._al_mensaje(mk)
	check(ds.marcador.cuantos() == 3 and is_equal_approx(n0.global_transform.basis.z.length(), 1.0),
			"marcador: MODIFY a ARROW (largo = scale.x)")
	mk.action = 2
	ds.marcador._al_mensaje(mk)
	check(ds.marcador.cuantos() == 2 and not n0.visible, "marcador: DELETE oculta y devuelve al pool")
	_marcador(mk, "t", 1, 9, Vector3(0, 0, 0.3))
	mk.text = "meta"
	ds.marcador._al_mensaje(mk)
	check(ds.marcador.cuantos() == 3 and v.texto.cuantos() == 2, "marcador: TEXT_VIEW_FACING por TextoSuperpuesto")
	mk.action = 3
	mk.ns = "a"
	ds.marcador._al_mensaje(mk)
	check(ds.marcador.cuantos() == 1, "marcador: DELETEALL con ns borra solo ese ns")
	_marcador(mk, "v", 1, 4, Vector3(0.1, 0.1, 0.1))                    # LINE_STRIP: del gestor (V8)
	ds.marcador._al_mensaje(mk)
	check(ds.marcador.ignorados == 1 and ds.marcador.cuantos() == 1, "marcador: LINE_STRIP se ignora (gestor V8)")
	_marcador(mk, "vida", 1, 1, Vector3.ONE)
	mk.lifetime.nanosec = 100000000                                     # 0,1 s
	ds.marcador._al_mensaje(mk)
	check(ds.marcador.cuantos() == 2, "marcador: con lifetime")
	await create_timer(0.45).timeout
	check(ds.marcador.cuantos() == 1, "marcador: caduca por lifetime (barrido 4 Hz)")
	mk.action = 3
	mk.ns = ""
	ds.marcador._al_mensaje(mk)
	check(ds.marcador.cuantos() == 0 and v.texto.cuantos() == 1, "marcador: DELETEALL sin ns borra todo (y su texto)")

	# Polígono: huella de 4 puntos; misma forma = no redibuja; NaN = se ignora.
	var pg = _tipico("geometry_msgs/msg/PolygonStamped")
	ds.poligono._al_mensaje(_ida_vuelta(pg, "geometry_msgs/msg/PolygonStamped"))
	check(ds.poligono._pts.size() == 4 and ds.poligono._px[0].is_equal_approx(Vector2(0.3, -0.2) * v.px_por_m),
			"polígono: 4 vértices en px de la planta (y hacia abajo)")
	check(ds.poligono._procesar(pg) == null, "polígono: misma forma → no redibuja")
	pg.polygon.points[1].x = NAN
	check(ds.poligono._procesar(pg) == null, "polígono: vértice NaN → se ignora (T2)")

	# Covarianza: σx = 0,5, σy = 0,2 ⇒ semiejes 1,0 y 0,4 m; abanico ±2σ_yaw.
	ds.cov._al_mensaje(_ida_vuelta(_tipico("geometry_msgs/msg/PoseWithCovarianceStamped"), "geometry_msgs/msg/PoseWithCovarianceStamped"))
	check(ds.cov.datos != null and is_equal_approx(ds.cov.datos[2], 0.25) and is_equal_approx(ds.cov.datos[3], 0.04),
			"covarianza: λ1 = 0,25 y λ2 = 0,04")
	var semieje: float = ds.cov._elipse_px[0].distance_to(ds.cov._c0) / v.px_por_m
	check(is_equal_approx(semieje, 1.0) and ds.cov._abanico_px.size() == 8, "covarianza: semieje 2σ = 1 m y abanico de 7 rayos")
	var fm = _msg("std_msgs/msg/Float32MultiArray")
	fm.data = PackedFloat32Array([1, 2, 0.3, 0.25, 0.0, 0.04, 0.0])
	var dc = ds.cov._procesar_compacto(fm)
	check(dc != null and is_equal_approx(dc[2], 0.25) and is_zero_approx(dc[5]), "covarianza: formato pose_cov del relay (D5.4)")
	ds.cov._pintar(dc)
	check(ds.cov._abanico_px.is_empty(), "covarianza: σ_yaw = 0 → raya en lugar de abanico (sin polígono degenerado)")

	# GPS: dos fixes a ~11 m al norte; NO_FIX no mueve el rastro.
	var fx = _tipico("sensor_msgs/msg/NavSatFix")
	fx.latitude = 40.4168
	fx.longitude = -3.7038
	fx.status.status = 0
	var pc := PackedFloat64Array()
	pc.resize(9)
	pc[0] = 4.0
	pc[4] = 4.0
	fx.position_covariance = pc
	fx.position_covariance_type = 2
	ds.gps._al_mensaje(_ida_vuelta(fx, "sensor_msgs/msg/NavSatFix"))
	fx.latitude = 40.4169
	ds.gps._al_mensaje(_ida_vuelta(fx, "sensor_msgs/msg/NavSatFix"))
	check(ds.gps._rastro.size() == 2 and absf(ds.gps.ultimo.y - 11.13) < 0.05 and absf(ds.gps.ultimo.x) < 1e-6,
			"gps: 0,0001° al norte = 11,13 m (origen en float de 64 bit)")
	check(is_equal_approx(ds.gps.sigma, 2.0), "gps: σ = 2 m de la covarianza")
	fx.status.status = -1
	ds.gps._al_mensaje(fx)
	check(ds.gps.estado_fix == -1 and ds.gps._rastro.size() == 2, "gps: NO_FIX no añade al rastro (círculo rojo)")

	# Por loopback de verdad: tres tipos publicados → canal → display.
	var nodo = v.contexto.nodo
	var be = v.contexto.qos(true, 1, false)
	var pubs := {
		"punto": [nodo.create_publisher("/clicked_point", "geometry_msgs/msg/PointStamped", be), "geometry_msgs/msg/PointStamped"],
		"rango": [nodo.create_publisher("/sonar", "sensor_msgs/msg/Range", be), "sensor_msgs/msg/Range"],
		"poligono": [nodo.create_publisher("/footprint", "geometry_msgs/msg/PolygonStamped", be), "geometry_msgs/msg/PolygonStamped"],
		"cov": [nodo.create_publisher("/amcl_pose", "geometry_msgs/msg/PoseWithCovarianceStamped", be), "geometry_msgs/msg/PoseWithCovarianceStamped"],
	}
	var antes := {}
	for k in pubs:
		antes[k] = ds[k].canal.mostrados
	var pp = _tipico("geometry_msgs/msg/PointStamped")
	pp.point.y = 2.0
	pubs.punto[0].publish(pp)
	rg.min_range = 0.02
	rg.max_range = 4.0
	rg.range = 2.0
	pubs.rango[0].publish(rg)
	var pg2 = _tipico("geometry_msgs/msg/PolygonStamped")
	pg2.polygon.points[0].x = 0.5
	pubs.poligono[0].publish(pg2)
	pubs.cov[0].publish(_tipico("geometry_msgs/msg/PoseWithCovarianceStamped"))
	await _fotogramas(4)
	for k in pubs:
		check(ds[k].canal.mostrados > antes[k], "loopback: %s llega por el canal (%s)" % [k, pubs[k][1].get_file()])
	check(ds.punto.ultimo.is_equal_approx(Vector3(-2, 0, -1)), "loopback: punto (1, 2, 0) ROS")
	check(is_equal_approx(ds.rango.largo, 2.0), "loopback: rango 2 m")

	await _fotogramas(3)
	for k in ["poligono", "cov", "gps"]:
		check(ds[k].visible and ds[k].is_visible_in_tree(), "2D %s visible tras pintar" % k)
	check(vigia.errores == 0, "PC: los 12 displays pintan sin errores de script (%s)" % vigia.ultimo)
	await _cerrar(v)


# ---------------------------------------------------------------------------------------------------------------
# Vita simulada (perfil HMI): directo (sin topic_vita no hay camino compacto) y cupos parciales
# ---------------------------------------------------------------------------------------------------------------
func _probar_vita() -> void:
	var punto := _display(D + "3d/punto.gd", "Punto", {"topic": "/clicked_point", "tipo": "geometry_msgs/msg/PointStamped",
			"historial": 2, "hz": 0.0})
	var imu := _display(D + "3d/imu.gd", "Imu", {"topic": "/imu", "tipo": "sensor_msgs/msg/Imu", "hz": 0.0})
	var vec := _display(D + "3d/vector.gd", "Vector", {"topic": "/vector", "tipo": "geometry_msgs/msg/Vector3Stamped"})
	var mk := _display(D + "3d/marcador_simple.gd", "Marcador", {"topic": "/marcador", "tipo": "visualization_msgs/msg/Marker",
			"max_marcadores": 20})
	var gps := _display(D + "2d/gps.gd", "Gps", {"topic": "/fix", "tipo": "sensor_msgs/msg/NavSatFix"})
	var v := _visor(true, [punto, imu, vec, mk], [gps])
	await _esperar(v)
	check(v.usa_compactos() and not punto.canal.compacto and punto.estado == "ok",
			"Vita: sin topic_vita el display va en directo aunque el visor use compactos")
	check(punto.cupo == 2 and imu.cupo == 2 and vec.estado == "sin cupo", "Vita: capa poses (4) = punto 2 + imu 2; vector sin cupo")
	check(mk.cupo == 12, "Vita: marcador simple limitado al cupo de «marcadores» (12)")
	var m = _tipico("sensor_msgs/msg/Imu")
	m.orientation.w = 1.0
	m.linear_acceleration.z = 9.81
	m.angular_velocity.z = 0.5
	imu._al_mensaje(_ida_vuelta(m, "sensor_msgs/msg/Imu"))
	check(imu._ejes.visible and imu._acel.visible and imu._giro == null, "Vita: IMU con cupo 2 = ejes + aceleración, sin giro")
	check(gps.canal.hz == 5.0 and gps.estado == "ok", "Vita: GPS directo a 5 Hz")
	await _fotogramas(2)
	check(vigia.errores == 0, "Vita: sin errores de script (%s)" % vigia.ultimo)
	await _cerrar(v)
