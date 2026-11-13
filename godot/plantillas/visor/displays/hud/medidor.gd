extends "res://comun/visor/display_ros_hud.gd"
## Medidor (doc 36a §4.4.5, fichas hmi#3–6): un escalar con unidades, barra con umbral y *sparkline*. Un solo script;
## cada tipo es configuración del `.tscn`:
##
##   | Tipo                            | campo               | escala | unidad | minimo–maximo (aviso) | esquema Vita |
##   | sensor_msgs/msg/Temperature      | temperature         | 1      | °C     | −10–60 (45)           | NO (V5)      |
##   | sensor_msgs/msg/FluidPressure    | fluid_pressure      | 0,01   | hPa    | 950–1050 (1040)       | sí           |
##   | sensor_msgs/msg/Illuminance      | illuminance         | 1      | lx     | 0–2000 (1500)         | NO (V5)      |
##   | sensor_msgs/msg/RelativeHumidity | relative_humidity   | 100    | %      | 0–100 (80)            | NO (V5)      |
##
## Sin esquema `.rsch` el canal no suscribe y el estado es «sin esquema: …» (T20); entran con `TIPOS_VISOR` (V5).
## Pestaña Estado: 6 medidores ≤ 240 *quads* ⇒ ≤ 40 cada uno: fondo 1 + barra 1 + texto ≤ MAX_CAR + sparkline
## `muestras − 1` (una polilínea fina = 1 comando, H17). Con `muestras` = 24 sale 40 justos (catálogo: 60 muestras,
## que pasaban de 70 *quads*; decisión conservadora V4 anotada en visor/README.md).

const MAX_CAR := 14

@export var etiqueta := "Temp"
@export var campo := "temperature"
@export var escala := 1.0
@export var unidad := "°C"
@export var minimo := -10.0
@export var maximo := 60.0
@export var aviso := 45.0
@export_range(2, 120) var muestras := 24
@export var formato := "%.1f"

var _serie := PackedFloat32Array()


static func nombre_display() -> String:
	return "Medidor"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/Temperature", "sensor_msgs/msg/FluidPressure",
			"sensor_msgs/msg/Illuminance", "sensor_msgs/msg/RelativeHumidity"])


func _procesar(msg):
	# `get_member` y no `msg.get(campo)`: portable rclgd ↔ ros2_vita y sin choques con métodos de Object (T1).
	var v := float(msg.get_member(campo)) * escala
	if is_nan(v) or is_inf(v):
		return NAN                                 # «no medido»: se pinta «—» y no entra en la serie (T2)
	_serie.append(v)
	while _serie.size() > muestras:
		_serie.remove_at(0)
	return v


## Color por umbral, como rqt_robot_monitor: < aviso OK, < maximo AVISO, resto ERROR (también < minimo: fuera de rango).
func color_valor(v: float) -> Color:
	if not (v >= minimo):
		return COLOR_ERROR
	return COLOR_OK if v < aviso else (COLOR_AVISO if v < maximo else COLOR_ERROR)


func _dibujar() -> bool:
	rect(Rect2(Vector2.ZERO, size), COLOR_FONDO)
	if datos == null:
		texto(Vector2(4, 14), "%s ..." % etiqueta, color_estado(COLOR_TEXTO), MAX_CAR)
		return true
	var v: float = datos
	if is_nan(v):
		texto(Vector2(4, 14), "%s — %s" % [etiqueta, unidad], color_estado(COLOR_TEXTO), MAX_CAR)
		return true
	var c := color_estado(color_valor(v))
	var f := clampf(inverse_lerp(minimo, maximo, v), 0.0, 1.0) if maximo > minimo else 0.0
	rect(Rect2(0, size.y - 6, size.x * f, 6), c)
	texto(Vector2(4, 14), "%s %s %s" % [etiqueta, num(v, formato), unidad], c, MAX_CAR)
	if _serie.size() > 1:
		var pts := PackedVector2Array()
		pts.resize(_serie.size())
		var alto := maxf(size.y - 26.0, 1.0)
		for i in _serie.size():
			var fi := clampf(inverse_lerp(minimo, maximo, _serie[i]), 0.0, 1.0) if maximo > minimo else 0.0
			pts[i] = Vector2(size.x * i / maxf(1.0, muestras - 1.0), 18.0 + alto * (1.0 - fi))
		polilinea(pts, c)
	return true


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 2 + MAX_CAR + maxi(muestras - 1, 0)}
