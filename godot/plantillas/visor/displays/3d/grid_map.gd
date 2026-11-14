extends "res://comun/visor/display_ros_3d.gd"
## GridMap (V14, `solo_pc`; doc 36a §4.6.6 mapas#7–8): `grid_map_msgs/GridMap` → malla de alturas de la capa
## `capa_altura` coloreada por `capa_color` (o por la propia altura) con MapasColor, en UNA `ArrayMesh` (2 triángulos
## por cuadrado de 4 celdas válidas; color por vértice, solo PC).
## Geometría [I: `grid_map_core` y `GridMapRosConverter` de ROS 2]:
##   - `info.pose` = CENTRO del mapa; `length_x/y` en m; filas = length_x/res (eje x), columnas = length_y/res;
##   - el índice (0, 0) es la esquina +x,+y: la celda (i, j) está en centro + (length_x/2 − (i+½)·res,
##     length_y/2 − (j+½)·res);
##   - `data[k]` es una `Float32MultiArray` *column-major* (`dim[0]` = «column_index», `dim[1]` = «row_index»):
##     valor (i, j) = data[j_b · filas + i_b] con el búfer circular i_b = (i + outer_start_index) % filas,
##     j_b = (j + inner_start_index) % columnas.
## NaN = celda vacía (sin triángulos). Coste ≈ 30–60 ms por 100×100 en GDScript [I] → `hz` = 1 por defecto (ficha).
## En la Vita no existe (relay a raster 2D, doc 36a §4.6.6).

const MapasColor = preload("res://comun/visor/mapas_color.gd")

@export var capa_altura := "elevation"
@export var capa_color := ""                   # "" = la altura
@export_enum("arcoiris", "turbo", "gris") var mapa_color := 1
@export var rango_auto := true
@export var rango_color := Vector2(0.0, 1.0)
@export var max_celdas := 250000

var filas := 0
var columnas := 0
var triangulos := 0
var motivo := ""
var us_ultimo := 0
var rango_usado := Vector2.ZERO
var _vis: MeshInstance3D
var _mat: StandardMaterial3D


static func nombre_display() -> String:
	return "GridMap"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["grid_map_msgs/msg/GridMap"])


func _init() -> void:
	tipo = "grid_map_msgs/msg/GridMap"
	capa = "mundo"
	solo_pc = true
	hz = 1.0


func conectar(v) -> void:
	super.conectar(v)
	if estado == "desactivado" or estado == "sin cupo" or _vis != null:
		return
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.vertex_color_is_srgb = true          # MapasColor da colores sRGB
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_vis = MeshInstance3D.new()
	_vis.name = "Malla"
	_vis.material_override = _mat
	add_child(_vis)                            # sin owner (doc 35)


## Valores de una capa como matriz desenrollada fila a fila: v[i·columnas + j] (i = 0 en +x, j = 0 en +y).
static func desenrollar(datos: PackedFloat32Array, f: int, c: int, outer: int, inner: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(f * c)
	if datos.size() < f * c:
		out.fill(NAN)
		return out
	for i in f:
		var ib := (i + outer) % f
		for j in c:
			out[i * c + j] = datos[((j + inner) % c) * f + ib]
	return out


## GridMap → {posiciones (ROS, PackedVector3Array por celda, NaN si vacía), valores color, filas, columnas} o {}.
func _procesar(msg):
	var t0 := Time.get_ticks_usec()
	var info = msg.info
	var res := float(info.resolution)
	if res <= 0.0:
		motivo = "resolución nula"
		return null
	var f := int(round(float(info.length_x) / res))
	var c := int(round(float(info.length_y) / res))
	if f <= 0 or c <= 0 or f * c > max_celdas:
		motivo = "tamaño no válido o > max_celdas"
		return null
	var capas := PackedStringArray(msg.layers)
	var ia := capas.find(capa_altura)
	if ia < 0:
		motivo = "sin capa «%s»" % capa_altura
		return null
	var ic := capas.find(capa_color) if capa_color != "" else ia
	if ic < 0:
		ic = ia
	var outer := int(msg.outer_start_index)
	var inner := int(msg.inner_start_index)
	var arr: Array = msg.data
	var alt := desenrollar(PackedFloat32Array(arr[ia].data), f, c, outer, inner)
	var col := alt if ic == ia else desenrollar(PackedFloat32Array(arr[ic].data), f, c, outer, inner)
	var p = info.pose.position
	var o = info.pose.orientation
	var q := Quaternion(o.x, o.y, o.z, o.w)
	q = q.normalized() if q.length_squared() > 1e-6 else Quaternion.IDENTITY
	var centro := Vector3(p.x, p.y, p.z)
	var pos := PackedVector3Array()
	pos.resize(f * c)
	var hx := float(info.length_x) * 0.5
	var hy := float(info.length_y) * 0.5
	for i in f:
		for j in c:
			var z := alt[i * c + j]
			pos[i * c + j] = centro + q * Vector3(hx - (i + 0.5) * res, hy - (j + 0.5) * res, z)
	us_ultimo = Time.get_ticks_usec() - t0
	return {"pos": pos, "alt": alt, "col": col, "filas": f, "columnas": c}


func _pintar(d) -> void:
	if _vis == null:
		return
	var t0 := Time.get_ticks_usec()
	filas = d["filas"]
	columnas = d["columnas"]
	var pos: PackedVector3Array = d["pos"]
	var alt: PackedFloat32Array = d["alt"]
	var col: PackedFloat32Array = d["col"]
	var r := rango_color
	if rango_auto:
		var mn := INF
		var mx := -INF
		for x in col:
			if is_finite(x):
				mn = minf(mn, x)
				mx = maxf(mx, x)
		r = Vector2(mn, mx if mx > mn else mn + 1.0) if mn <= mx else Vector2(0, 1)
	rango_usado = r
	var esc := 255.0 / maxf(r.y - r.x, 1e-6)
	var v := PackedVector3Array()
	var cs := PackedColorArray()
	var vg := PackedVector3Array()
	vg.resize(pos.size())
	var cg := PackedColorArray()
	cg.resize(pos.size())
	for k in pos.size():
		vg[k] = rclgd.ros_to_godot_vector(pos[k])
		cg[k] = MapasColor.color(mapa_color, int((col[k] - r.x) * esc)) if is_finite(col[k]) else Color.BLACK
	for i in filas - 1:
		for j in columnas - 1:
			var a := i * columnas + j
			var b := a + 1
			var e := a + columnas
			var g := e + 1
			if not (is_finite(alt[a]) and is_finite(alt[b]) and is_finite(alt[e]) and is_finite(alt[g])):
				continue
			v.append_array([vg[a], vg[e], vg[b], vg[b], vg[e], vg[g]])
			cs.append_array([cg[a], cg[e], cg[b], cg[b], cg[e], cg[g]])
	triangulos = v.size() / 3
	if v.is_empty():
		_vis.mesh = null
		return
	var arrs := []
	arrs.resize(Mesh.ARRAY_MAX)
	arrs[Mesh.ARRAY_VERTEX] = v
	arrs[Mesh.ARRAY_COLOR] = cs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
	_vis.mesh = m
	us_ultimo += Time.get_ticks_usec() - t0


func _coste() -> Dictionary:
	return {"instancias": 1, "triangulos": 0, "quads": 0}
