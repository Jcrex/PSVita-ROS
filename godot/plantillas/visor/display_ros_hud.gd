extends Control
## DisplayRosHud (ADR 0013 §1; doc 36 §2.9.5): base de widget HUD. SIN TF (con `Control` no hay `transform` 3D,
## trampa T10); `_draw()` propio; redibuja solo si llegó algo (a ≤ `hz`) y atenúa lo caducado (gris).
## Sustituye al `widget_hud.gd` de los borradores (D1). El cupo de *quads* del HUD lo lleva GestorHud por pestaña
## (V4), no esta base.
##
## Para escribir un widget: `extends "res://comun/visor/display_ros_hud.gd"`, `_procesar(msg)` devuelve el dato
## (queda en `datos`) y `_draw()` lo pinta con `color_estado(c)`. Texto con `draw_string`, nunca un `Label` por
## dato (trampa T16). Ver visor/README.md.

const Canal = preload("res://comun/visor/canal_display.gd")
const Perfil = preload("res://comun/ros/perfil.gd")

## Gris de dato viejo. Provisional hasta PaletaViz (V2), que tendrá `STALE`; mismo papel.
const COLOR_CADUCADO := Color(0.45, 0.45, 0.48)

@export var habilitado := true
@export var topic := ""
@export var tipo := ""
@export var topic_vita := ""
@export var tipo_vita := ""
@export var frame_id := ""                     # sin uso en HUD (se conserva por el contrato)
@export var hz := 10.0                         # Label/HUD ≤ 10 Hz (docs/31:139)
@export var hz_vita := 4.0                     # perfil ligero: HUD a 4 Hz (doc 34)
@export_enum("AUTO", "BEST_EFFORT", "FIABLE") var fiabilidad := 0
@export var latched := false
@export var caducidad_s := 2.0
@export var persistencia_s := 0.0
@export var solo_pc := false

var profundidad := 0
var capa := "hud"
var visor
var canal = Canal.new()
var estado := "sin conectar"
var datos = null                               # último dato intermedio
var gris := false                              # caducado: el widget pinta en COLOR_CADUCADO
var _seccion := ""


static func nombre_display() -> String:
	return "DisplayRosHud"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray()


func _enter_tree() -> void:
	add_to_group("display_ros")


func conectar(v) -> void:
	visor = v
	_seccion = "visor/" + name
	if not habilitado or (solo_pc and v.en_vita):
		visible = false
		estado = "desactivado"
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
	estado = "desconectado"
	set_process(false)


func _process(_dt: float) -> void:
	var t := Perfil.t0() if Perfil.activo else 0
	canal.bombear()
	var c: bool = canal.caducado(caducidad_s)
	if c != gris:
		gris = c
		_caducar()
	if Perfil.activo:
		Perfil.sumar(_seccion, t)


func _al_mensaje(msg) -> void:
	var d = _procesar_compacto(msg) if canal.compacto else _procesar(msg)
	if d == null:
		return
	datos = d
	estado = "ok"
	_pintar(d)


func _procesar(_msg):
	return null


func _procesar_compacto(msg):
	return _procesar(msg)


func _pintar(_d) -> void:
	queue_redraw()                             # el dibujo va en _draw() de cada widget


## Cambio de caducado ↔ vivo (`gris`): por defecto solo redibuja.
func _caducar() -> void:
	queue_redraw()


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 0}


func color_estado(c: Color) -> Color:
	return COLOR_CADUCADO if gris else c
