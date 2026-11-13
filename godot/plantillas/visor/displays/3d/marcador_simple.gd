extends "res://comun/visor/display_ros_3d.gd"
## Marcador simple (V5; doc 36a §4.7.1–4.7.2, D mapas#10 y V mapas#11–15): `visualization_msgs/Marker` suelto EN
## DIRECTO (229 B sin puntos: cabe en 488 hasta 10 puntos). Solo los tipos sólidos de una instancia: 0 ARROW (por
## pose), 1 CUBE, 2 SPHERE, 3 CYLINDER, y 9 TEXT_VIEW_FACING por TextoSuperpuesto (D11). El resto (líneas, listas,
## puntos, mallas, ARROW por 2 puntos) y `MarkerArray` son del gestor `3d/marcadores.gd` (V8) y el relay
## `marcadores` (D14): aquí se ignoran (`ignorados` los cuenta).
##
## Semántica de RViz2 Jazzy (`marker_common.cpp:205-310`): clave ns/id; 0 ADD = MODIFY, 2 DELETE, 3 DELETEALL
## (con `ns` no vacío borra solo ese ns); `lifetime` > 100 µs ⇒ caduca con el reloj de RECEPCIÓN (barrido a 4 Hz);
## NaN/Inf en pose o escala ⇒ se rechaza; cuaternión nulo ⇒ identidad (T14); escala nula ⇒ no se dibuja.
## `frame_locked` no se aplica (el marco se resuelve al llegar el mensaje): eso es del gestor (V8).
##
## Cada marcador es una instancia `top_level` colocada en el marco fijo (marco del mensaje × pose): así conviven
## marcadores de marcos distintos aunque la base mueva el nodo raíz. Malla compartida de PrimitivasViz por (forma,
## color de PaletaViz): cambiar de color o forma = cambiar `mesh`, sin crear geometría. Capa «marcadores»
## (HMI 12, Viz 32): hasta min(`max_marcadores`, cupo) a la vez; los nodos borrados vuelven a un pool.

const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")

const ARROW := 0
const CUBE := 1
const SPHERE := 2
const CYLINDER := 3
const TEXT_VIEW_FACING := 9
## Ancho de la FLECHA unidad: punta de radio 0,1 (diámetro 0,2). RViz dibuja la ARROW por pose con la cabeza de
## diámetro 2·scale.y (`arrow_marker.cpp`, Arrow(0.77, 1.0, 0.23, 2.0)) ⇒ factor 10 en los ejes del ancho.
const ANCHO_FLECHA := 10.0

@export var max_marcadores := 8

var _vivos := {}                                # "ns/id" -> {"n": MeshInstance3D o null (texto), "expira": ms o -1}
var _libres: Array[MeshInstance3D] = []
var _t_barrido := 0
var ignorados := 0                              # tipos que no son de este display


static func nombre_display() -> String:
	return "MarcadorSimple"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["visualization_msgs/msg/Marker"])


func _init() -> void:
	capa = "marcadores"
	hz = 0.0                                    # cada mensaje cuenta (acciones ADD/DELETE)


func conectar(v) -> void:
	canal.coalescer = false                     # «el último gana» perdería DELETE/ADD de otros id
	super.conectar(v)


func cuantos() -> int:
	return _vivos.size()


func _procesar(msg):
	var accion := int(msg.action)
	var clave := "%s/%d" % [String(msg.ns), int(msg.id)]
	if accion == 3:                                                     # DELETEALL
		return {"accion": 3, "ns": String(msg.ns)}
	if accion == 2:                                                     # DELETE
		return {"accion": 2, "clave": clave}
	var t := int(msg.type)
	if not (t in [ARROW, CUBE, SPHERE, CYLINDER, TEXT_VIEW_FACING]):
		ignorados += 1
		return null
	if t == ARROW and msg.points.size() > 0:                           # ARROW por 2 puntos: gestor (V8)
		ignorados += 1
		return null
	var s = msg.scale
	var escala := Vector3(s.x, s.y, s.z)
	var pose: Transform3D = Prim.pose_godot(msg.pose)
	if not (pose.is_finite() and escala.is_finite()):
		return null                                                     # marker_common.cpp:195-213
	var vida: float = float(msg.lifetime.sec) + float(msg.lifetime.nanosec) * 1e-9
	var c: Color = Paleta.de_ros(msg.color)
	return {"accion": 0, "clave": clave, "tipo": t, "pose": pose, "escala": escala, "color": c,
			"texto": String(msg.text), "vida": vida}


func _pintar(d) -> void:
	match int(d["accion"]):
		3:
			for k in _vivos.keys():
				if d["ns"] == "" or String(k).begins_with(d["ns"] + "/"):
					_borrar(k)
		2:
			_borrar(d["clave"])
		0:
			_add(d)


func _add(d: Dictionary) -> void:
	var clave: String = d["clave"]
	var e = _vivos.get(clave)
	var t: int = d["tipo"]
	if e != null and (e["n"] == null) != (t == TEXT_VIEW_FACING):     # cambia entre texto y sólido: recrear
		_borrar(clave)
		e = null
	if e == null:
		if _vivos.size() >= mini(max_marcadores, cupo):
			return                                                      # sin cupo: se ignora (como el gestor)
		e = {"n": null if t == TEXT_VIEW_FACING else _sacar()}
		_vivos[clave] = e
	var vida: float = d["vida"]
	e["expira"] = Time.get_ticks_msec() + int(vida * 1000.0) if vida > 1e-4 else -1
	var c: Color = d["color"]
	var pose: Transform3D = d["pose"]
	var s: Vector3 = d["escala"]
	if t == TEXT_VIEW_FACING:
		if visor != null and visor.texto != null:
			visor.texto.poner(name + "/" + clave, marco * pose.origin, d["texto"], c)
		return
	var n: MeshInstance3D = e["n"]
	var dibujar := c.a > 0.01 and s.x * s.y * s.z != 0.0                # RViz: alfa 0 o escala nula = invisible
	if t == ARROW:
		n.mesh = Prim.malla(Prim.FLECHA, Paleta.indice(c))
		# ROS x = largo (−Z Godot), y = ancho (X Godot), z = alto (Y Godot)
		n.global_transform = marco * Transform3D(pose.basis * Basis.from_scale(
				Vector3(absf(s.y) * ANCHO_FLECHA, absf(s.z) * ANCHO_FLECHA, absf(s.x))), pose.origin)
	else:
		n.mesh = Prim.malla(t, Paleta.indice(c))                           # CUBO/ESFERA/CILINDRO = 1/2/3
		n.global_transform = marco * Transform3D(pose.basis * Basis.from_scale(Prim.escala_ros(s)), pose.origin)
	n.visible = dibujar


func _sacar() -> MeshInstance3D:
	if not _libres.is_empty():
		return _libres.pop_back()
	var n := MeshInstance3D.new()
	n.top_level = true
	n.visible = false
	add_child(n)                                                        # sin owner (doc 35)
	return n


func _borrar(clave: String) -> void:
	var e = _vivos.get(clave)
	if e == null:
		return
	if e["n"] != null:
		var n: MeshInstance3D = e["n"]
		n.visible = false
		_libres.append(n)
	elif visor != null and visor.texto != null:
		visor.texto.quitar(name + "/" + clave)
	_vivos.erase(clave)


func _process(dt: float) -> void:
	super._process(dt)
	var ahora := Time.get_ticks_msec()
	if ahora - _t_barrido < 250:                                        # caducidad a 4 Hz
		return
	_t_barrido = ahora
	for k in _vivos.keys():
		var x: int = _vivos[k]["expira"]
		if x >= 0 and ahora > x:
			_borrar(k)


func _coste() -> Dictionary:
	return {"instancias": max_marcadores, "triangulos": max_marcadores * Prim.TRIANGULOS[Prim.CILINDRO], "quads": 0}
