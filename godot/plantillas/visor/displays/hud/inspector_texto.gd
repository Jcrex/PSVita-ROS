extends "res://comun/visor/display_ros_hud.gd"
## Inspector de texto (doc 36a §4.1.3, ficha nucleo#7; tarea V12): `ros2 topic echo` en la pestaña Inspector, Vita
## y PC. Filas planas «sangría campo: valor» con `draw_string` (vía `texto()`, que cuenta glifos), redibujadas solo si
## cambia el texto. Es el comodín de RegistroDisplays (cualquier tipo).
##
## Presupuesto (⚖ D6; doc 36 §7.2): en la Vita **8 filas × 30 caracteres a 4 Hz** = 240 *quads* (la pestaña entera).
## En la Vita `filas` y `ancho_max` se recortan a FILAS_VITA × ANCHO_VITA aunque la escena pida más (el texto plano
## de la Vita no admite más de 12 filas, sentencia W13; elegimos el límite más bajo de la tabla §7.2). En el PC se
## usan los de la escena.
##
## Navegación: `desplazar(n)` mueve la ventana de filas; `alternar(i)` despliega o pliega el submensaje de la fila
## visible i. Con `usar_cruceta = true` la cruceta lo hace (arriba/abajo = desplazar, derecha/izquierda =
## desplegar/plegar la primera fila visible); por defecto está apagada porque la cruceta suele ser del teleop.
## Los campos se leen con `get_member` (choque de `reference`, doc 36 §1.1) y la lista de campos viene de la caché
## de IntrospeccionRos (una vez por tipo). Arrays: tamaño + los 4 primeros elementos (sin convertir el resto).
##
## datos = PackedStringArray con las líneas.

const Intro = preload("res://comun/visor/introspeccion_ros.gd")

const FILAS_VITA := 8
const ANCHO_VITA := 30
const MAX_LINEAS := 64                       # tope del aplanado (submensajes desplegados incluidos)

@export var filas := 8
@export var ancho_max := 30
@export var alto_linea := 16.0
@export var usar_cruceta := false

var desplegados := {}                        # ruta "/a/b" -> true
var lineas := PackedStringArray()
var rutas := PackedStringArray()             # ruta del submensaje de cada línea ("" si es hoja)
var primera := 0
var filas_dibujadas := 0                     # líneas pintadas en el último _draw (pruebas: ≤ 12 en la Vita)
var _ultimo = null                           # último mensaje (para re-aplanar al desplegar)


static func nombre_display() -> String:
	return "Inspector"


func _init() -> void:
	hz = 4.0
	hz_vita = 4.0
	caducidad_s = 0.0


func conectar(v) -> void:
	if v != null and v.en_vita:
		filas = mini(filas, FILAS_VITA)
		ancho_max = mini(ancho_max, ANCHO_VITA)
	super.conectar(v)
	set_process_unhandled_input(usar_cruceta)              # revisión V3: la pestaña suele estar oculta al conectar


func _procesar(msg):
	_ultimo = msg
	return _aplanar_todo(msg)


func _pintar(d) -> void:
	lineas = d
	primera = clampi(primera, 0, maxi(lineas.size() - filas, 0))
	queue_redraw()


## Devuelve null (= no redibujar) si el texto no cambió.
func _aplanar_todo(msg):
	var out := PackedStringArray()
	var rs := PackedStringArray()
	_aplanar(msg, "", 0, out, rs)
	if out == lineas:
		return null
	rutas = rs
	return out


func _aplanar(m, ruta: String, nivel: int, out: PackedStringArray, rs: PackedStringArray) -> void:
	for c in Intro.campos(m):
		if out.size() >= MAX_LINEAS:
			return
		var v = m.get_member(StringName(c))
		var r := ruta + "/" + c
		var abierto := v is RosMsg and desplegados.has(r)
		var marca := ("- " if abierto else "+ ") if v is RosMsg else ""
		out.append(("  ".repeat(nivel) + marca + "%s: %s" % [c, _corto(v)]).left(ancho_max))
		rs.append(r if v is RosMsg else "")
		if abierto:
			_aplanar(v, r, nivel + 1, out, rs)


func _corto(v) -> String:
	if v is RosMsg:
		return "{…}"
	if v == null:
		return "—"
	if typeof(v) >= TYPE_ARRAY:
		if v.size() > 0 and v[0] is RosMsg:
			return "[%d] {…}" % v.size()
		return "[%d] %s" % [v.size(), str(v.slice(0, 4))]
	if v is float:
		return num(v, "%.3f")
	return str(v)


func desplazar(n: int) -> void:
	var p := clampi(primera + n, 0, maxi(lineas.size() - filas, 0))
	if p != primera:
		primera = p
		queue_redraw()


## Despliega o pliega el submensaje de la fila visible i (0 = la primera visible). false si no es un submensaje.
func alternar(i: int) -> bool:
	var k := primera + i
	if k < 0 or k >= rutas.size() or rutas[k] == "":
		return false
	if desplegados.has(rutas[k]):
		desplegados.erase(rutas[k])
	else:
		desplegados[rutas[k]] = true
	if _ultimo != null:
		var d = _aplanar_todo(_ultimo)
		if d != null:
			_pintar(d)
	return true


func _unhandled_input(e: InputEvent) -> void:
	if not usar_cruceta or not is_visible_in_tree():
		return
	if e.is_action_pressed("ui_down"):
		desplazar(1)
	elif e.is_action_pressed("ui_up"):
		desplazar(-1)
	elif e.is_action_pressed("ui_right") or e.is_action_pressed("ui_left"):
		alternar(0)
	else:
		return
	get_viewport().set_input_as_handled()


func _dibujar() -> bool:
	filas_dibujadas = 0
	if lineas.is_empty():
		texto(Vector2(4, alto_linea), (topic if topic != "" else "inspector") + " ...", color_estado(COLOR_CADUCADO), ancho_max)
		return true
	for i in mini(filas, lineas.size() - primera):
		texto(Vector2(4, alto_linea * (i + 1)), lineas[primera + i], color_estado(COLOR_TEXTO), ancho_max)
		filas_dibujadas += 1
	return true


func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": filas * ancho_max}   # 8 × 30 = 240 = una pestaña entera
