extends SceneTree
## Prueba de host de V8 (marcadores; doc 36 §5.3 y §10; doc 36a §4.7; sentencia W13 D14). Transporte `loopback`:
##   - bytes Python = GDScript: `vc1.gd` (bloque marcadores) da los MISMOS float32 que `vita_relay_formatos.py`
##     (huellas de `docker/scripts/test_vita_relay.py`: marcadores, puntos, texto y clave), con `PaletaViz.indice`
##     = `indice_paleta` de Python; 33 marcadores = 3 trozos de ≤ 472 B (CDR real de Float32MultiArray + 4 B);
##   - directo (PC): los 13 `type` de Marker (0–11 y ARROW_STRIP 12) repartidos entre el gestor 3D y el 2D, ARROW
##     por 2 puntos, MESH_RESOURCE sin malla = cubo, listas > 64 = puntos 2D; acciones ADD/MODIFY/DELETE/DELETEALL
##     (por ns y todo), recrear si cambia el tipo (también entre 3D y 2D), NaN rechazado, lifetime, frame_locked;
##     dibujo 2D dentro del cupo de *quads*;
##   - compacto (Vita simulada, perfil HMI): estado completo por trozos, sin fantasmas tras un DELETE (la clave que
##     falta se recicla), trozo perdido = no se purga hasta el siguiente estado completo, yaw ROS = giro +Y Godot,
##     cupo 12, puntos (2 trozos) y texto del relay, purga del 2D con el estado del gestor 3D;
##   - pool lleno sin fugas de nodos (PC con tope 20 y Vita con cupo 12, 30 ciclos con claves nuevas).
##
##   set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
##   $GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_marcadores.gd

const VisorRos = preload("res://comun/visor/visor_ros.gd")
const Texto = preload("res://comun/visor/texto_superpuesto.gd")
const Registro = preload("res://comun/visor/registro_displays.gd")
const Fab = preload("res://comun/visor/fabrica_marcadores.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
const VC1 = preload("res://comun/ros/vc1.gd")
const D := "res://comun/visor/displays/"

## Huellas de `docker/scripts/test_vita_relay.py` (HUELLA_MARCADORES / _PUNTOS / _TEXTO, CLAVE_VISOR_3).
const HUELLA_MARCADORES := "a2f417e25439969dec1637dd4cd66bdd"
const HUELLA_PUNTOS := "170eed3a87485e2bf9c13e4ccc2e400a"
const HUELLA_TEXTO := "32eb49e4a031452af4e90ddeff303c72"
const CLAVE_VISOR_3 := 14529283


## MarkerArray falso (el esquema de la Vita no lo trae: en la Vita llega por el relay).
class Falso:
	extends RefCounted
	var _m := {}

	func _init(m: Dictionary) -> void:
		_m = m

	func _get(n: StringName):
		return _m.get(String(n))


## TF falso (visor.tf): un marco «base» que se puede mover.
class TfFalso:
	extends RefCounted
	var marcos := {}

	func can_transform(_a: String, b: String) -> bool:
		return marcos.has(b)

	func lookup_transform(_a: String, b: String) -> Transform3D:
		return marcos[b]


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
	_probar_bytes()
	_probar_registro()
	await _probar_directo()
	await _probar_compacto()
	await _probar_pool()
	check(vigia.errores == 0, "sin errores de script en visor/ (%s)" % vigia.ultimo)
	OS.remove_logger(vigia)
	print("RESULTADO: ", pruebas - fallos, "/", pruebas)
	quit(0 if fallos == 0 else 1)


# ---------------------------------------------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------------------------------------------
func _fotogramas(n: int) -> void:
	for _i in n:
		await process_frame


func _esperar_ms(ms: int) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < ms:
		await process_frame


func _esperar(v: Node) -> void:
	for _i in 60:
		if v.estado != "sin conectar":
			return
		await process_frame


func _punto(x: float, y: float, z: float):
	var p = RosMsg.from_type("geometry_msgs/msg/Point")
	p.x = x
	p.y = y
	p.z = z
	return p


## Marker real (esquema de visor-ros): pose (x, y, z) y yaw en ROS.
func _mk(ns: String, id: int, tipo: int, pos := Vector3.ZERO, escala := Vector3(0.5, 0.5, 0.5), color := Color(0.1, 0.8, 0.2),
		puntos: Array = [], accion := 0):
	var m = RosMsg.from_type("visualization_msgs/msg/Marker")
	m.header.frame_id = "map"
	m.ns = ns
	m.id = id
	m.type = tipo
	m.action = accion
	m.pose.position.x = pos.x
	m.pose.position.y = pos.y
	m.pose.position.z = pos.z
	m.pose.orientation.w = 1.0
	m.scale.x = escala.x
	m.scale.y = escala.y
	m.scale.z = escala.z
	m.color.r = color.r
	m.color.g = color.g
	m.color.b = color.b
	m.color.a = color.a
	var ps := []
	for q in puntos:
		ps.append(_punto(q.x, q.y, q.z))
	m.points = ps
	return m


func _f32(datos: Array):
	var m = RosMsg.from_type("std_msgs/msg/Float32MultiArray")
	m.data = PackedFloat32Array(datos)
	return m


func _visor(en_vita: bool, d3: Array, d2: Array) -> Node:
	var v: Node = VisorRos.new()
	v.name = "VisorPrueba"
	v.transporte = "loopback"
	v.config_json = ""
	v.reintento_s = 0.0
	v.en_vita = en_vita
	for d in d3:
		v.add_child(d)
	var capa := CanvasLayer.new()
	capa.name = "Marcas2D"
	v.add_child(capa)
	for d in d2:
		capa.add_child(d)
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
	cam.position = Vector3(0, 8, 8)
	raiz.add_child(cam)
	cam.look_at_from_position(cam.position, Vector3.ZERO)
	raiz.add_child(v)
	root.add_child(raiz)
	cam.current = true
	v.camara = cam
	return v


func _cerrar(v: Node) -> void:
	v.get_parent().queue_free()
	await _fotogramas(2)


func _displays(props3: Dictionary = {}, props2: Dictionary = {}) -> Array:
	var m3: Node = load(D + "3d/marcadores.gd").new()
	m3.name = "Marcadores"
	m3.topic = "/visualization_marker"
	m3.tipo = "visualization_msgs/msg/Marker"
	for k in props3:
		m3.set(k, props3[k])
	var m2: Node = load(D + "2d/marcadores_2d.gd").new()
	m2.name = "Marcadores2D"
	m2.topic = "/visualization_marker"
	m2.tipo = "visualization_msgs/msg/Marker"
	for k in props2:
		m2.set(k, props2[k])
	return [m3, m2]


# ---------------------------------------------------------------------------------------------------------------
# Bytes: vc1.gd = vita_relay_formatos.py
# ---------------------------------------------------------------------------------------------------------------
## Mismos vectores que `vector_marcadores()` y `puntos_prueba()` de test_vita_relay.py.
func _elementos_prueba() -> Array:
	var cols := [Color(0.9, 0.1, 0.1), Color(0.1, 0.8, 0.2), Color(0.15, 0.35, 1.0), Color(1.0, 1.0, 0.0),
		Color(0.5, 0.25, 0.75), Color(0.3, 0.3, 0.3)]
	var out := []
	for i in 33:
		var c: Color = cols[i % cols.size()]
		out.append([VC1.clave_marcador("ns%d" % (i % 4), i * 7 - 20), i % 4, i * 0.25 - 3.0, 1.5 - i * 0.125,
			0.0625 * (i % 5), -1.5 + i * 0.09375, 0.5 + (i % 3) * 0.25, 0.25, 0.75,
			VC1.color_marcador(Paleta.indice(c), (i % 4) / 3.0)])
	return out


func _puntos_prueba() -> Array:
	var out := []
	for i in 50:
		out.append([i * 0.5 - 4.0, (i % 6) * 0.25, 0.125 * (i % 3)])
	return out


func _huella_f32(trozos: Array) -> String:
	var plano := PackedFloat32Array()
	for t in trozos:
		plano.append_array(PackedFloat32Array(t))
	return plano.to_byte_array().hex_encode().md5_text()


func _probar_bytes() -> void:
	var t: Array = VC1.empaquetar_marcadores(_elementos_prueba(), 70000)
	check(t.size() == 3 and t[0][3] == 11 and t[1][3] == 11 and t[2][3] == 11 and t[0][0] == (70000 & 0x7FFF),
			"bytes: 33 marcadores = 3 trozos de 11")
	var tam := []
	for x in t:
		tam.append(_f32(x).serialize().size() + 4)               # + 4 B de encapsulación = tamaño con rosbags
	print("marcadores: CDR por trozo (con encapsulación) ", tam)
	check(tam[0] == 472 and tam[1] <= 472 and tam[2] <= 472, "bytes: cada trozo ≤ 472 B (CDR real)")
	check(_huella_f32(t) == HUELLA_MARCADORES, "bytes: marcadores = vita_relay_formatos (float32 idénticos)")
	var cl := VC1.clave_marcador("lineas", 2)
	var p: Array = VC1.empaquetar_puntos(cl, 4, VC1.color_marcador(2, 1.0), 0.05, _puntos_prueba(), 9)
	check(p.size() == 2 and p[0][3] == 36 and p[1][3] == 14 and _f32(p[0]).serialize().size() + 4 <= 480,
			"bytes: 50 puntos = 2 trozos (36 + 14) ≤ 480 B")
	check(_huella_f32(p) == HUELLA_PUNTOS, "bytes: marcador_puntos = vita_relay_formatos")
	var largo := "hola|mundo "
	for _i in 100:
		largo += "x"
	var tx := VC1.texto_marcador(VC1.clave_marcador("txt", 1), 1.25, -2.5, 0.125, largo)
	check(tx.md5_text() == HUELLA_TEXTO, "bytes: marcador_texto = vita_relay_formatos (%s…)" % tx.left(30))
	var r: Dictionary = VC1.leer_texto_marcador(tx)
	check(r.clave == VC1.clave_marcador("txt", 1) and r.texto.begins_with("hola|mundo") and r.texto.length() == 80
			and VC1.leer_texto_marcador("1|2|3").is_empty(), "texto: lectura con «|» en el texto y tope 80")
	check(VC1.clave_marcador("visor", 3) == CLAVE_VISOR_3 and VC1.color_marcador(255, 1.0) == 4095
			and VC1.leer_color_marcador(3 + 256 * 8) == [3, 8.0 / 15.0], "clave FNV-1a y color = Python")
	check(VC1.empaquetar_marcadores([], 5) == [[5, 0, 1, 0]], "estado vacío = un trozo con n = 0")


func _probar_registro() -> void:
	check(Registro.regla("/visualization_marker", "visualization_msgs/msg/Marker", true).get("script", "") == D + "3d/marcadores.gd"
			and Registro.regla("/marker_array", "visualization_msgs/msg/MarkerArray", false).get("script", "") == D + "3d/marcadores.gd"
			and Registro.regla("/vita/marcadores", "std_msgs/msg/Float32MultiArray", true).get("script", "") == D + "3d/marcadores.gd"
			and Registro.regla("/vita/marcador_puntos", "std_msgs/msg/Float32MultiArray", true).get("script", "") == D + "2d/marcadores_2d.gd",
			"registro: Marker/MarkerArray → gestor; relay marcadores y marcador_puntos")
	for k in 13:
		var esperado: int = [Fab.SOLIDO, Fab.SOLIDO, Fab.SOLIDO, Fab.SOLIDO, Fab.PLANO, Fab.PLANO, Fab.SOLIDO,
			Fab.SOLIDO, Fab.PLANO, Fab.TEXTO, Fab.SOLIDO, Fab.SOLIDO, Fab.PLANO][k]
		check(Fab.capa(k, 3) == esperado, "fábrica: %s → capa %d" % [Fab.NOMBRES[k], esperado])
	check(Fab.capa(Fab.CUBE_LIST, 65) == Fab.PLANO and Fab.capa(99, 0) == Fab.NINGUNA, "fábrica: lista > 64 = 2D; tipo raro = nada")


# ---------------------------------------------------------------------------------------------------------------
# Directo (PC)
# ---------------------------------------------------------------------------------------------------------------
func _probar_directo() -> void:
	var ds := _displays({"mallas": {"package://robot/meshes/base.dae": "res://no_existe.tres"}})
	var m3: Node = ds[0]
	var m2: Node = ds[1]
	var v := _visor(false, [m3], [m2])
	await _esperar(v)
	check(m3.estado == "ok" and m2.estado == "ok" and not m3.canal.compacto and m2.capa == "resto_2d",
			"PC: gestor 3D y 2D suscritos en directo")
	# Los 13 tipos en un MarkerArray
	var cuadrado := [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)]
	var lista := []
	for k in 13:
		var pts: Array = []
		match k:
			Fab.LINE_STRIP, Fab.LINE_LIST, Fab.POINTS, Fab.ARROW_STRIP, Fab.CUBE_LIST, Fab.SPHERE_LIST:
				pts = cuadrado
			Fab.TRIANGLE_LIST:
				pts = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(2, 1, 0), Vector3(1, 2, 0)]
		var m = _mk("t", k, k, Vector3(k, 0, 0), Vector3(0.3, 0.3, 0.3), Color(0.1, 0.8, 0.2), pts)
		if k == Fab.TEXT_VIEW_FACING:
			m.text = "hola"
		if k == Fab.MESH_RESOURCE:
			m.mesh_resource = "package://robot/meshes/base.dae"
		lista.append(m)
	var fl = _mk("t", 13, Fab.ARROW, Vector3.ZERO, Vector3(0.05, 0.1, 0.0), Color.RED, [Vector3(0, 0, 0), Vector3(0, 2, 0)])
	lista.append(fl)
	var arr := Falso.new({"markers": lista})
	m3._al_mensaje(arr)
	m2._al_mensaje(arr)
	check(m3.cuantos() == 9 and m2.cuantos() == 5, "directo: 13 tipos + ARROW por puntos → 9 sólidos y 5 en 2D")
	var todos_malla := true
	for k in [0, 1, 2, 3, 6, 7, 10, 11]:
		var e = m3.entrada("t/%d" % k)
		todos_malla = todos_malla and e != null and (e.n as MeshInstance3D).mesh != null and e.n.visible
	check(todos_malla, "directo: cada sólido (ARROW, CUBE, SPHERE, CYLINDER, listas, MESH, TRIANGLE_LIST) con malla y visible")
	var n1: MeshInstance3D = m3.entrada("t/1").n
	check(n1.global_position.is_equal_approx(Vector3(0, 0, -1)) and n1.transform.basis.get_scale().is_equal_approx(Vector3(0.3, 0.3, 0.3)),
			"directo: CUBE en (1, 0, 0) ROS con escala 0,3")
	check((m3.entrada("t/6").n as MeshInstance3D).mesh.get_faces().size() == 4 * 12 * 3
			and (m3.entrada("t/7").n as MeshInstance3D).mesh.get_faces().size() == 4 * 8 * 3
			and (m3.entrada("t/11").n as MeshInstance3D).mesh.get_faces().size() == 2 * 3,
			"directo: CUBE_LIST 4 × 12 tri, SPHERE_LIST 4 × 8 tri, TRIANGLE_LIST 2 tri horneados")
	check((m3.entrada("t/10").n as MeshInstance3D).mesh == preload("res://comun/visor/primitivas_viz.gd").malla(1, Paleta.indice(Color(0.1, 0.8, 0.2))),
			"directo: MESH_RESOURCE sin malla horneada = cubo (aviso)")
	var nf: MeshInstance3D = m3.entrada("t/13").n
	var cuerpo := nf.get_node_or_null("cuerpo") as MeshInstance3D
	var cabeza := nf.get_node_or_null("cabeza") as MeshInstance3D
	check(cuerpo != null and cuerpo.visible and cabeza.visible and nf.mesh == null
			and cabeza.global_position.is_equal_approx(Vector3(-2, 0, 0))
			and is_equal_approx((cabeza.global_transform.basis.z).length(), 0.23 * 2.0),
			"directo: ARROW por 2 puntos = cuerpo + cabeza (0,23·d) con la punta en (0, 2, 0) ROS")
	check(v.texto.cuantos() == 1, "directo: TEXT_VIEW_FACING en TextoSuperpuesto")
	await _fotogramas(3)
	m2.queue_redraw()
	await _fotogramas(2)
	print("marcadores 2D: quads dibujados ", m2.quads_dibujados, " de ", m2.cupo)
	check(m2.quads_dibujados > 0 and m2.quads_dibujados <= m2.cupo, "directo: el 2D dibuja líneas y puntos dentro del cupo")
	# MODIFY (mismo nodo), recrear al cambiar de tipo y paso entre 3D y 2D
	m3._al_mensaje(_mk("t", 1, Fab.CUBE, Vector3(2, 0, 0)))
	check(m3.entrada("t/1").n == n1 and n1.global_position.is_equal_approx(Vector3(0, 0, -2)), "MODIFY: mismo nodo, nueva pose")
	var cambio = _mk("t", 1, Fab.LINE_STRIP, Vector3.ZERO, Vector3(0.05, 0, 0), Color.WHITE, cuadrado)
	m3._al_mensaje(cambio)
	m2._al_mensaje(cambio)
	check(m3.entrada("t/1") == null and not n1.visible and m2.entrada("t/1") != null and m2.entrada("t/1").tipo == Fab.LINE_STRIP,
			"cambio de tipo CUBE → LINE_STRIP: sale del 3D (al pool) y entra en el 2D")
	var vuelta = _mk("t", 1, Fab.SPHERE)
	m3._al_mensaje(vuelta)
	m2._al_mensaje(vuelta)
	check(m3.entrada("t/1") != null and m3.entrada("t/1").tipo == Fab.SPHERE and m2.entrada("t/1") == null,
			"cambio de tipo LINE_STRIP → SPHERE: vuelve al 3D y sale del 2D")
	# NaN
	var nan = _mk("t", 1, Fab.SPHERE, Vector3(NAN, 0, 0))
	m3._al_mensaje(nan)
	check(m3.rechazados == 1 and m3.entrada("t/1").n.global_position.is_equal_approx(Vector3(0, 0, 0)),
			"NaN: se rechaza y la entrada anterior sigue")
	# DELETE
	var hijos: int = m3.get_child_count()
	var n2: MeshInstance3D = m3.entrada("t/2").n
	m3._al_mensaje(_mk("t", 2, 0, Vector3.ZERO, Vector3.ONE, Color.WHITE, [], Fab.DELETE))
	m2._al_mensaje(_mk("t", 9, 0, Vector3.ZERO, Vector3.ONE, Color.WHITE, [], Fab.DELETE))
	check(m3.entrada("t/2") == null and not n2.visible and m3.get_child_count() == hijos and v.texto.cuantos() == 0,
			"DELETE: el nodo se oculta y vuelve al pool (sin queue_free); el texto se quita")
	# DELETEALL por ns y total
	for i in 3:
		m3._al_mensaje(_mk("otro", i, Fab.CUBE, Vector3(0, i, 0)))
	var antes: int = m3.cuantos()
	m3._al_mensaje(_mk("otro", 0, 0, Vector3.ZERO, Vector3.ONE, Color.WHITE, [], Fab.DELETEALL))
	check(m3.cuantos() == antes - 3 and m3.entrada("t/3") != null, "DELETEALL con ns: borra solo ese ns")
	var todo = _mk("", 0, 0, Vector3.ZERO, Vector3.ONE, Color.WHITE, [], Fab.DELETEALL)
	m3._al_mensaje(todo)
	m2._al_mensaje(todo)
	check(m3.cuantos() == 0 and m2.cuantos() == 0 and m3.get_child_count() == m3.nodos_creados(), "DELETEALL sin ns: todo, sin perder nodos")
	# lifetime con el reloj de recepción
	var vida = _mk("vida", 0, Fab.CUBE)
	vida.lifetime.nanosec = 300000000
	var vida2 = _mk("vida", 1, Fab.POINTS, Vector3.ZERO, Vector3(0.1, 0.1, 0.1), Color.WHITE, cuadrado)
	vida2.lifetime.nanosec = 300000000
	m3._al_mensaje(vida)
	m2._al_mensaje(vida2)
	check(m3.cuantos() == 1 and m2.cuantos() == 1, "lifetime: vivos al llegar")
	await _esperar_ms(700)
	check(m3.cuantos() == 0 and m2.cuantos() == 0, "lifetime: caducan (barrido a 4 Hz) en 3D y 2D")
	# frame_locked
	var tf := TfFalso.new()
	tf.marcos["base"] = Transform3D.IDENTITY
	v.tf = tf
	var fijo = _mk("f", 0, Fab.CUBE)
	fijo.header.frame_id = "base"
	var movil = _mk("f", 1, Fab.CUBE)
	movil.header.frame_id = "base"
	movil.frame_locked = true
	var sin_tf = _mk("f", 2, Fab.CUBE)
	sin_tf.header.frame_id = "luna"
	m3._al_mensaje(fijo)
	m3._al_mensaje(movil)
	m3._al_mensaje(sin_tf)
	check(not m3.entrada("f/2").n.visible, "sin TF del marco: oculto hasta que llegue")
	tf.marcos["base"] = Transform3D(Basis.IDENTITY, Vector3(0, 0, -5))
	tf.marcos["luna"] = Transform3D.IDENTITY
	await _esperar_ms(400)
	check(m3.entrada("f/0").n.global_position.is_equal_approx(Vector3.ZERO)
			and m3.entrada("f/1").n.global_position.is_equal_approx(Vector3(0, 0, -5))
			and m3.entrada("f/2").n.visible, "frame_locked: solo el bloqueado sigue al marco; el que esperaba TF aparece")
	v.tf = null
	# Lista grande → 2D
	var grande := []
	for i in 80:
		grande.append(Vector3(i * 0.1, 0, 0))
	var lg = _mk("g", 0, Fab.SPHERE_LIST, Vector3.ZERO, Vector3(0.05, 0.05, 0.05), Color.WHITE, grande)
	m3._al_mensaje(lg)
	m2._al_mensaje(lg)
	check(m3.entrada("g/0") == null and m2.entrada("g/0") != null, "SPHERE_LIST de 80 > 64: puntos 2D")
	await _cerrar(v)


# ---------------------------------------------------------------------------------------------------------------
# Compacto (Vita simulada, perfil HMI)
# ---------------------------------------------------------------------------------------------------------------
func _entrada_c(clave: int, tipo: int, x: float, yaw := 0.0) -> Array:
	return [clave, tipo, x, 0.0, 0.0, yaw, 0.5, 0.5, 0.5, VC1.color_marcador(Paleta.ROJO, 1.0)]


func _enviar(m3: Node, trozos: Array, saltar := -1) -> void:
	for i in trozos.size():
		if i != saltar:
			m3._al_mensaje(_f32(trozos[i]))


func _probar_compacto() -> void:
	var ds := _displays()
	var m3: Node = ds[0]
	var m2: Node = ds[1]
	var v := _visor(true, [m3], [m2])
	await _esperar(v)
	check(m3.canal.compacto and m3.canal.topic_abierto == "/vita/marcadores" and m2.canal.topic_abierto == "/vita/marcador_puntos"
			and m2.canal_texto.topic_abierto == "/vita/marcador_texto", "Vita: relay marcadores, marcador_puntos y marcador_texto")
	check(m3.cupo == 12 and m3.tope() == 12 and m2.cupo == 150, "Vita HMI: 12 instancias (D7) y 150 quads en resto_2d")
	# Estado completo de 10 sólidos + 1 línea + 1 texto
	var el := []
	for i in 10:
		el.append(_entrada_c(100 + i, [0, 1, 2, 3, 10][i % 5], i * 1.0, PI / 2 if i == 0 else 0.0))
	el.append(_entrada_c(500, Fab.LINE_STRIP, 0.0))
	el.append(_entrada_c(600, Fab.TEXT_VIEW_FACING, 0.0))
	_enviar(m3, VC1.empaquetar_marcadores(el, 1))
	check(m3.cuantos() == 10 and m3.estados_completos == 1 and m3.claves_estado.size() == 12,
			"compacto: 12 marcadores en 2 trozos → 10 sólidos; el estado guarda también las claves 2D")
	var flecha: MeshInstance3D = m3.entrada(100).n
	var adelante := (flecha.global_transform.basis * Vector3.FORWARD).normalized()
	check(adelante.is_equal_approx(Vector3(-1, 0, 0)), "compacto: yaw π/2 ROS (+Y) = −X Godot (giro +Y del mismo signo)")
	check(is_equal_approx(m3.entrada(101).n.global_transform.basis.get_scale().x, 0.5)
			and m3.entrada(104).n.mesh != null, "compacto: CUBE con escala y MESH_RESOURCE como cubo")
	# Puntos (2 trozos) y texto del relay
	var pts := []
	for i in 50:
		pts.append([i * 0.1, 0.0, 0.0])
	var tp: Array = VC1.empaquetar_puntos(500, Fab.LINE_STRIP, VC1.color_marcador(Paleta.VERDE, 1.0), 0.05, pts, 7)
	m2._al_mensaje(_f32(tp[0]))
	check(m2.entrada(500) == null, "puntos: el primer trozo no basta")
	m2._al_mensaje(_f32(tp[1]))
	check(m2.entrada(500) != null and m2.entrada(500).pts.size() == 50, "puntos: 2 trozos → LINE_STRIP de 50 puntos")
	var s = RosMsg.from_type("std_msgs/msg/String")
	s.data = VC1.texto_marcador(600, 1.0, 2.0, 0.5, "meta")
	m2._al_texto(s)
	check(m2.entrada(600) != null and v.texto.cuantos() == 1, "texto: del relay a TextoSuperpuesto")
	# DELETE en el relay = la clave no llega en el siguiente estado completo
	var sin := el.duplicate()
	sin.remove_at(3)                                     # clave 103
	sin.remove_at(sin.size() - 1)                        # el texto 600
	var n103: MeshInstance3D = m3.entrada(103).n
	var trozos2: Array = VC1.empaquetar_marcadores(sin, 2)
	_enviar(m3, trozos2, 0)                              # se pierde el trozo 0: estado incompleto
	check(m3.entrada(103) != null and m3.estados_completos == 1, "trozo perdido: sin estado completo no se purga")
	_enviar(m3, VC1.empaquetar_marcadores(sin, 3))
	check(m3.entrada(103) == null and not n103.visible and m3.cuantos() == 9 and m3.estados_completos == 2,
			"estado completo: lo que no llegó vuelve al pool (sin fantasmas tras DELETE)")
	await _esperar_ms(400)
	check(m2.entrada(600) == null and v.texto.cuantos() == 0 and m2.entrada(500) != null,
			"2D: purga el texto borrado con el estado del gestor 3D; la línea sigue")
	_enviar(m3, VC1.empaquetar_marcadores([], 4))
	await _esperar_ms(400)
	check(m3.cuantos() == 0 and m2.cuantos() == 0, "estado vacío: todo fuera en 3D y 2D")
	# Cupo 12: 33 sólidos → 12 nodos
	var muchos := []
	for i in 33:
		muchos.append(_entrada_c(1000 + i, Fab.CUBE, i))
	var t33: Array = VC1.empaquetar_marcadores(muchos, 5)
	_enviar(m3, t33)
	check(t33.size() == 3 and m3.cuantos() == 12 and m3.nodos_creados() == 12 and m3.sin_sitio == 21,
			"cupo: 33 marcadores (3 trozos) → 12 nodos en la Vita; 21 sin sitio")
	await _fotogramas(2)
	check(vigia.errores == 0, "Vita: sin errores de script (%s)" % vigia.ultimo)
	await _cerrar(v)


# ---------------------------------------------------------------------------------------------------------------
# Pool lleno sin fugas
# ---------------------------------------------------------------------------------------------------------------
func _probar_pool() -> void:
	var ds := _displays({"max_marcadores": 20})
	var m3: Node = ds[0]
	var v := _visor(false, [m3], [ds[1]])
	await _esperar(v)
	var tipos := [Fab.ARROW, Fab.CUBE, Fab.SPHERE, Fab.CYLINDER]
	var nodos0 := -1
	var objetos0 := 0
	for ciclo in 30:
		var lista := []
		for i in 40:
			lista.append(_mk("c%d" % ciclo, i, tipos[(i + ciclo) % 4], Vector3(i * 0.1, 0, 0)))
		m3._al_mensaje(Falso.new({"markers": lista}))
		m3._al_mensaje(_mk("c%d" % ciclo, 0, 0, Vector3.ZERO, Vector3.ONE, Color.WHITE, [], Fab.DELETEALL))
		if ciclo == 1:
			nodos0 = m3.get_child_count()
			objetos0 = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	check(m3.nodos_creados() == 20 and m3.get_child_count() == nodos0 and m3.cuantos() == 0
			and int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)) == objetos0,
			"PC: 30 ciclos de 40 ADD (tope 20) + DELETEALL: 20 nodos, sin fugas (%d nodos)" % m3.get_child_count())
	await _cerrar(v)
	ds = _displays()
	m3 = ds[0]
	v = _visor(true, [m3], [ds[1]])
	await _esperar(v)
	var hijos := -1
	for ciclo in 30:
		var el := []
		for i in 33:
			el.append(_entrada_c(ciclo * 100 + i, [0, 1, 2, 3, 10][(i + ciclo) % 5], i))
		_enviar(m3, VC1.empaquetar_marcadores(el, ciclo + 10))
		if ciclo == 0:
			hijos = m3.get_child_count()
	check(m3.nodos_creados() == 12 and m3.get_child_count() == hijos and m3.cuantos() == 12,
			"Vita: 30 estados completos con claves nuevas: siempre 12 nodos (pool lleno, sin fugas)")
	await _cerrar(v)
	# Revisión V2: un nodo horneado (CUBE_LIST) que pasa a CUBO y vuelve a la MISMA lista no conserva el cubo.
	var n := Fab.crear()
	var lista_m = _mk("l", 1, Fab.CUBE_LIST, Vector3.ZERO, Vector3(0.2, 0.2, 0.2), Color(0.1, 0.8, 0.2),
			[Vector3(0, 0, 0), Vector3(1, 0, 0)])
	Fab.aplicar(n, lista_m, {"intervalo_horneado_ms": 1000})
	var horneada = n.mesh
	Fab.aplicar(n, _mk("l", 2, Fab.CUBE), {"intervalo_horneado_ms": 1000})
	var cubo = n.mesh
	Fab.aplicar(n, lista_m, {"intervalo_horneado_ms": 1000})
	check(horneada is ArrayMesh and n.mesh != cubo and n.mesh is ArrayMesh and n.mesh.get_faces().size() == horneada.get_faces().size(),
			"pool: lista → cubo → la misma lista vuelve a hornear (no se queda el cubo)")
	n.free()
