extends RefCounted
## FabricaMarcadores (ADR 0013 §1–§2; doc 36a §4.7.2; sentencia W13 D2): `visualization_msgs/Marker` → instancias de
## PrimitivasViz con el color de PaletaViz. Solo TRADUCE: las mallas unidad son de PrimitivasViz; aquí se hornean
## únicamente las geometrías que dependen de los datos (CUBE_LIST/SPHERE_LIST ≤ 64 y TRIANGLE_LIST ≤ 1 000 tri),
## con los mismos ayudantes de PrimitivasViz (`_caja`, `_tri`, `_malla_de`) y la UV de la paleta.
##
## Reparto por capa (ADR 0011, doc 36a §4.7): sólido rígido → 3D por instancia (`displays/3d/marcadores.gd`);
## líneas, puntos y texto → 2D superpuesto (`displays/2d/marcadores_2d.gd`). Los dos displays usan `capa()` para
## decidir qué es suyo y así nunca dibujan dos veces el mismo marcador.
##
## | type | Representación | Display |
## |---|---|---|
## | 0 ARROW (pose) | FLECHA × (sy·10, sz·10, sx) (cabeza de diámetro 2·scale.y, `arrow_marker.cpp`) | 3D |
## | 0 ARROW (2 points) | CILINDRO girado 90° (cuerpo, diámetro scale.x) + CONO (cabeza scale.y × scale.z o 0,23·d) | 3D |
## | 1 CUBE · 2 SPHERE · 3 CYLINDER | malla unidad × `escala_ros(scale)` | 3D |
## | 4 LINE_STRIP · 5 LINE_LIST · 8 POINTS · 12 ARROW_STRIP | 2D superpuesto (un lote por marcador) | 2D |
## | 6 CUBE_LIST · 7 SPHERE_LIST | ≤ 64 elementos: UNA malla horneada (12 / 8 tri por elemento); más: puntos 2D | 3D / 2D |
## | 9 TEXT_VIEW_FACING | TextoSuperpuesto (D11) | 2D |
## | 10 MESH_RESOURCE | tabla `package://…` → `res://…` de mallas horneadas; si falta, CUBO + aviso | 3D |
## | 11 TRIANGLE_LIST | ArrayMesh horneada con la UV de la paleta por triángulo (≤ 1 000 tri) | 3D |
##
## Uso: `const Fab = preload("res://comun/visor/fabrica_marcadores.gd")` (sin `class_name`, D15; trampa T9).

const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")

const ARROW := 0
const CUBE := 1
const SPHERE := 2
const CYLINDER := 3
const LINE_STRIP := 4
const LINE_LIST := 5
const CUBE_LIST := 6
const SPHERE_LIST := 7
const POINTS := 8
const TEXT_VIEW_FACING := 9
const MESH_RESOURCE := 10
const TRIANGLE_LIST := 11
const ARROW_STRIP := 12
const NOMBRES := ["ARROW", "CUBE", "SPHERE", "CYLINDER", "LINE_STRIP", "LINE_LIST", "CUBE_LIST", "SPHERE_LIST",
	"POINTS", "TEXT_VIEW_FACING", "MESH_RESOURCE", "TRIANGLE_LIST", "ARROW_STRIP"]

const ADD := 0
const MODIFY := 1                              # obsoleto en ROS 2: igual que ADD
const DELETE := 2
const DELETEALL := 3

enum { NINGUNA, SOLIDO, PLANO, TEXTO }        # capa de un marcador (quién lo dibuja)

## Ancho de la FLECHA unidad: punta de diámetro 0,2 ⇒ ×10 para cabeza de diámetro 2·scale.y (igual que V5).
const ANCHO_FLECHA := 10.0
const PUNTA_RELATIVA := 0.23                   # arrow_marker.cpp: cabeza = 0,23·d si scale.z = 0
const MAX_HORNEADO := 64                       # elementos de CUBE_LIST/SPHERE_LIST en 3D (doc 36a §4.7.2)
const MAX_TRIANGULOS := 1000                   # TRIANGLE_LIST (H5)
const GIRO_CILINDRO := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   # +Y → −Z (eje de la flecha)

static var _cache_mallas := {}                 # ruta res:// → Mesh (MESH_RESOURCE)
static var _avisados := {}                     # uri → true (aviso una vez)


## Quién dibuja un marcador de `tipo` con `n_puntos` puntos.
static func capa(tipo: int, n_puntos: int) -> int:
	match tipo:
		ARROW, CUBE, SPHERE, CYLINDER, MESH_RESOURCE, TRIANGLE_LIST:
			return SOLIDO
		CUBE_LIST, SPHERE_LIST:
			return SOLIDO if n_puntos <= MAX_HORNEADO else PLANO
		LINE_STRIP, LINE_LIST, POINTS, ARROW_STRIP:
			return PLANO
		TEXT_VIEW_FACING:
			return TEXTO
	return NINGUNA


static func capa_de(m) -> int:
	return capa(int(m.type), m.points.size())


## Clave del gestor: «ns/id» (marker_common.cpp: MarkerID = (ns, id)).
static func clave(m) -> String:
	return "%s/%d" % [String(m.ns), int(m.id)]


## ms de caducidad con el reloj de RECEPCIÓN (`marker_base.cpp:84`, trampa T17); -1 = nunca (lifetime ≤ 100 µs).
static func expira_ms(m, ahora_ms: int) -> int:
	var vida: float = float(m.lifetime.sec) + float(m.lifetime.nanosec) * 1e-9
	return ahora_ms + int(vida * 1000.0) if vida > 1e-4 else -1


static func marco(m) -> String:
	return String(m.header.frame_id).trim_prefix("/")


## NaN/Inf en pose, escala o puntos ⇒ el marcador se rechaza (`marker_common.cpp:195-213`).
static func valido(m) -> bool:
	var p = m.pose.position
	var o = m.pose.orientation
	var s = m.scale
	if not (Vector3(p.x, p.y, p.z).is_finite() and Quaternion(o.x, o.y, o.z, o.w).is_finite()
			and Vector3(s.x, s.y, s.z).is_finite()):
		return false
	for q in m.points:
		if not Vector3(q.x, q.y, q.z).is_finite():
			return false
	return true


static func color(m) -> Color:
	return Paleta.de_ros(m.color)


## Punto ROS (RosMsg Point) → ejes Godot.
static func punto(q) -> Vector3:
	return rclgd.ros_to_godot_vector(Vector3(q.x, q.y, q.z))


## Puntos del marcador en ejes Godot (marco del marcador, sin la pose).
static func puntos(m) -> PackedVector3Array:
	var out := PackedVector3Array()
	for q in m.points:
		out.append(punto(q))
	return out


## Colores por punto si `colors` tiene uno por punto; si no, vacío (se usa `color`).
static func colores(m) -> PackedColorArray:
	var out := PackedColorArray()
	if m.colors.size() == m.points.size():
		for c in m.colors:
			out.append(Paleta.de_ros(c))
	return out


## Nodo nuevo para un sólido (sin malla, oculto, sin sombra). Las piezas de la flecha por 2 puntos se crean al
## usarse (`_flecha_puntos`), así cualquier nodo del pool vale para cualquier tipo.
static func crear() -> MeshInstance3D:
	var n := MeshInstance3D.new()
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.visible = false
	return n


## Coloca el sólido `m` en `n`: malla, color y `transform` LOCAL al marco del marcador (pose × escala). Devuelve
## false si no se dibuja (alfa < 0,01, escala nula, puntos inválidos…). `opciones`: `mallas` (tabla package:// →
## res://) e `intervalo_horneado_ms` (tope de re-horneado de listas y triángulos; 1 000 en la Vita).
static func aplicar(n: MeshInstance3D, m, opciones: Dictionary = {}) -> bool:
	var c := color(m)
	var ic := Paleta.indice(c)
	var pose: Transform3D = Prim.pose_godot(m.pose)
	var s = m.scale
	_piezas(n, false)
	var tipo := int(m.type)
	var se_ve := c.a > 0.01
	match tipo:
		ARROW:
			if m.points.size() >= 2:
				n.mesh = null
				n.transform = pose
				return _flecha_puntos(n, m, ic) and se_ve
			n.mesh = Prim.malla(Prim.FLECHA, ic)
			n.transform = Transform3D(pose.basis * Basis.from_scale(Vector3(absf(s.y) * ANCHO_FLECHA,
					absf(s.z) * ANCHO_FLECHA, absf(s.x))), pose.origin)
			return se_ve and s.x * s.y * s.z != 0.0
		CUBE, SPHERE, CYLINDER:
			n.mesh = Prim.malla(tipo, ic)                       # CUBO/ESFERA/CILINDRO = 1/2/3 (PrimitivasViz)
			n.transform = Transform3D(pose.basis * Basis.from_scale(Prim.escala_ros(s)), pose.origin)
			return se_ve and s.x * s.y * s.z != 0.0
		MESH_RESOURCE:
			var malla := malla_recurso(String(m.mesh_resource), opciones.get("mallas", {}))
			n.mesh = malla if malla != null else Prim.malla(Prim.CUBO, ic)
			n.transform = Transform3D(pose.basis * Basis.from_scale(Prim.escala_ros(s)), pose.origin)
			return se_ve and s.x * s.y * s.z != 0.0
		CUBE_LIST, SPHERE_LIST, TRIANGLE_LIST:
			n.transform = pose
			if m.points.is_empty():
				return false
			_hornear_si_cambia(n, m, ic, opciones.get("intervalo_horneado_ms", 0))
			return se_ve and n.mesh != null
	return false


## Flecha por 2 puntos (`arrow_marker.cpp:108-152`): cuerpo de diámetro scale.x, cabeza de diámetro scale.y y largo
## scale.z (0 ⇒ 0,23·d); 1 punto o d ≈ 0 ⇒ no se dibuja. Piezas hijas en el marco del marcador × pose.
static func _flecha_puntos(n: MeshInstance3D, m, ic: int) -> bool:
	var a := punto(m.points[0])
	var b := punto(m.points[1])
	var d := b - a
	var dist := d.length()
	if dist < 1e-6 or m.scale.x + m.scale.y == 0.0:
		return false
	var cabeza: float = clampf(m.scale.z, 0.0, dist) if m.scale.z != 0.0 else PUNTA_RELATIVA * dist
	var dn := d / dist
	var arriba := Vector3.UP if absf(dn.y) < 0.99 else Vector3.RIGHT
	var mira := Basis.looking_at(dn, arriba)                       # −Z a lo largo de d
	_piezas(n, true)
	var cuerpo := n.get_node("cuerpo") as MeshInstance3D
	var punta := n.get_node("cabeza") as MeshInstance3D
	cuerpo.mesh = Prim.malla(Prim.CILINDRO, ic)
	punta.mesh = Prim.malla(Prim.CONO, ic)
	var largo := dist - cabeza
	# CILINDRO unidad: eje +Y, alto 1 centrado → girado a −Z y escalado (diámetro, diámetro, largo).
	cuerpo.transform = Transform3D(mira * GIRO_CILINDRO * Basis.from_scale(Vector3(absf(m.scale.x), largo,
			absf(m.scale.x))), a + dn * (largo * 0.5))
	cuerpo.visible = largo > 1e-6
	# CONO unidad: vértice en el origen y base en −Z ⇒ mirando hacia −d con el vértice en la punta b.
	var atras := Basis.looking_at(-dn, arriba)
	punta.transform = Transform3D(atras * Basis.from_scale(Vector3(absf(m.scale.y), absf(m.scale.y), cabeza)), b)
	return true


## Hijos «cuerpo» y «cabeza» (sin owner, doc 35): se crean la primera vez y se ocultan si no hacen falta.
static func _piezas(n: MeshInstance3D, usar: bool) -> void:
	var c := n.get_node_or_null("cuerpo") as MeshInstance3D
	if c == null:
		if not usar:
			return
		for h in ["cuerpo", "cabeza"]:
			var p := MeshInstance3D.new()
			p.name = h
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(p)
		c = n.get_node("cuerpo") as MeshInstance3D
	c.visible = usar
	(n.get_node("cabeza") as MeshInstance3D).visible = usar


## Re-hornea solo si cambian los datos (firma) y como mucho cada `intervalo_ms`: cada malla nueva gasta arena en
## la Vita (H9), que no la libera. Con el intervalo sin cumplir se conserva la malla anterior (meta «pendiente»).
static func _hornear_si_cambia(n: MeshInstance3D, m, ic: int, intervalo_ms: int) -> void:
	var firma := hash([int(m.type), ic, m.scale.x, m.scale.y, m.scale.z, _plano(m.points), _plano_c(m.colors)])
	if n.mesh != null and n.get_meta("firma", 0) == firma:
		n.set_meta("pendiente", false)
		return
	var ahora := Time.get_ticks_msec()
	if n.mesh != null and n.has_meta("t_horneado") and ahora - int(n.get_meta("t_horneado")) < intervalo_ms:
		n.set_meta("pendiente", true)
		return
	n.mesh = hornear(m, ic)
	n.set_meta("firma", firma)
	n.set_meta("t_horneado", ahora)
	n.set_meta("pendiente", false)


static func _plano(pts) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for q in pts:
		out.append_array([q.x, q.y, q.z])
	return out


static func _plano_c(cs) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for c in cs:
		out.append_array([c.r, c.g, c.b])
	return out


## Malla horneada de CUBE_LIST / SPHERE_LIST (≤ MAX_HORNEADO elementos, 12 / 8 tri cada uno) o TRIANGLE_LIST
## (≤ MAX_TRIANGULOS), en el marco del marcador × pose, con la UV de la paleta por elemento o triángulo.
static func hornear(m, ic: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var t := PackedVector2Array()
	var pts := puntos(m)
	var cols := colores(m)
	var tipo := int(m.type)
	if tipo == TRIANGLE_LIST:
		var n_tri := mini(pts.size() / 3, MAX_TRIANGULOS)
		for k in n_tri:
			var ick := Paleta.indice(cols[3 * k]) if cols.size() > 0 else ic
			Prim._tri(v, t, pts[3 * k], pts[3 * k + 1], pts[3 * k + 2], ick)
	else:
		var lados := Prim.escala_ros(m.scale)
		for k in mini(pts.size(), MAX_HORNEADO):
			var ick := Paleta.indice(cols[k]) if cols.size() > 0 else ic
			if tipo == CUBE_LIST:
				Prim._caja(v, t, pts[k], lados, ick)
			else:
				_octaedro(v, t, pts[k], lados * 0.5, ick)
	if v.is_empty():
		return null
	return Prim._malla_de(v, t)


## Octaedro de semiejes `h` centrado en `c` (la «esfera» de la Vita, 8 tri; como PrimitivasViz._octaedro).
static func _octaedro(v: PackedVector3Array, t: PackedVector2Array, c: Vector3, h: Vector3, ic: int) -> void:
	var ejes := [Vector3(h.x, 0, 0), Vector3(0, 0, h.z), Vector3(-h.x, 0, 0), Vector3(0, 0, -h.z)]
	for i in 4:
		var a: Vector3 = ejes[i]
		var b: Vector3 = ejes[(i + 1) % 4]
		Prim._tri(v, t, c + Vector3(0, h.y, 0), c + a, c + b, ic)
		Prim._tri(v, t, c + Vector3(0, -h.y, 0), c + b, c + a, ic)


## MESH_RESOURCE: `uri` → ruta `res://` (tabla de la app, o la propia uri si ya es `res://`) → Mesh (o la primera
## malla de una escena horneada). Sin malla: null y un aviso por uri (el llamador dibuja un CUBO). El GLTF en
## caliente (`GLTFDocument`) no entra en V8 [decisión V8].
static func malla_recurso(uri: String, tabla: Dictionary) -> Mesh:
	var ruta: String = tabla.get(uri, uri if uri.begins_with("res://") else "")
	if _cache_mallas.has(ruta):
		return _cache_mallas[ruta]
	var malla: Mesh = null
	if ruta != "" and ResourceLoader.exists(ruta):
		var r = load(ruta)
		if r is Mesh:
			malla = r
		elif r is PackedScene:
			var raiz: Node = (r as PackedScene).instantiate()
			for h in [raiz] + raiz.find_children("*", "MeshInstance3D", true, false):
				if h is MeshInstance3D and (h as MeshInstance3D).mesh != null:
					malla = (h as MeshInstance3D).mesh
					break
			raiz.free()
	if malla == null:
		if not _avisados.has(uri):
			_avisados[uri] = true
			push_warning("FabricaMarcadores: MESH_RESOURCE «%s» sin malla horneada; se dibuja un cubo" % uri)
		return null
	_cache_mallas[ruta] = malla
	return malla
