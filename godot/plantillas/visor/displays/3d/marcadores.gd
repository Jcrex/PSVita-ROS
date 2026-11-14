extends "res://comun/visor/display_ros_3d.gd"
## Gestor de marcadores 3D (V8; doc 36a §4.7.1 y §4.7.4; sentencia W13 D14): `visualization_msgs/Marker` y
## `MarkerArray` EN DIRECTO (PC, o un Marker suelto en la Vita) o el ESTADO COMPLETO del relay `<p>/marcadores`
## (Vita). Dibuja los SÓLIDOS (ARROW, CUBE, SPHERE, CYLINDER, MESH_RESOURCE, TRIANGLE_LIST y listas ≤ 64) con
## PrimitivasViz y la paleta; líneas, puntos y texto son de `displays/2d/marcadores_2d.gd` (FabricaMarcadores.capa).
##
## Semántica de RViz2 Jazzy (`marker_common.cpp:195-310`, `marker_base.cpp:84-115`):
## - clave (ns, id); 0 ADD = 1 MODIFY; 2 DELETE; 3 DELETEALL (con ns no vacío, solo ese ns);
## - si cambia `type`, la entrada se recrea; NaN/Inf ⇒ se rechaza (la entrada anterior sigue);
## - `lifetime` > 100 µs ⇒ caduca con el reloj de RECEPCIÓN (T17), barrido a 4 Hz;
## - `frame_locked`: el marco se resuelve en cada barrido; sin él, una sola vez (o hasta que haya TF).
## Reciclado: los nodos borrados se ocultan y vuelven a un pool por tipo; nunca `queue_free` en régimen estable.
## Nunca se crean más de `tope()` nodos (cupo de la capa «marcadores», HMI 12 / Viz 32, y ≤ 48 en la Vita): con el
## pool de un tipo vacío y el tope alcanzado se reutiliza un nodo libre de otro tipo.
##
## Camino compacto (D14): cada trozo `[seq, trozo, n_trozos, n] + [clave, tipo, x, y, z, yaw, sx, sy, sz, color]·n`
## coloca sus sólidos; al completar un `seq` se reciclan las claves que no llegaron (un DELETE perdido no deja
## fantasmas). `claves_estado` (el último estado completo, también las claves 2D) lo usa marcadores_2d para purgar.

const Fab = preload("res://comun/visor/fabrica_marcadores.gd")
const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
const Vc1 = preload("res://comun/ros/vc1.gd")

const TOPE_VITA := 48                           # doc 36a §4.7 (la ficha de mapas): nunca más nodos en la Vita
const SOLIDOS_COMPACTOS := [Fab.ARROW, Fab.CUBE, Fab.SPHERE, Fab.CYLINDER, Fab.MESH_RESOURCE]

@export var max_marcadores := 256               # nodos como mucho (en la Vita, además, cupo y TOPE_VITA)
@export var mallas := {}                        # MESH_RESOURCE: "package://…" → "res://…" (mallas horneadas)

var ignorados := 0                              # marcadores que no son de este display (2D) o que no viajan
var rechazados := 0                             # NaN/Inf
var sin_sitio := 0                              # ADD sin nodo libre (tope alcanzado)
var claves_estado := {}                         # compacto: clave → tipo del último estado COMPLETO
var estados_completos := 0                      # compacto: nº de `seq` completados
var _vivos := {}                                # clave ("ns/id" o int compacta) → entrada
var _pool := {}                                 # tipo → Array de MeshInstance3D ocultos
var _creados := 0
var _t_barrido := 0
var _seq := -1
var _vistos := {}
var _trozos := {}
var _sin_nodo := []                             # sólidos de este seq sin nodo libre todavía
var _t_informe := 0


static func nombre_display() -> String:
	return "Marcadores"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["visualization_msgs/msg/Marker", "visualization_msgs/msg/MarkerArray"])


func _init() -> void:
	capa = "marcadores"
	hz = 0.0                                    # cada mensaje cuenta (acciones)
	topic_vita = "marcadores"
	tipo_vita = "std_msgs/msg/Float32MultiArray"


func conectar(v) -> void:
	canal.coalescer = false                     # «el último gana» perdería ADD/DELETE (directo) y trozos (compacto)
	canal.max_pendientes = 32
	super.conectar(v)


## Nodos que este display puede llegar a tener a la vez.
func tope() -> int:
	var t := max_marcadores
	if visor != null and visor.en_vita:
		t = mini(t, TOPE_VITA)
	return mini(t, cupo) if cupo > 0 else t


func cuantos() -> int:
	return _vivos.size()


func nodos_creados() -> int:
	return _creados


func entrada(k):
	return _vivos.get(k)


## Sin pasar por la base: cada marcador lleva su marco (el nodo raíz queda en la identidad del marco fijo).
func _al_mensaje(msg) -> void:
	if canal.compacto:
		_compacto(msg)
	else:
		var lista = msg.markers if "markers" in msg else [msg]
		for m in lista:
			_accion(m)
	visible = true
	estado = "ok"


# --- directo ---------------------------------------------------------------------------------------------------

func _accion(m) -> void:
	match int(m.action):
		Fab.DELETEALL:
			_borrar_ns(String(m.ns))
		Fab.DELETE:
			_borrar(Fab.clave(m))
		Fab.ADD, Fab.MODIFY:
			_add(m)


func _add(m) -> void:
	var k := Fab.clave(m)
	if Fab.capa_de(m) != Fab.SOLIDO:
		_borrar(k)                              # si era sólido y cambia a línea/texto, lo recrea el 2D
		ignorados += 1
		return
	if not Fab.valido(m):
		rechazados += 1
		return
	var tipo := int(m.type)
	var e = _vivos.get(k)
	if e != null and e.tipo != tipo:
		_borrar(k)
		e = null
	if e == null:
		var n := _sacar(tipo)
		if n == null:
			sin_sitio += 1
			return
		e = {"n": n, "tipo": tipo, "ns": String(m.ns)}
		_vivos[k] = e
	var n: MeshInstance3D = e.n
	e.expira = Fab.expira_ms(m, Time.get_ticks_msec())
	e.frame = Fab.marco(m)
	e.locked = bool(m.frame_locked)
	e.dibujar = Fab.aplicar(n, m, {"mallas": mallas, "intervalo_horneado_ms": 1000 if visor.en_vita else 0})
	e.local = n.transform
	e.con_tf = false
	_colocar(e)


## Marco del marcador → fijo. Sin TF se oculta y se reintenta en el barrido.
func _colocar(e: Dictionary) -> void:
	var t = visor.transformada(e.frame)
	var n: MeshInstance3D = e.n
	if t == null:
		n.visible = false
		return
	e.con_tf = true
	n.transform = (t as Transform3D) * (e.local as Transform3D)
	n.visible = e.dibujar


# --- compacto (relay <p>/marcadores) -----------------------------------------------------------------------------

func _compacto(msg) -> void:
	var d = msg.data
	var cab: Dictionary = Vc1.cabecera(d)
	if cab.is_empty():
		return
	if cab.seq != _seq:
		_seq = cab.seq
		_vistos = {}
		_trozos = {}
		_sin_nodo = []
	_trozos[cab.trozo] = true
	for i in cab.n:
		var b: int = 4 + i * Vc1.POR_MARCADOR
		if b + Vc1.POR_MARCADOR > d.size():
			break
		var clave := int(d[b])
		var tipo := int(d[b + 1])
		_vistos[clave] = tipo
		if tipo in SOLIDOS_COMPACTOS:
			var pos := Vector3(d[b + 2], d[b + 3], d[b + 4])
			var esc := Vector3(d[b + 6], d[b + 7], d[b + 8])
			if pos.is_finite() and esc.is_finite() and is_finite(d[b + 5]):
				var t := Transform3D(Basis(Vector3.UP, d[b + 5]), rclgd.ros_to_godot_vector(pos))
				if not poner_compacto(clave, tipo, t, esc, int(d[b + 9])):
					_sin_nodo.append([clave, tipo, t, esc, int(d[b + 9])])   # se reintenta al reciclar
		elif _vivos.has(clave):
			_borrar(clave)                          # pasó a ser 2D (lo dibuja marcadores_2d)
	if _trozos.size() == cab.n_trozos:
		retener_solo(_vistos)
		for x in _sin_nodo:                         # claves nuevas que esperaban a que se reciclaran las viejas
			if not poner_compacto(x[0], x[1], x[2], x[3], x[4]):
				sin_sitio += 1
		_sin_nodo = []
		claves_estado = _vistos
		estados_completos += 1


## Sólido del relay: `t` = pose en el marco fijo (ejes Godot, solo yaw), `esc` = escala ROS (sx, sy, sz).
## false = sin nodo libre (tope alcanzado).
func poner_compacto(clave: int, tipo: int, t: Transform3D, esc: Vector3, col: int) -> bool:
	var e = _vivos.get(clave)
	if e != null and e.tipo != tipo:
		_borrar(clave)
		e = null
	if e == null:
		var n := _sacar(tipo)
		if n == null:
			return false
		e = {"n": n, "tipo": tipo, "ns": "", "expira": -1, "frame": "", "locked": false, "con_tf": true}
		_vivos[clave] = e
	var n: MeshInstance3D = e.n
	var c: Array = Vc1.leer_color_marcador(col)
	Fab._piezas(n, false)
	var lados: Vector3
	if tipo == Fab.ARROW:
		n.mesh = Prim.malla(Prim.FLECHA, c[0])
		lados = Vector3(absf(esc.y) * Fab.ANCHO_FLECHA, absf(esc.z) * Fab.ANCHO_FLECHA, absf(esc.x))
	else:
		n.mesh = Prim.malla(Prim.CUBO if tipo == Fab.MESH_RESOURCE else tipo, c[0])   # MESH en la Vita = cubo
		lados = Vector3(absf(esc.y), absf(esc.z), absf(esc.x))                          # escala_ros
	n.transform = Transform3D(t.basis * Basis.from_scale(lados), t.origin)
	e.local = n.transform
	e.dibujar = c[1] > 0.01 and esc.x * esc.y * esc.z != 0.0
	n.visible = e.dibujar
	return true


## Estado completo: lo que no está en `claves` vuelve al pool (solo claves compactas).
func retener_solo(claves: Dictionary) -> void:
	for k in _vivos.keys():
		if typeof(k) == TYPE_INT and not claves.has(k):
			_borrar(k)


# --- pool ----------------------------------------------------------------------------------------------------------

func _sacar(tipo: int) -> MeshInstance3D:
	var libres: Array = _pool.get(tipo, [])
	if not libres.is_empty():
		return libres.pop_back()
	if _creados < tope():
		var n := Fab.crear()
		add_child(n)                                # sin owner (doc 35)
		_creados += 1
		return n
	for t in _pool:                                 # tope alcanzado: un nodo libre de otro tipo
		if not _pool[t].is_empty():
			return _pool[t].pop_back()
	return null


func _borrar(k) -> void:
	var e = _vivos.get(k)
	if e == null:
		return
	var n: MeshInstance3D = e.n
	n.visible = false
	if not _pool.has(e.tipo):
		_pool[e.tipo] = []
	_pool[e.tipo].append(n)
	_vivos.erase(k)


func _borrar_ns(ns: String) -> void:
	for k in _vivos.keys():
		if ns == "" or _vivos[k].ns == ns:
			_borrar(k)


func _process(dt: float) -> void:
	super._process(dt)
	var ahora := Time.get_ticks_msec()
	if ahora - _t_barrido < 250:                    # caducidad, frame_locked y TF pendiente a 4 Hz
		return
	_t_barrido = ahora
	for k in _vivos.keys():
		var e: Dictionary = _vivos[k]
		if e.expira >= 0 and ahora > e.expira:
			_borrar(k)
		elif e.locked or not e.con_tf:
			_colocar(e)
	# Revisión V2: gates G-W13-M1/M2/M3 en la Vita (o con `-- perfil`): nodos constantes, sin sitio y estados.
	if Perfil.activo and ahora - _t_informe >= 5000:
		_t_informe = ahora
		printerr("[visor-marc] vivos=%d nodos=%d hijos=%d tope=%d sin_sitio=%d completos=%d rechazados=%d" % [
				_vivos.size(), _creados, get_child_count(), tope(), sin_sitio, estados_completos, rechazados])


func _coste() -> Dictionary:
	var n := mini(max_marcadores, TOPE_VITA) if (visor != null and visor.en_vita) else max_marcadores
	return {"instancias": n, "triangulos": n * Prim.TRIANGULOS[Prim.CILINDRO], "quads": 0}
