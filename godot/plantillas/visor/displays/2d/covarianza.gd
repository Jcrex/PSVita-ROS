extends "res://comun/visor/display_ros_2d.gd"
## Covarianza 2D en planta (V5; doc 36a §4.2.5, V geom#5; `covariance_visual.cpp`): elipse de posición de semiejes
## 2·√λ (bloque 2×2 x-y, 24 lados, `draw_polyline`) + abanico de yaw ±2σ (`draw_colored_polygon`) + punto central.
## Sin elipsoide translúcido (sin orden de transparencias en el port, docs/31 §2.4). La elipse vive en los ejes del
## `header.frame_id` y no gira con la pose [I].
##   PC y Vita : `PoseWithCovarianceStamped` (364 B, cabe en directo; AMCL `/amcl_pose`) → `_procesar`.
##   Vita (opc.): `<p>/pose_cov` = `[x, y, yaw, σxx, σxy, σyy, σyaw]` (⚖ D5.4; módulo `pose_cov` del relay, V9: las
##              varianzas cov[0], cov[1], cov[7], cov[35], `vc1.gd empaquetar_pose_cov`) → `_procesar_compacto`;
##              activo solo si la escena pone `topic_vita = "pose_cov"` (decisión V9: el directo de 364 B ya cabe).
## Dato intermedio: `[centro m, yaw, λ1, λ2, θ, σ_yaw]`. Cupo: 30 *quads*.

@export var escala_pos := 1.0
@export var color := Color(1.0, 0.4, 1.0)
@export var radio_abanico_m := 0.5

var datos = null                                 # último dato intermedio (pruebas)
var _elipse_px := PackedVector2Array()
var _abanico_px := PackedVector2Array()
var _c0 := Vector2.ZERO


static func nombre_display() -> String:
	return "Covarianza"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["geometry_msgs/msg/PoseWithCovarianceStamped"])


func _init() -> void:
	hz = 2.0
	tipo_vita = "std_msgs/msg/Float32MultiArray"


func _procesar(msg):
	var c: PackedFloat64Array = msg.pose.covariance
	if c.size() < 36:
		return null
	var p = msg.pose.pose
	var o = p.orientation
	var yaw := atan2(2.0 * (o.w * o.z + o.x * o.y), 1.0 - 2.0 * (o.y * o.y + o.z * o.z))
	return _elipse(Vector2(p.position.x, p.position.y), yaw, c[0], c[1], c[7], c[35])


func _procesar_compacto(msg):
	var d: PackedFloat32Array = msg.data
	return null if d.size() < 7 else _elipse(Vector2(d[0], d[1]), d[2], d[3], d[4], d[5], d[6])


## Autovalores 2×2 en forma cerrada: [[a, b], [b, dd]] → λ1 ≥ λ2 y ángulo θ del eje mayor.
func _elipse(p: Vector2, yaw: float, a: float, b: float, dd: float, var_yaw: float):
	if not (p.is_finite() and is_finite(yaw) and is_finite(a) and is_finite(b) and is_finite(dd) and is_finite(var_yaw)):
		return null                                                     # T2
	var h := sqrt(((a - dd) * 0.5) ** 2 + b * b)
	var l1 := maxf((a + dd) * 0.5 + h, 0.0)
	var l2 := maxf((a + dd) * 0.5 - h, 0.0)
	return [p, yaw, l1, l2, 0.5 * atan2(2.0 * b, a - dd), sqrt(maxf(var_yaw, 0.0))]


func _pintar(d) -> void:
	datos = d
	var centro: Vector2 = d[0]
	var ejes := Vector2(2.0 * sqrt(d[2]), 2.0 * sqrt(d[3])) * escala_pos
	_elipse_px.resize(25)
	for i in 25:
		var a := TAU * i / 24.0
		_elipse_px[i] = px(centro + Vector2(cos(a) * ejes.x, sin(a) * ejes.y).rotated(d[4]))
	_c0 = px(centro)
	_abanico_px.clear()
	var medio := minf(2.0 * float(d[5]), 3.0)        # ±2σ, recortado para que el abanico no se cierre sobre sí
	if medio > 1e-3:
		var r: float = radio_abanico_m * visor.px_por_m
		_abanico_px.append(_c0)
		for k in 7:
			var ang: float = d[1] - medio + 2.0 * medio * k / 6.0
			_abanico_px.append(_c0 + Vector2(cos(ang), -sin(ang)) * r)
	queue_redraw()


func _draw() -> void:
	if datos == null:
		return
	draw_polyline(_elipse_px, color, -1.0)
	if _abanico_px.size() >= 3:
		draw_colored_polygon(_abanico_px, Color(color, 0.5))
	else:                                                               # yaw sin incertidumbre: una raya
		var f: Vector2 = Vector2(cos(datos[1]), -sin(datos[1])) * radio_abanico_m * visor.px_por_m
		draw_line(_c0, _c0 + f, color, -1.0)
	draw_rect(Rect2(_c0 - Vector2(2, 2), Vector2(4, 4)), color)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 30}
