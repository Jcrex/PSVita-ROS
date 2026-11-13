extends Control
## TextoSuperpuesto (ADR 0013; doc 36 §2.9.7; W13 D11): TODO el texto anclado al 3D (nombres de frames, Marker
## TEXT_VIEW_FACING, etiquetas) en UN `_draw()` de un único CanvasItem, con `draw_string` tras
## `Camera3D.is_position_behind` + `unproject_position`. Nunca `Label3D` (invisible en la Vita, T15) ni un `Label`
## por texto (multiplica lotes, T16). Una fuente y **sin contorno** (el contorno multiplicó los lotes: 222 *draws*
## para 305 *quads*, `docs/34-perfil-vita-ligero.md:52`).
##
## Tope de 40 glifos en la Vita (D11: ≤ 10 textos, reproyección ≤ 20 Hz). Los widgets HUD NO pasan por aquí:
## pintan su texto en su propio `_draw()`.
##
## Uso: un nodo con este script en el `.tscn` (a pantalla completa, encima del 3D), enlazado en `VisorRos.texto`;
## los displays 3D llaman a `visor.texto.poner(clave, pos_godot_mundo, "texto", color)` y `quitar(clave)`.
## No captura el ratón ni el tacto (MOUSE_FILTER_IGNORE): el 3D de debajo sigue recibiendo la entrada.

const MAX_GLIFOS_VITA := 40

@export var camara: Camera3D                   # null = la cámara activa del viewport
@export var tam := 12
@export var hz := 20.0                         # reproyección ≤ 20 Hz (docs/31 §3)
## 0 = automático (40 en la Vita, sin tope en el PC). Las pruebas de host lo fijan para simular la Vita.
@export var max_glifos := 0

var glifos_dibujados := 0                      # último `_draw()` (diagnóstico y pruebas)
var _textos := {}                              # clave -> [Vector3 mundo (Godot), String, Color]
var _t := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Añade o actualiza un texto. `pos` en coordenadas de mundo de Godot (ya convertidas desde ROS).
func poner(clave: String, pos: Vector3, texto: String, color: Color = Color.WHITE) -> void:
	_textos[clave] = [pos, texto, color]


func quitar(clave: String) -> void:
	_textos.erase(clave)


func vaciar() -> void:
	_textos.clear()
	queue_redraw()


func cuantos() -> int:
	return _textos.size()


func _process(dt: float) -> void:
	_t += dt
	if _t >= 1.0 / maxf(hz, 0.1):
		_t = 0.0
		if not _textos.is_empty() or glifos_dibujados > 0:
			queue_redraw()


func _tope() -> int:
	if max_glifos > 0:
		return max_glifos
	return MAX_GLIFOS_VITA if OS.has_feature("vita") else 1 << 30


func _camara() -> Camera3D:
	if camara != null:
		return camara
	var vp := get_viewport()
	return vp.get_camera_3d() if vp != null else null


## Lo que se pintaría ahora: [[Vector2 pantalla, String, Color], …], sin lo que queda detrás de la cámara y
## cortado en el tope de glifos (se descartan los textos enteros que no caben). Separado de `_draw()` para probarlo.
func preparar() -> Array:
	var out := []
	var cam := _camara()
	if cam == null:
		return out
	var glifos := 0
	var tope := _tope()
	for e in _textos.values():
		var p: Vector3 = e[0]
		if cam.is_position_behind(p):
			continue
		var s: String = e[1]
		if glifos + s.length() > tope:
			break
		glifos += s.length()
		out.append([cam.unproject_position(p), s, e[2]])
	return out


func _draw() -> void:
	var fuente := get_theme_default_font()
	var n := 0
	for e in preparar():
		var s: String = e[1]
		n += s.length()
		draw_string(fuente, e[0], s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, e[2])
	glifos_dibujados = n
