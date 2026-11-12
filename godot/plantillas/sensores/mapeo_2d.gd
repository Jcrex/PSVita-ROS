extends Node3D

const Contexto = preload("res://comun/ros/contexto_ros.gd")
const Util = preload("res://comun/ros/util_ros.gd")
const VC1 = preload("res://comun/ros/vc1.gd")

@export var scan_topic := "/scan"
@export var map_topic := "/map"
@export var topic_meta_compacto := ""
@export var topic_tesela_compacta := ""
@export var resolucion := 0.25
@export var tamano := 128
## Marco del mapa. Las coordenadas son las del mundo de Godot = marco de odometría; nadie publica map→odom,
## así que por defecto se usa el marco de odometría del robot (revisión R2-A7.3: antes «map» sin TF).
@export var frame_id := "odom"
## Centro del mapa (ROS, m). Con `centrar_en_spawn` se toma la posición inicial del robot (R2-A7.2: el mapa
## de 32 m centrado en el origen no cubría el spawn de RB-KAIROS+ y G1 en y = −17 m).
@export var centro_ros := Vector2.ZERO
@export var centrar_en_spawn := true
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
var _valores := PackedInt32Array()   # -1 o 0..100 por celda; se actualiza solo en las celdas tocadas
var _lidar: Node                     # sensor lidar_2d padre: se lee en memoria (R4-C9)
var _ultimo_seq := 0
var _scan_ros: RosMsg
var _transform_ros := Transform3D.IDENTITY
var _acumulado := 0.0
var _tesela := 0
var _version := 0
var _meta_pendiente := true
var _origen := Vector2.ZERO
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
	var centro := centro_ros
	if centrar_en_spawn and robot != null:
		var p := Util.vector_ros(robot.global_position)
		centro = Vector2(p.x, p.y)
	# Origen alineado a la resolución para que las celdas no dependan de decimales del spawn.
	_origen = (centro - Vector2.ONE * tamano * resolucion * 0.5).snapped(Vector2.ONE * resolucion)
	_ocupacion.resize(tamano * tamano)
	_ocupacion.fill(0.0)
	_valores.resize(tamano * tamano)
	_valores.fill(-1)
	# VC/1: version = ÉPOCA del mapa (igual en meta y teselas), no un contador de teselas (R4 §1.2).
	_version = int(Time.get_unix_time_from_system()) % 65536
	var padre := get_parent()
	if padre != null and padre.has_method("ultimo_scan"):
		_lidar = padre
	else:
		# Respaldo: si el padre no es un lidar_2d, suscribirse por ROS como antes.
		_sub = contexto.suscripcion(scan_topic, "sensor_msgs/msg/LaserScan", _on_scan, true)
	if not _en_vita and contexto.transporte != "xrce":
		_msg = RosMsg.from_type("nav_msgs/msg/OccupancyGrid")
		_pub_mapa = contexto.publicador(map_topic, "nav_msgs/msg/OccupancyGrid", false, true)
		_msg.info.resolution = resolucion
		_msg.info.width = tamano
		_msg.info.height = tamano
		_msg.info.origin.position.x = _origen.x
		_msg.info.origin.position.y = _origen.y
		_msg.info.origin.orientation.w = 1.0
	if topic_meta_compacto != "":
		_pub_meta = contexto.publicador(topic_meta_compacto, "std_msgs/msg/Float32MultiArray", false, true)
	if topic_tesela_compacta != "":
		_pub_tesela = contexto.publicador(topic_tesela_compacta, "std_msgs/msg/UInt8MultiArray", true)


func _on_scan(msg) -> void:
	_scan_ros = msg
	_transform_ros = global_transform


## Vacía el mapa y abre una época nueva (los clientes VC/1 descartan las teselas de la anterior).
func reiniciar_mapa() -> void:
	_ocupacion.fill(0.0)
	_valores.fill(-1)
	_version = (_version + 1) % 65536
	_meta_pendiente = true


func _physics_process(dt: float) -> void:
	_acumulado += dt
	var periodo := 1.0 / hz
	if _acumulado < periodo:
		return
	# Mismo esquema que sensor_base (R2-C1): restar el periodo en vez de ponerlo a cero (perdía el resto).
	_acumulado -= periodo
	if _acumulado > periodo:
		_acumulado = 0.0
	_integrar_nuevo()
	if _pub_mapa != null:
		_publicar_mapa()
	if _pub_meta != null and _meta_pendiente:
		_publicar_meta()   # VC/1: la meta (fiable + TRANSIENT_LOCAL) solo se publica al cambiar
	if _pub_tesela != null:
		_publicar_tesela()


func _integrar_nuevo() -> void:
	if _lidar != null:
		var s: Dictionary = _lidar.call("ultimo_scan")
		# R2-M6: integrar cada barrido una sola vez y con la pose del instante del barrido.
		if s.seq == _ultimo_seq or s.rangos.is_empty():
			return
		_ultimo_seq = s.seq
		_integrar(s.rangos, s.angulo_min, s.incremento, s.rango_min, s.rango_max, s.transform)
	elif _scan_ros != null:
		_integrar(_scan_ros.ranges, _scan_ros.angle_min, _scan_ros.angle_increment, _scan_ros.range_min,
			_scan_ros.range_max, _transform_ros)
		_scan_ros = null


func _indice(x: int, y: int) -> int:
	return y * tamano + x


func _celda(p: Vector2) -> Vector2i:
	return Vector2i(floori((p.x - _origen.x) / resolucion), floori((p.y - _origen.y) / resolucion))


func _marcar(x: int, y: int, ocupado: bool) -> void:
	if x < 0 or y < 0 or x >= tamano or y >= tamano:
		return
	var i := _indice(x, y)
	_ocupacion[i] = clampf(_ocupacion[i] + (0.85 if ocupado else -0.4), -4.0, 4.0)
	_valores[i] = clampi(int(round(100.0 / (1.0 + exp(-_ocupacion[i])))), 0, 100)


func _integrar(rangos: PackedFloat32Array, angulo_min: float, incremento: float, rango_min: float,
		rango_max: float, t: Transform3D) -> void:
	# R2-A7.1: el punto final se calcula con la base 3D completa del láser y se proyecta a XY. Antes se usaba
	# yaw + a, que solo vale con el láser boca arriba: los SICK del RB-KAIROS+ (pitch π) daban un mapa en espejo.
	var base := t.basis.orthonormalized()
	var o := Util.vector_ros(t.origin)
	var p0 := Vector2(o.x, o.y)
	var c0 := _celda(p0)
	for i in rangos.size():
		var r: float = rangos[i]
		var impacto := true
		if is_inf(r) and r > 0.0:
			r = rango_max   # sin retorno (REP-117): espacio libre hasta el alcance, sin celda ocupada
			impacto = false
		elif is_nan(r) or is_inf(r) or r < rango_min:
			continue
		elif r >= rango_max * 0.995:
			r = rango_max
			impacto = false
		var a := angulo_min + i * incremento
		var d := Util.vector_ros(base * Vector3(-sin(a), 0.0, -cos(a)))
		var p1 := p0 + Vector2(d.x, d.y) * r
		var c1 := _celda(p1)
		var dx := absi(c1.x - c0.x)
		var sx := 1 if c0.x < c1.x else -1
		var dy := -absi(c1.y - c0.y)
		var sy := 1 if c0.y < c1.y else -1
		var err := dx + dy
		var c := c0
		while c != c1:
			_marcar(c.x, c.y, false)
			var e2 := 2 * err
			if e2 >= dy:
				err += dy
				c.x += sx
			if e2 <= dx:
				err += dx
				c.y += sy
		if impacto:
			_marcar(c1.x, c1.y, true)


func _publicar_mapa() -> void:
	contexto.sello(_msg.header)
	_msg.header.frame_id = frame_id
	_msg.info.map_load_time = _msg.header.stamp
	_msg.data = _valores
	_pub_mapa.publish(_msg)


func _publicar_meta() -> void:
	var m = RosMsg.from_type("std_msgs/msg/Float32MultiArray")
	var nt := ceili(float(tamano) / VC1.TESELA)
	m.data = PackedFloat32Array([resolucion, tamano, tamano, _origen.x, _origen.y, nt, nt, _version])
	_pub_meta.publish(m)
	_meta_pendiente = false


func _publicar_tesela() -> void:
	var nt := ceili(float(tamano) / VC1.TESELA)
	var tx := _tesela % nt
	var ty := int(_tesela / nt) % nt
	_tesela = (_tesela + 1) % (nt * nt)
	var m = RosMsg.from_type("std_msgs/msg/UInt8MultiArray")
	# VC/1: mismo empaquetado y umbrales que vita_relay.py (libre ≤ 25, ocupado ≥ 65, resto desconocido).
	m.data = VC1.empaquetar_tesela(_valores, tamano, tamano, tx, ty, _version)
	_pub_tesela.publish(m)
