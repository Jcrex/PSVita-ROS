extends Node2D
## DisplayRos2D (ADR 0013 §1; doc 36 §2.9.4): base de display en la planta 2D (norte arriba) y en la
## superposición al 3D. Igual que DisplayRos3D salvo que el cupo se pide en *quads* y que el marco se aplica como
## `transform = visor.planta_desde(t)`. Los displays **superpuestos** (dibujan en coordenadas de pantalla con
## `visor.camara`) ponen `en_pantalla = true` y usan `marco` (Transform3D) en su `_draw()`.
##
## Para escribir un display: `extends "res://comun/visor/display_ros_2d.gd"`, `_procesar`/`_procesar_compacto`
## devuelven el dato intermedio, `_pintar(datos)` lo guarda y llama a `queue_redraw()`, y `_draw()` pinta en lote
## (un `draw_*` por lote, nunca un nodo por punto). Ver visor/README.md.

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

var profundidad := 0                 # 0 = automática (ADR 0013 §6)
var capa := "sensores_2d"            # o "resto_2d" (marcadores 2D, detecciones)
var en_pantalla := false             # true = superpuesto con la cámara: no se toca el transform del nodo
var cupo := 0                        # quads concedidos por el visor
var visor
var canal = Canal.new()
var estado := "sin conectar"
var marco := Transform3D.IDENTITY
var _seccion := ""


static func nombre_display() -> String:
	return "DisplayRos2D"


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
	var pide: int = _coste().get("quads", 0)
	cupo = v.reservar(capa, pide, name)
	if pide > 0 and cupo == 0:
		visible = false
		estado = "sin cupo"
		set_process(false)
		return
	if not canal.mensaje.is_connected(_al_mensaje):
		canal.mensaje.connect(_al_mensaje)
	estado = canal.abrir_para(self, v)
	set_process(true)


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
	if not en_pantalla:
		transform = visor.planta_desde(t)
	visible = true
	estado = "ok"
	_pintar(datos)


## Punto ROS (m, marco del display) → px locales de la planta.
func px(p: Vector2) -> Vector2:
	return Vector2(p.x, -p.y) * visor.px_por_m


func _procesar(_msg):
	return null


func _procesar_compacto(msg):
	return _procesar(msg)


## Por defecto solo pide redibujar; el dibujo va en `_draw()` de cada display.
func _pintar(_datos) -> void:
	queue_redraw()


func _caducar() -> void:
	visible = false


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 0}
