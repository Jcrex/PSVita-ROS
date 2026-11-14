# Visor de topics ROS 2 (`res://comun/visor/`)

Visor propio y portable: **el mismo GDScript** en el PC (rclgd, o el editor de host con `ros2_vita`) y en la PS Vita
(`ros2_vita`). Diseño en `docs/adr/0013-visualizacion-topics-godot.md` y `docs/36-visualizacion-topics-godot.md`
(§2 arquitectura, §8 trampas, §10 tareas). Estado: **V1–V5 hechos y verdes en host** (V5 = esquema `TIPOS_VISOR` y displays directos pequeños); **V6** (relay
VC/1 rev. 2, consola y diagnóstico) y V7 también, ver sus secciones; V8 (marcadores), V9 (TfLigero, TF y poses), V10 (percepción),
V11 (costmap) y V12 (inspector, trazador y explorador) hechos (2026-11-14): **V1–V12 hechos**; V13–V15 pendientes.
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
   → **Hecho en V9**: sin `create_tf_listener`, `visor.tf` es un `TfLigero` (ver «TF y poses (V9)»).
2. **Paleta:** ~~gris provisional~~ → integrada en la revisión V1: `COLOR_CADUCADO` es el gris 242 de la rampa de
   `PaletaViz` (no `Paleta.STALE`, ver «Revisión V1»).
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
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor.gd    # RESULTADO: 57/57
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
   para simular la Vita en host. Está en `visor-ros/main.tscn` (`VisorRos/Hud/Texto`, `VisorRos.texto`) desde la
   revisión V1.
9. **HUD:** colores integrados con `PaletaViz` en la revisión V1 (caducado = gris de la rampa, no STALE).

```fish
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_primitivas.gd   # RESULTADO: 114/114
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

**Esquemas:** desde V5 todos los tipos del HUD están en el `.rsch` de `visor-ros` (`TIPOS_VISOR`): `Joy`,
`Temperature`, `Illuminance`, `RelativeHumidity`, `GoalStatusArray` y `NavigateToPose_FeedbackMessage` (registro
manual, `ros/msg/nav2_msgs/action/`). Una app con el visor que no use `--visor` deja esos widgets en «sin esquema: …»
sin suscribir (T20).

### Decisiones de V4 no cubiertas por el ADR 0013 (las más conservadoras)

1. **Paleta:** `COLOR_OK/AVISO/ERROR/ACENTO/INFO/CADUCADO` de `display_ros_hud.gd` salen de `paleta_viz.gd`
   (revisión V1); `COLOR_TEXTO`/`COLOR_FONDO` siguen propios del HUD. Ningún widget toca colores sueltos salvo
   `COLOR_APAGADO` de joy.
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
5. ~~`nav_msgs/Path` no está en el esquema~~ → en `TIPOS_VISOR` desde V5 (directo hasta 6 poses en 488 B; en la
   Vita un plan real sigue yendo por el relay `path_compacto`).
6. Con dos displays de mapa en la Vita, cada uno decodifica sus teselas (por eso Mapa3D es `solo_pc` en el ejemplo).
7. Medida en hardware: `displays/2d/mapa.gd` escribe cada 5 s `[visor-mapa] teselas= media_us= max_us=` en la Vita
   (o con `-- perfil`).

```fish
set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_displays.gd    # RESULTADO: 105/105
```

## Revisión V1 (2026-11-13)

Revisión escéptica y de código de V1–V4: `docs/ia/workshops/posts/V1-revision.md` (hallazgos, veredictos de las
decisiones anotadas arriba y comandos de hardware). Cambios:

- `vita_relay.gd`: la primera subida de la textura del mapa ya no espera 250 ms desde el arranque del motor (hacía
  fallar a ratos `visor_displays.gd`, 103/104).
- `robot_joints.gd`: `pose2d` conserva la escala propia del robot (los EJES de respaldo volvían a tamaño 1).
- `2d/pose.gd`, `3d/pose.gd`, `robot_joints.gd`: poses con NaN/Inf se ignoran (T2).
- HUD con colores de `PaletaViz`; dato viejo en gris (no `Paleta.STALE`: azul ilegible como texto, DESAFÍO a
  doc 36 §2.9.5).
- `VisorRos` activa `Perfil` en la Vita (o con `-- perfil`) y vuelca cada 300 fotogramas
  `[perfil-gd] … visor/<display>=µs … hud_barra_q= hud_pestana_q= hud_glifos=`; la sección de cada display se fija
  en `_enter_tree` (antes salía una sección vacía).
- `godot/visor-ros/main.tscn`: `TextoSuperpuesto` (`VisorRos/Hud/Texto`) y `BancoPrimitivas`
  (`banco_primitivas.gd`, gate E-W8-1: 80 instancias con Select o la tecla B; apagado al arrancar).
- Estación: `docker/vita-ros.sh fuente-visor` (`docker/scripts/fuente_prueba_visor.py`, la fuente sintética de V3,
  ahora versionada, con batería, presión y temperatura).

## Esquema `TIPOS_VISOR` y displays directos (V5)

Estado: **hecho y verde en host** (`pruebas/visor_directos.gd`, 228/228) y **probado en vivo en el host** contra la
estación (`docker/vita-ros.sh up` + `ros2 topic pub` desde `vita_station`, `transporte=xrce`, `agente=127.0.0.1`):
`PointStamped`, `Range`, `Marker`, `WrenchStamped`, `NavSatFix`, `PoseWithCovarianceStamped` y `PolygonStamped`
llegan (60/60 a 5 Hz) y se pintan. **Sin validar en hardware** (gate V5 de doc 36 §10: cada tipo publicado desde el
PC se ve en la Vita, sin `ERR_FAIL` de esquema).

**Esquema.** `godot/plantillas/generar_esquemas.py` tiene `TIPOS_VISOR` (lista D10 + `nav_msgs/Path` +
`nav2_msgs/action/NavigateToPose_FeedbackMessage`); se añade con `--visor`:

```fish
toolchains/rosbags-venv/bin/python godot/plantillas/generar_esquemas.py --visor --salida godot/visor-ros/ros/schema.rsch
```

`visor-ros/ros/schema.rsch`: 85 tipos, 10 545 B (antes 44 tipos, 6 030 B). Los demás proyectos **no cambian** (sin
`--visor` el blob sale idéntico byte a byte al de `rbkairos-plus`/`dron-mapeo`; comprobado con `cmp`). Tamaños CDR
típicos sin encapsulación (la prueba los imprime): `PointStamped` 48, `Range` 44, `NavSatFix` 129, `Imu` 320,
`PoseWithCovarianceStamped` 360, `Marker` 225 (10 puntos caben, 11 no), `Path` de 5 poses 384, `Log` 124,
`DiagnosticArray` (1 estado, 2 valores) 148, feedback de NavigateToPose 112. Todos ≤ 488.

| Display | Archivo | Tipos | Capa · coste | Dato intermedio |
|---|---|---|---|---|
| Punto | `displays/3d/punto.gd` | `PointStamped` (y `Point` con `frame_id`) | poses · `historial` inst. ESFERA | Vector3 Godot |
| Vector | `displays/3d/vector.gd` | `Vector3Stamped` (y `Vector3`) | poses · 1 FLECHA | Vector3 Godot × `escala` |
| Ejes | `displays/3d/ejes.gd` | `QuaternionStamped`, `TransformStamped` | poses · EJES + FLECHA | `[Transform3D, hijo]` |
| Imu | `displays/3d/imu.gd` | `Imu` | poses · EJES + 2 FLECHA | `[quat o null, acel, giro]` |
| Fuerza | `displays/3d/fuerza.gd` | `WrenchStamped`, `AccelStamped`, `TwistStamped`, `Twist` | poses · 2 FLECHA + ANILLO | `[lineal, angular]` |
| Rango | `displays/3d/rango.gd` | `Range` | poses · 1 CONO | `[r, ancho, radiation]` o 0.0 |
| MarcadorSimple | `displays/3d/marcador_simple.gd` | `Marker` (ARROW por pose, CUBE, SPHERE, CYLINDER, TEXT) | marcadores · `max_marcadores` | diccionario de acción |
| Poligono | `displays/2d/poligono.gd` | `PolygonStamped` | sensores_2d · `max_puntos` quads | PackedVector2Array m |
| Covarianza | `displays/2d/covarianza.gd` | `PoseWithCovarianceStamped` (+ `<p>/pose_cov` opcional) | sensores_2d · 30 | `[centro, yaw, λ1, λ2, θ, σyaw]` |
| Gps | `displays/2d/gps.gd` | `NavSatFix` | sensores_2d · `max_puntos` + 24 | Vector2 ENU m |

Todos van **en directo también en la Vita** (sin `topic_vita`: el canal no usa el camino compacto). Reglas nuevas en
`RegistroDisplays` (Marker: el gestor `3d/marcadores.gd` de V8 cuando exista; hasta entonces el simple).

### Decisiones de V5 no cubiertas (las más conservadoras)

1. **`--visor` opcional:** `TIPOS_VISOR` solo entra en las apps que lo piden; regenerar las demás no cambia su blob
   (un `.rsch` por app, T20; cada tipo más alarga la búsqueda lineal P1).
2. **Feedback de NavigateToPose por registro manual** (`ros/msg/nav2_msgs/action/*.msg`, Nav2 Jazzy) aunque D10 deja
   `nav2_msgs` fuera: lo pedía V4 (`estado_meta.gd`) y es un solo tipo (112 B). `generar_esquemas.py` registra solo
   cualquier `.msg` de `ros/msg/<paquete>/<msg|action>/`. Validar contra el Nav2 real (orden de campos).
3. **`nav_msgs/Path` en `TIPOS_VISOR`** (no está en D10): V3 lo usa en directo en el PC con ros2_vita.
4. **`std_msgs/Empty` sigue fuera** (D10 [?]); la prueba comprueba que no está.
5. **Nombres de la sentencia:** `ejes.gd` = orientación + transformada (doc 36a §4.2.7–4.2.8) y `fuerza.gd` = tornillo
   (§4.2.6), como dice doc 36 §10.
6. **Anillo del par perpendicular al eje** angular y de radio |par|/4 a mitad de la flecha: el esqueleto de §4.2.6
   lo escalaba en los ejes de la flecha y quedaba en el plano que contiene el eje (el ANILLO unidad tiene eje +Y).
7. **Cupo parcial:** con menos instancias que las pedidas, imu/fuerza/ejes crean sus piezas por orden (ejes →
   aceleración → giro; lineal → angular → anillo) en lugar de quedarse sin nada.
8. **MarcadorSimple** no es el gestor de V8: sin `frame_locked`, sin listas/líneas/puntos/mallas ni ARROW por 2 puntos
   (los cuenta en `ignorados`); alfa < 0,01 o escala nula = invisible (como RViz); ancho de la ARROW = 10 × `scale.y`
   (cabeza de diámetro 2·`scale.y`, como `arrow_marker.cpp`). Cada marcador es `top_level` en el marco fijo para que
   convivan marcos distintos. `canal.coalescer = false` (no perder ADD/DELETE).
9. **Covarianza:** sin elipsoide 3D (solo planta); abanico de yaw recortado a ±3 rad y sustituido por una raya si
   σ_yaw ≈ 0 (un polígono degenerado da «Invalid polygon»). `topic_vita` vacío por defecto: `pose_cov` llega con V6.
10. **GPS:** sin teselas de fondo; rastro solo si el fix se aleja `tol_pos` (0,5 m, como `2d/pose.gd`); marco = el fijo
    si la escena no pone `frame_id`.
11. **Polígono:** relleno solo si `Geometry2D.triangulate_polygon` triangula (evita el error con autocortes).
12. **Twist sin cabecera** → `frame_id = "base_link"` si la escena no pone otro.
13. Los displays V5 **no** se añaden aún a `visor-ros/main.tscn` (el ejemplo queda como en V1–V4; regla doc 35:
    se colocan como nodos en el `.tscn` de cada app); la prueba los monta en código.

```fish
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_directos.gd   # RESULTADO: 228/228
```

El `ERROR: RosMsg: tipo 'std_msgs/msg/Empty' no esta en el esquema` del log es el caso negativo (decisión 4). Con V5,
`pruebas/visor_hud.gd` comprueba que Joy, medidores, GoalStatusArray y el feedback **suscriben** (antes «sin
esquema») y `pruebas/visor_displays.gd` ve el Path estándar en «ok».

## Herramientas que publican (V7)

Estado: **hecho y verde en host** (`pruebas/visor_herramientas.gd`, 70/70) y **probado en vivo en el host** contra la
estación (`docker/vita-ros.sh up`, `transporte=xrce`, agente 127.0.0.1): `ros2 topic echo` en `vita_station` recibe
`/goal_pose`, `/initialpose` (con la covarianza de RViz) y `/clicked_point` con `frame_id: map`. **Sin validar en
hardware** (gate V7 de doc 36 §10: un toque = un evento; meta con ✕ llega a `/goal_pose`; panel trasero no disponible,
`docs/28:59`).

| Archivo | Herramienta (RViz) | Mensaje → topic | PC | Vita | QoS (doc 36 §6) |
|---|---|---|---|---|---|
| `herramienta_visor.gd` | base (`rviz_common::Tool`) | — | — | — | fiable, KEEP_LAST 5 (PC) / 1 (Vita), volátil |
| `herramientas/teleop.gd` | Teleop | `Twist` → `/cmd_vel`, 20 Hz | flechas + Mayús | stick izq. + **R mantenido**; △/✕ escala | fiable, 1 (`fiabilidad` = BE con el G1) |
| `herramientas/meta.gd` | Nav2 Goal | `PoseStamped` → `goal_pose` | pulsar, arrastrar el rumbo, soltar | igual + **✕** confirma (○ descarta) | fiable, 5/1 |
| `herramientas/pose_inicial.gd` | 2D Pose Estimate | `PoseWithCovarianceStamped` → `initialpose` | igual que meta | igual que meta | fiable, 5/1 |
| `herramientas/punto.gd` | Publish Point | `PointStamped` → `/clicked_point` | al soltar | un toque (sin ✕) | fiable, 5/1 |

**Controles.** SELECT (Tab en el PC) recorre ninguna → Teleop → Meta → Pose inicial → Punto → ninguna (orden del
árbol); la activa sale en la barra de estado. El táctil delantero llega como ratón (`emulate_mouse_from_touch`); en la
Vita cada pulsación escribe `[visor-herr] <nombre> toque n=… publicados=…`. Con la planta 2D visible (`planta` = el
nodo `Vista`) el punto tocado es la inversa de `VisorRos.planta_desde`; si no, rayo de `visor.camara` al suelo de
`marco_fijo_nodo` (o del origen) y, en Publish Point, rayo de física contra las colisiones del mundo. Todo pasa a ROS
con `rclgd.godot_to_ros_vector`; `header.frame_id` = `visor.marco_fijo`; sello `nodo.now()`.

**En la escena** (`godot/visor-ros/main.tscn`): `VisorRos/Hud/Herramientas` con Teleop, Meta, PoseInicial y Punto
(`planta` → `Planta/Vista`). Para que no choquen los botones: el banco E-W8-1 pasa a **START** (`boton = 6`) y
GestorHud cambia de pestaña solo con **L** (`boton_siguiente = -1`, R queda para el hombre muerto).

### Decisiones de V7 no cubiertas (las más conservadoras)

1. **`extends Node2D`** (el esqueleto de doc 36 §2.9.9 decía `Node`): cada herramienta dibuja su flecha fantasma (y la
   meta pendiente en naranja) en su `_draw()`, bajo el CanvasLayer del HUD; ≤ 4 *quads* fuera del recuento de
   GestorHud.
2. **El ciclo de SELECT incluye «ninguna»** y se arranca sin herramienta activa (`activa_al_inicio` lo cambia).
   Atiende el SELECT la herramienta activa (o la primera si no hay ninguna): un evento = un cambio.
3. **Rumbo a 0 en cada pulsación** (el esqueleto de doc 36a heredaba el de la meta anterior). Una pulsación nueva
   sustituye la meta pendiente; ○/Esc la descartan; al desactivar se descarta.
4. **Publish Point desactiva y vuelve a «ninguna»** (RViz vuelve a su herramienta por defecto; aquí no hay
   «Interact»). En la planta 2D el punto es el suelo (z = 0): sin física 2D.
5. **Teleop:** solo con la herramienta activa; al desactivarla en marcha manda el Twist cero. Escala multiplicativa
   1,0 (paso 0,25, tope 2,0) sobre `v_max`/`w_max` (g6-hmi usa m/s absolutos). `tick()` y `simular()` son públicos
   para las pruebas.
6. **Botones** [I, validar en hardware]: SELECT = `JOY_BUTTON_BACK`, ✕ = `JOY_BUTTON_A` (validado en G6), ○ =
   `JOY_BUTTON_B`, R = `JOY_BUTTON_RIGHT_SHOULDER`. `ui_accept` (Intro/Espacio) confirma en el PC.
7. **Sin táctil** (cursor con el stick derecho, rumbo con L/R) y la fuente `/vita/joy` **no** entran en V7.
8. `RegistroDisplays` y GestorHud no cambian: las herramientas no son displays de un tipo (no se crean por topic).

```fish
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_herramientas.gd   # RESULTADO: 70/70
```

**En la Vita** (con `docker/vita-ros.sh up` en el PC y el `.vpk` de `visor-ros`):

```fish
docker exec -it vita_station bash -lc "source /opt/ros/jazzy/setup.bash; ros2 topic echo /goal_pose geometry_msgs/msg/PoseStamped"
```

Verde: SELECT dos veces → barra «Meta»; un toque con arrastre deja la flecha naranja y **no** publica; ✕ → un solo
mensaje en el `echo` (`frame_id: map`, posición del toque); cada toque da una sola línea `[visor-herr] Meta toque n=`
en el log (n sube de uno en uno). Igual con `/initialpose` (covarianza 0,25 / 0,25 / 0,0685) y `/clicked_point` (sin ✕).

## TF y poses (V9)

Estado: **hecho y verde en host** (`pruebas/visor_tf.gd`, 78/78; `python3 docker/scripts/test_vita_relay.py`). **Sin
probar en vivo contra la estación ni validar en hardware** (gate V9 de doc 36 §10: 8 marcos a 10 Hz con `process` +≤
0,5 ms y ejes en su sitio frente a RViz). La comparación «mismo resultado que `RosTfListener` en el PC (± 1 mm)» queda
para el PC con rclgd: el editor de host (ros2_vita) no tiene `create_tf_listener`; la prueba compara con la
composición de transformadas esperada.

| Archivo | Pieza | Papel |
|---|---|---|
| `tf_ligero.gd` | TfLigero (`RefCounted`) | subconjunto de `RosTfListener` con la semántica de `modules/tf-tree`: `lookup_transform`, `can_transform`, `frame_exists`, `get_frame_names`, `get_frame_parent`, `get_last_error`, `clear`; ejes de Godot; ≤ 32 marcos |
| `displays/3d/tf.gd` | TF (`tf2_msgs/TFMessage`) | EJES por marco consultando `visor.tf` a 10 Hz; flechas hijo → padre y nombres solo en el PC; capa `tf` (8 HMI / 32 Viz) |
| `displays/2d/poses.gd` | PoseArray / ParticleCloud | triángulos en un lote; en la Vita `<p>/poses` (n ≤ 36); 100 *quads* |
| `displays/2d/covarianza.gd` | (V5, sin cambios de código) | ya leía `<p>/pose_cov`; ahora existe el módulo del relay |
| `ros/vc1.gd` | + `empaquetar_pose_cov`, `diezmar`, `empaquetar_poses`, `empaquetar_tf`, `leer_poses`, `leer_tf`, `leer_tf_marcos` | copia de `vita_relay_formatos.py` |

**Fuentes de TfLigero** (D3, 0 B extra por defecto): (1) `<p>/pose2d` → `marco_pose2d` (o el fijo) → `marco_base`,
suscrito por `VisorRos` en el camino compacto; (2) los links del robot horneado (`robot_joints.gd` llama a
`registrar_robot`; se leen en vivo de los nodos movidos por `/vita/joints`); (3) `VisorRos.tf_estaticos` en el `.tscn`
(«`padre>hijo x y z yaw`», ROS); (4) opcional, `tf_relay = true`: `<p>/tf`, `<p>/tf_marcos` y `<p>/tf_estatico`.
Con esto los displays 2D/3D dejan de dibujarse en el origen: `visor.transformada(frame)` coloca el scan (`base_scan`),
el robot (`base_link`) y lo demás. `godot/visor-ros/main.tscn` trae el display `TF` y el estático
`base_link>base_scan -0.032 0 0.172 0` (TurtleBot3 burger [I: valores del URDF de TB3, validar contra la estación]).

**Relay** (`vita_relay.py` + `vita_relay_formatos.py`, doc 36 §5.3): `pose_cov` (2 Hz, 44 B, de `pose_cov_in` =
`/amcl_pose`), `poses` (2 Hz, ≤ 464 B, de `poses_in` = `/particle_cloud`, `PoseArray` o `nav2_msgs/ParticleCloud`
con el tipo descubierto en el grafo) y `tf` (10 Hz, ≤ 288 B: hijos de `tf_lista`, por defecto `[odom]` = map → odom;
`tf_marcos` y `tf_estatico` fiables + TRANSIENT_LOCAL, ≤ 16 estáticos = 544 B). Comprobar: `python3
docker/scripts/vita_relay.py --comprobar hmi,pose_cov,poses,tf` (23,0 KB/s, 122 dgr/s). El perfil `viz` sigue sin
arrancar hasta que existan `marcadores` (V8) y `costmap` (V11).

### Decisiones de V9 no cubiertas (las más conservadoras)

1. **TfLigero sin el marco fijo = como sin TF** (D3): mientras no llegue nada que conecte con `marco_fijo` (p. ej. sin
   relay `pose` o en el host sin relay) `transformada()` devuelve la identidad, como V1–V8. Con el marco fijo
   conocido, un `frame` desconocido da `null` y el display se oculta con «sin TF» (como RViz).
2. **`marco_pose2d` = "" ⇒ el fijo** (supone map ≈ odom, la deriva visible de doc 36 §9.3.3). Con el módulo `tf` del
   relay (lista blanca por defecto `[odom]` = map → odom) la escena pone `marco_pose2d = "odom"`. `pose2d` no se amplía
   (D5.4).
3. **`tf_relay` apagado por defecto** (el módulo es opcional): 3 suscripciones más solo si la escena lo pide.
4. **Estáticos de la escena** como texto `padre>hijo x y z yaw` (solo yaw: montajes planos); una línea que no vale se
   avisa y se salta. El `tf_estatico` del relay los pisa (mismo hijo).
5. **Tope de 32 marcos contando padres y raíces**, como `tf-tree` (el esqueleto de doc 36 §2.9.6 solo contaba hijos y
   no pasaba `test_full`). `registrar_robot` deja 8 huecos libres para pose2d y el relay y registra solo `Node3D` puros
   sin `urdf_joint` (ni mallas ni juntas ni `RosFrame`/`Base`); supone la estructura de urdf2godot (links bajo
   `RosFrame`, en ejes de ROS). `link_raiz` del robot debe ser `VisorRos.marco_base`.
6. **Robot con TfLigero:** si `frame_id` es un marco (por defecto `base_link`), cada pose2d coloca el **display** con
   `visor.transformada(frame_id)` (no el hijo: así no se suma dos veces) y mete el mismo valor en TfLigero (idempotente;
   el orden de los callbacks de VisorRos y del robot no está garantizado). Con `frame_id` vacío, como V3.
7. **Display TF:** cupo `max_marcos_vita` (8) en la Vita y `max_marcos` (32) en el PC (× 2 con flechas); los marcos que
   no caben no se crean; sin caducidad por marco (TfLigero no guarda sello); nombres apagados por defecto (glifos, D11).
   No se suscribe a `/tf` aunque `RegistroDisplays.crear()` le ponga ese topic.
8. **Lo demás se recoloca al llegar su mensaje** (no en cada cambio de TF): el scan a 10 Hz va con la última pose.
9. **poses:** diezmado por paso fijo (como el scan); los pesos de `ParticleCloud` no se usan; sin `3d/poses.gd`.
10. **pose_cov lleva varianzas** (`cov[0]`, `cov[1]`, `cov[7]`, `cov[35]`), aunque la tabla §5.3 las llame σ: es lo que
    ya leía `covarianza.gd` (V5). Su `topic_vita` sigue vacío por defecto: el directo de 364 B cabe en la Vita.
11. **tf del relay:** índices fijos por orden de llegada; un hijo que cambia de padre ocupa un índice nuevo; `/tf_static`
    se suscribe fiable + TRANSIENT_LOCAL; el `tf_estatico` que llega antes que `tf_marcos` se reaplica al llegar éste.
12. **Prueba de bytes** con la huella de los **bits float32** (`huella_f32`), en `pruebas/visor_tf.gd` y
    `test_vita_relay.py` (no en `pruebas/runner.gd`, para no chocar con V8 en paralelo).

```fish
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_tf.gd   # RESULTADO: 78/78
python3 docker/scripts/test_vita_relay.py                                        # TODO OK
```

**En la Vita** (gate V9; con `docker/vita-ros.sh up`, una fuente con `/tf` map → odom, p. ej. Nav2 + TB3, y el `.vpk`
de `visor-ros` con `tf_relay = true` y `marco_pose2d = "odom"` en `VisorRos`):

```fish
docker/vita-ros.sh relay hmi,tf,pose_cov,poses
```

Verde: el scan sigue al robot en la planta (no en el origen); la vista orbital enseña los EJES de map, odom, base_link
y base_scan donde los pone RViz; `[perfil-gd] … visor/TF=` ≤ 500 µs más que sin el display; `relay_bw` +≤ 4 KB/s.

## Relay VC/1 rev. 2: base + `rosout`, `diag`, `ritmo` (V6)

Estado: **hecho y verde en host** (`pruebas/visor_relay.gd`, 80/80; `python3 docker/scripts/test_vita_relay.py`;
`pruebas/runner.gd` 16/16 con la huella cruzada). **Sin validar en hardware** (gate V6 de doc 36 §10: 20 avisos/s
durante 5 min, FPS sin bajar de escalón y `reliable_dropped` = 0).

**Relay** (`docker/scripts/`; contrato en doc 36 §5 y sentencia W13 D4–D5):

| Pieza | Qué |
|---|---|
| `vita_relay_formatos.py` (nuevo) | funciones puras, referencia de bytes: VC/1 de siempre (sin cambiar un byte), `trocear`/`cabecera` (cabecera común `[seq & 0x7FFF, trozo, n_trozos, n, …]`), `relay_info`, `PRESUPUESTO`/`PERFILES`/`resolver_modulos` (tope 100 KB/s y 200 dgr/s), `epoca_mapa`, `cdr_log`/`cdr_diag` (tamaño exacto = rosbags), `compactar_log`, `compactar_estado`, `PlanDiag`, `parsear_ritmo`, `CuboBytes` |
| `vita_relay.py` | solo el nodo (reexporta lo de arriba); módulos nuevos `rosout`, `diag`, `ritmo`; `relay_info`; se niega a arrancar si el presupuesto se pasa; época del mapa |
| `docker/vita-ros.sh relay [mód] [pref] [ritmo]` | p. ej. `relay hmi` o `relay hmi,ritmo /vita imu=/imu/data@20`; `relay todo` → «NO arranca: presupuesto 65.9 KB/s, 229 dgr/s > 100/200» |

Salidas nuevas: `<p>/relay_info` (String fiable + TRANSIENT_LOCAL, `VC/1.2;scan,pose,…`), `<p>/rosout` (`Log`, ≥ WARN,
`file`/`function` vacíos, `msg` ≤ 200 car., fiable, ≤ 10/s), `<p>/diagnostics` (`DiagnosticArray` de UN estado, ≤ 3
pares, textos ≤ 40 car., best effort ≤ 10 Hz: primero los que cambian de nivel o mensaje y un repaso a 1 Hz por
estado) y `<p>/ritmo/<nombre>` (el mismo mensaje, bytes tal cual, a Hz fija y solo si ≤ 488 B). Perfil `hmi` =
19,1 KB/s y 108 dgr/s nominales (doc 36 §5.4). Comprobar sin ROS: `python3 docker/scripts/vita_relay.py --comprobar hmi`.

**Godot:** `ros/vc1.gd` gana `MAX_BE`, `MAX_F32`, `MAX_I16`, `cabecera(d)`, `trocear(...)` (misma salida que Python;
huella en `pruebas/runner.gd` y en `test_vita_relay.py`) y `leer_relay_info(s)`; lo de VC/1 no cambia, así que V3 y
g1-sensores siguen igual. `canal_display.gd` gana `max_pendientes`/`descartados` (tope de cola con `coalescer = false`).

| Display | Archivo | PC | Vita | Pestaña · cupo (D6) |
|---|---|---|---|---|
| Consola | `displays/hud/consola.gd` | `/rosout` directo, fiable | `<p>/rosout` (mismo tipo) | Consola · 6 líneas × 40 car. = 240 |
| Diagnostico | `displays/hud/diagnostico.gd` | `/diagnostics` directo, fiable, profundidad 1 | `<p>/diagnostics`, best effort, «solo problemas» | Diagnóstico · 8 filas × 30 = 240 |

Los dos están en `RegistroDisplays` y en `godot/visor-ros/main.tscn` (pestañas `Diagnostico` y `Consola` tras `Mando`).

### Decisiones de V6 no cubiertas (las más conservadoras)

1. **Perfiles `viz` y `percepcion`** se expanden y caben en el presupuesto, pero el relay no arranca con ellos hasta
   que existan sus módulos (V8–V11): dice cuáles faltan. «todo» se rechaza por presupuesto (lo pide la sentencia).
2. **Módulos por defecto sin cambios** (`scan,pose,joints,mapa,path`): `rosout` y `diag` se piden con `hmi` o a mano.
3. **Época del mapa:** con la misma geometría ya no se republica `mapa_meta` (es *latched* y no cambia); una época
   nueva vacía la caché de teselas para mandarlas todas.
4. **rosout:** nombre del nodo recortado a 60 car. (el formato no lo fijaba); cola de 20 y un mensaje por tic de 0,1 s
   (lo que sobra se descarta); si el UTF-8 lo pasa de 488 B, se recorta más el texto.
5. **diagnostics:** `hardware_id` vacío (el widget no lo enseña); «cambio» = nivel o mensaje (no los valores, que
   cambian siempre y saturarían); entrada por defecto `/diagnostics` (en el PC el widget también, no
   `/diagnostics_agg`: el agregador es opcional).
6. **ritmo:** entradas `nombre=/topic@hz` (sin «:» para que pasen por `-p ritmo:='[…]'`), tipo descubierto en el grafo
   (reintento cada 2 s), reenvío de bytes crudos (`raw=True`), solo mensajes nuevos, ≤ 30 Hz en total al arrancar y
   ≤ 10 KB/s por ventana de 1 s en marcha.
7. **D6 «8 × 30 caracteres»** más el cuadro de color daba 248 > 240: el cuadro entra en los 30 (texto ≤ 29). Consola
   sin fondo (6 × 40 ya son los 240). Mismos números en el PC.
8. **Diagnóstico en directo** (PC o Vita sin relay): fiable y profundidad 1 (doc 36 §6) si `fiabilidad` es AUTO;
   nivel `byte` leído de forma defensiva (entero, `PackedByteArray` o String).
9. `relay_info` aún no lo consume el HUD (barra de estado): el lector está en `vc1.gd`.
10. **Qué módulo «sobra»** cuando el tope se pasa: el que más pesa en la dimensión excedida (datagramas o bytes) y, a
    igualdad, el pedido más tarde (los extras van tras el perfil `hmi`): `relay todo` dice «sobra «ritmo»».

Medido en la estación (2026-11-14, `fuente-visor` + 20 avisos/s en `/rosout` + 6 estados en `/diagnostics`, relay
`hmi`): `relay_bw` 14,1 KB/s y 103 msg/s (≤ 20 KB/s); `ros2 topic bw` `/vita/rosout` 1,25 KB/s (10 Hz),
`/vita/diagnostics` 1,38 KB/s, `/vita/scan_compacto` 3,87 KB/s.

```fish
python3 docker/scripts/test_vita_relay.py                                          # TODO OK
toolchains/rosbags-venv/bin/python docker/scripts/test_vita_relay.py               # + tamaños CDR = rosbags
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_relay.gd  # RESULTADO: 80/80
```

## Marcadores (V8)

Estado: **hecho y verde en host** (`pruebas/visor_marcadores.gd`, 62/62; `python3 docker/scripts/test_vita_relay.py`)
y **probado en vivo en el host** contra la estación (`docker/vita-ros.sh up` + relay `marcadores` + un publicador de
`MarkerArray` a 5 Hz con 5 sólidos, un LINE_STRIP de 50 puntos y un texto; `main.tscn` con `transporte=xrce
compacto=1`): `/vita/marcadores` a 5,0 Hz (≈ 0,31 KB por estado), `/vita/marcador_puntos` a 4 Hz, el texto llega
fiable; en Godot 5 sólidos, la línea (49 *quads*) y el texto, y al borrar el cubo con DELETE el siguiente estado
completo lo quita (5 → 4 vivos). **Sin validar en hardware**: gates **G-W13-M1** (pool lleno a 10 Hz: `drawn` + cupo,
`avg_submit_us` ≤ 9 000, ≥ 30 FPS), **G-W13-M2** (48 marcadores con `lifetime` 2 s y DELETEALL por ns, 5 min: nº de
hijos constante) y **G-W13-M3** (10 % de pérdida con netem: sin fantasmas > 0,4 s, `process` ≤ 4 ms, ≤ 15 KB/s).

| Archivo | Pieza | Papel |
|---|---|---|
| `fabrica_marcadores.gd` | FabricaMarcadores (estático) | `Marker.type` → PrimitivasViz + PaletaViz; `capa()` decide quién dibuja (SOLIDO / PLANO / TEXTO); `valido` (NaN), `expira_ms` (reloj de recepción), `aplicar` (pose × escala), ARROW por 2 puntos, horneado de listas ≤ 64 y TRIANGLE_LIST ≤ 1 000 tri, `malla_recurso` (tabla `package://` → `res://`) |
| `displays/3d/marcadores.gd` | Marcadores (`Marker`, `MarkerArray`; relay `<p>/marcadores`) | gestor ns/id de los SÓLIDOS: ADD = MODIFY, DELETE, DELETEALL por ns, recrear si cambia el tipo, NaN rechazado, `lifetime`, `frame_locked`, pool por tipo; estado completo por trozos en la Vita |
| `displays/2d/marcadores_2d.gd` | Marcadores2D (mismos tipos; relay `<p>/marcador_puntos` + `<p>/marcador_texto`) | LINE_STRIP, LINE_LIST, POINTS, ARROW_STRIP, listas > 64 y TEXT_VIEW_FACING superpuestos al 3D (reproyección ≤ 20 Hz), cupo `resto_2d` en *quads* |

**Relay** (`docker/scripts/`): módulo `marcadores` (`docker/vita-ros.sh relay hmi,marcadores`; entra en el perfil
`viz`, que sigue esperando a V9–V11). `vita_relay_formatos.py` gana `EstadoMarcadores` (la semántica de RViz sin
ROS), `PlanRonda` (puntos y textos: primero lo que cambia, después un repaso), `empaquetar_marcadores`,
`empaquetar_puntos`, `texto_marcador`, `clave_marcador` (FNV-1a), `color_marcador` e `indice_paleta` (copia de
`PaletaViz`). Parámetros nuevos del nodo: `marcadores_in` (`/visualization_marker_array`), `marcador_in`
(`/visualization_marker`) y `marco_fijo` (`map`, TF con tf2). **`vc1.gd`** gana el bloque «marcadores» (mismas
funciones; huellas de bytes float32 cruzadas en `test_vita_relay.py` y `pruebas/visor_marcadores.gd`).

**En la escena** (`godot/visor-ros/main.tscn`): `VisorRos/Marcadores` (3D) y `VisorRos/Marcas2D/Marcadores2D`
(`gestor_3d` → `../../Marcadores`), los dos sobre `/visualization_marker_array`. `RegistroDisplays`: `Marker` y
`MarkerArray` → el gestor (antes el marcador simple de V5) y `*/marcador_puntos` → `marcadores_2d.gd`.

### Decisiones de V8 no cubiertas (las más conservadoras)

1. **Dos displays, un reparto:** sólidos en 3D y líneas/puntos/texto en 2D, en el PC y en la Vita (un solo camino de
   código): los prismas 3D de LINE_STRIP del PC (doc 36a §4.7.2) y el `Label3D` no entran. Cada display lleva su
   propia tabla ns/id y `FabricaMarcadores.capa()` decide; si un id pasa de sólido a línea (o al revés), el que lo
   tenía lo borra y el otro lo crea.
2. **Clave compacta con FNV-1a de 32 bit** del ns en UTF-8 (`hash()` de Python cambia en cada proceso). Dos pares
   (ns, id) pueden dar la misma clave de 24 bit (se pisan; raro).
3. **Estado completo con cupo lleno:** las claves nuevas de un `seq` que no encuentran nodo libre se colocan al
   completarse el `seq`, después de reciclar las que no llegaron (sin eso, sustituir 12 marcadores por otros 12
   dejaba la pantalla vacía un ciclo). Un trozo perdido = ese `seq` no purga (lo hace el siguiente completo).
4. **Tope de nodos:** `max_marcadores` (256 en el PC), y en la Vita `min(cupo, 48)` (HMI 12, Viz 32). Con el pool de un
   tipo vacío y el tope alcanzado se reutiliza un nodo libre de otro tipo: nunca se crean más nodos que el tope.
5. **Relay:** el orden del estado es el de llegada y se cortan los que pasan de 33 (`cortados`); sin TF al
   `marco_fijo` el marcador no se manda ese ciclo (`sin_tf`), como RViz que no lo dibuja; sin `frame_locked` el TF se
   resuelve una vez. TRIANGLE_LIST **no viaja** a la Vita (`ignorados`); MESH_RESOURCE viaja como tipo 10 y la Vita
   dibuja un CUBO con su escala; ARROW por 2 puntos viaja como flecha por pose (yaw y largo; pierde el cabeceo, D14).
   Los colores por punto y el color del texto no viajan (un color por marcador; texto en blanco).
6. **Puntos del relay:** `[clave, tipo, color, ancho]` + ≤ 3 trozos de 36 = **108 puntos por marcador** (el resto se
   corta); un marcador por ronda a 4 trozos/s. La Vita monta la línea al tener todos los trozos de su `seq`.
7. **Purga 2D en la Vita:** las claves de puntos y textos que ya no están en el último estado completo de
   `<p>/marcadores` (lo recibe el gestor 3D: `gestor_3d`, o el primer display del visor con `retener_solo`); sin
   gestor, una entrada compacta caduca a los `caducidad_compacta_s` (10 s) sin refrescarse.
8. **ARROW por 2 puntos (3D):** `CILINDRO` girado 90° (no se añade `CILINDRO_Z` a PrimitivasViz: sin variantes nuevas)
   y `CONO` con el vértice en la punta. **ARROW_STRIP (12):** polilínea 2D + triángulo 2D en el último tramo (RViz no
   lo dibuja: semántica [?]).
9. **Listas y triángulos horneados:** se re-hornean solo si cambian los datos (firma) y en la Vita como mucho 1 vez/s
   (si no, se conserva la malla anterior: cada malla nueva gasta arena, H9). Más de 64 elementos → puntos 2D.
10. **MESH_RESOURCE:** solo mallas ya horneadas (`mallas` = tabla `package://…` → `res://…`, o una uri `res://`), Mesh o
    la primera malla de una escena; sin ella, CUBO y un aviso por uri. El GLTF en caliente del PC no entra en V8.
11. **Prueba de bytes en `pruebas/visor_marcadores.gd`** (proyecto `visor-ros`, que trae el esquema de `Marker`), no
    en `pruebas/runner.gd`: así `runner.gd` (g1-sensores 16/16) no cambia. Huella = MD5 del hex de los float32.
12. `MarkerArray` **no** entra en `TIPOS_VISOR` (D10): en la Vita llega solo por el relay; en el PC lo resuelve rclgd.

```fish
python3 docker/scripts/test_vita_relay.py                                              # … marcadores ok, TODO OK
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_marcadores.gd # RESULTADO: 62/62
docker/vita-ros.sh relay hmi,marcadores                                                # 28,3 KB/s, 129 dgr/s
```

El aviso «MESH_RESOURCE … sin malla horneada» y «Marcadores pide 48 … y recibe 12» del log son casos de la prueba.

## Revisión V2 (2026-11-14)

Revisión escéptica y de código de V5–V9 y de la fusión V8 + V9: `docs/ia/workshops/posts/V2-revision.md` (hallazgos,
veredictos de las decisiones anotadas arriba, presupuestos de `main.tscn` y guion único de hardware). Cambios:

- `VisorRos.marco_mundo_pose2d()`: con `marco_pose2d` puesto (p. ej. «odom») pero aún sin unir al marco fijo (relay sin
  el módulo `tf`), pose2d cuelga del fijo como con "" (antes TODO quedaba en el origen). Así `godot/visor-ros/main.tscn`
  lleva `marco_pose2d = "odom"` y `tf_relay = true` y la misma `.vpk` vale con y sin el módulo `tf`.
- `VisorRos` emite `pose2d_tf(m)`; `robot_joints.gd` se cuelga de ahí en lugar de abrir otra suscripción a
  `<p>/pose2d` (cada lector XRCE recibe su copia; V9 había pasado de 2 a 3 lectores).
- `[perfil-gd]` añade `rx_paq`, `topic_dropped`, `reliable_dropped`, `be_dropped` y `reconexiones` (gate V6) y
  `3d/marcadores.gd` escribe cada 5 s `[visor-marc] vivos= nodos= hijos= tope= sin_sitio= completos=` (gates M1–M3).
- `fabrica_marcadores.gd`: un nodo del pool que pasa de lista horneada a otro tipo y vuelve con los mismos datos ya
  no se queda con la malla del otro tipo (firma ligada a la malla horneada). Prueba nueva en `visor_marcadores.gd`.
- `2d/poses.gd`: `topic_vita = "poses"` por defecto (en la Vita el PoseArray directo no cabe con n > 8).
- `2d/marcadores_2d.gd`: ancho NaN del relay → ancho mínimo.
- Estación: `docker/vita-ros.sh relay … [tf_lista]`, `fuente-v2 [avisos,marcadores,vida,tf] [n]`
  (`docker/scripts/fuente_prueba_v2.py`) y `netem <IP_VITA> [%]` / `netem off` (pérdida solo hacia la Vita, M3).

```fish
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_tf.gd          # RESULTADO: 79/79
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_marcadores.gd  # RESULTADO: 63/63
```

## Decisiones del juez sobre la fase V2 (2026-11-14)

`docs/ia/workshops/posts/V2-juez-fable.md` (resuelve los desafíos N3 y N7 de la revisión V2):

- **Marcadores:** no cambia ningún límite (cupo 12 HMI / 32 Viz, relay 33, `TOPE_VITA` 48). Los gates miden el cupo:
  G-W13-M1 en HMI (`nodos=12`, ≥ 55 FPS, `avg_submit_us` ≤ 6 000) y G-W13-M1v en Viz (`nodos=32`, ≥ 30 FPS).
- **Escenas de prueba de `godot/visor-ros/`** (regla doc 35), conmutables en la Vita sin reexportar:
  `main.tscn` (HMI), `main_viz.tscn` (heredada: `perfil = VIZ`, TF con 32 marcos) y `banco_v5.tscn` (los 10 displays
  directos de V5 como nodos, perfil Viz; gate V5). El nodo `SelectorEscena` (`visor-ros/selector_escena.gd`) pasa a la
  siguiente con **L + R + START** (F9 en el PC) y guarda la elección en `user://visor_escena.txt`, que la escena
  principal lee al arrancar. **Validar en hardware.**
- `VisorRos._conectar_deferred` no falla si la escena se cambia antes de conectar.

```fish
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_escenas.gd     # RESULTADO: 21/21
```

## Percepción (V10)

Estado: **hecho y verde en host** (`pruebas/visor_percepcion.gd`, 63/63; `python3 docker/scripts/test_vita_relay.py`,
también dentro de la estación con OpenCV) y **probado en vivo en el host** contra la estación (dominio ROS 47 aislado:
`fuente_prueba_visor.py` + `fuente_prueba_v2.py percepcion` + relay `percepcion`, 20 s): `/vita/camara/compressed` a
2,9 Hz con 1 799 B por mensaje (JPEG 160×120 q40 de una escena 640×480 con ruido), `/vita/detecciones` 472 B a 4,9 Hz,
`/vita/detecciones3d` 464 B a 4,9 Hz, `/vita/nube2d` 480 B a 14,8 trozos/s, `det_clases` = «persona,coche,perro,bici»;
`relay_bw` **28,1 KB/s** medio (máx. 28,2) con el perfil `percepcion` completo (nominal 40,0 KB/s y 154 dgr/s).
**Sin validar en hardware**: gate **E-W8-5** (JPEG ≤ 6 ms decodificar + subir en la Vita; en el host 0,1 ms) y
`process` de un trozo de nube ≤ 2 ms (en el host 0,05–0,08 ms por trozo de 76 puntos).

| Archivo | Pieza | Papel |
|---|---|---|
| `displays/hud/imagen.gd` | Imagen (`CompressedImage`; `Image` solo PC; relay `<p>/camara/compressed`) | decodifica el motor (jpg/png), textura reutilizada (`update`), aspecto conservado, `rect_imagen()`; BGR con *shader* en el PC; `ms_ultimo`/`ms_max` para E-W8-5 |
| `displays/hud/cajas_2d.gd` | Cajas2D (`Detection2DArray` PC; relay `<p>/detecciones` + `<p>/det_clases`) | marcos y «clase 87%» sobre la imagen (`imagen` → hud/imagen.gd), ≤ 150 *quads* |
| `displays/2d/cajas_3d.gd` | Cajas3D (`Detection3DArray` PC; relay `<p>/detecciones3d`) | 12 aristas por caja superpuestas al 3D en un `draw_multiline_colors`, etiqueta en TextoSuperpuesto, reproyección ≤ 20 Hz, ⌊cupo/12⌋ cajas en la Vita |
| `displays/2d/nube.gd` | Nube (`PointCloud2` PC; relay `<p>/nube2d`) | planta 2D, color por banda de altura, un lote por trozo; PC con `to_float32_array()` y diezmado |
| `clases_deteccion.gd` | ClasesDeteccion | suscripción auxiliar *latched* a `<p>/det_clases` y color estable por clase |

**Relay** (`docker/scripts/`): módulos `camara`, `det2d`, `det3d` y `nube` (`docker/vita-ros.sh relay percepcion`).
Funciones puras en `vita_relay_formatos.py` (bloque «percepción (V10)»: `empaquetar_det2d`/`leer_det2d`,
`empaquetar_det3d`/`leer_det3d`, `TablaClasesDet`, `voxelizar_nube` (referencia) y `voxelizar_nube_np` (la del nodo,
misma salida), `empaquetar_nube`, `cdr_compressed_image` (= rosbags), `tam_camara`, `recomprimir_camara`); el NODO de
estos módulos va aparte en `vita_relay_percepcion.py` (`vita_relay.py` solo llama a `iniciar_percepcion`). Parámetros:
`camara_in` (`/camera/color/image_raw/compressed`; Image o CompressedImage, tipo descubierto en el grafo),
`camara_hz` (3; máx. 5; 0 apaga), `det2d_in` (`/detections`), `det2d_tam` (`[640, 480]`), `det3d_in`
(`/detections_3d`), `nube_in` (`/points`), `marco_fijo` (`map`, compartido con marcadores). **`vc1.gd`** gana el bloque
«percepción» (mismas funciones; huellas cruzadas det2d/det3d float32 y nube int16 en `test_vita_relay.py` y
`pruebas/visor_percepcion.gd`). Fuente sintética: `docker/vita-ros.sh fuente-v2 percepcion`.
Estación [V]: OpenCV 4.6.0, numpy 1.26 y PIL 10.2 dentro de `vita_station`; **sin** `cv_bridge` ni `sensor_msgs_py`
(la nube se decodifica con numpy y dtype estructurado). En el portátil/PC sin OpenCV, `recomprimir_camara` usa PIL.

**En la escena**: `godot/visor-ros/main_percepcion.tscn` hereda `main.tscn` y añade la pestaña **Cámara** (Imagen +
Cajas2D), `Planta/Vista/Nube` y `Marcas2D/Cajas3D`. **No** entra en la lista de `SelectorEscena` (la prueba
`visor_escenas.gd` fija el ciclo main → main_viz → banco_v5): se añade cuando toque el gate de hardware de V10.
`RegistroDisplays`: `*/detecciones`, `*/detecciones3d`, `CompressedImage`, `Image` (solo PC), `PointCloud2` y
`vision_msgs` 2D/3D (solo PC; no están en `TIPOS_VISOR`, D10).

### Decisiones de V10 no cubiertas (las más conservadoras)

1. **Tope de la cámara 2 994 B** de mensaje (no 3 000): el máximo con el que el perfil `percepcion` suma ≤ 40,0 KB/s
   nominales (39,998; con 3 000 eran 40,016). Se aplica en `PRESUPUESTO["camara"]` desde el bloque V10 (aditivo).
   Si el JPEG q40 no cabe, se baja a q30, q20 y q10; si ni así, la imagen se salta (`saltadas`, aviso cada 50).
2. **Aspecto conservado** al bajar a 160×120 (16:9 → 160×90), nunca se amplía; las cajas 2D viajan en px de la imagen
   ORIGINAL con su `[ancho, alto]` (del módulo `camara` si está activo; si no, `det2d_tam`).
3. **Solo lo nuevo**: det2d, det3d, nube y cámara no repiten un dato viejo (a diferencia de pose o scan); el display lo
   da por caducado (`caducidad_s` 1 s en cajas, 2 s en imagen y nube).
4. **Detecciones**: la mejor hipótesis de cada detección; las 18 / 12 de más score (empate: orden de llegada), fuera
   las que traen NaN/Inf. `class_id` → índice por orden de llegada en `det_clases` (≤ 64 clases, ≤ 24 caracteres, la
   coma pasa a «;»; las que no caben van como −1 = «?»). Sin resultados: el `id` de la detección y score 1.
5. **Det3d y nube se transforman al marco fijo en el relay** (tf2, como marcadores); sin TF ese ciclo no se manda.
   Yaw de la caja = yaw de la orientación compuesta (se pierden cabeceo y alabeo, como D12 acepta para el HUD).
6. **Nube**: el PRIMER punto de cada vóxel de 10 cm (con sus cm, no el centro del vóxel) y, si pasan de 228, diezmado
   por paso fijo (como el scan). Redondeo a cm con `floor(v·100 + 0,5)` (idéntico en numpy y GDScript; `round()` de
   Python redondea al par). En la Vita una nube nueva se enseña al completar sus trozos; si empieza otra antes, se
   enseña lo que llegó (un trozo perdido no congela la nube).
7. **Fiabilidad**: cajas 2D/3D directas (PC) en FIABLE con profundidad 1 (doc 36 §6); por el relay, `AUTO` = best
   effort (un suscriptor fiable no casaría con el relay). La imagen, fiable en los dos caminos.
8. **Imagen cruda solo PC** y solo 8 bit (rgb8, rgba8, bgr8, bgra8, mono8, 8UC1, 8UC3; BGR por *shader*); 16UC1,
   32FC1, `compressedDepth` (T4) y filas con relleno se rechazan con `motivo` (la profundidad del PC queda para V14).
   Un JPEG corrupto deja además un error del motor en el log (`image_loader_libjpeg_turbo`), no de script.
9. **PointCloud2 directo (PC)**: solo x, y, z FLOAT32; *big endian* rechazado (T28: no se usa `bswap32`); color por la z
   del marco del sensor; `max_puntos_pc` = 4 000.
10. **Prueba de bytes en `pruebas/visor_percepcion.gd`** (no en `runner.gd`, como V8).
11. **Hallazgo** (no corregido, fuera de V10): `2d/pose.gd` (Odom) pide 101 *quads* y doc 36 §7.2 le da 100; con la
    nube (228) la zona `sensores_2d` de `main_percepcion.tscn` se pasa en 1 y Odom recibe 99 (aviso en el log).

```fish
python3 docker/scripts/test_vita_relay.py                                               # … percepción ok, TODO OK
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_percepcion.gd  # RESULTADO: 63/63
docker/vita-ros.sh fuente-visor                                                         # (otra terminal)
docker/vita-ros.sh fuente-v2 percepcion                                                 # (otra terminal)
docker/vita-ros.sh relay percepcion                                                     # 40,0 KB/s y 154 dgr/s nominales
```

## Costmap (V11)

Estado: **hecho y verde en host** (`pruebas/visor_costmap.gd`, 54/54; `python3 docker/scripts/test_vita_relay.py`
«costmap ok») y **probado en vivo en el host** contra la estación (2026-11-14): `fuente_prueba_costmap.py` (10 × 10 m
a 5 cm con paredes, inflado, esquina desconocida y un obstáculo que se mueve por `_updates`) + relay
`mapa,costmap` con prefijo `/v11` + `visor-ros -- transporte=xrce compacto=1 agente=127.0.0.1 perfil` (por el
agente XRCE): 200×200 → 100×100 a 10 cm = 28 teselas de 260 B (`ros2 topic bw`: 0,28 KB por mensaje), 10,07
teselas/s, **repaso completo en 2,9–3,2 s** (con parches intercalados), parches del obstáculo primero, una tesela
descartada (llegó antes que la meta), tesela ≤ 158 µs y composición ≤ 242 µs en el host, `compuesto=true`.
**Sin validar en hardware**: gate **G-W13-M5** (costmap 4 bit con Nav2 + TB3: repaso completo ≤ 3 s, ≥ 30 FPS).

| Archivo | Pieza | Papel |
|---|---|---|
| `costmap_textura.gd` | CostmapTextura (`RefCounted`) | meta + teselas 32×16 a 4 bit → imagen del costmap (LUT 256 × 8 B + `blit_rect`, colores de `PaletaViz.lut16_costmap()` con `alfa`); época; **composición en CPU** sobre la imagen del mapa por regiones sucias (`blit_rect` del mapa + `resize` NEAREST + `blend_rect`), subida ≤ 4 Hz |
| `displays/2d/costmap.gd` | Costmap (`OccupancyGrid`; relay `<p>/costmap_tesela` + `<p>/costmap_meta`) | PC: `OccupancyGrid` con la rampa «costmap» de RViz (MapaTextura) dibujado encima del mapa con `alfa` 0,7. Vita: decodifica en CostmapTextura y, si `sobre_mapa` (`../Mapa`) es un Mapa con mapa, se engancha a él (`costmap_encima`) y no dibuja nada; si no, dibuja su propia textura. `[visor-costmap]` cada 5 s en la Vita |
| `displays/2d/mapa.gd` (cambio) | Mapa | con `costmap_encima`, marca la región de cada tesela del mapa y dibuja la textura COMPUESTA (sigue siendo 1 *quad*) |

**Relay** (`docker/scripts/`): módulo `costmap` (`docker/vita-ros.sh relay hmi,costmap`; con él **el perfil `viz`
ya arranca**: 35,0 KB/s, 153 dgr/s). `vita_relay_formatos.py` gana el bloque «V11» (`celda_costmap_4bit`,
`factor_costmap`, `reducir_costmap`, `empaquetar_tesela_costmap`/`desempaquetar_…`, `teselas_costmap`,
`meta_costmap` y `EstadoCostmap`, el módulo sin ROS: completo, parches, época y cola). Parámetros del nodo:
`costmap_in` (`/global_costmap/costmap`), `costmap_updates_in` (`costmap_in` + `_updates`, `map_msgs/OccupancyGridUpdate`)
y `costmap_res_min` (0,1 m). **`vc1.gd`** gana el bloque «costmap» (mismas funciones; huella de enteros
`HUELLA_COSTMAP` cruzada en `test_vita_relay.py` y `pruebas/visor_costmap.gd`). Estación: `docker/vita-ros.sh
fuente-costmap [s]` (`docker/scripts/fuente_prueba_costmap.py`). **Escena:** `godot/visor-ros/main.tscn` trae
`Planta/Vista/Costmap` (`/global_costmap/costmap`) justo después de `Mapa`. **RegistroDisplays:** `*/costmap_tesela`
y todo `OccupancyGrid` cuyo topic contenga «costmap» → `2d/costmap.gd`.

### Decisiones de V11 no cubiertas (las más conservadoras)

1. **Display propio + composición en el Mapa:** el costmap tiene su display (`2d/costmap.gd`: PC, registro, sin mapa)
   y la composición la dibuja el Mapa (una textura, 1 *quad*, D2 y doc 36a §4.6.2). El enganche es por `sobre_mapa`
   (NodePath), como `gestor_3d` de Marcadores2D. `Mapa3D` no compone (es `solo_pc` en la escena).
2. **Niveles de 4 bit:** el más cercano de la LUT (`[255, 0, 8, 16, …, 88, 98, 99, 100]`); 1–4 → 8 y 93–98 → 98;
   los ilegales > 100 → letal (Nav2 no los publica).
3. **Reducción por máximo** con `f = ceil(0,1 / res)` (5 cm → 10 cm); −1 solo si toda la celda gruesa es desconocida.
   Las celdas de una tesela fuera del costmap viajan como 0 y no se pintan.
4. **Época:** una tesela de otra época (o antes de la meta) se **descarta** (`descartadas`); meta con época o
   geometría nuevas = imagen nueva transparente y recomposición completa. Los `_updates` no cambian la época.
5. **Gate M5 «repaso ≤ 3 s» frente a ≤ 10 teselas/s:** se mantiene el presupuesto declarado (10/s, 276 B; tabla §5.3
   y perfiles §5.4 comprobados por `test_vita_relay.py`). Un repaso tarda `teselas / 10` s: 2,8 s con el costmap de
   10 × 10 m de la prueba, pero **9,1 s** con el de 20 × 20 m a 10 cm que cita doc 36a §4.6.2 (91 teselas). Lo
   cambiado (parches) sale primero y cerca del robot antes, así que lo que se mueve llega en < 1 s. Contradicción
   anotada para el juez: o el gate se lee «parches ≤ 3 s», o `costmap` necesita ≈ 30 teselas/s (8,3 KB/s, 30 dgr/s).
6. **Composición por regiones** (tesela del mapa = 32×32 px; tesela del costmap = sus píxeles); más de 24 regiones
   pendientes → una completa. La mezcla es `Image.blend_rect` (alfa del costmap en la LUT, 0,7 como RViz) y la alfa
   del Mapa (0,85) se aplica al dibujar. Con escala entera y orígenes alineados al píxel del mapa, recomponer por
   regiones = componer todo (byte a byte, probado); con escalas no enteras, NEAREST por redondeo [I].
7. Mientras compone, el Mapa **no sube su propia textura** ni escribe `[visor-mapa]` (lo mide `[visor-costmap]`:
   `composicion_us`): así no se suben dos texturas de 384² a 4 Hz.
8. **Desconocido del costmap** (−1) se pinta 0x708986 con la alfa del costmap encima del mapa, como RViz.
9. **PC sin `_updates`:** el display del PC solo lee el `OccupancyGrid` completo; con Nav2 hace falta
   `always_send_full_costmap: true` para verlo moverse en el PC (en la Vita los parches los aplica el relay).
10. **Costmap local rodante** (§9.3 punto 9 [?]): cada cambio de origen es una época nueva y un repaso completo; por
    defecto el relay lee el **global**.
11. **Relay:** sin `pose` ni `mapa`, el módulo se suscribe a `/odom` para ordenar por cercanía; parches fuera de
    límites o sin costmap se ignoran (como RViz); el costmap se suscribe fiable + TRANSIENT_LOCAL (el QoS de Nav2).
12. **Prueba de bytes en `pruebas/visor_costmap.gd`** (no en `pruebas/runner.gd`: g1-sensores sigue 16/16) con la
    huella de enteros `huella`/`_md5`. En `test_vita_relay.py`, la lista de módulos «aún sin implementar» pasa a
    calcularse de `FASE` − `IMPLEMENTADOS` (con V11, `viz` ya arranca).

```fish
python3 docker/scripts/test_vita_relay.py                                              # … costmap ok, TODO OK
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor_costmap.gd    # RESULTADO: 54/54
docker/vita-ros.sh fuente-costmap           # en otra terminal:
docker/vita-ros.sh relay hmi,costmap        # 21,9 KB/s, 118 dgr/s
```

**En la Vita** (gate G-W13-M5; Nav2 + TB3 en la estación, o `fuente-costmap`, y el `.vpk` de `visor-ros`):
`docker/vita-ros.sh relay hmi,costmap`. Verde: el costmap aparece sobre el mapa en la planta (paredes magenta con
borde cian y degradado azul → rojo), un repaso completo en ≤ 3 s para un costmap de ≤ 30 teselas, ≥ 30 FPS y
`[visor-costmap] … composicion_us=` ≤ 4 000.
## Inspector, trazador y explorador de topics (V12)

Doc 36 §1.1, §1.3, §7 y §10; doc 36a §4.1.1–§4.1.4 y §4.1.11; sentencia W13 D6 y D9. Hecho en host (2026-11-14);
gate de hardware pendiente (pestaña Gráficas con 3 series: `draws` +≤ 3 y `avg_canvas_us` +≤ 300).

| Archivo | Pieza | Papel |
|---|---|---|
| `introspeccion_ros.gd` | IntrospeccionRos (estático) | `campos_de_tipo(tipo)` con caché por tipo sobre un prototipo vacío (ClassDB en las clases tipadas de rclgd, `get_property_list()` en el RosMsg dinámico); `leer_ruta` con `get_member`; rutas de Foxglove (`partir_ruta("/odom.twist.twist.linear.x")`, `trocear("poses[3].x")`, `unir_ruta`); `rutas_numericas(tipo)` para elegir campos |
| `displays/hud/inspector_texto.gd` | Inspector | `ros2 topic echo` en texto plano (comodín de RegistroDisplays); pestaña Inspector |
| `displays/hud/trazador.gd` | Trazador | hasta 3 series de un topic; `draw_set_transform` + UNA polilínea por serie; pestaña Gráficas |
| `explorador_topics.gd` | ExploradorTopics (`Node`) | PC: sondea `get_topic_names_and_types()` cada 2 s y añade displays sin guardarlos; Vita: catálogo fijo |

`main.tscn` gana las pestañas **Gráficas** (trazador de `/odom`: `twist.twist.linear.x` y `angular.z`; en la Vita
`<p>/pose2d` con `campos_vita = data[3], data[5]` = vx y wz) e **Inspector** (`/odom`; en la Vita `<p>/pose2d`) y un
`ExploradorTopics` bajo `VisorRos`. Prueba: `pruebas/visor_inspector.gd` (63 comprobaciones).

### Decisiones de V12 no cubiertas (las más conservadoras)

- **Inspector en la Vita = 8 filas × 30 car.** (tabla §7.2, ⚖ D6), recortado en `conectar` aunque la escena pida más;
  la sentencia permite hasta 12 filas, pero se toma el límite más bajo hasta G-W13-H0. Tope de 64 líneas aplanadas.
- **Cruceta del inspector apagada** por defecto (`usar_cruceta`): la cruceta suele ser del teleop; la navegación se
  hace con `desplazar(n)` y `alternar(i)`. Arrays de mensajes: solo «[n] {…}» (no se despliegan).
- **Trazador:** el rango y no se encoge (mín./máx. desde `conectar`), rango plano centrado, NaN descartado (T2),
  `caducidad_s = 0` (una gráfica parada se sigue leyendo), tope de pendientes = `capacidad`. Etiquetas con `%.2f`
  (Godot no admite `%g`). Capacidad recortada a 64 y series a 3 en la Vita.
- **Explorador:** en la Vita no añade displays (D9: topics fijos en la escena); su catálogo son los topics de los
  displays de la escena (compactos con su nombre real) y los tipos de `RosMsg.list_types()` por
  `ClassDB.class_call_static` (así el script compila con rclgd). Sin `RosTimer`: sondeo acumulando `delta`.
- **RegistroDisplays sin cambios:** el comodín `*` ya apuntaba a `hud/inspector_texto.gd`; ahora que existe, un tipo
  sin display propio crea el inspector (se actualizó la comprobación de `pruebas/visor.gd`).
- `campos_de_tipo` no guarda en caché un tipo sin esquema (el esquema puede cargarse después).
