extends RefCounted
## ClasesDeteccion (V10; doc 36a §4.8.4–§4.8.5; sentencia W13 D12): nombres de clase de las detecciones del relay.
## `<p>/detecciones` y `<p>/detecciones3d` mandan la clase como índice; `<p>/det_clases` (String fiable +
## TRANSIENT_LOCAL, «persona,coche,…») da los nombres. Lo usan `hud/cajas_2d.gd` y `2d/cajas_3d.gd` como
## suscripción auxiliar *latched* (como `joints_orden`), solo en el camino compacto. En el PC directo la clase llega
## como texto (`class_id`) y no hace falta.

const Canal = preload("res://comun/visor/canal_display.gd")
const Vc1 = preload("res://comun/ros/vc1.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")

var canal = Canal.new()
var nombres := PackedStringArray()
var cambios := 0                               # veces que llegó una lista nueva (pruebas)


## Abre `<prefijo>/<sufijo>` en el visor `v`. false si no se pudo suscribir.
func abrir(v, sufijo: String) -> bool:
	if not canal.mensaje.is_connected(al_texto):
		canal.mensaje.connect(al_texto)
	var t: String = v.prefijo_compacto.trim_suffix("/") + "/" + sufijo.trim_prefix("/")
	return canal.abrir(v.contexto.nodo, t, "std_msgs/msg/String", v.contexto.qos(false, 1, true))


func cerrar() -> void:
	canal.cerrar()


## Una vez por fotograma desde el `_process` del display.
func bombear() -> void:
	canal.bombear()


func al_texto(m) -> void:
	nombres = Vc1.leer_det_clases(String(m.data))
	cambios += 1


## Nombre de la clase `k`: «?» si es −1 (el relay se quedó sin hueco) y el número si aún no llegó la lista.
func nombre(k: int) -> String:
	if k < 0:
		return "?"
	return nombres[k] if k < nombres.size() else str(k)


## Color estable por nombre de clase: índices nombrados de PaletaViz (rojo … naranja) por hash del texto.
static func color_clase(etiqueta: String) -> Color:
	var nombrados := [Paleta.ROJO, Paleta.VERDE, Paleta.AZUL, Paleta.AMARILLO, Paleta.CIAN, Paleta.MAGENTA, Paleta.NARANJA]
	return Paleta.NOMBRADOS[nombrados[absi(etiqueta.hash()) % nombrados.size()]]
