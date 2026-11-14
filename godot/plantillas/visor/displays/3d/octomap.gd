extends "res://comun/visor/display_ros_3d.gd"
## Octomap (V14, `solo_pc`; doc 36a §4.6.6 mapas#9): `octomap_msgs/Octomap` → vóxeles ocupados en UNA
## `MultiMeshInstance3D` de cubos (color por altura con MapasColor, o el color de un `ColorOcTree`).
## Decodificador en GDScript (`decodificar`, estático y sin nodos: se prueba sin mensajes) de los dos formatos de
## `octomap::AbstractOcTree` [I: formato leído de `OccupancyOcTreeBase::readBinaryNode` y `OcTreeBase::readNodesRecurs`]:
##   - binario (`binary = true`, id `OcTree`): 2 B por nodo interior (hijos 0–3 y 4–7), 2 bit por hijo; valor
##     `(bits >> 2i) & 3`: 0 desconocido, 1 libre, 2 ocupado, 3 con hijos (octomap lo comenta como «01 ocupado» =
##     bit[2i] 0 y bit[2i+1] 1); recorrido en profundidad, hijos en orden 0..7;
##   - completo (`binary = false`, id `OcTree` u `OcTreeStamped`/`ColorOcTree`): por nodo `float` log-odds (+ 3 B de
##     color en `ColorOcTree`) + 1 B con un bit por hijo existente. Ocupado si log-odds > `umbral_logodds` (0 = p 0,5).
## Geometría: árbol de 16 niveles centrado en el origen (raíz de lado `res·2^16`); el hijo i se desplaza ±¼ del lado
## del padre en x (bit 0), y (bit 1), z (bit 2). Una hoja a profundidad d mide `res·2^(16−d)` (hojas podadas).
## Coste: ≈ 2–4 µs por nodo en GDScript [I] → `hz` = 0,2 por defecto (la ficha: «hilo o ≤ 0,2 Hz»); tope
## `max_voxeles`. En la Vita no existe (el relay mandaría los ocupados como `nube2d`, doc 36a §4.6.6).

const MapasColor = preload("res://comun/visor/mapas_color.gd")

const PROFUNDIDAD := 16

@export var max_voxeles := 200000
@export var umbral_logodds := 0.0
@export_enum("arcoiris", "turbo", "gris") var mapa_color := 0
@export var alturas := Vector2(-0.5, 3.0)       # z (m) de los extremos del mapa de color
@export var alfa := 1.0

var voxeles := 0
var nodos := 0
var motivo := ""
var us_ultimo := 0
var _mmi: MultiMeshInstance3D


static func nombre_display() -> String:
	return "Octomap"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray(["octomap_msgs/msg/Octomap"])


func _init() -> void:
	tipo = "octomap_msgs/msg/Octomap"
	capa = "mundo"
	solo_pc = true
	latched = true                             # octomap_server publica `octomap_binary` latched [I]
	hz = 0.2


func conectar(v) -> void:
	super.conectar(v)
	if estado == "desactivado" or estado == "sin cupo" or _mmi != null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var caja := BoxMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true     # el color de instancia llega por COLOR
	mat.vertex_color_is_srgb = true
	if alfa < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	caja.material = mat
	mm.mesh = caja
	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Voxeles"
	_mmi.multimesh = mm
	add_child(_mmi)                            # sin owner (doc 35)


## Octomap → {centros: PackedVector3Array (ROS, m), lados: PackedFloat32Array, colores: PackedColorArray (vacío si
## no es ColorOcTree), nodos} o {} si no se entiende.
static func decodificar(binario: bool, id: String, res: float, data: PackedByteArray, umbral := 0.0, max_v := 200000) -> Dictionary:
	var centros := PackedVector3Array()
	var lados := PackedFloat32Array()
	var colores := PackedColorArray()
	if res <= 0.0 or data.is_empty():
		return {}
	var color := id.begins_with("ColorOcTree")
	if not binario and not (id.begins_with("OcTree") or color):
		return {}
	var lado_raiz := res * pow(2.0, PROFUNDIDAD)
	var o := 0
	var n := 0
	# Pila de nodos por visitar: [centro, lado, profundidad, (completo) datos ya leídos].
	var pila: Array = [[Vector3.ZERO, lado_raiz, 0]]
	if binario:
		while not pila.is_empty():
			var nodo: Array = pila.pop_back()
			if o + 2 > data.size():
				return {}
			var bits := data[o] | (data[o + 1] << 8)
			o += 2
			n += 1
			var c: Vector3 = nodo[0]
			var s: float = nodo[1] * 0.5
			var hijos_internos: Array = []
			for i in 8:
				var b := (bits >> (2 * i)) & 3
				if b == 0 or b == 1:
					continue                       # desconocido o libre
				var cc := c + _desplazamiento(i) * (s * 0.5)
				if b == 2:
					if centros.size() < max_v:
						centros.append(cc)
						lados.append(s)
				else:
					hijos_internos.append([cc, s, int(nodo[2]) + 1])
			# Recorrido en profundidad con hijos en orden 0..7: se apilan al revés.
			for k in range(hijos_internos.size() - 1, -1, -1):
				pila.append(hijos_internos[k])
		return {"centros": centros, "lados": lados, "colores": colores, "nodos": n, "leidos": o}
	# Completo: valor (float) [+ color] + byte de hijos; recursivo en preorden.
	var por_nodo := 4 + (3 if color else 0) + 1
	while not pila.is_empty():
		var nodo: Array = pila.pop_back()
		if o + por_nodo > data.size():
			return {}
		var lo := data.decode_float(o)
		var col := Color.WHITE
		if color:
			col = Color8(data[o + 4], data[o + 5], data[o + 6])
		var hijos := data[o + por_nodo - 1]
		o += por_nodo
		n += 1
		var c: Vector3 = nodo[0]
		var s: float = nodo[1] * 0.5
		if hijos == 0:
			if lo > umbral and centros.size() < max_v:
				centros.append(c)
				lados.append(float(nodo[1]))
				if color:
					colores.append(col)
			continue
		for i in range(7, -1, -1):
			if hijos & (1 << i):
				pila.append([c + _desplazamiento(i) * (s * 0.5), s, int(nodo[2]) + 1])
	return {"centros": centros, "lados": lados, "colores": colores, "nodos": n, "leidos": o}


## Signo del desplazamiento del hijo i: bit 0 → x, bit 1 → y, bit 2 → z (computeChildCenter de octomap).
static func _desplazamiento(i: int) -> Vector3:
	return Vector3(1.0 if i & 1 else -1.0, 1.0 if i & 2 else -1.0, 1.0 if i & 4 else -1.0)


func _procesar(msg):
	var t0 := Time.get_ticks_usec()
	var data = msg.data
	var b: PackedByteArray = data if data is PackedByteArray else PackedInt32Array(data).to_byte_array()
	if not (data is PackedByteArray):                # int8[] como PackedInt32Array (T6): byte bajo de cada int32
		var tmp := Image.create_from_data(b.size() / 4, 1, false, Image.FORMAT_RGBA8, b)
		tmp.convert(Image.FORMAT_R8)
		b = tmp.get_data()
	var d := decodificar(bool(msg.binary), String(msg.id), float(msg.resolution), b, umbral_logodds, max_voxeles)
	us_ultimo = Time.get_ticks_usec() - t0
	if d.is_empty():
		motivo = "octomap no válido (id «%s»)" % String(msg.id)
		return null
	return d


func _pintar(d) -> void:
	if _mmi == null:
		return
	var centros: PackedVector3Array = d["centros"]
	var lados: PackedFloat32Array = d["lados"]
	var colores: PackedColorArray = d["colores"]
	nodos = d["nodos"]
	voxeles = centros.size()
	var mm := _mmi.multimesh
	mm.instance_count = voxeles
	var esc := 255.0 / maxf(alturas.y - alturas.x, 1e-6)
	for i in voxeles:
		var c := centros[i]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * lados[i]), rclgd.ros_to_godot_vector(c)))
		var col: Color = colores[i] if not colores.is_empty() else MapasColor.color(mapa_color, int((c.z - alturas.x) * esc))
		col.a = alfa
		mm.set_instance_color(i, col)
	_mmi.visible = voxeles > 0


func _coste() -> Dictionary:
	return {"instancias": 1, "triangulos": 0, "quads": 0}
