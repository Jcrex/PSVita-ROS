extends "res://comun/visor/display_ros_hud.gd"
## Batería (doc 36a §4.4.6, ficha hmi#2): `sensor_msgs/msg/BatteryState` en la barra fija. Icono con relleno =
## `percentage` (0..1; NaN = no medido → `charge / capacity`), rojo si la salud es mala (`power_supply_health` 2–8)
## o por debajo de `umbral_bajo`; texto «% V A estado». Esquema ya en la Vita (`generar_esquemas.py:30`).
## Publica a 0,2–1 Hz (`plantillas/sensores/bateria.gd:15-16`) ⇒ `caducidad_s = 15` (rqt usa lo mismo).
## Coste: marco 4 + borne 1 + relleno 1 + texto ≤ MAX_CAR = 34 *quads* (catálogo ≈ 40).
##
## datos = [pct (0..1 o NaN), texto, alarma].

const ESTADO := ["?", "carga", "descarga", "sin carga", "llena"]   # POWER_SUPPLY_STATUS_* (0..4)
const MAX_CAR := 28

@export var umbral_bajo := 0.2
@export var ancho_icono := 44.0


static func nombre_display() -> String:
	return "Bateria"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["sensor_msgs/msg/BatteryState"])


func _init() -> void:
	caducidad_s = 15.0


func _procesar(msg):
	var pct := float(msg.percentage)
	var cap := float(msg.capacity)
	# NaN se descarta con comparaciones «positivas» (T2): `cap > 0` es falso con NaN.
	if not (pct >= 0.0 and pct <= 1.0):
		pct = clampf(float(msg.charge) / cap, 0.0, 1.0) if cap > 0.0 and not is_nan(float(msg.charge)) else NAN
	var st := int(msg.power_supply_status)
	var salud := int(msg.power_supply_health)
	var alarma := (salud >= 2 and salud <= 8) or (pct < umbral_bajo)   # NaN < x es falso: sin % no hay alarma
	var txt := "%s V %s A %s" % [num(float(msg.voltage)), num(float(msg.current), "%+.1f"),
			ESTADO[st] if st >= 0 and st < ESTADO.size() else "?"]
	return [pct, txt, alarma]


func _dibujar() -> bool:
	var alto := size.y
	var cuerpo := Rect2(2, 3, ancho_icono - 6, alto - 6)
	var blanco := color_estado(COLOR_TEXTO)
	marco(cuerpo, blanco)
	rect(Rect2(ancho_icono - 4, alto * 0.35, 3, alto * 0.3), blanco)
	if datos == null:
		texto(Vector2(ancho_icono + 4, alto - 7), "bat ...", blanco, MAX_CAR)
		return true
	var pct: float = datos[0]
	var alarma: bool = datos[2]
	var c := color_estado(COLOR_ERROR if alarma else COLOR_OK)
	var pct_txt := "—"
	if not is_nan(pct):
		rect(Rect2(cuerpo.position + Vector2(2, 2), Vector2((cuerpo.size.x - 4) * pct, cuerpo.size.y - 4)), c)
		pct_txt = "%d%%" % roundi(pct * 100.0)
	texto(Vector2(ancho_icono + 4, alto - 7), "%s %s" % [pct_txt, datos[1]], c if alarma else blanco, MAX_CAR)
	return true


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 6 + MAX_CAR}
