extends Node3D

const Contexto = preload("res://comun/ros/contexto_ros.gd")
const Util = preload("res://comun/ros/util_ros.gd")

@export var scan_topic := "/scan"
@export var map_topic := "/map"
@export var topic_meta_compacto := ""
@export var topic_tesela_compacta := ""
@export var resolucion := 0.25
@export var tamano := 128
@export var hz := 1.0
@export var hz_vita := 1.0
@export var hz_xrce := 1.0
@export var habilitado := true

var contexto: RefCounted
var robot: Node3D
var _sub: RosSubscriber
var _pub_mapa: RosPublisher
var _pub_meta: RosPublisher
var _pub_tesela: RosPublisher
var _msg: RosMsg
var _ocupacion := PackedFloat32Array()
var _conocida := PackedByteArray()
var _scan: RosMsg
var _acumulado := 0.0
var _tesela := 0
var _version := 0
var _en_vita := false


func _ready() -> void:
	_en_vita = OS.has_feature("vita")
	if _en_vita:
		hz = hz_vita
	if contexto != null and contexto.transporte == "xrce":
		hz = minf(hz, hz_xrce)
	if not habilitado or contexto == null or contexto.nodo == null:
		set_physics_process(false)
		return
	_ocupacion.resize(tamano * tamano)
	_ocupacion.fill(0.0)
	_conocida.resize(tamano * tamano)
	_conocida.fill(0)
	_sub = contexto.suscripcion(scan_topic, "sensor_msgs/msg/LaserScan", _on_scan, true)
	if not _en_vita and contexto.transporte != "xrce":
		_msg = RosMsg.from_type("nav_msgs/msg/OccupancyGrid")
		_pub_mapa = contexto.publicador(map_topic, "nav_msgs/msg/OccupancyGrid", false, true)
		_msg.info.resolution = resolucion
		_msg.info.width = tamano
		_msg.info.height = tamano
		_msg.info.origin.position.x = -tamano * resolucion * 0.5
		_msg.info.origin.position.y = -tamano * resolucion * 0.5
		_msg.info.origin.orientation.w = 1.0
	if topic_meta_compacto != "":
		_pub_meta = contexto.publicador(topic_meta_compacto, "std_msgs/msg/Float32MultiArray", false, true)
	if topic_tesela_compacta != "":
		_pub_tesela = contexto.publicador(topic_tesela_compacta, "std_msgs/msg/UInt8MultiArray", true)


func _on_scan(msg) -> void:
	_scan = msg


func _physics_process(dt: float) -> void:
	_acumulado += dt
	if _acumulado < 1.0 / hz:
		return
	_acumulado = 0.0
	if _scan != null:
		_integrar_scan()
	if _pub_mapa != null:
		_publicar_mapa()
	if _pub_meta != null:
		_publicar_meta()
	if _pub_tesela != null:
		_publicar_tesela()


func _indice(x: int, y: int) -> int:
	return y * tamano + x


func _celda(p: Vector2) -> Vector2i:
	var origen := -tamano * resolucion * 0.5
	return Vector2i(floori((p.x - origen) / resolucion), floori((p.y - origen) / resolucion))


func _marcar(x: int, y: int, ocupado: bool) -> void:
	if x < 0 or y < 0 or x >= tamano or y >= tamano:
		return
	var i := _indice(x, y)
	_ocupacion[i] = clampf(_ocupacion[i] + (0.85 if ocupado else -0.4), -4.0, 4.0)
	_conocida[i] = 1


func _integrar_scan() -> void:
	var origen := Util.vector_ros(global_position)
	var yaw := Util.yaw_de_quat(Util.quat_ros(global_basis.get_rotation_quaternion()))
	var p0 := Vector2(origen.x, origen.y)
	var c0 := _celda(p0)
	var n: int = _scan.ranges.size()
	for i in n:
		var r: float = _scan.ranges[i]
		if not is_finite(r) or r < _scan.range_min:
			continue
		r = minf(r, _scan.range_max)
		var a: float = _scan.angle_min + i * _scan.angle_increment + yaw
		var p1 := p0 + Vector2(cos(a), sin(a)) * r
		var c1 := _celda(p1)
		var dx := absi(c1.x - c0.x)
		var sx := 1 if c0.x < c1.x else -1
		var dy := -absi(c1.y - c0.y)
		var sy := 1 if c0.y < c1.y else -1
		var err := dx + dy
		var c := c0
		while true:
			if c == c1:
				break
			_marcar(c.x, c.y, false)
			var e2 := 2 * err
			if e2 >= dy:
				err += dy
				c.x += sx
			if e2 <= dx:
				err += dx
				c.y += sy
		if r < _scan.range_max * 0.995:
			_marcar(c1.x, c1.y, true)


func _valor_celda(i: int) -> int:
	if _conocida[i] == 0:
		return -1
	var probabilidad := 1.0 / (1.0 + exp(-_ocupacion[i]))
	return clampi(int(round(probabilidad * 100.0)), 0, 100)


func _publicar_mapa() -> void:
	contexto.sello(_msg.header)
	_msg.header.frame_id = "map"
	_msg.info.map_load_time = _msg.header.stamp
	var datos := PackedInt32Array()
	datos.resize(tamano * tamano)
	for i in datos.size():
		datos[i] = _valor_celda(i)
	_msg.data = datos
	_pub_mapa.publish(_msg)


func _publicar_meta() -> void:
	var m = RosMsg.from_type("std_msgs/msg/Float32MultiArray")
	var origen := -tamano * resolucion * 0.5
	var nt := ceili(float(tamano) / 32.0)
	m.data = PackedFloat32Array([resolucion, tamano, tamano, origen, origen, nt, nt, _version])
	_pub_meta.publish(m)


func _publicar_tesela() -> void:
	var nt := ceili(float(tamano) / 32.0)
	var tx := _tesela % nt
	var ty := int(_tesela / nt) % nt
	_tesela = (_tesela + 1) % (nt * nt)
	var datos := PackedByteArray([_version & 255, (_version >> 8) & 255, tx, ty])
	datos.resize(260)
	for j in 32:
		for i in 32:
			var x := tx * 32 + i
			var y := ty * 32 + j
			var valor := 0
			if x < tamano and y < tamano:
				var v := _valor_celda(_indice(x, y))
				valor = 0 if v < 0 else (2 if v >= 65 else 1)
			var k := j * 32 + i
			datos[4 + (k >> 2)] |= valor << ((k & 3) * 2)
	var m = RosMsg.from_type("std_msgs/msg/UInt8MultiArray")
	m.data = datos
	_pub_tesela.publish(m)
	_version = (_version + 1) % 65536
