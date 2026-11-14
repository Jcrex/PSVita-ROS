@tool
extends Node3D
## Modelo del mundo (edificio, coche, mueble…) en `mundo.tscn` (regla de escenas, doc 35).
##
## Se edita en el editor de Godot:
##  - posición, giro y escala del nodo: con el gizmo o el inspector;
##  - la colisión es el hijo `Colision` (StaticBody3D con escala 1/escala del nodo, para que su caja esté en
##    metros): mueve o cambia el tamaño de su CollisionShape3D con el gizmo. Sin hijo `Colision` = no choca;
##  - el resto, en las propiedades de abajo.
##
## Por qué la malla no se guarda en la escena: en la Vita se carga `modelo_vita` (pocos triángulos) y no
## `modelo`; si la escena guardara la malla de PC, la Vita la cargaría igualmente (memoria y tiempo de arranque).
## Por eso el nodo guarda solo las RUTAS y crea la malla: en el editor (vista previa, hijo `Vista` que no se guarda)
## y al arrancar (`montar()`, lo llama mundo_base.gd).

const NOMBRE_VISTA := "Vista"

## Modelo para el PC (.obj importado como malla, o una escena .tscn/.glb).
@export_file("*.obj", "*.tscn", "*.glb", "*.gltf") var modelo := "":
	set(v):
		modelo = v
		_refrescar_vista()
## Variante de pocos triángulos para la Vita. La rellena `tools/generar-lod-vita.py`; vacío = usa `modelo`.
@export_file("*.obj", "*.tscn", "*.glb", "*.gltf") var modelo_vita := ""
## false = adorno pequeño que no se dibuja en la Vita (su colisión y su movimiento se mantienen).
@export var dibujar_en_vita := true
## Para `tools/generar-lod-vita.py`: 0 = fracción por defecto; 0 < f ≤ 1 = conservar esa fracción de triángulos;
## < 0 = no reducir este modelo (p. ej. la persona: el agrupamiento deja brazos y piernas en hilos).
@export var lod_vita := 0.0

@export_group("Movimiento")
## Radio (m) de la órbita alrededor de la posición del nodo. 0 = quieto.
@export var radio_movimiento := 0.0
## Velocidad angular (rad/s) de la órbita.
@export var velocidad_movimiento := 0.0
## Fase inicial (rad) de la órbita.
@export var fase_movimiento := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		_refrescar_vista()


## Crea la malla según el perfil y devuelve el nodo dibujable (null si en este perfil no se dibuja).
func montar(perfil_ligero: bool) -> Node3D:
	if perfil_ligero and not dibujar_en_vita:
		return null
	var ruta := modelo
	if perfil_ligero and modelo_vita != "" and ResourceLoader.exists(modelo_vita):
		ruta = modelo_vita
	return _crear_visual(ruta)


func tiene_colision() -> bool:
	return get_node_or_null("Colision") != null


func se_mueve() -> bool:
	return radio_movimiento != 0.0 or velocidad_movimiento != 0.0


func _crear_visual(ruta: String) -> Node3D:
	var recurso = load(ruta) if ruta != "" else null
	if recurso == null:
		push_warning("Asset ausente: " + ruta)
		return null
	var n: Node3D
	if recurso is PackedScene:
		n = recurso.instantiate()
	else:
		var instancia := MeshInstance3D.new()
		instancia.mesh = recurso
		n = instancia
	n.name = NOMBRE_VISTA
	add_child(n)
	return n


## Solo en el editor: el hijo `Vista` no tiene `owner`, así que no se guarda en la escena.
func _refrescar_vista() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var vieja := get_node_or_null(NOMBRE_VISTA)
	if vieja != null:
		remove_child(vieja)
		vieja.queue_free()
	_crear_visual(modelo)
