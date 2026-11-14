extends "res://comun/visor/display_ros_2d.gd"
## Mapa en planta (V3; doc 36a §4.6.1): `nav_msgs/OccupancyGrid` como UNA textura (`draw_texture_rect`), norte
## arriba. Defecto en la Vita (D7); el 3D (`displays/3d/mapa.gd`) es el defecto del PC.
##   PC   : `topic` (OccupancyGrid, *latched*) → `_procesar` → índices R8 + rampa «map» de RViz en un *shader*
##          `canvas_item` (V14, `MapaTextura.material_canvas`; sin bucle por celda).
##   Vita : `<p>/mapa_tesela` (UInt8MultiArray, 32×32 a 2 bit, ≤ 20/s) + `<p>/mapa_meta` (F+TL) → teselas en la
##          imagen del relay con LUT + `blit_rect` (docs/31 §4.4); textura subida ≤ 4 Hz y redibujo solo si cambia.
## Dato intermedio común: el diccionario de MapaTextura (`img`, `res`, `ancho`, `alto`, `origen`, `yaw`).
## Medida: en la Vita (o con `-- perfil`) escribe cada 5 s `[visor-mapa] teselas= media_us= max_us=` (gate de V3:
## tesela ≤ 1,5 ms). Cupo: 1 *quad*.
## V11: con un display Costmap (`displays/2d/costmap.gd`) que apunte aquí (`sobre_mapa`), en la Vita este display dibuja
## la textura COMPUESTA (mapa + costmap en CPU, `visor/costmap_textura.gd`): sigue siendo 1 *quad*.

const MapaTextura = preload("res://comun/visor/mapa_textura.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")

@export var alfa := 0.85
@export_enum("map", "costmap", "raw") var esquema := 0

var mapa = MapaTextura.new()
var _version_dibujada := -1
var _informar := false
var costmap_encima = null                               # V11: CostmapTextura que se compone sobre este mapa (o null)


static func nombre_display() -> String:
	return "Mapa"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["nav_msgs/msg/OccupancyGrid"])


func _init() -> void:
	latched = true                                      # /map: fiable + TRANSIENT_LOCAL (llega aunque se conecte tarde)
	hz = 0.0                                            # teselas: entregar todas (cada una es distinta)
	topic_vita = "mapa_tesela"
	tipo_vita = "std_msgs/msg/UInt8MultiArray"


func conectar(v) -> void:
	canal.coalescer = false                             # «el último gana» perdería teselas
	mapa.esquema = esquema
	mapa.gpu = not v.en_vita                            # V14: índices + paleta en *shader* solo en el PC
	if v.usa_compactos() and topic_vita != "":
		latched = false                                 # la tesela del relay es best effort (fiable no casaría)
	super.conectar(v)
	_informar = v.en_vita or OS.get_cmdline_user_args().has("perfil")
	if estado == "ok" and canal.compacto:
		mapa.conectar_compacto(v)                       # la meta va aparte, *latched* (F+TL)


func desconectar() -> void:
	mapa.cerrar()
	super.desconectar()


func _procesar(msg):
	return mapa.de_grid(msg)


func _procesar_compacto(msg):
	var d = mapa.de_tesela(msg)
	if costmap_encima != null and d != null:            # V11: región del mapa que hay que recomponer
		var b: PackedByteArray = msg.data
		costmap_encima.marcar_base(costmap_encima.rect_tesela_mapa(b[2], b[3], mapa.relay.ancho, mapa.relay.alto))
	return d


func _pintar(d) -> void:
	mapa.aplicar(d)
	_redibujar_si_cambia()


func _process(dt: float) -> void:
	super._process(dt)
	if canal.compacto:
		if _compone():
			if costmap_encima.tic_compuesta(mapa.relay.mapa_img, mapa.relay.resolucion, mapa.relay.origen):
				mapa.version += 1
		else:
			mapa.tic(_informar)
	_redibujar_si_cambia()


## V11: ¿se dibuja la composición mapa + costmap? (camino compacto, con imagen de mapa y meta de costmap)
func _compone() -> bool:
	return costmap_encima != null and costmap_encima.tiene_datos() and mapa.relay.mapa_img != null


func _redibujar_si_cambia() -> void:
	if mapa.version != _version_dibujada:
		_version_dibujada = mapa.version
		# V14: con la textura de índices (PC) el color lo pone el *shader*; con la compuesta o la del relay, nada.
		var m: Material = mapa.material_canvas() if (mapa.indices and not (canal.compacto and _compone())) else null
		if material != m:
			material = m
		queue_redraw()


func _draw() -> void:
	var tex: Texture2D = mapa.textura
	if canal.compacto and _compone() and costmap_encima.textura_compuesta != null:
		tex = costmap_encima.textura_compuesta          # V11: misma geometría que el mapa
	if tex == null or mapa.ancho <= 0:
		return
	var tam: Vector2 = Vector2(mapa.ancho, mapa.alto) * mapa.res * visor.px_por_m
	# Esquina (0,0) del OccupancyGrid = abajo a la izquierda de la imagen (norte arriba); giro del origen si lo hay.
	draw_set_transform(px(mapa.origen), -mapa.yaw)
	draw_texture_rect(tex, Rect2(Vector2(0, -tam.y), tam), false, Color(1, 1, 1, alfa))
	draw_set_transform(Vector2.ZERO)


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 1}
