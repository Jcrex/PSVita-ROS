# Visor de topics ROS 2 (`res://comun/visor/`)

Visor propio y portable: **el mismo GDScript** en el PC (rclgd, o el editor de host con `ros2_vita`) y en la PS Vita
(`ros2_vita`). Diseño en `docs/adr/0013-visualizacion-topics-godot.md` y `docs/36-visualizacion-topics-godot.md`
(§2 arquitectura, §8 trampas, §10 tareas). Estado: **V1–V5 hechos y verdes en host** (V5 = esquema `TIPOS_VISOR` y displays directos pequeños); V6–V15
pendientes.
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
