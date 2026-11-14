extends "res://comun/visor/display_ros_3d.gd"
## Mapa 3D (V3; doc 36a §4.6.1): `nav_msgs/OccupancyGrid` como UN *quad* texturizado en el suelo (2 triángulos,
## 1 instancia de la capa «mundo»: HMI y Viz 12; D7). Defecto del PC; en la Vita el defecto es la planta 2D.
##   PC   : `topic` (OccupancyGrid, *latched*) → imagen con la rampa «map» de RViz en CPU (MapaTextura).
##   Vita : `<p>/mapa_tesela` + `<p>/mapa_meta` → imagen del relay (LUT + `blit_rect`), subida ≤ 4 Hz.
## V14 (solo PC): el *shader* de dos texturas de la ficha mapas#0 (índices R8 + paleta 256×1 de RViz,
## `MapaTextura.material_espacial`), sin bucle por celda. En la Vita (sin *shaders*) y en el camino compacto, material
## propio unshaded, NEAREST y sin *culling* (H15) con la textura ya en colores.
## El *quad* se reconstruye solo si cambia la geometría (resolución, tamaño u origen).

const MapaTextura = preload("res://comun/visor/mapa_textura.gd")

@export var altura := 0.01                              # m sobre el suelo (que no pelee con el suelo del mundo)
@export var alfa := 1.0
@export_enum("map", "costmap", "raw") var esquema := 0

var mapa = MapaTextura.new()
var _vis: MeshInstance3D
var _mat: StandardMaterial3D
var _geo := []                                          # geometría con la que se construyó el quad
var _version_aplicada := -1


static func nombre_display() -> String:
	return "Mapa3D"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["nav_msgs/msg/OccupancyGrid"])


func _init() -> void:
	capa = "mundo"
	latched = true
	hz = 0.0
	topic_vita = "mapa_tesela"
	tipo_vita = "std_msgs/msg/UInt8MultiArray"


func conectar(v) -> void:
	canal.coalescer = false                             # teselas: entregar todas
	mapa.esquema = esquema
	mapa.gpu = not v.en_vita                            # V14: paleta en *shader* solo en el PC
	if v.usa_compactos() and topic_vita != "":
		latched = false                                 # la tesela del relay es best effort
	super.conectar(v)
	if cupo <= 0:
		return
	if _vis == null:
		_mat = StandardMaterial3D.new()
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		if alfa < 1.0:
			_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_mat.albedo_color = Color(1, 1, 1, alfa)
		_vis = MeshInstance3D.new()
		_vis.name = "Quad"
		_vis.visible = false
		add_child(_vis)                                 # sin owner (doc 35)
	if estado == "ok" and canal.compacto:
		mapa.conectar_compacto(v)


func desconectar() -> void:
	mapa.cerrar()
	super.desconectar()


func _procesar(msg):
	return mapa.de_grid(msg)


func _procesar_compacto(msg):
	return mapa.de_tesela(msg)


func _pintar(d) -> void:
	mapa.aplicar(d)
	_actualizar()


func _process(dt: float) -> void:
	super._process(dt)
	if canal.compacto:
		mapa.tic(false)                                 # el informe de teselas lo da el display 2D
	_actualizar()


## Aplica textura y, si cambió la geometría, reconstruye el quad (2 triángulos, UV a la imagen norte arriba).
func _actualizar() -> void:
	if _vis == null or mapa.version == _version_aplicada or mapa.textura == null or mapa.ancho <= 0:
		return
	_version_aplicada = mapa.version
	var m: Material = _mat
	if mapa.indices:
		m = mapa.material_espacial(alfa)                # V14: índices + paleta en el *shader*
	elif _mat.albedo_texture != mapa.textura:
		_mat.albedo_texture = mapa.textura
	if _vis.material_override != m:
		_vis.material_override = m
	var geo := [mapa.res, mapa.ancho, mapa.alto, mapa.origen, mapa.yaw]
	if geo != _geo:
		_geo = geo
		_vis.mesh = _quad(mapa.ancho * mapa.res, mapa.alto * mapa.res)
		var q := Quaternion(Vector3(0, 0, 1), mapa.yaw)
		_vis.transform = Transform3D(Basis(rclgd.ros_to_godot_quat(q)),
				rclgd.ros_to_godot_vector(Vector3(mapa.origen.x, mapa.origen.y, altura)))
	_vis.visible = true


## Quad de w × h m en el plano XY de ROS con la esquina (0,0) en el origen local. La imagen tiene el norte (y
## máxima) en la fila 0: UV (x/w, 1 − y/h).
static func _quad(w: float, h: float) -> ArrayMesh:
	var esquinas := [Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]
	var v := PackedVector3Array()
	var t := PackedVector2Array()
	for i in [0, 1, 2, 0, 2, 3]:
		var e: Vector2 = esquinas[i]
		v.append(rclgd.ros_to_godot_vector(Vector3(e.x, e.y, 0.0)))
		t.append(Vector2(e.x / w, 1.0 - e.y / h))
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	a[Mesh.ARRAY_TEX_UV] = t
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


## Textura que pinta el quad (la del StandardMaterial3D o la de índices del *shader*). Para pruebas y HUD.
func textura_actual() -> Texture2D:
	if _vis == null or _vis.material_override == null:
		return null
	if _vis.material_override is ShaderMaterial:
		return _vis.material_override.get_shader_parameter("datos")
	return _mat.albedo_texture


func _coste() -> Dictionary:
	return {"instancias": 1, "triangulos": 2, "quads": 0}
