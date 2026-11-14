extends "res://comun/visor/herramienta_visor.gd"
## Interactuar (V14, solo PC; doc 36a §4.7.5 «Feedback», ficha mapas#27 con sus dos correcciones; ≈ Interact tool de
## RViz): con la herramienta activa, pulsar sobre un asa de un marcador interactivo de `cliente`
## (`displays/3d/im_cliente.gd`) y arrastrar mueve el marcador y publica `InteractiveMarkerFeedback` en
## `<ns>/feedback`:
##   MOUSE_DOWN (4) al pulsar · POSE_UPDATE (1) ≤ `hz_feedback` al arrastrar · POSE_UPDATE + MOUSE_UP (5) al soltar ·
##   BUTTON_CLICK (3) al soltar sobre un control BUTTON.
## QoS ⚖ C9: FIABLE y profundidad 1 en PC y Vita (el servidor suscribe con `rclcpp::QoS(1)` = fiable,
## `interactive_marker_server.hpp:87-88`; un publicador best effort no casaría). `header.frame_id` = marco del
## marcador (el servidor compara con el suyo) y la pose en ese marco.
## Arrastre según `interaction_mode` (rayo de cámara):
##   MOVE_AXIS: punto de la recta del eje más cercano al rayo · MOVE_PLANE / MOVE_ROTATE / MOVE_3D / MOVE_ROTATE_3D:
##   plano perpendicular al eje (MOVE_3D: plano de la pantalla) · ROTATE_AXIS / ROTATE_3D: ángulo alrededor del eje.
## `solo_pc`: la Vita no tiene servicios cliente (T-W4-9) y el cliente no existe allí (G-W13-M6 pendiente).

const IM = preload("res://comun/visor/displays/3d/im_cliente.gd")

const POSE_UPDATE := 1
const BUTTON_CLICK := 3
const MOUSE_DOWN := 4
const MOUSE_UP := 5

@export var cliente: Node3D                    # el display im_cliente.gd; su `ns` da el topic si `topic` = ""
@export var hz_feedback := 20.0
@export var radio_px := 24.0

var asa := {}                                  # asa agarrada (ver im_cliente.asa_en) o {}
var eventos: Array = []                        # tipos publicados (pruebas)
var _plano: Plane
var _inicio := Transform3D.IDENTITY
var _p0 := Vector3.ZERO                        # punto de agarre inicial (plano o recta)
var _t_ultimo := -1000000


static func nombre_herramienta() -> String:
	return "Interactuar"


func _init() -> void:
	tipo = "visualization_msgs/msg/InteractiveMarkerFeedback"
	fiabilidad = 0                             # FIABLE (corrección C9: mapas#27 lo tenía best effort)
	profundidad = 1                            # C9: 1 en los dos (la tabla genérica daría 5 en el PC)


func conectar(v) -> void:
	if topic == "" and cliente != null:
		topic = String(cliente.ns).trim_suffix("/") + "/feedback"
	if v.en_vita:
		estado = "desactivado"                 # solo PC (el cliente es `solo_pc`)
		visor = v
		return
	super.conectar(v)


func _entrada(e: InputEvent) -> bool:
	if cliente == null:
		return false
	var cam: Camera3D = _camara()
	if cam == null:
		return false
	# Corrección de check-only de mapas#27: `var pulsado: bool = …` (operandos Variant) y nada de `e.pressed` /
	# `e.position` sobre InputEvent sin estrechar (no compila): `is_pressed()` y `get("position")`.
	var boton: bool = (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT) or e is InputEventScreenTouch
	var pos: Vector2 = e.get("position") if "position" in e else Vector2.ZERO
	if boton and e.is_pressed() and asa.is_empty():
		asa = cliente.asa_en(cam, pos, radio_px)
		if asa.is_empty():
			return false
		cliente.arrastrando = asa["im"]
		_inicio = asa["inicio"]
		_preparar(cam, pos)
		_enviar(MOUSE_DOWN)
		return true
	if boton and not e.is_pressed() and not asa.is_empty():
		if asa["modo"] == IM.BUTTON:
			_enviar(BUTTON_CLICK)
		else:
			_enviar(POSE_UPDATE)
		_enviar(MOUSE_UP)
		cliente.arrastrando = ""
		asa = {}
		return true
	if not asa.is_empty() and (e is InputEventMouseMotion or e is InputEventScreenDrag):
		var g = _arrastre(cam, pos)
		if g != null:
			cliente.mover_global(asa["im"], g)
			var ahora := Time.get_ticks_msec()
			if ahora - _t_ultimo >= int(1000.0 / maxf(hz_feedback, 0.1)):
				_t_ultimo = ahora
				_enviar(POSE_UPDATE)
		return true
	return false


func _preparar(cam: Camera3D, p: Vector2) -> void:
	var eje: Vector3 = asa["eje"]
	var c: Vector3 = asa["centro"]
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	match asa["modo"]:
		IM.MOVE_AXIS:
			_p0 = _en_recta(o, d, c, eje)
		IM.MOVE_3D, IM.ROTATE_3D, IM.MOVE_ROTATE_3D:
			_plano = Plane(-cam.global_basis.z, c)
			var h = _plano.intersects_ray(o, d)
			_p0 = h if h != null else c
		_:
			_plano = Plane(eje, c)
			var h = _plano.intersects_ray(o, d)
			_p0 = h if h != null else c


## Pose global nueva del marcador para el puntero en `p`, o null.
func _arrastre(cam: Camera3D, p: Vector2):
	var o := cam.project_ray_origin(p)
	var d := cam.project_ray_normal(p)
	var eje: Vector3 = asa["eje"]
	var c: Vector3 = asa["centro"]
	match asa["modo"]:
		IM.MOVE_AXIS:
			var q := _en_recta(o, d, c, eje)
			return Transform3D(_inicio.basis, _inicio.origin + eje * eje.dot(q - _p0))
		IM.ROTATE_AXIS, IM.ROTATE_3D:
			var h = Plane(eje, c).intersects_ray(o, d)
			if h == null:
				return null
			var a: Vector3 = (_p0 - c).normalized()
			var b: Vector3 = ((h as Vector3) - c).normalized()
			if a.length_squared() < 1e-6 or b.length_squared() < 1e-6:
				return null
			var ang := a.signed_angle_to(b, eje)
			return Transform3D(Basis(eje, ang) * _inicio.basis, _inicio.origin)
		IM.BUTTON:
			return null
		_:
			var h = _plano.intersects_ray(o, d)
			if h == null:
				return null
			return Transform3D(_inicio.basis, _inicio.origin + ((h as Vector3) - _p0))


## Punto de la recta (c, eje) más cercano al rayo (o, d).
static func _en_recta(o: Vector3, d: Vector3, c: Vector3, eje: Vector3) -> Vector3:
	var w := c - o
	var b := eje.dot(d)
	var den := 1.0 - b * b
	if absf(den) < 1e-6:
		return c
	var t := (b * d.dot(w) - eje.dot(w)) / den
	return c + eje * t


func _enviar(evento: int) -> void:
	var n: String = asa.get("im", "")
	var d: Dictionary = cliente.ims.get(n, {})
	if d.is_empty():
		return
	var f = RosMsg.from_type(tipo)
	f.header.frame_id = d["marco"]
	f.header.stamp = visor.contexto.nodo.now()
	f.client_id = "/" + String(visor.nombre_nodo) + "/interactuar"
	f.marker_name = n
	f.control_name = asa.get("control", "")
	f.event_type = evento
	var pose: Transform3D = d["pose"]
	var p := rclgd.godot_to_ros_vector(pose.origin)
	var q := rclgd.godot_to_ros_quat(pose.basis.get_rotation_quaternion())
	f.pose.position.x = p.x
	f.pose.position.y = p.y
	f.pose.position.z = p.z
	f.pose.orientation.x = q.x
	f.pose.orientation.y = q.y
	f.pose.orientation.z = q.z
	f.pose.orientation.w = q.w
	eventos.append(evento)
	publicar(f)
