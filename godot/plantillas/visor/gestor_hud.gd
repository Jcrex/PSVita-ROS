extends Control
## GestorHud (ADR 0013 §4; doc 36 §2.9.7 y §7.2; sentencia W13 D6): barra fija + UNA pestaña visible a la vez y
## recuento de glifos y *quads* por zona. HUD de la Vita = 400 *quads* (`docs/31:255`): barra ≤ 120, pestaña
## activa ≤ 240 y texto superpuesto ≤ 40 (este último lo lleva TextoSuperpuesto, V2, no este gestor).
##
## Vive en el `.tscn` (regla doc 35): `barra` es un Control con los widgets HUD de la barra (24 px arriba) y
## `pestanas` un Control cuyos hijos son las pestañas (Control) con sus widgets. Los widgets son displays HUD
## (`display_ros_hud.gd`) y los conecta VisorRos como cualquier otro display (el gestor debe colgar del VisorRos).
##
## La pestaña oculta queda con `visible = false` (no se dibuja: 0 *quads*) y `PROCESS_MODE_DISABLED` (sin
## `_process`, así que tampoco bombea su canal: la suscripción sigue viva y apila como mucho un mensaje por el «último
## gana»). En el PC los cupos no se aplican: `todas_visibles = true` enseña todas las pestañas a la vez.
##
## Dos recuentos por zona:
##   - declarado: suma de `_coste().quads` (lo máximo que puede pintar cada widget); es lo que se avisa en la Vita;
##   - dibujado: suma de `quads_dibujados` / `glifos_dibujados` del último `_draw()` de cada widget (estimación por
##     primitiva de display_ros_hud.gd; la medida real es `[gxm2d-perf] quads=` en hardware, gate G-W13-H0).
##
## Decisiones no cubiertas por el ADR (las más conservadoras; anotadas en visor/README.md):
##   - Cambio de pestaña con `ui_page_down`/`ui_page_up` y con los gatillos R/L del mando (JOY_BUTTON_*_SHOULDER,
##     así se llaman en el port [I], validar en hardware); −1 en `boton_*` los desactiva si la app usa L/R.
##   - El gestor NO pinta títulos de pestaña (costarían glifos de la barra); `pestana_activa()` da el nombre por si la
##     barra quiere mostrarlo.
##   - Los avisos de cupo se dan al mostrar una pestaña (en la Vita, o con `avisar_en_pc`), una vez por pestaña.

const BARRA_MAX := 120
const PESTANA_MAX := 240
const HUD_MAX := 400                           # docs/31:255 (barra + pestaña + texto superpuesto)

signal pestana_cambiada(indice: int, nombre: String)

@export var barra: Control                     # widgets HUD de la barra fija
@export var pestanas: Control                  # cada hijo es una pestaña (Control) con sus widgets
@export var inicial := 0
@export var todas_visibles := false            # solo PC: enseña todas las pestañas (en la Vita se ignora)
@export var avisar_en_pc := false              # comprobar cupos también en el PC (pruebas)
@export var boton_siguiente := JOY_BUTTON_RIGHT_SHOULDER   # −1 = desactivado
@export var boton_anterior := JOY_BUTTON_LEFT_SHOULDER

var activa := 0
var en_vita := OS.has_feature("vita")          # las pruebas de host lo ponen a true
var _avisadas := {}                            # nombre de pestaña -> true


func _ready() -> void:
	mostrar(inicial)
	if barra != null:
		_avisar("barra", quads_declarados(barra), BARRA_MAX)


func num_pestanas() -> int:
	return 0 if pestanas == null else pestanas.get_child_count()


func pestana(i: int) -> Control:
	if pestanas == null or i < 0 or i >= pestanas.get_child_count():
		return null
	return pestanas.get_child(i) as Control


func pestana_activa() -> String:
	var p := pestana(activa)
	return "" if p == null else String(p.name)


## Enseña la pestaña i (con vuelta) y apaga las demás.
func mostrar(i: int) -> void:
	var n := num_pestanas()
	if n == 0:
		return
	activa = posmod(i, n)
	var todas := todas_visibles and not en_vita
	for k in n:
		var p := pestana(k)
		if p == null:
			continue
		var ver := todas or k == activa
		p.visible = ver
		p.process_mode = PROCESS_MODE_INHERIT if ver else PROCESS_MODE_DISABLED   # oculta = sin coste
		if ver:
			# Lo que llegó mientras estaba oculta se pinta ya (el canal lo entrega en el próximo _process).
			for w in _widgets(p):
				w.queue_redraw()
	var act := pestana(activa)
	_avisar(String(act.name), quads_declarados(act), PESTANA_MAX)
	pestana_cambiada.emit(activa, String(act.name))


func siguiente() -> void:
	mostrar(activa + 1)


func anterior() -> void:
	mostrar(activa - 1)


func _unhandled_input(e: InputEvent) -> void:
	var sig := e.is_action_pressed("ui_page_down")
	var ant := e.is_action_pressed("ui_page_up")
	if e is InputEventJoypadButton and e.pressed:
		sig = sig or (boton_siguiente >= 0 and e.button_index == boton_siguiente)
		ant = ant or (boton_anterior >= 0 and e.button_index == boton_anterior)
	if sig:
		siguiente()
	elif ant:
		anterior()
	else:
		return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------------------------------------------------------
# Recuentos
# ---------------------------------------------------------------------------------------------------------------
## Widgets HUD (con `_coste` y contadores) bajo `raiz`, incluida ella misma.
func _widgets(raiz: Node) -> Array:
	var out := []
	if raiz == null:
		return out
	if raiz.has_method("_coste") and "quads_dibujados" in raiz:
		out.append(raiz)
	for n in raiz.find_children("*", "Control", true, false):
		if n.has_method("_coste") and "quads_dibujados" in n:
			out.append(n)
	return out


## Suma de `_coste().quads` de los widgets visibles (habilitados) bajo `raiz`.
func quads_declarados(raiz: Node) -> int:
	var total := 0
	for w in _widgets(raiz):
		if w.visible:
			total += int(w.call("_coste").get("quads", 0))
	return total


## Suma de lo que pintó el último `_draw()` de cada widget visible bajo `raiz`.
func quads_dibujados(raiz: Node) -> int:
	var total := 0
	for w in _widgets(raiz):
		if w.is_visible_in_tree():
			total += int(w.quads_dibujados)
	return total


func glifos_dibujados(raiz: Node) -> int:
	var total := 0
	for w in _widgets(raiz):
		if w.is_visible_in_tree():
			total += int(w.glifos_dibujados)
	return total


## Resumen de la barra y de la pestaña activa (para el log de la app o el gate G-W13-H0).
func informe() -> Dictionary:
	var p := pestana(activa)
	return {
		"pestana": pestana_activa(),
		"barra_declarados": quads_declarados(barra),
		"barra_quads": quads_dibujados(barra),
		"barra_glifos": glifos_dibujados(barra),
		"pestana_declarados": quads_declarados(p),
		"pestana_quads": quads_dibujados(p),
		"pestana_glifos": glifos_dibujados(p),
	}


func _avisar(zona: String, quads: int, tope: int) -> void:
	if not (en_vita or avisar_en_pc) or quads <= tope or _avisadas.has(zona):
		return
	_avisadas[zona] = true
	push_warning("GestorHud: «%s» declara %d quads (> %d, doc 36 §7.2)" % [zona, quads, tope])
