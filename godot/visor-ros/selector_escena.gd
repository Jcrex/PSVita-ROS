extends Node
## SelectorEscena (juez Fable, desafíos de la fase V2, 2026-11-14; `docs/ia/workshops/posts/V2-juez-fable.md` F2):
## cambia de escena de prueba en la Vita **sin reexportar** la `.vpk` (la Vita no acepta argumentos).
##
## Las escenas son `.tscn` editables (regla doc 35); este nodo solo elige cuál se carga:
##   - `res://main.tscn`      visor de ejemplo, perfil HMI (gates H0, E-W8-1, V3, V6, V7, V9, M1-HMI, M2, M3)
##   - `res://main_viz.tscn`  la misma escena heredada con `perfil = VIZ` (gate M1-Viz: 32 marcadores a ≥ 30 FPS)
##   - `res://banco_v5.tscn`  displays directos de V5 (gate V5: cada tipo publicado desde el PC se ve)
##   - `res://main_percepcion.tscn`  main.tscn + pestaña Cámara, nube y cajas 3D (gates V10 y E-W8-5; revisión V3)
##
## Cómo se cambia:
##   - Vita: mantener **L + R** y pulsar **START** → pasa a la siguiente de `escenas` (y da la vuelta).
##     PC: tecla **F9**.
##   - La elección se guarda en `archivo` (`user://`, en la Vita bajo `ux0:/data/…`; la ruta real sale en el log
##     `[visor-escena]`). Al abrir la app, la escena principal del proyecto lee ese archivo y salta a la guardada.
##     Así, si el cambio en caliente fallara en hardware (cierra y reabre la sesión XRCE [I, validar en hardware]),
##     basta cerrar la app y abrirla otra vez. Borrar el archivo (o subir uno con otra ruta por FTP) también vale.
##
## Va como nodo en cada escena de la lista (no como autoload: con `--script` las pruebas de host no deben saltar).

@export var escenas := PackedStringArray(["res://main.tscn", "res://main_viz.tscn", "res://banco_v5.tscn",
		"res://main_percepcion.tscn"])
@export var archivo := "user://visor_escena.txt"
@export var boton := JOY_BUTTON_START                     # se pulsa…
@export var con_botones := PackedInt32Array([JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER])   # …con estos mantenidos
@export var tecla := KEY_F9                               # PC

var _pulsados := {}                                       # botón -> true (estado propio: no depende de Input)


func _ready() -> void:
	var actual := escena_actual()
	printerr("[visor-escena] escena=%s archivo=%s" % [actual, ProjectSettings.globalize_path(archivo)])
	# Solo la escena principal del proyecto redirige al arrancar: abrir otra a mano en el PC (o instanciarla en una
	# prueba) no salta a ningún sitio.
	if actual == "" or actual != String(ProjectSettings.get_setting("application/run/main_scene", "")):
		return
	var guardada := leer()
	if guardada != "" and guardada != actual:
		printerr("[visor-escena] guardada=%s" % guardada)
		get_tree().change_scene_to_file.call_deferred(guardada)


## Ruta de la escena en curso si este nodo cuelga de ella; "" si la escena está instanciada dentro de otra cosa.
func escena_actual() -> String:
	var e := get_tree().current_scene
	return e.scene_file_path if e != null and (e == self or e.is_ancestor_of(self)) else ""


## Escena guardada en `archivo`; "" si no hay archivo o no nombra una escena de la lista (nunca carga otra cosa).
func leer() -> String:
	if not FileAccess.file_exists(archivo):
		return ""
	var s := FileAccess.get_file_as_string(archivo).strip_edges()
	return s if escenas.has(s) else ""


func guardar(ruta: String) -> bool:
	var f := FileAccess.open(archivo, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(ruta + "\n")
	f.close()
	return true


## La que sigue a `ruta` en la lista (la primera si `ruta` no está).
func siguiente(ruta: String) -> String:
	if escenas.is_empty():
		return ""
	return escenas[(escenas.find(ruta) + 1) % escenas.size()]


func _input(e: InputEvent) -> void:
	var cambia := false
	if e is InputEventJoypadButton:
		_pulsados[e.button_index] = e.pressed
		if e.pressed and e.button_index == boton:
			cambia = true
			for b in con_botones:
				cambia = cambia and _pulsados.get(b, false)
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == tecla:
		cambia = true
	if not cambia:
		return
	get_viewport().set_input_as_handled()                 # START no llega al banco E-W8-1
	var destino := siguiente(escena_actual())
	if destino == "":
		return
	var ok := guardar(destino)
	printerr("[visor-escena] siguiente=%s guardada=%s (si no cambia sola: cerrar y abrir la app)" % [destino, ok])
	get_tree().change_scene_to_file.call_deferred(destino)
