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

## V2: primitivas, paleta y texto superpuesto

Estado: **hecho y verde en host** (`pruebas/visor_primitivas.gd`, 110/110). Sin validar en hardware: gate
**E-W8-1** (80 instancias: `[gxm3d] lit=` = 0 y `drawn` = 80) y captura con colores exactos.

| Archivo | Pieza | Papel |
|---|---|---|
| `paleta_viz.gd` | PaletaViz (estático) | textura-paleta 16×16, UN material, `indice(color)`, `uv(i)`, `color(i)`, `de_ros`, OK/WARN/ERROR/STALE, `rampa_mapa()`, `lut16_costmap()` |
| `primitivas_viz.gd` | PrimitivasViz (estático) | mallas unidad compartidas por (forma, color), `instancia`, `cinta`, `pose_godot`, `escala_ros`, `flecha_hacia`, `a_godot`, `grosor_minimo` |
| `texto_superpuesto.gd` | TextoSuperpuesto (`Control`) | todo el texto anclado al 3D en un `_draw()`; tope de 40 glifos en la Vita (D11) |

```gdscript
const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
var mi := Prim.instancia(Prim.FLECHA, Paleta.color(Paleta.FLECHA_RVIZ))   # una vez (pool)
add_child(mi)
mi.transform = Prim.pose_godot(msg.pose)                                   # por mensaje: solo transform
```

Formas (ejes de Godot; −Z = +X de ROS) y triángulos (tabla D2, iguales en PC y Vita): `CUBO` 12, `ESFERA` 8
(octaedro), `CILINDRO` 32, `CONO` 16, `FLECHA` 24, `EJES` 36, `DISCO` 12, `ANILLO` 56. Medidas unidad: cubo de lado 1,
esfera/cilindro/disco de diámetro 1, flecha y cono de largo 1 sobre −Z con el vértice/origen en 0.

Decisiones de V2 no cubiertas (las más conservadoras):

1. **Tope de 64 variantes estricto:** 56 huecos para colores y 8 reservados para el blanco de cada forma; con el
   cupo de color lleno se devuelve la variante blanca (un aviso). `EJES` ignora el color (una sola variante).
   `cinta()` no se cachea ni cuenta (quien la use limita su Hz).
2. **Triángulos:** la tabla D2 dice «8 lados, sin tapas» para el cilindro pero 32 triángulos; 8 lados sin tapas son
   16, así que lleva **tapas** (abanico 8 + 8), que es además lo que dibuja RViz. Cono y punta de flecha: un
   triángulo por lado + tapa de la base (mismo número que el esqueleto de doc 36 §3.4, sin triángulos degenerados).
3. **Anillo:** el arco de `wrench_visual.cpp` (i = 4..32 de 36 pasos: 40°→320°, 280°); el «315°» de doc 36 §3.2 no
   casa con i = 4..32. Cinta plana r 0,45–0,5 en el plano XY de ROS.
4. **Esfera:** octaedro también en el PC (un solo camino de código; la icosfera de 80 tri queda como mejora).
5. **Material:** unshaded, NEAREST y **sin culling** también en el PC (H15). Sin normales ni color por vértice.
   La opción «sombreado» (D2, reversión) no se implementa.
6. **Paleta en 8 bit con redondeo** (`Color.r8`): `set_pixel` trunca y el texel no casaba con `color(i)`.
   La caché `indice()` se vacía al llegar a 1 024 colores.
7. **Rampas de mapa:** `umbral` por defecto 100 en los tres esquemas (el de RViz), no 65.
8. **TextoSuperpuesto:** sin `camara` usa la del viewport; `mouse_filter = IGNORE`; `max_glifos` (0 = automático)
   para simular la Vita en host. No se ha añadido a `visor-ros/main.tscn` (lo hará el primer display que lo use).
9. **HUD:** el gris provisional `COLOR_CADUCADO` de `display_ros_hud.gd` sigue ahí (V4 trabaja ese archivo);
   sustituirlo por `Paleta.STALE` es un cambio de una línea para quien lo cierre.

```fish
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_primitivas.gd   # RESULTADO: 110/110
```

El `ERROR: PrimitivasViz: forma desconocida 99` y el aviso de «más de 64 variantes» del log son casos negativos.

## HUD (V4)

Estado: **hecho y verde en host** (`pruebas/visor_hud.gd`); el coste real en la Vita está sin medir (gate
**G-W13-H0**: `[gxm2d-perf] quads=` ≤ 400 y `draws` ≤ 30 con la pestaña Estado, µs por glifo). Diseño: doc 36 §2.9.7
y §7.2, sentencia W13 D6, fichas de doc 36a §4.1.10, §4.4.5–4.4.7 y §4.8.9.

| Archivo | Pieza | Zona | *Quads* declarados |
|---|---|---|---:|
| `gestor_hud.gd` | GestorHud (`Control`) | barra fija + UNA pestaña visible; recuento por zona | — |
| `displays/hud/bateria.gd` | `sensor_msgs/BatteryState` | barra | 34 |
| `displays/hud/estado_meta.gd` | `action_msgs/GoalStatusArray` + feedback de `NavigateToPose` (nivel 0) o puente VAB/1 (nivel 1) | barra | 40 |
| `displays/hud/barra_estado.gd` | enlace (`get_transport_info`), Hz del `vigilado`, herramienta, `relay_bw` opcional | barra | 40 |
| `displays/hud/medidor.gd` | `Temperature`, `FluidPressure`, `Illuminance`, `RelativeHumidity` (configuración por nodo) | pestaña Estado | 39 |
| `displays/hud/joy.gd` | `sensor_msgs/Joy` (dos sticks + botones) | pestaña Mando | 51 |

Cupos (doc 36 §7.2): barra ≤ 120 (114 con los tres), pestaña ≤ 240 (6 medidores = 234), texto superpuesto ≤ 40
(TextoSuperpuesto, V2). En la Vita (o con `avisar_en_pc`) GestorHud avisa una vez si una zona declara de más.

**En la escena** (`godot/visor-ros/main.tscn`, regla doc 35): `VisorRos/Hud/GestorHud` con `Barra` (Bateria, Meta,
Estado) y `Pestanas` (Estado: Temperatura y Presion; Mando: Joy). Cada pestaña es un `Control` hijo de `Pestanas`;
sus widgets son displays HUD normales (los conecta VisorRos). Cambio de pestaña: `ui_page_down`/`ui_page_up` o
R/L del mando (`boton_siguiente`/`boton_anterior`, −1 = desactivado). En el PC, `todas_visibles` las enseña todas.

**Contrato añadido a `display_ros_hud.gd`:** el widget pinta en `_dibujar() -> bool` (termina con `return true`) con
los ayudantes `texto` (recorta a `max_car`), `rect`, `marco`, `linea`, `polilinea`, `arco` y `num` (NaN → «—»),
que cuentan `glifos_dibujados` y `quads_dibujados` del último `_draw()` (estimación por primitiva, doc 31 H16–H17:
texto = 1 *quad* por carácter, polilínea fina de n puntos = n − 1). `_coste().quads` es la cota que se suma por
zona y la prueba comprueba que lo dibujado no la pasa. `mouse_filter = IGNORE` por defecto (el `.tscn` lo cambia).

**Tipos sin esquema `.rsch`** (Vita y editor de host, mismo `ros/schema.rsch`) → **V5** (`TIPOS_VISOR`):
`sensor_msgs/Joy`, `Temperature`, `Illuminance`, `RelativeHumidity`, `action_msgs/GoalStatusArray` y
`nav2_msgs/action/NavigateToPose_FeedbackMessage` (este, registro manual). Hasta entonces esos widgets quedan en
«sin esquema: …» sin suscribir (T20). Con esquema hoy: `BatteryState`, `FluidPressure`.

### Decisiones de V4 no cubiertas por el ADR 0013 (las más conservadoras)

1. **Paleta:** colores provisionales `COLOR_OK/AVISO/ERROR` (rqt_robot_monitor), `COLOR_TEXTO/FONDO/ACENTO` y
   `COLOR_CADUCADO` como constantes de `display_ros_hud.gd`. **Pendiente de integrar con `paleta_viz.gd` (V2)**: se
   cambian ahí y ningún widget toca colores sueltos (salvo `COLOR_APAGADO` de joy y el azul de «ejecutando» de
   estado_meta).
2. **Recuento de glifos** como cota alta: cuentan también los espacios. La medida buena es G-W13-H0.
3. **Medidor con 24 muestras** (el catálogo decía 60, que daba > 70 *quads*): así 6 medidores caben en 240.
4. **Joy:** circunferencias de 16 segmentos y botones siempre rellenos (un marco cuesta 4 *quads*); ≤ 17 botones.
   La fuente `/vita/joy` (publicar el mando de la Vita) es una herramienta: V7.
5. **estado_meta:** el camino del puente VAB/1 (`topic_vita = "accion/estado"`, docs/32:51 y :61) está escrito
   pero apagado: el puente no existe [I]. Sin esquema del feedback, se queda sin feedback (`estado_feedback`).
6. **barra_estado:** sin suscripción propia; `relay_bw` solo si se le da `topic_vita`. Paquetes/s calculados con
   `read_packets` entre refrescos (2 Hz).
7. **GestorHud** no pinta títulos de pestaña (gastarían glifos de la barra); `pestana_activa()` da el nombre.
8. **R/L como cambio de pestaña** [I]: nombres de botón del port sin validar en hardware.

```fish
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_hud.gd   # RESULTADO: 68/68
```

`pruebas/visor_hud.gd` (loopback): GestorHud (una pestaña visible, la oculta no procesa ni dibuja, aviso de cupo
una vez, vuelta con `siguiente`/`anterior`), glifos y *quads* por zona (barra ≤ 120, pestaña ≤ 240, lo dibujado ≤
lo declarado), cada widget con su mensaje (real por loopback con esquema; falso con los mismos campos sin él), NaN
(T2) en batería, medidor y mando, camino compacto de estado_meta y el HUD de `main.tscn`. Un `Logger` cuenta los
errores de script de `visor/` (debe ser 0). Los `ERROR: RosMsg: tipo … no esta en el esquema` del log son los
tipos V5 de arriba (esperados).

## Displays V3 (relay que ya existe)

Estado: **hecho y verde en host** (`pruebas/visor_displays.gd`, 104/104) y **probado en vivo en el host** contra la
estación (`docker/vita-ros.sh up` + `relay scan,pose,joints,mapa,path` + fuente sintética de `/map`, `/scan`,
`/odom`, `/joint_states` y `/plan`) con `-- transporte=xrce compacto=1`: los cinco topics compactos llegan y se
pintan (scan 180 puntos, path, 234 teselas con ≤ 102 µs por tesela en el host, robot con `joints_orden` y base
colocada con `pose2d`). **Sin validar en hardware** (gate de V3: escena tipo E-W8-6 sin marcadores ≥ 55 FPS,
`process` ≤ 4 ms, tesela ≤ 1,5 ms).

| Display | Archivo | PC (estándar, `_procesar`) | Vita (compacto, `_procesar_compacto`) | Dato intermedio | Capa · cupo |
|---|---|---|---|---|---|
| Scan | `displays/2d/scan.gd` | `LaserScan` (filtro REP-117, tabla cos/sin) | `<p>/scan_compacto` | `PackedVector2Array` m | sensores_2d · 360 quads |
| Path | `displays/2d/path.gd` | `nav_msgs/Path` | `<p>/path_compacto` | `PackedVector2Array` m | sensores_2d · 112 |
| Pose | `displays/2d/pose.gd` | `PoseStamped`, `Odometry`, `PoseWithCovarianceStamped` | `<p>/pose2d` | `Vector3(x, y, yaw)` | sensores_2d · 1 + rastro |
| Mapa | `displays/2d/mapa.gd` | `OccupancyGrid` (rampa «map» de RViz en CPU) | `<p>/mapa_tesela` + `<p>/mapa_meta` | diccionario de `MapaTextura` | sensores_2d · 1 |
| RobotModel | `displays/3d/robot_joints.gd` | `JointState` → `set_joints` | `<p>/joints` + `joints_orden` (+ `pose2d` para la base) | `[nombres, posiciones]` | robot · 40 inst. |
| Pose3D | `displays/3d/pose.gd` | igual que Pose | `<p>/pose2d` | `Transform3D` | poses · 1 inst. |
| Mapa3D | `displays/3d/mapa.gd` | igual que Mapa (quad texturizado) | igual que Mapa | igual que Mapa | mundo · 1 inst. |

`mapa_textura.gd` (no es un display) guarda la textura y la geometría del mapa para los dos displays de mapa.
`RegistroDisplays`: en el PC el defecto de `OccupancyGrid` y `PoseStamped` es el 3D; en la Vita las reglas
`orbital` se saltan y gana la planta 2D (D7). `vita_relay.gd` lleva los arreglos de `docs/31` §4.4: LUT +
`blit_rect` en las teselas (imagen idéntica a la de `set_pixel`, comprobado), tabla de direcciones del scan y
`actualizar_textura()` que devuelve si subió (redibujo solo al cambiar). Los formatos VC/1 no cambian.
`godot/visor-ros/main.tscn` trae Robot, Meta3D y Mapa3D (`solo_pc`) y, en `Planta/Vista`, Mapa, Plan, Scan y Odom.

Decisiones de V3 no cubiertas (las más conservadoras):

1. **Mapa sin *shader*** en PC y Vita: `OccupancyGrid` → colores con un bucle por celda en CPU al llegar (es
   *latched*); el *shader* de mapas#0 queda como mejora `solo_pc`. En la Vita, 3 colores (2 bit).
2. **Sub-texturas de 128²** (resto de `docs/31` §4.4) **no** entran: se sigue subiendo la textura entera ≤ 4 Hz.
3. **Odometría:** `2d/pose.gd` hace también de odometría (con rastro) hasta que exista `2d/odometria.gd`.
4. **Robot sin TF en la Vita:** `pose2d` mueve el robot en el plano solo si `visor.tf` es null; sin `escena_robot`
   se dibujan unos EJES. `visor-ros` no trae robot horneado (el G1 vive en `godot/g1-unitree`): se asigna
   `escena_robot` en el `.tscn` del proyecto que lo tenga.
5. **`nav_msgs/Path` no está en el esquema** de `visor-ros`: en el host con ros2_vita el Path estándar queda «sin
   esquema» (el `ERROR: … Path no esta en el esquema` del log de la prueba es esperado); en la Vita va por el relay.
6. Con dos displays de mapa en la Vita, cada uno decodifica sus teselas (por eso Mapa3D es `solo_pc` en el ejemplo).
7. Medida en hardware: `displays/2d/mapa.gd` escribe cada 5 s `[visor-mapa] teselas= media_us= max_us=` en la Vita
   (o con `-- perfil`).

```fish
set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_displays.gd    # RESULTADO: 104/104
```
