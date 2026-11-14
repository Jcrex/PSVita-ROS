extends "res://comun/visor/display_ros_3d.gd"
## Cliente de marcadores interactivos (V14, `solo_pc`; doc 36a §4.7.5, fichas mapas#26–27 con sus correcciones;
## protocolo de `interactive_markers` de jazzy). Dibuja los `InteractiveMarker` de un servidor (`<ns>`) y deja que
## la herramienta `herramientas/im_feedback.gd` («Interactuar», como la Interact tool de RViz) los arrastre.
##
## Protocolo (como `interactive_marker_client.cpp` de jazzy):
##   - estado inicial por el servicio `<ns>/get_interactive_markers` (`GetInteractiveMarkers`: `sequence_number` +
##     `markers[]`) si el nodo tiene `create_client` (rclgd); ros2_vita no tiene servicios cliente
##     (`API_PARITY.md`, T-W4-9) → sin servicio se empieza con la primera actualización (solo se ven los marcadores
##     que el servidor vuelva a publicar; [I], anotado en visor/README.md);
##   - `<ns>/update` (`InteractiveMarkerUpdate`, FIABLE, profundidad 100, todos los mensajes: `coalescer = false`):
##     `UPDATE` (1) con `markers` (alta o reemplazo), `poses` (solo pose) y `erases`; `KEEP_ALIVE` (0) sin cambios.
##     `seq_num` ≤ el aplicado se ignora; un hueco (seq > último + 1, o un KEEP_ALIVE adelantado) → se pide el
##     estado otra vez (con servicio) o se acepta y se cuenta en `huecos` (sin servicio).
##   - Mientras se arrastra un marcador, sus `poses` del servidor se ignoran (como RViz: el cliente manda).
## Dibujo: cada `InteractiveMarker` es un Node3D con `transform` = TF(marco del marcador) × pose; sus controles
## dibujan sus `markers` sólidos con FabricaMarcadores (los de líneas/texto no, en V14) y, si un control no trae
## marcadores, las asas por defecto de `autoComplete` (MOVE_AXIS: dos FLECHA; ROTATE_AXIS: ANILLO; MOVE_PLANE y
## MOVE_ROTATE: DISCO; MOVE_3D/ROTATE_3D/MOVE_ROTATE_3D: ESFERA) con el color del eje (x rojo, y verde, z azul).
## `orientation_mode` FIXED/VIEW_FACING se tratan como INHERIT (el eje gira con el marcador) [decisión V14].
## Menús (MENU, `menu_entries`) no se implementan (V14: sin menú contextual); BUTTON sí (BUTTON_CLICK).

const Fab = preload("res://comun/visor/fabrica_marcadores.gd")
const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")

const KEEP_ALIVE := 0
const UPDATE := 1
enum { NONE, MENU, BUTTON, MOVE_AXIS, MOVE_PLANE, ROTATE_AXIS, MOVE_ROTATE, MOVE_3D, ROTATE_3D, MOVE_ROTATE_3D }

@export var ns := "/basic_controls"           # espacio de nombres del servidor (topics `<ns>/update`, `<ns>/feedback`)
@export var max_marcadores := 64

var ims := {}                                  # nombre → {nodo, marco, pose (Transform3D Godot en su marco), msg, controles}
var seq := -1                                  # último seq_num aplicado
var huecos := 0                                # huecos de secuencia vistos
var estados_pedidos := 0                       # peticiones de estado al servicio
var arrastrando := ""                          # marcador que arrastra la herramienta (sus poses del servidor se ignoran)
var con_servicio := false
var _cli                                       # RosClient (sin anotar: no existe en ros2_vita, T7)
var _peticion                                  # RosRequest en curso
var _pendientes: Array = []                    # updates llegados antes del estado inicial


static func nombre_display() -> String:
	return "MarcadoresInteractivos"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["visualization_msgs/msg/InteractiveMarkerUpdate"])


func _init() -> void:
	tipo = "visualization_msgs/msg/InteractiveMarkerUpdate"
	capa = "marcadores"
	solo_pc = true
	fiabilidad = 2                             # FIABLE: el servidor publica con rclcpp::QoS(100) [I]
	profundidad = 100
	hz = 0.0


func conectar(v) -> void:
	if topic == "":
		topic = ns.trim_suffix("/") + "/update"
	canal.coalescer = false                    # cada update cuenta (son parciales)
	super.conectar(v)
	if estado == "desactivado" or estado == "sin cupo":
		return
	con_servicio = v.contexto.nodo != null and v.contexto.nodo.has_method("create_client")
	if con_servicio:
		_cli = v.contexto.nodo.create_client(ns.trim_suffix("/") + "/get_interactive_markers",
				"visualization_msgs/srv/GetInteractiveMarkers")
		if _cli == null:
			con_servicio = false
		else:
			_cli.service_available.connect(_al_servicio)
			_cli.wait_for_service_async(5.0)


func desconectar() -> void:
	_cli = null
	_peticion = null
	super.desconectar()


func _al_servicio(disponible: bool) -> void:
	if disponible:
		pedir_estado()


## Pide el estado completo (rclgd). Mientras llega, las actualizaciones se guardan.
func pedir_estado() -> void:
	if _cli == null or _peticion != null:
		return
	estados_pedidos += 1
	_peticion = _cli.async_send_request(_cli.create_request())
	if _peticion != null:
		_peticion.completed.connect(_al_estado)


## Respuesta de `GetInteractiveMarkers`: reemplaza todo y aplica las actualizaciones posteriores guardadas.
func _al_estado(r) -> void:
	_peticion = null
	if r == null:
		return
	aplicar_estado(int(r.sequence_number), r.markers)


func aplicar_estado(numero: int, marcadores: Array) -> void:
	for n in ims.keys():
		_borrar(n)
	for im in marcadores:
		_poner(im)
	seq = numero
	var guardados := _pendientes
	_pendientes = []
	for u in guardados:
		if int(u.seq_num) > seq:
			_aplicar(u)


func _procesar(msg):
	return msg                                 # el trabajo va en _pintar (una vez por mensaje entregado)


func _pintar(u) -> void:
	if con_servicio and (seq < 0 or _peticion != null):
		_pendientes.append(u)                  # aún sin estado inicial
		if _pendientes.size() > 100:
			_pendientes.pop_front()
		return
	_aplicar(u)


func _aplicar(u) -> void:
	var s := int(u.seq_num)
	var t := int(u.type)
	if seq >= 0:
		var esperado := seq if t == KEEP_ALIVE else seq + 1
		if s < esperado:
			return                             # viejo o repetido
		if s > esperado:
			huecos += 1
			if con_servicio:
				pedir_estado()
				_pendientes.append(u)
				return
	seq = s
	if t != UPDATE:
		return
	for im in u.markers:
		_poner(im)
	for p in u.poses:
		var n := String(p.name)
		if ims.has(n) and n != arrastrando:
			ims[n]["marco"] = String(p.header.frame_id).trim_prefix("/")
			ims[n]["pose"] = Prim.pose_godot(p.pose)
			_colocar(n)
	for n in u.erases:
		_borrar(String(n))


func _process(dt: float) -> void:
	super._process(dt)
	for n in ims:                              # pocos marcadores: el TF puede moverse (≤ max_marcadores)
		_colocar(n)


## Alta o reemplazo de un InteractiveMarker.
func _poner(im) -> void:
	var n := String(im.name)
	if not ims.has(n) and ims.size() >= max_marcadores:
		return
	_borrar(n)
	var nodo := Node3D.new()
	nodo.name = "IM_" + n.validate_node_name()
	add_child(nodo)                            # sin owner (doc 35)
	var esc: float = float(im.scale) if float(im.scale) > 0.0 else 1.0
	var controles: Array = []
	for c in im.controls:
		controles.append(_control(nodo, c, esc))
	ims[n] = {"nodo": nodo, "marco": String(im.header.frame_id).trim_prefix("/"), "pose": Prim.pose_godot(im.pose),
			"msg": im, "controles": controles, "escala": esc, "descripcion": String(im.description)}
	_colocar(n)


func _borrar(n: String) -> void:
	if not ims.has(n):
		return
	var nodo: Node3D = ims[n]["nodo"]
	remove_child(nodo)
	nodo.queue_free()
	ims.erase(n)
	if arrastrando == n:
		arrastrando = ""


## Control → {nombre, modo, eje (Godot, local al marcador), nodo}. Dibuja sus Marker o las asas por defecto.
func _control(padre: Node3D, c, esc: float) -> Dictionary:
	var o = c.orientation
	var q := Quaternion(o.x, o.y, o.z, o.w)
	q = q.normalized() if q.length_squared() > 1e-6 else Quaternion.IDENTITY
	var eje := (rclgd.ros_to_godot_quat(q) * Vector3.FORWARD).normalized()   # +X del control (ROS) = −Z Godot
	var nodo := Node3D.new()
	nodo.name = String(c.name).validate_node_name() if String(c.name) != "" else "control"
	padre.add_child(nodo)
	var modo := int(c.interaction_mode)
	var marcadores: Array = c.markers
	var dibujados := 0
	for m in marcadores:
		if Fab.capa_de(m) != Fab.SOLIDO or not Fab.valido(m):
			continue
		var mi := Fab.crear()
		nodo.add_child(mi)
		mi.visible = Fab.aplicar(mi, m)
		dibujados += 1
	if marcadores.is_empty():
		dibujados += _asas(nodo, modo, eje, esc)
	return {"nombre": String(c.name), "modo": modo, "eje": eje, "nodo": nodo, "dibujados": dibujados,
			"descripcion": String(c.description)}


## Color del eje como `autoComplete` de interactive_markers: x rojo, y verde, z azul (por el eje dominante).
static func color_eje(eje_godot: Vector3) -> Color:
	var r := rclgd.godot_to_ros_vector(eje_godot).abs()
	if r.x >= r.y and r.x >= r.z:
		return Color(1, 0, 0)
	return Color(0, 1, 0) if r.y >= r.z else Color(0, 0, 1)


func _asas(nodo: Node3D, modo: int, eje: Vector3, esc: float) -> int:
	var col := color_eje(eje)
	var hacia_eje := Basis(Quaternion(Vector3.UP, eje)) if not eje.is_equal_approx(Vector3.DOWN) else Basis(Vector3.RIGHT, PI)
	match modo:
		MOVE_AXIS:
			for s in [1.0, -1.0]:
				var f := Prim.instancia(Prim.FLECHA, col)
				var d: Vector3 = eje * s
				f.transform = Transform3D(Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT)
						* Basis.from_scale(Vector3(2.5, 2.5, 0.5) * esc), d * 0.5 * esc)
				nodo.add_child(f)
			return 2
		ROTATE_AXIS, MOVE_ROTATE:
			var a := Prim.instancia(Prim.ANILLO, col)
			a.transform = Transform3D(hacia_eje * Basis.from_scale(Vector3.ONE * 1.6 * esc), Vector3.ZERO)
			nodo.add_child(a)
			if modo == MOVE_ROTATE:
				var dm := Prim.instancia(Prim.DISCO, Color(col, 0.5))
				dm.transform = Transform3D(hacia_eje * Basis.from_scale(Vector3.ONE * 0.6 * esc), Vector3.ZERO)
				nodo.add_child(dm)
				return 2
			return 1
		MOVE_PLANE:
			var dp := Prim.instancia(Prim.DISCO, col)
			dp.transform = Transform3D(hacia_eje * Basis.from_scale(Vector3.ONE * esc), Vector3.ZERO)
			nodo.add_child(dp)
			return 1
		MOVE_3D, ROTATE_3D, MOVE_ROTATE_3D:
			var e := Prim.instancia(Prim.ESFERA, Color(1, 1, 0))
			e.transform = Transform3D(Basis.from_scale(Vector3.ONE * 0.3 * esc), Vector3.ZERO)
			nodo.add_child(e)
			return 1
	return 0


## Coloca el nodo del marcador: TF(marco → marco fijo) × pose. Sin TF se oculta.
func _colocar(n: String) -> void:
	var d: Dictionary = ims[n]
	var t = visor.transformada(d["marco"]) if visor != null else Transform3D.IDENTITY
	var nodo: Node3D = d["nodo"]
	if t == null:
		nodo.visible = false
		return
	nodo.visible = true
	nodo.transform = (t as Transform3D) * (d["pose"] as Transform3D)


## Transformada del marco del marcador al marco fijo (Godot), o null.
func marco_de(n: String):
	return visor.transformada(ims[n]["marco"]) if ims.has(n) else null


## Lo usa la herramienta al arrastrar: pose nueva en coordenadas GLOBALES de Godot → pose en el marco del marcador.
func mover_global(n: String, g: Transform3D) -> void:
	if not ims.has(n):
		return
	var t = marco_de(n)
	if t == null:
		return
	# global = cliente.global × TF(marco) × pose ⇒ pose = TF⁻¹ × cliente.global⁻¹ × global
	ims[n]["pose"] = (t as Transform3D).affine_inverse() * (global_transform.affine_inverse() * g)
	_colocar(n)


## Asa más cercana a un punto de pantalla (≤ `radio_px`): {im, control, modo, eje (global), centro (global)} o {}.
## Puntos de agarre: MOVE_AXIS en ±0,5·escala sobre el eje; ROTATE_AXIS en 8 puntos del anillo; el resto, el centro.
func asa_en(cam: Camera3D, p: Vector2, radio_px := 24.0) -> Dictionary:
	var mejor := {}
	var dmin := radio_px
	for n in ims:
		var d: Dictionary = ims[n]
		var nodo: Node3D = d["nodo"]
		if not nodo.visible:
			continue
		var g := nodo.global_transform
		var esc: float = d["escala"]
		for c in d["controles"]:
			var modo: int = c["modo"]
			if modo == NONE or modo == MENU:
				continue
			var eje_g: Vector3 = (g.basis * (c["eje"] as Vector3)).normalized()
			var puntos: Array = [g.origin]
			if modo == MOVE_AXIS:
				puntos = [g.origin + eje_g * 0.5 * esc, g.origin - eje_g * 0.5 * esc]
			elif modo == ROTATE_AXIS:
				puntos = []
				var u := eje_g.cross(Vector3.UP if absf(eje_g.y) < 0.99 else Vector3.RIGHT).normalized()
				for k in 8:
					puntos.append(g.origin + u.rotated(eje_g, k * TAU / 8.0) * 0.8 * esc)
			for q in puntos:
				if cam.is_position_behind(q):
					continue
				var dist := cam.unproject_position(q).distance_to(p)
				if dist < dmin:
					dmin = dist
					mejor = {"im": n, "control": c["nombre"], "modo": modo, "eje": eje_g, "centro": g.origin, "inicio": g}
	return mejor


func _caducar() -> void:
	pass                                       # los marcadores interactivos no caducan (el servidor los borra)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 0}
