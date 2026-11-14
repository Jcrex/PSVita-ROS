extends "res://comun/visor/display_ros_hud.gd"
## Cajas 2D (V10; doc 36a §4.8.4; sentencia W13 D12): rectángulos con etiqueta y % de score sobre la imagen de la
## pestaña Cámara, escalados de px de la imagen ORIGINAL al sitio donde `imagen` (hud/imagen.gd) pintó la suya.
##   PC   : `vision_msgs/Detection2DArray` directo, FIABLE y profundidad 1 (3 detecciones ≈ 1 377 B; doc 36 §6); la
##          mejor hipótesis de cada detección; `ancho_imagen` × `alto_imagen` = tamaño de la imagen original.
##   Vita : `<p>/detecciones` (Float32, best effort, 5 Hz; cab. común + [ancho, alto] + [clase, score, cx, cy, w, h]·n,
##          n ≤ 18) + `<p>/det_clases` (String *latched*, suscripción auxiliar, `ClasesDeteccion`).
## Dato intermedio común: [Vector2 tamaño de la imagen original, Array de [Rect2 px imagen, etiqueta (String o índice
## de clase), score]]. El nombre de un índice se resuelve al dibujar (la lista de clases puede llegar después).
## Cupo (doc 36 §7.2): ≤ `max_quads` (150): 4 por caja (marco) y las etiquetas mientras quepan (cortas: ≤ `max_car`).

const Clases = preload("res://comun/visor/clases_deteccion.gd")
const Vc1 = preload("res://comun/ros/vc1.gd")

@export var imagen: Control                   # hud/imagen.gd: cajas sobre su imagen; null = todo este widget
@export var ancho_imagen := 640.0             # PC directo: la detección no trae el tamaño de la imagen
@export var alto_imagen := 480.0
@export var umbral_score := 0.3
@export var max_cajas := 18
@export var max_car := 8                      # caracteres del nombre de clase (+ « 99%»)
@export var max_quads := 150
@export var topic_vita_clases := "det_clases"

var clases = Clases.new()
var cajas_dibujadas := 0
var etiquetas_dibujadas := 0
var _cambios_clases := 0


static func nombre_display() -> String:
	return "Cajas2D"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["vision_msgs/msg/Detection2DArray"])


func _init() -> void:
	tipo = "vision_msgs/msg/Detection2DArray"
	topic_vita = "detecciones"
	tipo_vita = "std_msgs/msg/Float32MultiArray"
	hz = 10.0
	hz_vita = 5.0
	caducidad_s = 1.0


func conectar(v) -> void:
	# Directo (PC): FIABLE y profundidad 1 (no cabe en 488 B). Relay: AUTO = best effort (lo publica así).
	if fiabilidad == Canal.AUTO and not (v.usa_compactos() and topic_vita != ""):
		fiabilidad = Canal.FIABLE
		profundidad = 1
	super.conectar(v)
	if canal.compacto and canal.abierto() and topic_vita_clases != "":
		clases.abrir(v, topic_vita_clases)


func desconectar() -> void:
	clases.cerrar()
	super.desconectar()


func _process(dt: float) -> void:
	super._process(dt)
	clases.bombear()
	if clases.cambios != _cambios_clases:
		_cambios_clases = clases.cambios
		queue_redraw()


func _procesar(msg):
	var cajas := []
	for d in msg.detections:
		var etiqueta := String(d.get_member("id"))
		var score := 1.0
		var primera := true
		for r in d.results:
			var h = r.hypothesis
			if primera or float(h.score) > score:
				etiqueta = String(h.class_id)
				score = float(h.score)
				primera = false
		var b = d.bbox
		var e := [0, score, float(b.center.position.x), float(b.center.position.y), float(b.size_x), float(b.size_y)]
		if score >= umbral_score and Vc1._finito_percepcion(e):
			var s := Vector2(e[4], e[5])
			cajas.append([Rect2(Vector2(e[2], e[3]) - s * 0.5, s), etiqueta, score])
	cajas.sort_custom(func(a, b): return a[2] > b[2])
	return [Vector2(ancho_imagen, alto_imagen), cajas.slice(0, max_cajas)]


func _procesar_compacto(msg):
	var r: Dictionary = Vc1.leer_det2d(msg.data)
	if r.is_empty() or not (r.ancho > 0.0 and r.alto > 0.0):
		return null
	var cajas := []
	for e in r.cajas:
		if e[1] >= umbral_score and cajas.size() < max_cajas:
			var s := Vector2(e[4], e[5])
			cajas.append([Rect2(Vector2(e[2], e[3]) - s * 0.5, s), int(e[0]), float(e[1])])
	return [Vector2(r.ancho, r.alto), cajas]


## Zona del widget donde está la imagen (coordenadas locales).
func zona() -> Rect2:
	if imagen != null and is_instance_valid(imagen) and imagen.has_method("rect_imagen"):
		var r: Rect2 = imagen.rect_imagen()
		return Rect2(r.position + imagen.global_position - global_position, r.size)
	return Rect2(Vector2.ZERO, size)


func _dibujar() -> bool:
	cajas_dibujadas = 0
	etiquetas_dibujadas = 0
	if datos == null or (datos[0] as Vector2).x <= 0.0:
		return true
	var z := zona()
	var k: Vector2 = z.size / (datos[0] as Vector2)
	var lista: Array = datos[1]
	var n := mini(lista.size(), max_quads / 4)
	for i in n:                                           # primero todos los marcos (4 quads cada uno)
		var r: Rect2 = lista[i][0]
		marco(Rect2(z.position + r.position * k, r.size * k), color_estado(Clases.color_clase(_etiqueta(lista[i][1]))))
		cajas_dibujadas += 1
	for i in n:                                           # luego las etiquetas, mientras quepan
		var et := "%s %d%%" % [_etiqueta(lista[i][1]).left(max_car), roundi(lista[i][2] * 100.0)]
		if _q + et.length() > max_quads:
			break
		var r: Rect2 = lista[i][0]
		var p := z.position + r.position * k + Vector2(2, -2)
		texto(Vector2(p.x, maxf(p.y, z.position.y + TAM_TEXTO)), et,
				color_estado(Clases.color_clase(_etiqueta(lista[i][1]))), -1, 11)
		etiquetas_dibujadas += 1
	return true


func _etiqueta(e) -> String:
	return e if e is String else clases.nombre(int(e))


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": max_quads}
