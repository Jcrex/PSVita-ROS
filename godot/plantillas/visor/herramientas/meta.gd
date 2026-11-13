extends "res://comun/visor/herramienta_visor.gd"
## Nav2 Goal (RViz `goal_tool.cpp` sobre `pose_tool.cpp`; doc 36a §4.8.10, ficha hmi#16): pulsar = posición,
## arrastrar = rumbo, soltar = publicar `geometry_msgs/PoseStamped` en `goal_pose` (relativo, como RViz; 76 B).
## En la Vita (`confirmar_en_vita`) soltar deja la meta «pendiente» (flecha naranja) y **✕** la publica: una meta de
## Nav2 mueve el robot y una consola de mano se roza con facilidad.
##
## Rumbo `atan2(Δy, Δx)` en ROS (`pose_tool.cpp:151`) → cuaternión (0, 0, sin θ/2, cos θ/2) (`:154-161`); umbral de
## arrastre 5 cm. Posición en el plano del suelo (z = 0, como RViz).
##
## Decisiones no cubiertas (las más conservadoras; visor/README.md):
##   - el rumbo se pone a 0 en cada pulsación (el esqueleto de doc 36a heredaba el de la meta anterior: un clic sin
##     arrastre publicaba el rumbo viejo);
##   - una pulsación nueva con una meta pendiente la sustituye (no se publica la vieja); ○ (JOY_BUTTON_B) o Esc la
##     descartan;
##   - al desactivar la herramienta se descarta lo pendiente.

const UMBRAL_ARRASTRE := 0.05                  # m

var _inicio = null                             # Vector3 ROS del punto pulsado, o null
var _yaw := 0.0
var _pendiente = null                          # [Vector3 ROS, yaw] en la Vita hasta ✕
var _px_inicio := Vector2.ZERO                 # pantalla (flecha fantasma)
var _px_fin := Vector2.ZERO


static func nombre_herramienta() -> String:
	return "Meta"


func _init() -> void:
	topic = "goal_pose"
	tipo = "geometry_msgs/msg/PoseStamped"


func pendiente() -> bool:
	return _pendiente != null


func _al_activar(on: bool) -> void:
	if not on:
		_inicio = null
		_pendiente = null


func _entrada(e: InputEvent) -> bool:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_inicio = suelo_ros(e.position)
			_yaw = 0.0
			_pendiente = null
			_px_inicio = a_local(e.position)
			_px_fin = _px_inicio
		elif _inicio != null:
			if visor.en_vita and confirmar_en_vita:
				_pendiente = [_inicio, _yaw]
			else:
				_publicar(_inicio, _yaw)
			_inicio = null
		queue_redraw()
		return true
	if e is InputEventMouseMotion and _inicio != null:
		var p = suelo_ros(e.position)
		if p != null and Vector2(p.x - _inicio.x, p.y - _inicio.y).length() > UMBRAL_ARRASTRE:
			_yaw = atan2(p.y - _inicio.y, p.x - _inicio.x)
			_px_fin = a_local(e.position)
			queue_redraw()
		return true
	if _pendiente != null and es_confirmar(e):
		_publicar(_pendiente[0], _pendiente[1])
		_pendiente = null
		queue_redraw()
		return true
	if _pendiente != null and _es_cancelar(e):
		_pendiente = null
		queue_redraw()
		return true
	return false


func _es_cancelar(e: InputEvent) -> bool:
	if e is InputEventJoypadButton:
		return e.pressed and e.button_index == JOY_BUTTON_B
	return e.is_action_pressed("ui_cancel")


## Mensaje de la meta (lo reutiliza pose_inicial.gd cambiando solo dónde va la pose).
func _publicar(p: Vector3, yaw: float) -> void:
	var m = RosMsg.from_type(tipo)
	cabecera(m)
	_poner_pose(m.pose, p, yaw)
	publicar(m)


func _poner_pose(pose, p: Vector3, yaw: float) -> void:
	pose.position.x = p.x
	pose.position.y = p.y
	pose.position.z = 0.0                      # en el suelo, como RViz
	pose.orientation.z = sin(yaw * 0.5)
	pose.orientation.w = cos(yaw * 0.5)


func _draw() -> void:
	if not activa:
		return
	if _inicio != null:
		flecha(_px_inicio, _px_fin, Paleta.color(Paleta.FLECHA_RVIZ))
	elif _pendiente != null:
		flecha(_px_inicio, _px_fin, Paleta.color(Paleta.NARANJA))
