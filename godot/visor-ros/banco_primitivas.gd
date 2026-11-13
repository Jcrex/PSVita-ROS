extends Node3D
## BancoPrimitivas (revisión V1 del visor, 2026-11-13): banco del gate **E-W8-1** de la tarea V2 en la Vita
## (doc 36 §10: 80 instancias de PrimitivasViz → `[gxm3d] lit=` = 0 y `drawn` = 80 + lo que ya hubiera).
## Sin él, `visor-ros` solo tiene 1 instancia 3D en la Vita (los EJES del Robot) y el gate no se podía medir.
##
## Apagado al arrancar (así la misma `.vpk` mide G-W13-H0 sin el banco). Se enciende y apaga con **Select**
## (`JOY_BUTTON_BACK` en el port [I], validar en hardware) o con la tecla B en el PC; escribe `[visor-banco]` en stderr.
## Las instancias son cosas de prueba creadas en ejecución (sin `owner`, doc 35); su sitio es la rejilla de abajo.
## Colores: 7 con nombre × 8 formas = 56 variantes con color (justo el tope de PrimitivasViz) + EJES.

const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
const COLORES := [Paleta.ROJO, Paleta.VERDE, Paleta.AZUL, Paleta.AMARILLO, Paleta.CIAN, Paleta.MAGENTA, Paleta.NARANJA]

@export var n := 80
@export var activo := false
@export var boton := JOY_BUTTON_BACK
@export var paso := 0.5                         # m entre instancias (rejilla de 10 × 8 = 4,5 × 3,5 m, en cámara)
@export var tam := 0.3                          # escala de cada forma unidad

var creadas := 0


func _ready() -> void:
	visible = activo
	if activo:
		_crear()


func _unhandled_input(e: InputEvent) -> void:
	var pulsado: bool = (e is InputEventJoypadButton and e.pressed and e.button_index == boton) \
			or (e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_B)
	if not pulsado:
		return
	activo = not activo
	if activo and creadas == 0:
		_crear()
	visible = activo
	printerr("[visor-banco] activo=%s instancias=%d variantes=%d" % [activo, creadas, Prim.variantes()])
	get_viewport().set_input_as_handled()


func _crear() -> void:
	for i in n:
		var forma: int = Prim.FORMAS[i % Prim.FORMAS.size()]
		var c := Paleta.color(COLORES[(i / Prim.FORMAS.size()) % COLORES.size()])
		var mi := Prim.instancia(forma, c)
		mi.transform = Transform3D(Basis.from_scale(Vector3.ONE * tam),
				Vector3((i % 10 - 4.5) * paso, 0.3, (i / 10 - 3.5) * paso))
		add_child(mi)                               # sin owner: no se guarda en la escena (doc 35)
	creadas = n
