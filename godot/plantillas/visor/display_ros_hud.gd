extends Control
## DisplayRosHud (ADR 0013 §1; doc 36 §2.9.5): base de widget HUD. SIN TF (con `Control` no hay `transform` 3D,
## trampa T10); `_draw()` propio; redibuja solo si llegó algo (a ≤ `hz`) y atenúa lo caducado (gris).
## Sustituye al `widget_hud.gd` de los borradores (D1). El cupo de *quads* del HUD lo lleva GestorHud por pestaña
## (V4), no esta base.
##
## Para escribir un widget: `extends "res://comun/visor/display_ros_hud.gd"`, `_procesar(msg)` devuelve el dato
## (queda en `datos`) y `_dibujar()` lo pinta con `color_estado(c)` y los ayudantes `texto`, `rect`, `marco`,
## `linea`, `polilinea` y `arco`, que dibujan Y cuentan glifos y *quads* (V4). Texto con `draw_string`, nunca un
## `Label` por dato (trampa T16). Un widget que sobrescriba `_draw()` directamente sigue funcionando, pero no
## cuenta. Ver visor/README.md.

const Canal = preload("res://comun/visor/canal_display.gd")
const Perfil = preload("res://comun/ros/perfil.gd")

## Gris de dato viejo. Provisional hasta PaletaViz (V2), que tendrá `STALE`; mismo papel.
const COLOR_CADUCADO := Color(0.45, 0.45, 0.48)
## Colores de estado de rqt_robot_monitor (`util_robot_monitor.py:48-54`; doc 36a §4.4.5) y de fondo/texto del HUD.
## PROVISIONALES (V4): PaletaViz (V2) los tendrá como OK/WARN/ERROR; al integrarla se cambian aquí y en ningún
## otro sitio (los widgets solo usan estas constantes).
const COLOR_OK := Color8(85, 178, 76)
const COLOR_AVISO := Color8(222, 213, 17)
const COLOR_ERROR := Color8(178, 23, 46)
const COLOR_TEXTO := Color(0.9, 0.9, 0.9)
const COLOR_FONDO := Color(0.08, 0.09, 0.12, 0.85)
const COLOR_ACENTO := Color(1.0, 0.75, 0.2)
const TAM_TEXTO := 12                          # una fuente, un tamaño, sin contorno (docs/34:52)

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
## Lo que pintó el último `_draw()` (V4; lo suma GestorHud por zona). Estimación por primitiva según el lienzo 2D
## de la Vita (doc 31 H16–H17): rect lleno = 1 *quad*; marco = 4; línea = 1; polilínea fina de n puntos = n − 1;
## arco de s segmentos = s; texto = 1 *quad* por carácter (cota alta: los espacios también cuentan). [I] hasta
## G-W13-H0, que separa el coste por glifo del coste por lote.
var glifos_dibujados := 0
var quads_dibujados := 0
var dibujos := 0                               # veces que se completó `_dibujar()`
var _seccion := ""
var _g := 0
var _q := 0


static func nombre_display() -> String:
	return "DisplayRosHud"


static func tipos_ros() -> PackedStringArray:
	return PackedStringArray()


## Los widgets HUD no se tragan los toques del 3D/planta que tienen debajo (V4; el `.tscn` puede cambiarlo, porque
## sus propiedades se aplican después de `_init`). Las subclases con `_init` propio llaman a este implícitamente.
func _init() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE


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


# ---------------------------------------------------------------------------------------------------------------
# Dibujo con recuento (V4). El motor llama a `_draw()` solo tras `queue_redraw()` (a ≤ `hz`, o al caducar).
# ---------------------------------------------------------------------------------------------------------------
func _draw() -> void:
	_g = 0
	_q = 0
	# `_dibujar()` devuelve true al terminar; si un error de script lo corta, devuelve null y no se cuenta como
	# dibujo completo (las pruebas lo usan para «pinta sin errores»).
	var fin = _dibujar()
	glifos_dibujados = _g
	quads_dibujados = _q
	if fin == true:
		dibujos += 1


## Lo que pinta el widget. Debe terminar con `return true`.
func _dibujar() -> bool:
	return true


## Texto en una línea, recortado a `max_car` caracteres (−1 = sin recorte). Devuelve los caracteres pintados.
func texto(pos: Vector2, s: String, c: Color, max_car := -1, tam := TAM_TEXTO) -> int:
	if max_car >= 0 and s.length() > max_car:
		s = s.left(max_car)
	if s.is_empty():
		return 0
	draw_string(get_theme_default_font(), pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, c)
	_g += s.length()
	_q += s.length()
	return s.length()


func rect(r: Rect2, c: Color) -> void:
	draw_rect(r, c)
	_q += 1


## Rectángulo hueco (4 líneas finas).
func marco(r: Rect2, c: Color) -> void:
	draw_rect(r, c, false, -1.0)
	_q += 4


func linea(a: Vector2, b: Vector2, c: Color) -> void:
	draw_line(a, b, c, -1.0)
	_q += 1


## Polilínea fina: UN comando (H17).
func polilinea(pts: PackedVector2Array, c: Color) -> void:
	if pts.size() < 2:
		return
	draw_polyline(pts, c, -1.0)
	_q += pts.size() - 1


## Arco o circunferencia fina de `segmentos` lados (un comando).
func arco(centro: Vector2, radio: float, segmentos: int, c: Color, desde := 0.0, hasta := TAU) -> void:
	draw_arc(centro, radio, desde, hasta, segmentos + 1, c, -1.0)
	_q += segmentos


## Número con formato, o «—» si es NaN o infinito (trampa T2: los sensores mandan NaN para «no medido»).
static func num(v: float, formato := "%.1f") -> String:
	return "—" if (is_nan(v) or is_inf(v)) else formato % v
