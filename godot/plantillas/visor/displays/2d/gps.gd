extends "res://comun/visor/display_ros_2d.gd"
## GPS en planta (V5; doc 36a §4.4.3, V geom#20): rastro ENU local (plano tangente desde el primer fix) con
## `draw_polyline` + círculo de 2σ coloreado por estado (rojo NO_FIX, verde FIX, azul SBAS/GBAS). Sin teselas de
## fondo (OSM en el PC y prehorneadas en la Vita quedan para más adelante). `NavSatFix` = 125 B, directo.
## TRAMPA: grados en float32 pierden ~1 m (1e-5°): el origen se guarda en `float` de GDScript (64 bit) y se pasa a
## metros ANTES de meterlo en un Vector2. El marco del display es el fijo (`frame_id` = `visor.marco_fijo` si la
## escena no pone otro): el GPS no tiene TF a `map` salvo `navsat_transform` [I].
## Dato intermedio: Vector2 (este, norte) en m. Cupo: `max_puntos` + 24 *quads* (rastro + círculo).

const Paleta = preload("res://comun/visor/paleta_viz.gd")
const R_TIERRA := 6378137.0                     # WGS84, radio ecuatorial (m)

@export var max_puntos := 100
@export var tol_pos := 0.5                      # m: el rastro solo crece si el fix se aleja esto
@export var color := Color(0.2, 0.8, 1.0)

var lat0 := NAN                                 # float de GDScript = 64 bit; NO Vector2
var lon0 := 0.0
var estado_fix := -1
var sigma := 0.0
var ultimo := Vector2.ZERO
var _rastro := PackedVector2Array()             # m ENU (este, norte)
var _rastro_px := PackedVector2Array()


static func nombre_display() -> String:
	return "Gps"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/NavSatFix"])


func _init() -> void:
	hz = 5.0


func conectar(v) -> void:
	if frame_id == "":
		frame_id = v.marco_fijo
	super.conectar(v)


func _procesar(msg):
	estado_fix = int(msg.status.status)
	var lat: float = msg.latitude
	var lon: float = msg.longitude
	if estado_fix < 0 or not (is_finite(lat) and is_finite(lon)):
		queue_redraw()                                  # NO_FIX: el círculo pasa a rojo
		return null
	if is_nan(lat0):
		lat0 = lat
		lon0 = lon
	var este: float = deg_to_rad(lon - lon0) * R_TIERRA * cos(deg_to_rad(lat0))
	var norte: float = deg_to_rad(lat - lat0) * R_TIERRA
	var c: PackedFloat64Array = msg.position_covariance
	sigma = 0.0
	if int(msg.position_covariance_type) > 0 and c.size() >= 5 and is_finite(c[0]) and is_finite(c[4]):
		sigma = sqrt(maxf(maxf(c[0], c[4]), 0.0))
	return Vector2(este, norte)


func _pintar(p) -> void:
	ultimo = p
	var limite := max_puntos
	if visor != null and visor.en_vita:
		limite = mini(max_puntos, maxi(cupo - 24, 1))
	if _rastro.is_empty() or _rastro[-1].distance_to(p) > tol_pos:
		_rastro.append(p)
		while _rastro.size() > limite:
			_rastro.remove_at(0)
	_rastro_px.resize(_rastro.size())
	for i in _rastro.size():
		_rastro_px[i] = px(_rastro[i])
	queue_redraw()


func _draw() -> void:
	if _rastro_px.is_empty():
		return
	if _rastro_px.size() >= 2:
		draw_polyline(_rastro_px, color, -1.0)
	var col: Color = Paleta.ERROR if estado_fix < 0 else (Paleta.OK if estado_fix == 0 else Paleta.color(Paleta.AZUL))
	draw_arc(px(ultimo), maxf(2.0 * sigma * visor.px_por_m, 3.0), 0.0, TAU, 24, col, -1.0)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": max_puntos + 24}
