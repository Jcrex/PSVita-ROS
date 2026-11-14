extends SceneTree
## Prueba de host de V9 (doc 36 §10; sentencia W13 D3): TfLigero, display TF, poses y módulos `tf`, `pose_cov` y
## `poses` del relay.
##   - TfLigero pasa los casos de `modules/tf-tree/tests/parity_test.c` (cadena, inversa, hermanos, errores, ciclos,
##     nombres, re-padre, cuaternión no unitario, árbol lleno de 32, TFMessage con un rechazo), ± 1 mm;
##   - en el host coincide con la composición de transformadas esperada (cadena aleatoria en ejes de ROS) y con
##     `RosTfListener` si el nodo lo tiene (rclgd; el editor de host con ros2_vita no lo tiene);
##   - prueba de bytes Python = GDScript de pose_cov, poses, tf y tf_estatico (huellas de bits float32 de
##     `docker/scripts/test_vita_relay.py`);
##   - VisorRos en la Vita simulada (loopback): pose2d + estáticos de la escena + relay tf (tf_estatico ANTES que
##     tf_marcos) → el scan deja de dibujarse en el origen; robot, display TF (cupo 8), poses y pose_cov;
##   - fuente «por nodo» (robot horneado de urdf2godot) y RegistroDisplays.
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_tf.gd

const TfLigero = preload("res://comun/visor/tf_ligero.gd")
const VisorRos = preload("res://comun/visor/visor_ros.gd")
const Registro = preload("res://comun/visor/registro_displays.gd")
const VC1 = preload("res://comun/ros/vc1.gd")
const D := "res://comun/visor/displays/"
const MM := 1e-3                                       # ± 1 mm (criterio de doc 36 §10 V9)
const C := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))

# Huellas de `docker/scripts/test_vita_relay.py` (HUELLA_POSE_COV, _POSES, _TF, _TF_ESTATICO).
const HUELLA_POSE_COV := "919121b347346f313e0ec41b5b0132c7"
const HUELLA_POSES := "52d3f6f9108908b2abd20f08ce668f4d"
const HUELLA_TF := "474c8b147c4b652f59c1959f628dbd40"
const HUELLA_TF_ESTATICO := "3b84bb423aeaedebed5039a2aa5ab62e"


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
	_paridad_tf_tree()
	_composicion_host()
	_probar_bytes()
	await _probar_robot_horneado()
	_probar_registro()
	await _probar_vita()
	await _probar_pc()
	await _probar_tf_nativo()
	check(vigia.errores == 0, "sin errores de script en visor/ (%s)" % vigia.ultimo)
	OS.remove_logger(vigia)
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


# ---------------------------------------------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------------------------------------------
## Punto en ejes de ROS de `origen` → `destino` con TfLigero (como `xform` de parity_test.c). Vector3 o el código.
func _xf(tr, destino: String, origen: String, p := Vector3.ZERO):
	var rc: int = tr.estado_lookup(destino, origen)
	if rc != TfLigero.OK_TF:
		return rc
	var m: Transform3D = tr.lookup_transform(destino, origen)
	return C.transposed() * (m * (C * p))


func _cerca(v, esperado: Vector3, tol := MM) -> bool:
	return v is Vector3 and (v as Vector3).distance_to(esperado) <= tol


func _qz(rad: float) -> Quaternion:
	return Quaternion(Vector3(0, 0, 1), rad)


func _arbol():
	var tr = TfLigero.new()
	var ok: bool = tr.poner_ros("world", "odom", Vector3(1, 0, 0), Quaternion.IDENTITY) == 0 \
		and tr.poner_ros("odom", "base_link", Vector3(0, 2, 0), _qz(PI / 2)) == 0 \
		and tr.poner_ros("base_link", "laser", Vector3(0.5, 0, 0), Quaternion.IDENTITY) == 0 \
		and tr.poner_ros("base_link", "camera", Vector3(0, 0, 1), Quaternion.IDENTITY) == 0
	check(ok, "tf-tree build(): 4 transformadas aceptadas")
	return tr


func _arr(tipo: String, datos):
	var m = RosMsg.from_type(tipo)
	m.data = datos
	return m


func _display(script: String, nombre: String, props: Dictionary) -> Node:
	var d: Node = load(script).new()
	d.name = nombre
	for k in props:
		d.set(k, props[k])
	return d


func _fotogramas(n: int) -> void:
	for _i in n:
		await process_frame


func _md5_f32(valores: Array) -> String:
	var bytes := PackedFloat32Array(valores).to_byte_array()
	var partes := PackedStringArray()
	for i in bytes.size() / 4:
		partes.append(str(bytes.decode_u32(4 * i)))
	return ",".join(partes).md5_text()


# ---------------------------------------------------------------------------------------------------------------
# 1. Casos de modules/tf-tree/tests/parity_test.c
# ---------------------------------------------------------------------------------------------------------------
func _paridad_tf_tree() -> void:
	# test_create
	var vacio = TfLigero.new()
	check(vacio.cuantos() == 0 and vacio.rechazados() == 0 and TfLigero.MAX_MARCOS == 32, "tf-tree create: vacío, tope 32")

	# test_lookup_chain
	var tr = _arbol()
	check(tr.cuantos() == 5, "tf-tree lookup_chain: 5 marcos")
	check(_cerca(_xf(tr, "world", "laser"), Vector3(1, 2.5, 0)), "tf-tree: laser (0,0,0) en world = (1, 2.5, 0)")
	check(_cerca(_xf(tr, "world", "laser", Vector3(1, 0, 0)), Vector3(1, 3.5, 0)), "tf-tree: laser (1,0,0) en world = (1, 3.5, 0)")
	check(_cerca(_xf(tr, "laser", "world", Vector3(1, 2.5, 0)), Vector3.ZERO), "tf-tree: inversa world → laser (origen)")
	check(_cerca(_xf(tr, "laser", "world", Vector3(1, 3.5, 0)), Vector3(1, 0, 0)), "tf-tree: inversa world → laser (1,0,0)")
	check(_cerca(_xf(tr, "camera", "laser"), Vector3(0.5, 0, -1)), "tf-tree: hermanos laser en camera = (0.5, 0, −1)")
	check(_cerca(_xf(tr, "odom", "base_link"), Vector3(0, 2, 0)), "tf-tree: un salto odom ← base_link")
	check(_cerca(_xf(tr, "odom", "odom", Vector3(3, 4, 5)), Vector3(3, 4, 5)), "tf-tree: mismo marco = identidad")
	check(_cerca(_xf(tr, "/world", "/laser"), Vector3(1, 2.5, 0)), "tf-tree: barra inicial («/world» == «world»)")

	# test_errors
	tr = _arbol()
	check(_xf(tr, "world", "nada") == TfLigero.ERR_DESCONOCIDO and _xf(tr, "nada", "world") == TfLigero.ERR_DESCONOCIDO,
			"tf-tree: marco desconocido")
	check(_xf(tr, "", "world") == TfLigero.ERR_ARG and tr.lookup_transform("", "world") == null, "tf-tree: nombre vacío")
	check(tr.poner_ros("map", "mapchild", Vector3.ZERO, Quaternion.IDENTITY) == 0
			and _xf(tr, "world", "mapchild") == TfLigero.ERR_SIN_CAMINO and not tr.can_transform("world", "mapchild"),
			"tf-tree: árbol desconectado = sin camino")
	check(tr.poner_ros("laser", "world", Vector3.ZERO, Quaternion.IDENTITY) == TfLigero.ERR_CICLO
			and tr.poner_ros("odom", "odom", Vector3.ZERO, Quaternion.IDENTITY) == TfLigero.ERR_CICLO,
			"tf-tree: ciclos (padre descendiente y auto-referencia)")
	check(_cerca(_xf(tr, "world", "laser"), Vector3(1, 2.5, 0)), "tf-tree: el árbol queda intacto tras los ciclos")
	var largo := "x".repeat(70)
	check(tr.poner_ros(largo, "a", Vector3.ZERO, Quaternion.IDENTITY) == TfLigero.ERR_ARG
			and tr.poner_ros("a", "", Vector3.ZERO, Quaternion.IDENTITY) == TfLigero.ERR_ARG
			and tr.poner_ros("a", "/", Vector3.ZERO, Quaternion.IDENTITY) == TfLigero.ERR_ARG
			and tr.poner_ros("a", "b", Vector3(NAN, 0, 0), Quaternion.IDENTITY) == TfLigero.ERR_ARG,
			"tf-tree: nombres no válidos (70 car., vacío, «/») y NaN (T2)")

	# test_update_reparent
	tr = _arbol()
	check(tr.poner_ros("odom", "laser", Vector3(5, 0, 0), Quaternion.IDENTITY) == 0
			and _cerca(_xf(tr, "world", "laser"), Vector3(6, 0, 0)) and tr.cuantos() == 5,
			"tf-tree: re-padre del laser a odom (6, 0, 0)")
	check(tr.get_frame_parent("laser") == "odom", "tf-tree: get_frame_parent tras re-padre")
	check(tr.poner_ros("world", "spin", Vector3.ZERO, Quaternion(0, 0, 2, 2)) == 0
			and _cerca(_xf(tr, "world", "spin", Vector3(1, 0, 0)), Vector3(0, 1, 0)), "tf-tree: cuaternión (0,0,2,2) normalizado = 90°")
	check(tr.poner_ros("world", "nulo", Vector3.ZERO, Quaternion(0, 0, 0, 0)) == 0
			and _cerca(_xf(tr, "world", "nulo", Vector3(1, 0, 0)), Vector3(1, 0, 0)), "tf-tree: cuaternión nulo = identidad")
	tr.clear()
	check(tr.cuantos() == 0 and _xf(tr, "world", "spin") == TfLigero.ERR_DESCONOCIDO, "tf-tree: clear")

	# test_full
	tr = TfLigero.new()
	var ok := 0
	var lleno := 0
	for i in 40:
		var rc: int = tr.poner_ros("root", "f%d" % i, Vector3.ZERO, Quaternion.IDENTITY)
		if rc == 0:
			ok += 1
		elif rc == TfLigero.ERR_LLENO:
			lleno += 1
	check(ok == 31 and lleno == 9 and tr.cuantos() == 32, "tf-tree full: root + 31 hijos, 9 rechazados (%d/%d)" % [ok, lleno])
	check(tr.poner_ros("root", "f0", Vector3.ZERO, Quaternion.IDENTITY) == 0, "tf-tree full: actualizar uno existente")
	check(tr.poner_ros("nuevo", "f0", Vector3.ZERO, Quaternion.IDENTITY) == TfLigero.ERR_LLENO and tr.cuantos() == 32
			and tr.get_frame_parent("f0") == "root", "tf-tree full: padre nuevo con el árbol lleno no modifica")

	# test_apply_message (TFMessage real, CDR)
	tr = TfLigero.new()
	var msg = RosMsg.from_type("tf2_msgs/msg/TFMessage")
	check(msg != null, "esquema: tf2_msgs/msg/TFMessage")
	if msg != null:
		var lista := []
		for par in [["odom", "base_link", Vector3(1.5, -2.25, 0)], ["base_link", "laser", Vector3(0.5, 0, 0)],
				["laser", "odom", Vector3.ZERO]]:
			var ts = RosMsg.from_type("geometry_msgs/msg/TransformStamped")
			ts.header.frame_id = par[0]
			ts.child_frame_id = par[1]
			ts.transform.translation.x = par[2].x
			ts.transform.translation.y = par[2].y
			ts.transform.rotation.w = 1.0
			lista.append(ts)
		msg.transforms = lista
		var ida = RosMsg.from_type("tf2_msgs/msg/TFMessage")
		ida.deserialize(msg.serialize())
		check(tr.aplicar_tf_message(ida) == 2 and tr.rechazados() == 1, "tf-tree apply_message: 2 aplicados, 1 rechazado (ciclo)")
		check(_cerca(_xf(tr, "odom", "laser"), Vector3(2.0, -2.25, 0)), "tf-tree apply_message: laser en odom = (2, −2.25, 0)")
	check(tr.aplicar_tf_message(null) == TfLigero.ERR_ARG, "tf-tree apply_message: null")


# ---------------------------------------------------------------------------------------------------------------
# 2. Composición esperada en el host (y RosTfListener si existe)
# ---------------------------------------------------------------------------------------------------------------
func _composicion_host() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var tr = TfLigero.new()
	var marcos := ["map", "odom", "base_link", "torso", "cabeza", "camara"]
	var esperado := Transform3D.IDENTITY                 # camara en map, ejes ROS
	var en_map := {"map": Transform3D.IDENTITY}
	for i in range(1, marcos.size()):
		var pos := Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-1, 1))
		var q := Quaternion(Vector3(rng.randf(), rng.randf(), rng.randf()).normalized(), rng.randf_range(-PI, PI))
		tr.poner_ros(marcos[i - 1], marcos[i], pos, q)
		esperado = esperado * Transform3D(Basis(q), pos)
		en_map[marcos[i]] = esperado
	var m: Transform3D = TfLigero.a_ros(tr.lookup_transform("map", "camara"))
	check(m.origin.distance_to(esperado.origin) <= MM and (m.basis.x - esperado.basis.x).length() < 1e-4
			and (m.basis.y - esperado.basis.y).length() < 1e-4, "host: map ← camara = composición T1·…·T5 (± 1 mm)")
	var rel: Transform3D = TfLigero.a_ros(tr.lookup_transform("odom", "cabeza"))
	var rel_esp: Transform3D = (en_map["odom"] as Transform3D).affine_inverse() * en_map["cabeza"]
	check(rel.origin.distance_to(rel_esp.origin) <= MM, "host: odom ← cabeza = T_odom⁻¹·T_cabeza")
	var g: Transform3D = tr.lookup_transform("map", "camara")
	check(g.origin.is_equal_approx(C * esperado.origin) and (g.basis * Vector3.FORWARD).is_equal_approx(C * (esperado.basis * Vector3(1, 0, 0))),
			"host: ejes de Godot (−Z = +X de ROS, como RosTfListener)")
	check(tr.get_frame_names() == PackedStringArray(marcos) and tr.frame_exists("/odom") and tr.can_transform("map", "camara"),
			"host: get_frame_names, frame_exists y can_transform")
	# rclgd en el PC: el mismo resultado que RosTfListener (no existe con el editor de host + ros2_vita).
	print("  RosTfListener en el host: ", "no (ros2_vita: TfLigero)" if not ClassDB.class_exists("RosTfListener") else "sí")


# ---------------------------------------------------------------------------------------------------------------
# 3. Bytes Python = GDScript (vc1.gd ↔ vita_relay_formatos.py)
# ---------------------------------------------------------------------------------------------------------------
func _probar_bytes() -> void:
	var cov := []
	for i in 36:
		cov.append(i * 0.01 - 0.1)
	var poses := []
	for i in 100:
		poses.append([i * 0.25 - 3, (i % 7) * 0.5, (i % 13) * 0.125 - 0.75])
	var items := []
	for k in 10:
		items.append([k, k * 0.5, -k * 0.25, 0.1 * k, 0, 0, 0.6, 0.8])
	var pc: Array = VC1.empaquetar_pose_cov(1.5, -2.25, 0.3, cov)
	check(pc.size() == 7 and _md5_f32(pc) == HUELLA_POSE_COV, "bytes: pose_cov = vita_relay_formatos.empaquetar_pose_cov")
	var tp: Array = VC1.empaquetar_poses(poses, 40000)
	check(VC1.cabecera(tp) == {"seq": 7232, "trozo": 0, "n_trozos": 1, "n": 34} and 16 + 4 * tp.size() <= 464
			and _md5_f32(tp) == HUELLA_POSES, "bytes: poses (100 → 34 diezmadas, ≤ 464 B) = empaquetar_poses")
	var tt: Array = VC1.empaquetar_tf(items, 7)
	check(VC1.cabecera(tt).n == 8 and 16 + 4 * tt.size() == 288 and _md5_f32(tt) == HUELLA_TF,
			"bytes: tf (10 → 8 marcos, 288 B) = empaquetar_tf")
	var te: Array = VC1.empaquetar_tf(items + items, 3, VC1.MAX_TF_ESTATICOS)
	check(VC1.cabecera(te).n == 16 and 16 + 4 * te.size() == 544 and _md5_f32(te) == HUELLA_TF_ESTATICO,
			"bytes: tf_estatico (16 marcos, 544 B fiable) = empaquetar_tf")
	var lp: PackedVector3Array = VC1.leer_poses(PackedFloat32Array(tp))
	check(lp.size() == 34 and lp[1].is_equal_approx(Vector3(-2.25, 1.5, -0.375)), "leer_poses: ida y vuelta")
	var lt: Array = VC1.leer_tf(PackedFloat32Array(tt))
	check(lt.size() == 8 and lt[2][0] == 2 and (lt[2][1] as Vector3).is_equal_approx(Vector3(1, -0.5, 0.2))
			and (lt[2][2] as Quaternion).is_equal_approx(Quaternion(0, 0, 0.6, 0.8)), "leer_tf: ida y vuelta")
	check(VC1.leer_tf([1, 2, 2, 0]).is_empty() and VC1.leer_poses([1, 0, 1]).is_empty(), "leer_*: cabecera no válida = vacío")
	check(VC1.leer_tf_marcos("map>odom,base_link>base_scan") == PackedStringArray(["map>odom", "base_link>base_scan"]),
			"leer_tf_marcos")


# ---------------------------------------------------------------------------------------------------------------
# 4. Fuente «por nodo»: robot horneado de urdf2godot (RosFrame gira ROS → Godot)
# ---------------------------------------------------------------------------------------------------------------
func _probar_robot_horneado() -> void:
	var raiz := Node3D.new()
	raiz.name = "robot"
	var ros_frame := Node3D.new()
	ros_frame.name = "RosFrame"
	ros_frame.transform = Transform3D(C, Vector3.ZERO)
	raiz.add_child(ros_frame)
	var base := Node3D.new()
	base.name = "Base"
	ros_frame.add_child(base)
	var junta := Node3D.new()
	junta.name = "cabeza_joint"
	junta.set_meta("urdf_joint", "cabeza_joint")
	junta.transform = Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(0.2, 0, 0.5))   # ROS: z arriba
	base.add_child(junta)
	var cabeza := Node3D.new()
	cabeza.name = "cabeza_link"
	junta.add_child(cabeza)
	var malla := MeshInstance3D.new()
	malla.name = "visual_0"
	cabeza.add_child(malla)
	root.add_child(raiz)
	raiz.position = Vector3(3, 0, 1)                   # el robot puede estar en cualquier sitio del mundo
	await process_frame
	var tr = TfLigero.new()
	check(tr.registrar_robot(raiz, "base_link") == 1 and tr.get_frame_names() == PackedStringArray(["base_link", "cabeza_link"]),
			"robot horneado: solo los links (sin juntas, mallas, RosFrame ni Base)")
	check(_cerca(_xf(tr, "base_link", "cabeza_link", Vector3(1, 0, 0)), Vector3(0.2, 1, 0.5)),
			"robot horneado: (1,0,0) de cabeza_link en base_link = (0.2, 1, 0.5) (giro 90° + desplazamiento)")
	junta.transform = Transform3D(Basis.IDENTITY, Vector3(0.2, 0, 0.5))   # /vita/joints mueve el nodo: sin tráfico TF
	check(_cerca(_xf(tr, "base_link", "cabeza_link", Vector3(1, 0, 0)), Vector3(1.2, 0, 0.5)),
			"robot horneado: el link sigue a la junta (lectura en vivo del nodo)")
	tr.poner_ros("map", "base_link", Vector3(10, 0, 0), Quaternion.IDENTITY)
	check(_cerca(_xf(tr, "map", "cabeza_link"), Vector3(10.2, 0, 0.5)), "robot horneado: map ← base_link ← cabeza_link")
	raiz.queue_free()
	await process_frame
	check(_cerca(_xf(tr, "map", "cabeza_link"), Vector3(10, 0, 0)), "robot horneado: nodo liberado = identidad, sin error")


func _probar_registro() -> void:
	var f32 := "std_msgs/msg/Float32MultiArray"
	check(Registro.regla("/vita/poses", f32, true).get("script", "") == D + "2d/poses.gd", "Registro: <p>/poses → 2d/poses.gd")
	check(Registro.regla("/vita/pose_cov", f32, true).get("script", "") == D + "2d/covarianza.gd", "Registro: <p>/pose_cov → 2d/covarianza.gd")
	check(Registro.regla("/particlecloud", "geometry_msgs/msg/PoseArray", false).get("script", "") == D + "2d/poses.gd",
			"Registro: PoseArray → 2d/poses.gd")
	check(Registro.regla("/tf", "tf2_msgs/msg/TFMessage", true).get("capa", "") == "tf", "Registro: TFMessage → 3d/tf.gd (capa tf)")
	var d: Node = Registro.crear("/tf", "tf2_msgs/msg/TFMessage", false)
	check(d != null and d.nombre_display() == "TF", "Registro: crear() del display TF")
	if d != null:
		d.free()


# ---------------------------------------------------------------------------------------------------------------
# 5. VisorRos en la Vita simulada (loopback, camino compacto)
# ---------------------------------------------------------------------------------------------------------------
func _visor(en_vita: bool) -> Node:
	var v: Node = VisorRos.new()
	v.name = "VisorTf"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = en_vita
	v.tf_estaticos = PackedStringArray(["base_link>base_scan -0.032 0 0.172 0", "malo"])
	return v


func _probar_vita() -> void:
	var v := _visor(true)
	v.marco_pose2d = "odom"
	v.tf_relay = true
	var tf3 = _display(D + "3d/tf.gd", "TF", {})
	var robot = _display(D + "3d/robot_joints.gd", "Robot", {"topic": "/joint_states", "tipo": "sensor_msgs/msg/JointState"})
	var planta := CanvasLayer.new()
	planta.name = "Planta"
	var scan = _display(D + "2d/scan.gd", "Scan", {"topic": "/scan", "tipo": "sensor_msgs/msg/LaserScan", "frame_id": "base_scan", "hz": 0.0})
	var poses = _display(D + "2d/poses.gd", "Particulas", {"topic": "/particle_cloud", "tipo": "geometry_msgs/msg/PoseArray",
			"topic_vita": "poses", "hz": 0.0})
	var cov = _display(D + "2d/covarianza.gd", "Amcl", {"topic": "/amcl_pose", "tipo": "geometry_msgs/msg/PoseWithCovarianceStamped",
			"topic_vita": "pose_cov", "hz": 0.0})
	v.add_child(tf3)
	v.add_child(robot)
	v.add_child(planta)
	for d in [scan, poses, cov]:
		planta.add_child(d)
	var raiz := Node3D.new()
	raiz.add_child(v)
	root.add_child(raiz)
	for _i in 60:
		if v.estado != "sin conectar":
			break
		await process_frame
	check(v.ros_listo and v.usa_compactos() and v.es_tf_ligero(), "Vita: VisorRos con TfLigero (sin create_tf_listener)")
	check(v.tf.get_frame_names() == PackedStringArray(["base_link", "base_scan"]),
			"Vita: estáticos de la escena (la línea «malo» se avisa y se salta)")
	check(tf3.cupo == 8 and v.usado("tf") == 8 and not tf3.mostrar_flechas and tf3.estado == "ok",
			"Vita: display TF con cupo 8 (HMI), sin flechas (D7)")
	check(poses.canal.topic_abierto == "/vita/poses" and cov.canal.topic_abierto == "/vita/pose_cov",
			"Vita: poses y covarianza por el relay")

	var nodo = v.contexto.nodo
	var be = v.contexto.qos(true, 1, false)
	var fiable = v.contexto.qos(false, 1, true)
	var f32 := "std_msgs/msg/Float32MultiArray"
	var p_pose = nodo.create_publisher("/vita/pose2d", f32, be)
	var p_scan = nodo.create_publisher("/vita/scan_compacto", "std_msgs/msg/Int16MultiArray", be)
	var p_marcos = nodo.create_publisher("/vita/tf_marcos", "std_msgs/msg/String", fiable)
	var p_est = nodo.create_publisher("/vita/tf_estatico", f32, fiable)
	var p_tf = nodo.create_publisher("/vita/tf", f32, be)
	var p_poses = nodo.create_publisher("/vita/poses", f32, be)
	var p_cov = nodo.create_publisher("/vita/pose_cov", f32, be)
	var rangos := PackedFloat32Array()
	for i in 180:
		rangos.append(2.0)
	var scan_msg = _arr("std_msgs/msg/Int16MultiArray", VC1.empaquetar_scan(rangos, -PI, TAU / 180.0, 0.1, 20.0, 1))

	# A) Solo pose2d, `marco_pose2d` = odom pero sin map → odom (relay sin `tf`): revisión V2, la base cuelga del fijo
	#    (como `marco_pose2d` = "", supone map ≈ odom) en lugar de dejar TODO en el origen.
	p_pose.publish(_arr(f32, PackedFloat32Array([1.0, 2.0, PI / 2, 0, 0, 0])))
	await _fotogramas(3)
	p_scan.publish(scan_msg)
	await _fotogramas(3)
	check(v.tf.get_frame_parent("base_link") == "map" and not v.tf.frame_exists("odom"),
			"Vita A: pose2d sin map → odom: la base cuelga del fijo (revisión V2)")
	var esperado_a: Vector2 = Vector2(1.0, -(2.0 - 0.032)) * v.px_por_m
	check(scan.estado == "ok" and scan.transform.origin.distance_to(esperado_a) < 0.05,
			"Vita A: el scan va con la base (1, 1.968) m, no en el origen (%s)" % scan.transform.origin)

	# B) Relay tf: tf_estatico ANTES que tf_marcos (latched, orden libre), luego tf (map → odom).
	p_est.publish(_arr(f32, PackedFloat32Array(VC1.empaquetar_tf([[1, 0.1, 0.0, 0.2, 0, 0, 0, 1]], 0, VC1.MAX_TF_ESTATICOS))))
	await _fotogramas(3)
	p_marcos.publish(_arr("std_msgs/msg/String", "map>odom,base_link>base_scan"))
	await _fotogramas(3)
	p_tf.publish(_arr(f32, PackedFloat32Array(VC1.empaquetar_tf([[0, 10.0, 0.0, 0.0, 0, 0, 0, 1]], 1))))
	await _fotogramas(3)
	check(v.tf.orden_relay().size() == 2 and _cerca(_xf(v.tf, "base_link", "base_scan"), Vector3(0.1, 0, 0.2)),
			"Vita B: tf_estatico llegado antes que tf_marcos se aplica (y pisa el estático de la escena)")
	p_pose.publish(_arr(f32, PackedFloat32Array([1.0, 2.0, PI / 2, 0, 0, 0])))
	p_scan.publish(scan_msg)
	await _fotogramas(3)
	check(v.tf.get_frame_parent("base_link") == "odom" and _cerca(_xf(v.tf, "map", "base_link"), Vector3(11, 2, 0)),
			"Vita B: map → odom (relay tf) → base_link (el siguiente pose2d pasa la base a odom)")
	# base_scan en map: (11, 2) + R(90°)·(0.1, 0) = (11, 2.1); planta: x = ROS x, y = −ROS y, rotación −yaw.
	var esperado: Vector2 = Vector2(11.0, -2.1) * v.px_por_m
	check(scan.estado == "ok" and scan.transform.origin.distance_to(esperado) < 0.05 and absf(scan.transform.get_rotation() + PI / 2) < 1e-3,
			"Vita B: el scan YA NO va en el origen: base_scan en (11, 2.1) m, rumbo 90° (%s)" % scan.transform.origin)
	check(robot.poses_base >= 1 and robot.transform.origin.distance_to(C * Vector3(11, 2, 0)) < MM,
			"Vita B: el robot (frame_id base_link) se coloca con TfLigero, sin sumar pose2d dos veces")
	check(robot.robot.transform.origin.is_equal_approx(Vector3.ZERO), "Vita B: el hijo del robot no se mueve (una sola vez)")
	check(v.suscrito_pose2d() and robot._subs.size() == 1 and v.pose2d_tf.is_connected(robot._al_pose2d),
			"Vita: el robot recibe pose2d por VisorRos, sin una suscripción más (revisión V2)")

	scan.frame_id = "laser_x"
	p_scan.publish(scan_msg)
	await _fotogramas(3)
	check(scan.estado == "sin TF laser_x→map" and not scan.visible and v.transformada("laser_x") == null,
			"Vita B: marco desconocido = oculto y «sin TF» (como RViz)")
	scan.frame_id = "base_scan"

	# Display TF: ejes en su sitio, dentro del cupo.
	tf3.refrescar()
	check(tf3.marcos_dibujados == 4 and tf3.marcos_dibujados <= tf3.cupo, "Vita: display TF dibuja map, odom, base_link y base_scan (≤ 8)")
	var pe = tf3.pose_de("base_scan")
	check(pe != null and (pe as Transform3D).origin.distance_to(C * Vector3(11, 2.1, 0.2)) < MM, "Vita: EJES de base_scan en (11, 2.1, 0.2)")
	for i in 10:                                         # más marcos que cupo: no se crean más de 8 EJES
		v.tf.poner_ros("map", "extra%d" % i, Vector3(i, 0, 0), Quaternion.IDENTITY)
	tf3.refrescar()
	check(tf3.marcos_dibujados == 8 and tf3.get_child_count() == 8, "Vita: display TF con 14 marcos dibuja 8 (cupo HMI)")

	# Poses y covarianza por el relay.
	var lista := []
	for i in 100:
		lista.append([i * 0.25 - 3, (i % 7) * 0.5, (i % 13) * 0.125 - 0.75])
	p_poses.publish(_arr(f32, PackedFloat32Array(VC1.empaquetar_poses(lista, 5))))
	var c36 := PackedFloat64Array()
	c36.resize(36)
	c36[0] = 0.04
	c36[7] = 0.01
	c36[35] = 0.0025
	p_cov.publish(_arr(f32, PackedFloat32Array(VC1.empaquetar_pose_cov(1.5, -2.25, 0.3, c36))))
	await _fotogramas(3)
	check(poses.estado == "ok" and poses.poses_dibujadas == 34 and poses._v.size() == 3 * 34, "Vita: <p>/poses → 34 triángulos en un lote")
	check(cov.estado == "ok" and cov.datos != null and (cov.datos[0] as Vector2).is_equal_approx(Vector2(1.5, -2.25))
			and is_equal_approx(cov.datos[2], 0.04) and is_equal_approx(cov.datos[3], 0.01) and is_equal_approx(cov.datos[5], 0.05),
			"Vita: <p>/pose_cov → elipse λ = 0.04 / 0.01, σ_yaw 0.05")
	var nan_poses := PackedFloat32Array([1, 0, 1, 2, NAN, 0, 0, 1, 1, 0])
	check(VC1.leer_poses(nan_poses).size() == 1, "Vita: poses con NaN se ignoran (T2)")
	check(v.tf.desde_pose2d(PackedFloat32Array([NAN, 0, 0]), "odom", "base_link") == TfLigero.ERR_ARG
			and _cerca(_xf(v.tf, "odom", "base_link"), Vector3(1, 2, 0)), "Vita: pose2d con NaN no toca TfLigero (T2)")

	for p in [p_pose, p_scan, p_marcos, p_est, p_tf, p_poses, p_cov]:
		p = null
	raiz.queue_free()
	await _fotogramas(2)


# ---------------------------------------------------------------------------------------------------------------
# 6. PC (host, sin relay): TfLigero de respaldo y display TF con flechas
# ---------------------------------------------------------------------------------------------------------------
func _probar_pc() -> void:
	var v := _visor(false)
	var tf3 = _display(D + "3d/tf.gd", "TF", {"mostrar_nombres": false})
	v.add_child(tf3)
	var raiz := Node3D.new()
	raiz.add_child(v)
	root.add_child(raiz)
	for _i in 60:
		if v.estado != "sin conectar":
			break
		await process_frame
	check(not v.usa_compactos() and v.es_tf_ligero() and v._subs_tf.is_empty(), "PC host: TfLigero sin suscripciones del relay")
	check(v.transformada("base_scan") == Transform3D.IDENTITY, "PC host: sin el marco fijo en TfLigero, todo en el fijo (como V1–V8)")
	check(tf3.cupo == 64 and tf3.mostrar_flechas, "PC: display TF con 32 marcos + 32 flechas")
	v.tf.poner_ros("map", "base_link", Vector3(2, 0, 0), Quaternion.IDENTITY)
	check(v.transformada("base_scan").origin.distance_to(C * Vector3(1.968, 0, 0.172)) < MM,
			"PC host: con map, base_scan = (2 − 0.032, 0, 0.172)")
	tf3.refrescar()
	check(tf3.marcos_dibujados == 3 and tf3._flechas["base_scan"].visible and not tf3._flechas["map"].visible,
			"PC: flecha hijo → padre (la raíz no tiene)")
	raiz.queue_free()
	await _fotogramas(2)


# ---------------------------------------------------------------------------------------------------------------
# 7. V13a: RosTfListener nativo de ros2_vita (tf-tree) en lugar de TfLigero, con los MISMOS displays
# ---------------------------------------------------------------------------------------------------------------
func _ts_ros(padre: String, hijo: String, t: Vector3) -> RosMsg:
	var ts := RosMsg.from_type("geometry_msgs/msg/TransformStamped")
	ts.header.frame_id = padre
	ts.child_frame_id = hijo
	ts.transform.translation.x = t.x
	ts.transform.translation.y = t.y
	ts.transform.translation.z = t.z
	ts.transform.rotation.w = 1.0
	return ts


func _probar_tf_nativo() -> void:
	var v := _visor(false)
	check(not v.tf_nativo, "V13a: tf_nativo apagado por defecto (TfLigero, como hasta V12)")
	v.tf_nativo = true
	var tf3 = _display(D + "3d/tf.gd", "TF", {"mostrar_nombres": false})
	v.add_child(tf3)
	var raiz := Node3D.new()
	raiz.add_child(v)
	root.add_child(raiz)
	for _i in 60:
		if v.estado != "sin conectar":
			break
		await process_frame
	if not ClassDB.class_exists("RosTfListener"):
		# Editor anterior a V13a: la selección cae en TfLigero sin errores.
		check(v.es_tf_ligero(), "V13a: sin RosTfListener en el motor, TfLigero (editor anterior a V13a)")
		raiz.queue_free()
		await _fotogramas(2)
		return
	check(v.usa_tf_nativo() and v.tf != null and v.tf.get_class() == "RosTfListener" and not v.es_tf_ligero(),
			"V13a: tf_nativo + ros2_vita con RosTfListener => listener nativo")
	var pub = v.contexto.nodo.create_publisher("/tf", "tf2_msgs/msg/TFMessage")
	var m := RosMsg.from_type("tf2_msgs/msg/TFMessage")
	m.transforms = [_ts_ros("map", "base_link", Vector3(2, 0, 0)), _ts_ros("base_link", "base_scan", Vector3(-0.032, 0, 0.172))]
	pub.publish(m)
	await _fotogramas(2)
	check(v.transformada("base_scan").origin.distance_to(C * Vector3(1.968, 0, 0.172)) < MM,
			"V13a nativo: base_scan en map = (2 − 0.032, 0, 0.172), igual que con TfLigero")
	check(v.transformada("nada") == null, "V13a nativo: marco desconocido => null (los displays dicen «sin TF»)")
	tf3.refrescar()
	check(tf3.marcos_dibujados == 3 and tf3._flechas["base_scan"].visible and not tf3._flechas["map"].visible,
			"V13a nativo: el display TF dibuja los mismos 3 marcos y flechas sin cambios")
	pub = null
	raiz.queue_free()
	await _fotogramas(2)
