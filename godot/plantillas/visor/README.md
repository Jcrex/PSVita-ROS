# Visor de topics ROS 2 (`res://comun/visor/`)

Visor propio y portable: **el mismo GDScript** en el PC (rclgd, o el editor de host con `ros2_vita`) y en la PS Vita
(`ros2_vita`). Diseño en `docs/adr/0013-visualizacion-topics-godot.md` y `docs/36-visualizacion-topics-godot.md`
(§2 arquitectura, §8 trampas, §10 tareas). Estado: **V1 (núcleo) hecho y verde en host**; V2–V15 pendientes.
Lo que no se puede ver en el host (render GXM, FPS, XRCE real, reconexión) está sin validar en hardware.

| Archivo | Pieza | Papel |
|---|---|---|
| `visor_ros.gd` | VisorRos (`Node`) | contexto único: nodo ROS, marco fijo, TF, prefijo compacto, perfil y cupos |
| `canal_display.gd` | CanalDisplay (`RefCounted`) | suscripción, QoS, «el último gana», tope de Hz, Hz medido, caducidad |
| `display_ros_3d.gd` | DisplayRos3D (`Node3D`) | base en la vista orbital (frame → TF → `transform`) |
| `display_ros_2d.gd` | DisplayRos2D (`Node2D`) | base en la planta 2D (norte arriba) y superpuesta al 3D |
| `display_ros_hud.gd` | DisplayRosHud (`Control`) | base de widget HUD, sin TF, gris al caducar |
| `registro_displays.gd` | RegistroDisplays (estático) | (tipo, patrón de topic) → script y capa; no crea la escena |
| `tiempo_ros.gd` | TiempoRos (estático) | `Time`/`Duration`/`Header`: segundos, texto, latencia |

Sin `class_name` (D15): todo se usa con `preload("res://comun/visor/…")` o `extends "res://comun/visor/…"`.

## Uso en una escena (regla doc 35)

Un nodo `VisorRos` en el `.tscn` y, **debajo de él**, los displays como nodos con sus `@export` (posición, tamaño,
topic…). Al arrancar (dos fotogramas después, como `aplicacion_robot.gd`) `VisorRos` llama a `conectar(self)` en
cada nodo del grupo `display_ros` que desciende de él. El código del display solo crea lo que depende de los datos
(pools, puntos), sin `owner`. Ejemplo: `godot/visor-ros/main.tscn`.

`VisorRos`: `transporte` (`""` = argumento `transporte=`, o `ros/transport` del proyecto si es `ros2_vita`),
`marco_fijo`, `prefijo_compacto` (lo sobrescribe `prefijo_compacto` de `robot.json`), `perfil` (HMI/VIZ),
`px_por_m`, `forzar_compacto`, `camara`, `texto`. Argumentos tras `--`: `transporte=loopback|xrce`, `compacto=1`,
`agente=IP`, `puerto=N`.

## Escribir un display

Esquema (el scan real llega con V3; `_puntos` y `VitaRelay` como en doc 36 §2.5):

```gdscript
extends "res://comun/visor/display_ros_2d.gd"      # o display_ros_3d.gd / display_ros_hud.gd
var _v := PackedVector2Array()

static func nombre_display() -> String: return "Scan"
static func tipos_ros() -> PackedStringArray: return PackedStringArray(["sensor_msgs/msg/LaserScan"])

func _procesar(msg):                 # mensaje estándar → dato intermedio (null = ignorar)
	return _puntos(msg.ranges, msg.angle_min, msg.angle_increment, msg.range_min, msg.range_max)
func _procesar_compacto(msg):        # formato del relay (/vita/*) → el MISMO dato intermedio
	return VitaRelay.scan_puntos(msg)
func _pintar(puntos) -> void:        # guardar y pedir UN redibujado (dibujo en lote en _draw)
	_v = puntos
	queue_redraw()
func _coste() -> Dictionary:         # máximos: lo que se reserva en la capa
	return {"instancias": 0, "triangulos": 0, "quads": 360}
```

**`@export` comunes:** `habilitado`, `topic`, `tipo`, `topic_vita` (sufijo bajo el prefijo compacto; `""` = en la
Vita se usa `topic` en directo), `tipo_vita`, `frame_id` (`""` = el de la cabecera; marco fijo en el camino
compacto), `hz` / `hz_vita` (tope de entrega; `hz_vita` = 0 ⇒ el mismo), `fiabilidad` (AUTO = best effort salvo
`latched`), `latched` (fiable + TRANSIENT_LOCAL), `caducidad_s` (0 = nunca), `persistencia_s`, `solo_pc`.

**Variables que la subclase puede fijar** (en `_init` o antes de `conectar`): `capa` (`"robot"`, `"mundo"`, `"tf"`,
`"marcadores"`, `"poses"`, `"lento"`, `"reserva"`, `"sensores_2d"`, `"resto_2d"`), `profundidad` (0 = automática),
`canal.coalescer = false` (entregar todos, p. ej. un trazador), y en 2D `en_pantalla = true` (superpuesto).

**Ganchos:** `conectar(visor)` (si se amplía, `super.conectar(v)` primero), `desconectar()`, `_procesar(msg)`,
`_procesar_compacto(msg)`, `_pintar(datos)`, `_caducar()` (3D/2D: se oculta; HUD: redibuja en gris con
`color_estado(c)`), `_coste()`, y los estáticos `nombre_display()` y `tipos_ros()`.

**Estado y diagnóstico:** `estado` (`ok`, `sin topic`, `sin esquema: …`, `sin cupo`, `desactivado`, `sin TF a→b`),
`cupo`, `canal.hz_medido`, `canal.recibidos`, `canal.mostrados`, `canal.compacto`, `canal.topic_abierto`.

### Reglas (trampas de doc 36 §8)

- Mensajes como `RosMsg` sin clases tipadas; `tf` y `visor` sin anotar (T7); tipos explícitos con `Variant` (T8).
- QoS solo con `visor.contexto.qos(...)` (`set_*()`); nunca `qos.reliability = …` (T3, falla en la Vita).
- Campos que chocan con métodos de `RefCounted`/`Object`: `msg.get_member("reference")` (T1).
- Filtros de rango que descartan NaN e Inf: `if not (r >= mn and r <= mx): continue` (T2).
- Nada de bucles por elemento en `_process`: el canal ya entrega a ≤ `hz` y «el último gana»; el trabajo por
  elemento va en `_procesar` (una vez por mensaje entregado) y el dibujo, en lote en `_draw()`.
- Sin `Label3D`, MultiMesh, líneas/puntos 3D ni color por vértice (T15); texto con `draw_string` (T16).

## Decisiones de V1 no cubiertas por el ADR 0013 (las más conservadoras)

1. **TF:** `TfLigero` llega con V9. Hasta entonces `visor.tf` es el `RosTfListener` de rclgd si el nodo tiene
   `create_tf_listener`, y si no `null`: `transformada()` supone que todo está en el marco fijo (D3).
2. **Paleta:** `PaletaViz` llega con V2. El HUD usa un gris provisional `COLOR_CADUCADO` en lugar de `Paleta.STALE`.
3. **Transporte:** `ros/transport` del proyecto solo se aplica con `ros2_vita` (detectado por
   `rclgd.get_transport_info`); con rclgd en el PC, «xrce» no tiene sentido y activaría el camino compacto.
4. **Caducidad:** se cuenta desde la última **llegada** (no desde la última entrega al display), para que un tope
   de Hz bajo no haga caducar un topic vivo.
5. **Arranque:** si ROS no arranca (agente caído al abrir), reintento cada `reintento_s` (3 s). Las caídas
   posteriores las resuelve la reconexión del transporte XRCE. Validar en hardware.
6. **`set_process(false)`** solo con `desactivado` y `sin cupo`; con `sin topic` el display sigue procesando
   (displays sin suscripción propia, como el de TF).
7. **RegistroDisplays:** solo las reglas de doc 36 §2.9.8 más `Path`, `OccupancyGrid` y `mapa_tesela`;
   `crear()` devuelve null mientras el script del display no exista. La sección `visor` de `robot.json` (cambiar
   `topic`/`hz` por nodo) queda para cuando haga falta.
8. **Exportación de `visor-ros`:** excluye `comun/mundo/*` porque `main.tscn` aún no instancia el mundo (V3 lo
   añadirá y entonces se quita la exclusión).

## Prueba

```fish
set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor.gd    # RESULTADO: 56/56
```

`pruebas/visor.gd` (loopback): recibe en las tres bases, «el último gana», tope de Hz y aviso D8, caducidad,
estados, cupos (Vita simulada con `en_vita = true`), `solo_pc`, camino compacto con `hz_vita`, RegistroDisplays,
TiempoRos y arranque de `main.tscn`. El `ERROR: RosMsg: tipo 'paquete_falso/msg/Nada'` del log es el caso negativo.
