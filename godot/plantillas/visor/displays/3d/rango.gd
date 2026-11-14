extends "res://comun/visor/display_ros_3d.gd"
## Rango 3D (V5; doc 36a §4.4.4, V geom#21; `range_display.cpp getDisplayedRange`): CONO unidad (vértice en el
## origen, base en z = −1 de Godot = +X de ROS, radio 0,5) escalado a (ancho, ancho, r), ancho = 2·r·tan(fov/2).
## r fuera de [min_range, max_range] ⇒ oculto, salvo −Inf en un sensor de distancia fija (min = max) ⇒ min_range.
## Filtro que descarta NaN (T2): `r >= min and r <= max`. Cono OPACO en PC y Vita (sin orden de transparencias en
## el port, docs/31 §2.4). Color por `radiation_type` (0 ultrasonido, 1 infrarrojo). `Range` = 52 B, hasta 60 Hz.
## Dato intermedio: `[largo, ancho, radiation_type]` o 0.0 (= ocultar). Capa «poses»: 1 instancia, 16 tri.

const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")

@export var color_ultrasonido := Color(0.2, 0.6, 1.0)
@export var color_infrarrojo := Color(1.0, 0.3, 0.2)

var _cono: MeshInstance3D
var _tipo_rad := 0
var largo := 0.0                                # último rango mostrado (m); 0 = oculto


static func nombre_display() -> String:
	return "Rango"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/Range"])


func _init() -> void:
	capa = "poses"
	hz = 10.0


func conectar(v) -> void:
	super.conectar(v)
	if cupo > 0 and _cono == null:
		_cono = Prim.instancia(Prim.CONO, color_ultrasonido)
		_cono.visible = false
		add_child(_cono)


func _procesar(msg):
	var r: float = msg.range
	var mn: float = msg.min_range
	var mx: float = msg.max_range
	var fov: float = msg.field_of_view
	if not is_finite(fov):
		return 0.0
	if r >= mn and r <= mx:
		pass
	elif mn == mx and is_inf(r) and r < 0.0:
		r = mn
	else:
		return 0.0                                     # fuera de rango o NaN: ocultar
	return [r, 2.0 * r * tan(clampf(fov, 0.0, 3.0) * 0.5), int(msg.radiation_type)]


func _pintar(d) -> void:
	if _cono == null:
		return
	var ok := d is Array and float(d[0]) > 0.0
	_cono.visible = ok
	largo = float(d[0]) if ok else 0.0
	if not ok:
		return
	if int(d[2]) != _tipo_rad:
		_tipo_rad = int(d[2])
		_cono.mesh = Prim.malla(Prim.CONO, Paleta.indice(color_infrarrojo if _tipo_rad == 1 else color_ultrasonido))
	var ancho := maxf(float(d[1]), 1e-3)
	_cono.transform = Transform3D(Basis.from_scale(Vector3(ancho, ancho, float(d[0]))), Vector3.ZERO)


func _coste() -> Dictionary:
	return {"instancias": 1, "triangulos": Prim.TRIANGULOS[Prim.CONO], "quads": 0}
