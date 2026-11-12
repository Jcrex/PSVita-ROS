extends Node3D

const Contexto = preload("res://comun/ros/contexto_ros.gd")

@export var topic := ""
@export var tipo := ""
@export var frame_id := "sensor"
@export var hz := 10.0
@export var hz_vita := 0.0
@export var hz_xrce := 0.0
@export var best_effort := true
@export var habilitado := true
@export var solo_pc := false

var contexto: RefCounted
var robot: Node3D
var pub: RosPublisher
var mensajes_publicados := 0
var _acumulado := 0.0
var _en_vita := false


func _ready() -> void:
	_en_vita = OS.has_feature("vita")
	if _en_vita and solo_pc:
		habilitado = false
		push_warning("%s: sensor solo PC; se desactiva en Vita" % name)
	if not habilitado or contexto == null or contexto.nodo == null:
		set_physics_process(false)
		return
	if _en_vita and hz_vita > 0.0:
		hz = hz_vita
	if contexto.transporte == "xrce" and hz_xrce > 0.0:
		hz = minf(hz, hz_xrce)
	if topic != "" and tipo != "":
		pub = contexto.publicador(topic, tipo, _qos_best_effort())
	_sensor_listo()
	set_physics_process(habilitado)


func _qos_best_effort() -> bool:
	return best_effort


func _sensor_listo() -> void:
	pass


func _physics_process(dt: float) -> void:
	_actualizar_sensor(dt)
	if hz <= 0.0:
		return
	_acumulado += dt
	var periodo := 1.0 / hz
	if _acumulado + 0.00001 < periodo:
		return
	_acumulado = fmod(_acumulado, periodo)
	if _listo_para_publicar():
		_publicar()
		mensajes_publicados += 1


func _actualizar_sensor(_dt: float) -> void:
	pass


func _listo_para_publicar() -> bool:
	return true


func _publicar() -> void:
	pass


func _sellar_y_fijar_frame(msg) -> void:
	contexto.sello(msg.header)
	msg.header.frame_id = frame_id
