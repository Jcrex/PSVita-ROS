extends "res://comun/visor/display_ros_2d.gd"
## Marcadores 2D superpuestos al 3D (V8; doc 36a §4.7.2 y §4.7.4; ADR 0011: líneas, puntos y texto → 2D en un
## comando por lote, H16–H17): LINE_STRIP, LINE_LIST, POINTS, ARROW_STRIP, CUBE_LIST/SPHERE_LIST de más de 64
## elementos (como puntos) y TEXT_VIEW_FACING (por TextoSuperpuesto, D11). Los sólidos son de `3d/marcadores.gd`.
## El mismo script en el PC y en la Vita (un solo camino de código; los prismas 3D del PC no entran en V8).
##
## Directo: `Marker`/`MarkerArray` con la semántica de RViz (igual que el gestor 3D: ns/id, ADD = MODIFY, DELETE,
## DELETEALL por ns, recrear si cambia el tipo, NaN rechazado, lifetime con el reloj de recepción, frame_locked).
## Compacto (relay): `<p>/marcador_puntos` (este canal, trozos `[seq, trozo, n_trozos, n, clave, tipo, color, ancho,
## xyz…]`) y `<p>/marcador_texto` (segundo canal, fiable, «clave|x|y|z|texto»). Lo borrado lo dice el ESTADO COMPLETO
## de `<p>/marcadores`, que recibe el gestor 3D (`gestor_3d`; si no se asigna, el primer display del visor con
## `retener_solo`); sin gestor, una entrada compacta caduca a los `caducidad_compacta_s` sin refrescarse.
##
## Dibujo en `_draw()` reproyectado con la cámara del visor a ≤ `hz_reproyeccion` (20 Hz): un `draw_polyline`/
## `draw_multiline` por marcador de líneas y UN `canvas_item_add_triangle_array` con todos los puntos. Cupo en *quads*
## de la capa `resto_2d` (≤ 150 por defecto): un segmento o un punto = 1 *quad*; lo que pasa del cupo no se dibuja.

const Fab = preload("res://comun/visor/fabrica_marcadores.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Vc1 = preload("res://comun/ros/vc1.gd")

@export var topic_vita_texto := "marcador_texto"   # sufijo del segundo canal (compacto)
@export var gestor_3d: Node                         # 3d/marcadores.gd con el estado completo (compacto)
@export var caducidad_compacta_s := 10.0            # sin gestor: entrada compacta sin refrescar → fuera
@export var hz_reproyeccion := 20.0
@export var max_quads := 150
@export var punto_min_px := 2.0
@export var linea_min_px := 1.0

var canal_texto = Canal.new()
var ignorados := 0
var rechazados := 0
var quads_dibujados := 0
var _vivos := {}                                    # clave ("ns/id" o int compacta) → entrada
var _parciales := {}                                # compacto: clave → {seq, n_trozos, trozos: {i: PackedVector3Array}}
var _t_barrido := 0
var _t_redibujo := 0
var _estado_visto := -1


static func nombre_display() -> String:
	return "Marcadores2D"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["visualization_msgs/msg/Marker", "visualization_msgs/msg/MarkerArray"])


func _init() -> void:
	capa = "resto_2d"
	en_pantalla = true
	hz = 0.0
	topic_vita = "marcador_puntos"
	tipo_vita = "std_msgs/msg/Float32MultiArray"


func conectar(v) -> void:
	canal.coalescer = false
	canal.max_pendientes = 32
	super.conectar(v)
	if canal.compacto and canal.abierto() and topic_vita_texto != "":
		canal_texto.coalescer = false
		canal_texto.max_pendientes = 16
		if not canal_texto.mensaje.is_connected(_al_texto):
			canal_texto.mensaje.connect(_al_texto)
		var t: String = v.prefijo_compacto.trim_suffix("/") + "/" + topic_vita_texto.trim_prefix("/")
		canal_texto.abrir(v.contexto.nodo, t, "std_msgs/msg/String", v.contexto.qos(false, 5 if v.en_vita else 10))


func desconectar() -> void:
	canal_texto.cerrar()
	_vaciar_textos()
	super.desconectar()


func cuantos() -> int:
	return _vivos.size()


func entrada(k):
	return _vivos.get(k)


func _al_mensaje(msg) -> void:
	if canal.compacto:
		_puntos_compactos(msg)
	else:
		var lista = msg.markers if "markers" in msg else [msg]
		for m in lista:
			_accion(m)
	visible = true
	estado = "ok"
	queue_redraw()


# --- directo ---------------------------------------------------------------------------------------------------

func _accion(m) -> void:
	match int(m.action):
		Fab.DELETEALL:
			for k in _vivos.keys():
				if String(m.ns) == "" or _vivos[k].ns == String(m.ns):
					_borrar(k)
		Fab.DELETE:
			_borrar(Fab.clave(m))
		Fab.ADD, Fab.MODIFY:
			_add(m)


func _add(m) -> void:
	var k := Fab.clave(m)
	var c := Fab.capa_de(m)
	if c != Fab.PLANO and c != Fab.TEXTO:
		_borrar(k)                                  # cambia a sólido: lo recrea el gestor 3D
		ignorados += 1
		return
	if not Fab.valido(m):
		rechazados += 1
		return
	var tipo := int(m.type)
	var e = _vivos.get(k)
	if e != null and e.tipo != tipo:
		_borrar(k)
	e = {"tipo": tipo, "ns": String(m.ns), "frame": Fab.marco(m), "locked": bool(m.frame_locked),
		"local": Prim.pose_godot(m.pose), "pts": Fab.puntos(m), "cols": Fab.colores(m), "color": Fab.color(m),
		"ancho": absf(m.scale.x), "alto": absf(m.scale.y), "texto": String(m.text),
		"expira": Fab.expira_ms(m, Time.get_ticks_msec()), "t": null, "refresco": Time.get_ticks_msec()}
	_vivos[k] = e
	_colocar(k, e)


## Marco → fijo (`t` = marco × pose, ejes Godot); sin TF la entrada no se dibuja hasta el siguiente barrido.
func _colocar(k, e: Dictionary) -> void:
	var t = visor.transformada(e.frame) if e.frame != "" else Transform3D.IDENTITY
	e.t = (t as Transform3D) * (e.local as Transform3D) if t != null else null
	if e.tipo == Fab.TEXT_VIEW_FACING and visor.texto != null:
		if e.t == null or e.color.a <= 0.01:
			visor.texto.quitar(_clave_texto(k))
		else:
			visor.texto.poner(_clave_texto(k), (e.t as Transform3D).origin, e.texto, e.color)


func _clave_texto(k) -> String:
	return "%s/%s" % [name, str(k)]


func _borrar(k) -> void:
	var e = _vivos.get(k)
	if e == null:
		return
	if e.tipo == Fab.TEXT_VIEW_FACING and visor != null and visor.texto != null:
		visor.texto.quitar(_clave_texto(k))
	_vivos.erase(k)


func _vaciar_textos() -> void:
	for k in _vivos.keys():
		_borrar(k)


# --- compacto ------------------------------------------------------------------------------------------------------

func _puntos_compactos(msg) -> void:
	var d = msg.data
	var cab: Dictionary = Vc1.cabecera(d)
	if cab.is_empty() or d.size() < 4 + Vc1.EXTRA_PUNTOS:
		return
	var clave := int(d[4])
	var p = _parciales.get(clave)
	if p == null or p.seq != cab.seq:
		p = {"seq": cab.seq, "n_trozos": cab.n_trozos, "trozos": {}}
		_parciales[clave] = p
	var pts := PackedVector3Array()
	for i in cab.n:
		var b: int = 4 + Vc1.EXTRA_PUNTOS + 3 * i
		if b + 3 > d.size():
			break
		var q := Vector3(d[b], d[b + 1], d[b + 2])
		if q.is_finite():
			pts.append(rclgd.ros_to_godot_vector(q))
	p.trozos[cab.trozo] = pts
	if p.trozos.size() < p.n_trozos:
		return
	var todos := PackedVector3Array()
	for t in p.n_trozos:
		todos.append_array(p.trozos[t])
	_parciales.erase(clave)
	var c: Array = Vc1.leer_color_marcador(int(d[6]))
	var col: Color = Paleta.color(c[0], c[1])
	var ancho: float = absf(d[7]) if is_finite(d[7]) else 0.0   # revisión V2: NaN → ancho mínimo (T2)
	var e = _vivos.get(clave)
	if e != null and e.tipo != int(d[5]):
		_borrar(clave)
	_vivos[clave] = {"tipo": int(d[5]), "ns": "", "frame": "", "locked": false, "local": Transform3D.IDENTITY,
		"pts": todos, "cols": PackedColorArray(), "color": col, "ancho": ancho, "alto": ancho,
		"texto": "", "expira": -1, "t": Transform3D.IDENTITY, "refresco": Time.get_ticks_msec()}


func _al_texto(msg) -> void:
	var r: Dictionary = Vc1.leer_texto_marcador(String(msg.data))
	if r.is_empty() or not (r.pos as Vector3).is_finite():
		return
	var clave: int = r.clave
	var e = _vivos.get(clave)
	if e != null and e.tipo != Fab.TEXT_VIEW_FACING:
		_borrar(clave)
	var t := Transform3D(Basis.IDENTITY, rclgd.ros_to_godot_vector(r.pos))
	e = {"tipo": Fab.TEXT_VIEW_FACING, "ns": "", "frame": "", "locked": false, "local": t, "pts": PackedVector3Array(),
		"cols": PackedColorArray(), "color": Color.WHITE, "ancho": 0.0, "alto": 0.0, "texto": String(r.texto),
		"expira": -1, "t": t, "refresco": Time.get_ticks_msec()}
	_vivos[clave] = e
	if visor != null and visor.texto != null:
		visor.texto.poner(_clave_texto(clave), t.origin, e.texto, e.color)
	visible = true


## Estado completo del gestor 3D: fuera las claves compactas que ya no están.
func retener_solo(claves: Dictionary) -> void:
	for k in _vivos.keys():
		if typeof(k) == TYPE_INT and not claves.has(k):
			_borrar(k)
	for k in _parciales.keys():
		if not claves.has(k):
			_parciales.erase(k)


func _buscar_gestor():
	if gestor_3d != null and is_instance_valid(gestor_3d):
		return gestor_3d
	if visor != null:
		for d in visor.displays:
			if d != self and is_instance_valid(d) and d.has_method("retener_solo") and d.has_method("tope"):
				gestor_3d = d
				return d
	return null


# --- bucle ---------------------------------------------------------------------------------------------------------

func _process(dt: float) -> void:
	super._process(dt)
	canal_texto.bombear()
	var ahora := Time.get_ticks_msec()
	if ahora - _t_barrido >= 250:                       # caducidad, frame_locked, TF pendiente y purga a 4 Hz
		_t_barrido = ahora
		_barrido(ahora)
	if not _vivos.is_empty() and ahora - _t_redibujo >= 1000.0 / maxf(hz_reproyeccion, 0.1):
		_t_redibujo = ahora
		queue_redraw()                                  # la cámara se mueve: reproyectar


func _barrido(ahora: int) -> void:
	if canal.compacto:
		var g = _buscar_gestor()
		if g != null:
			if g.estados_completos != _estado_visto:
				_estado_visto = g.estados_completos
				retener_solo(g.claves_estado)
		else:
			for k in _vivos.keys():
				if typeof(k) == TYPE_INT and ahora - int(_vivos[k].refresco) > caducidad_compacta_s * 1000.0:
					_borrar(k)
	for k in _vivos.keys():
		var e: Dictionary = _vivos[k]
		if e.expira >= 0 and ahora > e.expira:
			_borrar(k)
		elif e.locked or e.t == null:
			_colocar(k, e)


func _camara() -> Camera3D:
	if visor != null and visor.camara != null:
		return visor.camara
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


## Px por metro a la distancia de `p` (focal de la cámara en px).
func _px_por_m(cam: Camera3D, p: Vector3) -> float:
	var alto := get_viewport_rect().size.y
	var focal := alto * 0.5 / tan(deg_to_rad(cam.fov) * 0.5)
	return focal / maxf(cam.global_position.distance_to(p), 0.01)


func _tope_quads() -> int:
	return cupo if cupo > 0 else max_quads


func _draw() -> void:
	quads_dibujados = 0
	var cam := _camara()
	if cam == null or visor == null:
		return
	var tope := _tope_quads()
	var tri_v := PackedVector2Array()
	var tri_c := PackedColorArray()
	for e in _vivos.values():
		if e.tipo == Fab.TEXT_VIEW_FACING or e.t == null or e.color.a <= 0.01 or e.pts.is_empty():
			continue
		var t: Transform3D = e.t
		var pts: PackedVector3Array = e.pts
		var cols: PackedColorArray = e.cols
		match int(e.tipo):
			Fab.LINE_STRIP, Fab.ARROW_STRIP, Fab.LINE_LIST:
				var ancho: float = maxf(linea_min_px, e.ancho * _px_por_m(cam, t * pts[0]))
				var lista: bool = e.tipo == Fab.LINE_LIST
				var p2 := PackedVector2Array()
				var c2 := PackedColorArray()
				var paso := 2 if lista else 1
				var n := pts.size() - (pts.size() % 2 if lista else 0)
				var i := 0
				while i < n:
					var segs := 1 if lista else (1 if p2.size() > 0 else 0)
					if quads_dibujados + segs > tope:
						break
					var tramo := [i, i + 1] if lista else [i]
					var detras := false
					for j in tramo:
						if cam.is_position_behind(t * pts[j]):
							detras = true
					if detras:
						if not lista:
							_linea(p2, c2, false, e.color, ancho)  # corta la tira en lo que queda detrás
							p2 = PackedVector2Array()
							c2 = PackedColorArray()
						i += paso
						continue
					for j in tramo:
						p2.append(cam.unproject_position(t * pts[j]))
						c2.append(cols[j] if cols.size() == pts.size() else e.color)
					quads_dibujados += segs
					i += paso
				_linea(p2, c2, lista, e.color, ancho)
				if e.tipo == Fab.ARROW_STRIP and p2.size() >= 2 and quads_dibujados < tope:
					_punta(p2[p2.size() - 2], p2[p2.size() - 1], maxf(ancho * 4.0, 6.0), e.color)   # semántica [?]
					quads_dibujados += 1
			_:                                              # POINTS y listas grandes como puntos
				for j in pts.size():
					if quads_dibujados >= tope:
						break
					var w := t * pts[j]
					if cam.is_position_behind(w):
						continue
					var lado: float = maxf(punto_min_px, e.ancho * _px_por_m(cam, w))
					var c: Color = cols[j] if cols.size() == pts.size() else e.color
					_cuadrado(tri_v, tri_c, cam.unproject_position(w), lado * 0.5, c)
					quads_dibujados += 1
	if not tri_v.is_empty():
		var idx := PackedInt32Array()
		for k in tri_v.size():
			idx.append(k)
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), idx, tri_v, tri_c)


func _linea(p2: PackedVector2Array, c2: PackedColorArray, lista: bool, color: Color, ancho: float) -> void:
	if p2.size() < 2:
		return
	var uno := true
	for c in c2:
		if c != c2[0]:
			uno = false
			break
	if lista:
		if uno:
			draw_multiline(p2, c2[0] if c2.size() > 0 else color, ancho)
		else:
			var cs := PackedColorArray()
			for k in range(0, c2.size(), 2):
				cs.append(c2[k])
			draw_multiline_colors(p2, cs, ancho)
	elif uno:
		draw_polyline(p2, c2[0] if c2.size() > 0 else color, ancho)
	else:
		draw_polyline_colors(p2, c2, ancho)


func _punta(a: Vector2, b: Vector2, largo: float, color: Color) -> void:
	var d := b - a
	if d.length_squared() < 1e-6:
		return
	d = d.normalized()
	var n := Vector2(-d.y, d.x)
	draw_colored_polygon(PackedVector2Array([b + d * largo * 0.5, b - d * largo * 0.5 + n * largo * 0.4,
			b - d * largo * 0.5 - n * largo * 0.4]), color)


func _cuadrado(v: PackedVector2Array, c: PackedColorArray, p: Vector2, h: float, col: Color) -> void:
	var a := p + Vector2(-h, -h)
	var b := p + Vector2(h, -h)
	var d := p + Vector2(h, h)
	var e := p + Vector2(-h, h)
	v.append_array([a, b, d, a, d, e])
	for _k in 6:
		c.append(col)


func _caducar() -> void:
	pass                                                # los marcadores tienen su propia vida (lifetime / estado)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": max_quads}
