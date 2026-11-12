extends "res://comun/ros/sensor_base.gd"

const Util = preload("res://comun/ros/util_ros.gd")

@export var resolucion := Vector2i(320, 240)
@export var resolucion_profundidad := Vector2i(80, 60)
@export var fov_vertical := 39.0
@export var near := 0.1
@export var far := 30.0
@export_flags_3d_render var mascara_render := 1048575
@export_flags_3d_physics var mascara_profundidad := 1
@export var publicar_raw := true
@export var publicar_comprimida := true
@export var publicar_profundidad := false
@export var calidad_jpeg := 0.65
@export var optical_frame := ""
@export var publicar_rgb_en_xrce := false
@export var publicar_profundidad_en_xrce := true
@export var resolucion_xrce := Vector2i(160, 120)
@export var resolucion_profundidad_xrce := Vector2i(40, 30)

var _viewport: SubViewport
var _camera: Camera3D
var _pub_info: RosPublisher
var _pub_raw: RosPublisher
var _pub_jpeg: RosPublisher
var _pub_depth: RosPublisher
var _pub_depth_info: RosPublisher
var _capturando := false


func _init() -> void:
	topic = "/camera/color"
	hz = 5.0
	hz_xrce = 1.0
	solo_pc = true


func _sensor_listo() -> void:
	if contexto.transporte == "xrce":
		publicar_raw = publicar_raw and publicar_rgb_en_xrce
		publicar_profundidad = publicar_profundidad and publicar_profundidad_en_xrce
		resolucion = resolucion_xrce
		resolucion_profundidad = resolucion_profundidad_xrce
		hz = minf(hz, hz_xrce)
	_pub_info = contexto.publicador(topic + "/camera_info", "sensor_msgs/msg/CameraInfo", false)
	if publicar_raw:
		_pub_raw = contexto.publicador(topic + "/image_raw", "sensor_msgs/msg/Image", false)
	if publicar_comprimida:
		_pub_jpeg = contexto.publicador(topic + "/image_raw/compressed", "sensor_msgs/msg/CompressedImage", false)
	if publicar_profundidad:
		var base_depth := topic.get_slice("/color", 0) + "/depth" if "/color" in topic else topic + "/depth"
		_pub_depth = contexto.publicador(base_depth + "/image_raw", "sensor_msgs/msg/Image", false)
		_pub_depth_info = contexto.publicador(base_depth + "/camera_info", "sensor_msgs/msg/CameraInfo", false)
	_viewport = SubViewport.new()
	_viewport.name = "CapturaROS"
	_viewport.size = resolucion
	_viewport.world_3d = get_viewport().world_3d
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.fov = fov_vertical
	_camera.near = near
	_camera.far = far
	_camera.cull_mask = mascara_render
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_viewport.add_child(_camera)
	var sync := RemoteTransform3D.new()
	add_child(sync)
	sync.remote_path = sync.get_path_to(_camera)


func _optical_frame() -> String:
	return optical_frame if optical_frame != "" else frame_id + "_optical"


func _listo_para_publicar() -> bool:
	return not _capturando


func _publicar() -> void:
	_capturando = true
	_capturar()


func _capturar() -> void:
	var stamp = contexto.nodo.now()
	if DisplayServer.get_name() != "headless":
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var imagen := _viewport.get_texture().get_image()
		if imagen != null and not imagen.is_empty():
			imagen.convert(Image.FORMAT_RGB8)
			if _pub_raw != null:
				var raw = RosMsg.from_type("sensor_msgs/msg/Image")
				raw.header.stamp = stamp
				raw.header.frame_id = _optical_frame()
				raw.height = resolucion.y
				raw.width = resolucion.x
				raw.encoding = "rgb8"
				raw.is_bigendian = 0
				raw.step = resolucion.x * 3
				raw.data = imagen.get_data()
				_pub_raw.publish(raw)
			if _pub_jpeg != null:
				var jpeg = RosMsg.from_type("sensor_msgs/msg/CompressedImage")
				jpeg.header.stamp = stamp
				jpeg.header.frame_id = _optical_frame()
				jpeg.format = "jpeg"
				jpeg.data = imagen.save_jpg_to_buffer(calidad_jpeg)
				_pub_jpeg.publish(jpeg)
	_publicar_info(_pub_info, stamp, resolucion)
	if publicar_profundidad:
		_publicar_depth(stamp)
	_capturando = false


func _publicar_info(p: RosPublisher, stamp, tam: Vector2i) -> void:
	if p == null:
		return
	var info = RosMsg.from_type("sensor_msgs/msg/CameraInfo")
	info.header.stamp = stamp
	info.header.frame_id = _optical_frame()
	info.width = tam.x
	info.height = tam.y
	info.distortion_model = "plumb_bob"
	info.d = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var fy := tam.y / (2.0 * tan(deg_to_rad(fov_vertical) / 2.0))
	var cx := tam.x * 0.5
	var cy := tam.y * 0.5
	var k := PackedFloat64Array([fy, 0.0, cx, 0.0, fy, cy, 0.0, 0.0, 1.0])
	var r := PackedFloat64Array([1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0])
	var proyeccion := PackedFloat64Array([fy, 0.0, cx, 0.0, 0.0, fy, cy, 0.0, 0.0, 0.0, 0.0, 1.0])
	info.k = k
	info.r = r
	info.set_member("p", proyeccion)
	p.publish(info)


func _publicar_depth(stamp) -> void:
	var w := resolucion_profundidad.x
	var h := resolucion_profundidad.y
	var datos := PackedByteArray()
	datos.resize(w * h * 4)
	var fy := h / (2.0 * tan(deg_to_rad(fov_vertical) / 2.0))
	var espacio := get_world_3d().direct_space_state
	var excluir: Array[RID] = []
	if robot is CollisionObject3D:
		excluir.append(robot.get_rid())
	for y in h:
		for x in w:
			var local := Vector3((x + 0.5 - w * 0.5) / fy, (y + 0.5 - h * 0.5) / fy, -1.0)
			var direccion := _camera.global_basis.orthonormalized() * local.normalized()
			var query := PhysicsRayQueryParameters3D.create(_camera.global_position,
				_camera.global_position + direccion * far, mascara_profundidad, excluir)
			var hit := espacio.intersect_ray(query)
			var z := 0.0
			if not hit.is_empty():
				z = _camera.global_position.distance_to(hit.position) * (-local.z) / local.length()
			datos.encode_float((y * w + x) * 4, z)
	var depth = RosMsg.from_type("sensor_msgs/msg/Image")
	depth.header.stamp = stamp
	depth.header.frame_id = _optical_frame()
	depth.height = h
	depth.width = w
	depth.encoding = "32FC1"
	depth.is_bigendian = 0
	depth.step = w * 4
	depth.data = datos
	_pub_depth.publish(depth)
	_publicar_info(_pub_depth_info, stamp, resolucion_profundidad)
