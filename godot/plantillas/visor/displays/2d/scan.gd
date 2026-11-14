extends "res://comun/visor/display_ros_2d.gd"
## Scan (V3; doc 36a §4.5.1): `sensor_msgs/LaserScan` en la planta 2D. UN lote por mensaje: un triángulo por punto
## en una sola llamada `canvas_item_add_triangle_array`, redibujado solo al llegar mensaje (H16–H17).
##   PC   : `topic` (LaserScan) → `_procesar`. Filtro REP-117 que descarta NaN y ±Inf (trampa T2) y tabla de
##          direcciones cos/sin recalculada solo si cambian angle_min, angle_increment o n (docs/31:210).
##   Vita : `<p>/scan_compacto` (Int16MultiArray, cm, 0 = sin dato; ≤ 180 rayos, 384 B, 10 Hz) →
##          `_procesar_compacto` con `VitaRelay.scan_puntos` (también con tabla de direcciones).
## Dato intermedio común: PackedVector2Array de puntos en METROS del marco del sensor.
## El compacto no trae cabecera: `frame_id` (p. ej. "base_scan") dice el marco del sensor; "" = marco fijo.
## Cupo (D7; doc 36 §7.2): ≤ 360 *quads* de la zona «sensores_2d»; en la Vita se dibujan como mucho `cupo` puntos.

const VitaRelay = preload("res://comun/vita_relay.gd")

@export var lado_px := 3.0
@export var color := Color(1.0, 0.2, 0.2)

var puntos_dibujados := 0                # para el HUD y las pruebas
var _dirs := PackedVector2Array()
var _clave := Vector3.INF
var _v := PackedVector2Array()
var _c := PackedColorArray()
var _idx := PackedInt32Array()


static func nombre_display() -> String:
	return "Scan"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/LaserScan"])


func _init() -> void:
	hz = 10.0
	topic_vita = "scan_compacto"
	tipo_vita = "std_msgs/msg/Int16MultiArray"


func _procesar(msg):
	var r = msg.ranges                                    # PackedFloat32Array
	var n: int = r.size()
	var a0: float = msg.angle_min
	var inc: float = msg.angle_increment
	var mn: float = msg.range_min
	var mx: float = msg.range_max
	var clave := Vector3(a0, inc, n)
	if clave != _clave:                                   # cos/sin solo si cambia la geometría del escáner
		_clave = clave
		_dirs.resize(n)
		for i in n:
			_dirs[i] = Vector2.from_angle(a0 + i * inc)
	var out := PackedVector2Array()
	out.resize(n)
	var k := 0
	for i in n:
		var d: float = r[i]
		if not (d >= mn and d <= mx):                     # ±Inf y NaN fuera (REP-117, trampa T2)
			continue
		out[k] = _dirs[i] * d
		k += 1
	out.resize(k)
	return out


func _procesar_compacto(msg):
	return VitaRelay.scan_puntos(msg)


func _pintar(puntos) -> void:
	var n: int = puntos.size()
	if visor != null and visor.en_vita:
		n = mini(n, cupo)                                 # cupo en quads = puntos (D7)
	puntos_dibujados = n
	_v.resize(n * 3)
	_c.resize(n * 3)
	_c.fill(color)
	for i in n:
		var p := px(puntos[i])
		_v[3 * i] = p + Vector2(0, -lado_px)
		_v[3 * i + 1] = p + Vector2(lado_px, lado_px)
		_v[3 * i + 2] = p + Vector2(-lado_px, lado_px)
	if _idx.size() != n * 3:
		_idx.resize(n * 3)
		for i in n * 3:
			_idx[i] = i
	queue_redraw()


func _draw() -> void:
	if _v.size() > 0:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _v, _c)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 360}
