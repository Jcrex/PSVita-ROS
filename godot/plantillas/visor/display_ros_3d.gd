extends Node3D
## DisplayRos3D (ADR 0013 §1; doc 36 §2.9.3): base de display en la vista orbital.
## Resuelve frame → TF → `transform` del nodo y llama a `_pintar(datos)`. Toda la parte ROS está en CanalDisplay.
##
## Para escribir un display: `extends "res://comun/visor/display_ros_3d.gd"` y sobrescribir `_procesar(msg)`
## (mensaje estándar → dato intermedio), si hay relay `_procesar_compacto(msg)` (formato /vita/* → el MISMO dato),
## `_pintar(datos)` (solo PrimitivasViz/PaletaViz, V2) y `_coste()`. Ver visor/README.md.
## El nodo debe colgar de VisorRos o de un nodo sin transformación: `transform` es la pose en el marco fijo.

const Canal = preload("res://comun/visor/canal_display.gd")
const Perfil = preload("res://comun/ros/perfil.gd")

@export var habilitado := true
@export var topic := ""
@export var tipo := ""
@export var topic_vita := ""                   # sufijo bajo visor.prefijo_compacto; "" = en la Vita, `topic` directo
@export var tipo_vita := ""
@export var frame_id := ""                     # "" = header.frame_id del mensaje; en el camino compacto, marco fijo
@export var hz := 15.0
@export var hz_vita := 0.0                     # 0 = el mismo que `hz`
@export_enum("AUTO", "BEST_EFFORT", "FIABLE") var fiabilidad := 0
@export var latched := false
@export var caducidad_s := 0.0                 # 0 = nunca
@export var persistencia_s := 0.0              # decay de RViz (displays que acumulan)
@export var solo_pc := false

var profundidad := 0                 # 0 = automática (ADR 0013 §6); las subclases la fijan en _init si hace falta
var capa := "reserva"                # capa de ADR 0013 §4: "robot", "mundo", "tf", "marcadores", "poses", "lento"…
var cupo := 0                        # instancias concedidas por el visor
var visor
var canal = Canal.new()
var estado := "sin conectar"
var marco := Transform3D.IDENTITY
var _seccion := ""


static func nombre_display() -> String:
	return "DisplayRos3D"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray()


func _enter_tree() -> void:
	add_to_group("display_ros")
	_seccion = "visor/" + name          # ya aquí: `_process` corre antes de `conectar` (revisión V1: sección «»)


## Lo llama VisorRos. Las subclases que lo amplíen llaman primero a `super.conectar(v)`.
func conectar(v) -> void:
	visor = v
	_seccion = "visor/" + name
	if not habilitado or (solo_pc and v.en_vita):
		visible = false
		estado = "desactivado"
		set_process(false)
		return
	var pide: int = _coste().get("instancias", 0)
	cupo = v.reservar(capa, pide, name)
	if pide > 0 and cupo == 0:
		visible = false
		estado = "sin cupo"
		set_process(false)
		return
	if not canal.mensaje.is_connected(_al_mensaje):
		canal.mensaje.connect(_al_mensaje)
	estado = canal.abrir_para(self, v)
	set_process(true)   # también «sin topic»: displays sin suscripción propia (p. ej. TF) usan _process


func desconectar() -> void:
	canal.cerrar()
	if canal.mensaje.is_connected(_al_mensaje):
		canal.mensaje.disconnect(_al_mensaje)
	if visor:
		visor.liberar(capa, cupo)
	cupo = 0
	estado = "desconectado"
	set_process(false)


func _process(_dt: float) -> void:
	var t := Perfil.t0() if Perfil.activo else 0
	canal.bombear()
	if visible and canal.caducado(caducidad_s):
		_caducar()
	if Perfil.activo:
		Perfil.sumar(_seccion, t)


func _al_mensaje(msg) -> void:
	var datos = _procesar_compacto(msg) if canal.compacto else _procesar(msg)
	if datos == null:
		return
	var f: String = frame_id
	if f == "" and not canal.compacto and "header" in msg:
		f = String(msg.header.frame_id).trim_prefix("/")
	var t = visor.transformada(f)
	if t == null:
		estado = "sin TF %s→%s" % [f, visor.marco_fijo]
		visible = false
		return
	marco = t
	transform = t
	visible = true
	estado = "ok"
	_pintar(datos)


## Mensaje estándar → dato intermedio (o null = ignorar).
func _procesar(_msg):
	return null


## Formato del relay → el MISMO dato intermedio que `_procesar`. Por defecto, igual que `_procesar`.
func _procesar_compacto(msg):
	return _procesar(msg)


func _pintar(_datos) -> void:
	pass


## Sin mensajes en `caducidad_s`: por defecto se oculta (vuelve a verse con el siguiente mensaje).
func _caducar() -> void:
	visible = false


## Máximos del display: `instancias` (lo que se reserva en la capa), `triangulos` y `quads`.
func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 0}
