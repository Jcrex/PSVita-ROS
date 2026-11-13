extends "res://comun/visor/display_ros_hud.gd"
## Mando (doc 36a §4.4.7, ficha hmi#1): `sensor_msgs/msg/Joy` dibujado: dos sticks (circunferencia + punto) y una
## fila de botones. Best effort, 128 B (8 ejes, 17 botones) a 20 Hz en origen; aquí se dibuja a ≤ `hz`.
## Convención de `joy`: stick arriba e izquierda = +1 [I] ⇒ en pantalla x = −eje (con `invertir_x`) e y = −eje.
## SIN esquema en la Vita (`sensor_msgs/Joy` no está en `generar_esquemas.py`): estado «sin esquema» hasta V5.
## La fuente `/vita/joy` (la Vita publica su mando, negando X e Y por T23) es una herramienta que publica: V7.
##
## Coste: 2 circunferencias de `segmentos` + 2 puntos + ≤ MAX_BOTONES rectángulos llenos (los apagados también
## llenos y oscuros: un marco costaría 4) = 2·16 + 2 + 17 = 51 *quads* (catálogo ≈ 70).
##
## datos = [PackedFloat32Array ejes, PackedInt32Array botones].

const MAX_BOTONES := 17
const COLOR_APAGADO := Color(0.25, 0.27, 0.32)

@export var pares_sticks: Array[Vector2i] = [Vector2i(0, 1), Vector2i(3, 4)]   # índices (x, y) en `axes`
@export var invertir_x := true
@export_range(6, 48) var segmentos := 16


static func nombre_display() -> String:
	return "Joy"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/Joy"])


func _init() -> void:
	topic = "/joy"
	tipo = "sensor_msgs/msg/Joy"


func _procesar(msg):
	# `axes` float32[] y `buttons` int32[] llegan como Packed*Array (o Array): se copian sin anotar el tipo de
	# origen (T6) y se limpian aquí, una vez por mensaje entregado.
	var ejes_m = msg.axes
	var bot_m = msg.buttons
	var ejes := PackedFloat32Array()
	ejes.resize(ejes_m.size())
	for i in ejes_m.size():
		var a := float(ejes_m[i])
		ejes[i] = clampf(a, -1.0, 1.0) if not is_nan(a) else 0.0     # NaN = eje sin dato (T2)
	var botones := PackedInt32Array()
	var nb := mini(bot_m.size(), MAX_BOTONES)
	botones.resize(nb)
	for i in nb:
		botones[i] = 1 if int(bot_m[i]) != 0 else 0
	return [ejes, botones]


func _eje(ejes: PackedFloat32Array, i: int) -> float:
	return ejes[i] if i >= 0 and i < ejes.size() else 0.0


func _dibujar() -> bool:
	var base := color_estado(COLOR_TEXTO)
	var punto := color_estado(COLOR_ACENTO)
	var radio := minf(size.y * 0.3, size.x * 0.2)
	var ejes := PackedFloat32Array()
	var botones := PackedInt32Array()
	if datos != null:
		ejes = datos[0]
		botones = datos[1]
	var n := mini(pares_sticks.size(), 2)
	for k in n:
		var c := Vector2(size.x * (0.25 + 0.5 * k), size.y * 0.4)
		arco(c, radio, segmentos, base)
		if datos != null:
			var sx := _eje(ejes, pares_sticks[k].x) * (-1.0 if invertir_x else 1.0)
			var p := c + Vector2(sx, -_eje(ejes, pares_sticks[k].y)) * radio
			rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), punto)
	if botones.size() > 0:
		var paso := size.x / float(botones.size())
		for b in botones.size():
			rect(Rect2(b * paso + 1, size.y - 14, paso - 2, 12), color_estado(COLOR_OK) if botones[b] != 0 else COLOR_APAGADO)
	return true


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 2 * segmentos + 2 + MAX_BOTONES}
