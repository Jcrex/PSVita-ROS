extends "res://comun/visor/display_ros_2d.gd"
## Costmap en planta (V11; doc 36a §4.6.2, doc 36 §5.3): `nav_msgs/OccupancyGrid` de un costmap de Nav2 con la
## paleta «costmap» de RViz (0 transparente, 1–98 azul → rojo, 99 cian inscrito, 100 magenta letal, −1 0x708986).
##   PC   : `topic` (OccupancyGrid, *latched*, p. ej. `/global_costmap/costmap`) → imagen con la rampa costmap
##          (MapaTextura, esquema costmap) dibujada ENCIMA del mapa (orden del árbol) con `alfa`.
##   Vita : `<p>/costmap_tesela` (UInt8MultiArray, 32×16 a 4 bit, ≤ 10/s) + `<p>/costmap_meta` (F+TL) →
##          CostmapTextura. Si `sobre_mapa` apunta a un display Mapa con mapa, el costmap se COMPONE EN CPU sobre
##          la imagen del mapa (una textura, 1 *quad*: la dibuja el Mapa y este display no dibuja nada); si no, dibuja
##          su propia textura con su geometría.
## Medida: en la Vita (o con `-- perfil`) escribe cada 5 s `[visor-costmap] teselas= descartadas= max_us=
## composicion_us=` (gate G-W13-M5: repaso ≤ 3 s, ≥ 30 FPS). Cupo: 1 *quad*.

const MapaTextura = preload("res://comun/visor/mapa_textura.gd")
const CostmapTextura = preload("res://comun/visor/costmap_textura.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")

@export var alfa := 0.7                                  # RViz: 0,7 en el display de costmap
@export var sobre_mapa: NodePath = ^"../Mapa"            # display Mapa sobre el que se compone en la Vita
@export var topic_meta_vita := "costmap_meta"

var mapa = MapaTextura.new()                             # PC: OccupancyGrid entero con la rampa costmap
var costmap = CostmapTextura.new()                       # Vita: teselas de 4 bit (+ composición)
var _destino: Node = null                                # el display Mapa que dibuja la composición
var _version_dibujada := -1
var _informar := false
var _t_informe := 0


static func nombre_display() -> String:
	return "Costmap"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["nav_msgs/msg/OccupancyGrid"])


func _init() -> void:
	latched = true                                       # Nav2: el costmap es fiable + TRANSIENT_LOCAL
	hz = 0.0                                             # teselas: entregar todas
	topic_vita = "costmap_tesela"
	tipo_vita = "std_msgs/msg/UInt8MultiArray"


func conectar(v) -> void:
	canal.coalescer = false
	mapa.esquema = Paleta.ESQUEMA_COSTMAP
	costmap.alfa = alfa
	if v.usa_compactos() and topic_vita != "":
		latched = false                                  # la tesela del relay es best effort
	super.conectar(v)
	_informar = v.en_vita or OS.get_cmdline_user_args().has("perfil")
	if estado == "ok" and canal.compacto:
		costmap.conectar(v, topic_meta_vita)
		var d := get_node_or_null(sobre_mapa)
		if d != null and "costmap_encima" in d:
			_destino = d
			d.costmap_encima = costmap


func desconectar() -> void:
	costmap.cerrar()
	if _destino != null and is_instance_valid(_destino) and _destino.costmap_encima == costmap:
		_destino.costmap_encima = null
	_destino = null
	super.desconectar()


func _procesar(msg):
	return mapa.de_grid(msg)


func _procesar_compacto(msg):
	return {} if costmap.de_tesela(msg) else null


func _pintar(d) -> void:
	if not canal.compacto:
		mapa.aplicar(d)
	_redibujar_si_cambia()


## ¿Lo dibuja el Mapa (composición)? Solo con costmap y con la imagen del mapa ya creada.
func compuesto() -> bool:
	return _destino != null and costmap.tiene_datos() and _destino.mapa.relay.mapa_img != null


func _process(dt: float) -> void:
	super._process(dt)
	if canal.compacto and not compuesto():
		costmap.tic_propia()                             # con Mapa, el tic de la composición lo hace el Mapa
	if _informar and canal.compacto:
		var ahora := Time.get_ticks_msec()
		if ahora - _t_informe >= 5000:
			_t_informe = ahora
			printerr("[visor-costmap] teselas=%d descartadas=%d max_us=%d composicion_us=%d compuesto=%s" % [
					costmap.teselas, costmap.descartadas, costmap.us_max, costmap.us_composicion, compuesto()])
	_redibujar_si_cambia()


func _redibujar_si_cambia() -> void:
	var v: int = costmap.version + mapa.version
	if v != _version_dibujada:
		_version_dibujada = v
		queue_redraw()


func _draw() -> void:
	var tex: Texture2D = null
	var res := 0.0
	var tam := Vector2.ZERO
	var org := Vector2.ZERO
	var giro := 0.0
	if canal != null and canal.compacto:
		if compuesto() or costmap.textura == null:
			return
		tex = costmap.textura
		res = costmap.res
		tam = Vector2(costmap.ancho, costmap.alto)
		org = costmap.origen
	else:
		if mapa.textura == null or mapa.ancho <= 0:
			return
		tex = mapa.textura
		res = mapa.res
		tam = Vector2(mapa.ancho, mapa.alto)
		org = mapa.origen
		giro = mapa.yaw
	var t: Vector2 = tam * res * visor.px_por_m
	draw_set_transform(px(org), -giro)
	# La alfa del costmap va en la LUT en la Vita (para que la composición sea la misma); en el PC, en el modulado.
	var a := 1.0 if canal.compacto else alfa
	draw_texture_rect(tex, Rect2(Vector2(0, -t.y), t), false, Color(1, 1, 1, a))
	draw_set_transform(Vector2.ZERO)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 1}
