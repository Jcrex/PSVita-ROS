# ADR 0013: Visualización de topics ROS 2 en Godot 4 — visor propio portable PC/Vita (`plantillas/visor/`)

- **Estado:** Aceptada (juez Fable 5.2, 2026-11-13).
  - Diseño cerrado; **nada implementado todavía**. Las cifras de la Vita son de diseño [I] hasta los gates
    E-W8-0…6 (doc 31 §6) y G-W13-* (lista en `docs/ia/workshops/posts/W13-juez-fable.md` §5).
  - Sale del workshop W13 (`docs/ia/workshops/W13-visualizacion-topics.md`): 107 fichas de cinco investigadores,
    revisión del escéptico (`posts/W13-revision.md`: contradicciones C1–C10, decisiones D1–D15). Por regla del
    usuario (2026-11-13) las decisiones no se le preguntan: las toma el juez.
  - Detalle de cada decisión (motivo, descartes, riesgo y reversión) y tareas V1–V15:
    `docs/ia/workshops/posts/W13-juez-fable.md`.
- **Fecha:** 2026-11-13
- **Concreta, sin cambiarlos:** ADR 0011 §6 (reparte su presupuesto entre displays) y ADR 0012 §1 (catálogo del
  relay). **Sustituye** la tarea T-W4-4 «capa GXM-safe de gdviz» (`docs/24-portabilidad-ozuba.md:286`).

## Contexto

Se quiere ver en Godot 4 cualquier tipo de topic que muestran RViz2, rqt y Foxglove, con **el mismo GDScript** en el
PC (rclgd) y en la PS Vita (`ros2_vita`). Hechos que condicionan el diseño:

1. **Límites de la Vita** [V]: best effort ≤ 488 B de carga XRCE por mensaje (`godot/ros2_vita/xrce_transport.cpp:147,678`);
   sin API de grafo, sin TF, sin servicios ni acciones (`godot/ros2_vita/API_PARITY.md:32-38`); `RosQoS` solo con
   métodos `set_*` (`godot/ros2_vita/ros_runtime.cpp:76-92`); cada mensaje se decodifica entero antes del callback
   (doc 31, H25).
2. **Render** [V]: solo triángulos de `MeshInstance3D`, sin color por vértice, MultiMesh, `Label3D` ni SubViewport;
   el 2D es la ruta validada y cuesta en proporción a los *quads* de cada fotograma (ADR 0011; doc 31 H1–H3, H16).
   Presupuesto: 150 / 80 instancias 3D (Viz / HMI) y 1 500 *quads* 2D, de ellos 400 de HUD
   (`docs/adr/0011-presupuesto-render-vita.md:44-47`; `docs/31-render-visualizacion-vita.md:255`).
3. **Red** [I]: ≤ 100 KB/s y ≤ ~200 datagramas/s de recepción (`docs/27-xrce-limites-y-relay.md:42-43`).
4. **Regla del usuario** (doc 35): lo que se ve y dónde está vive en un `.tscn` editable
   (`docs/35-regla-escenas-editables.md:33-35`).
5. **Los cinco posts de W13 no encajan entre sí** [V, `posts/W13-revision.md` §4]: cinco contratos de display, dos
   bibliotecas de primitivas, ~18 topics `/vita/*` nuevos con cabeceras distintas, > 1 000 *quads* de HUD contra 400
   y 172–204 instancias contra 80.
6. **Existe gdviz** (Ozuba, MIT), un RViz completo sobre rclgd, estudiado en `docs/24` §1–§4. Ningún post lo citó.
   En la Vita no funciona tal cual: usa propiedades de `RosQoS`, `RosTfListener`, API de grafo, compilación de
   scripts en ejecución, vista 3D en SubViewport, MultiMesh, color por vértice y `Label3D`
   (`docs/24-portabilidad-ozuba.md:102-112,147`).

## Decisión

### 1. Arquitectura propia, con gdviz como modelo y no como dependencia

- Se escribe un **visor propio y pequeño** en `godot/plantillas/visor/`. Los proyectos lo ven como
  `res://comun/visor/` por el enlace `comun -> ../plantillas` que ya usan (`godot/g1-sensores/comun`). No es un addon,
  no se resucita `godot/comun/` y no se usa `class_name` (convención de `plantillas/`: `preload`).
- De gdviz se toma **el contrato** (un registro por tipo de mensaje y ganchos por display, `docs/24:229-240`) y, donde
  convenga, código de lógica pura con su aviso MIT. En el PC, quien quiera un RViz completo usa gdviz sin portar.
- Piezas y nombres definitivos (archivo = nombre de la pieza):

  | Pieza | Archivo en `godot/plantillas/visor/` | Base | Papel |
  |---|---|---|---|
  | **VisorRos** | `visor_ros.gd` | `Node` | contexto único: nodo ROS, marco fijo, TF, prefijo compacto, perfil y cupos |
  | **RegistroDisplays** | `registro_displays.gd` | estático | tabla (tipo, patrón de topic) → display, capa y coste |
  | **CanalDisplay** | `canal_display.gd` | `RefCounted` | suscripción, QoS, «el último gana», Hz medido, caducidad |
  | **DisplayRos3D** | `display_ros_3d.gd` | `Node3D` | base de display en la vista orbital |
  | **DisplayRos2D** | `display_ros_2d.gd` | `Node2D` | base de display en la planta 2D y en la superposición |
  | **DisplayRosHud** | `display_ros_hud.gd` | `Control` | base de widget HUD (sin TF); sustituye a `widget_hud.gd` |
  | **GestorHud** | `gestor_hud.gd` | `Control` | barra fija + **una** pestaña visible + cupo de *quads* |
  | **TfLigero** | `tf_ligero.gd` | `RefCounted` | TF de último valor, ≤ 32 marcos, API de `RosTfListener` |
  | **PrimitivasViz** | `primitivas_viz.gd` | estático | mallas unidad (solo triángulos) y poses |
  | **PaletaViz** | `paleta_viz.gd` | estático | textura-paleta 16×16, un material, colores de estado |
  | **FabricaMarcadores** | `fabrica_marcadores.gd` | estático | `Marker`/`shape_msgs` → instancias de PrimitivasViz |
  | **TextoSuperpuesto** | `texto_superpuesto.gd` | `Control` | todo el texto anclado al 3D en un solo `_draw()` |
  | **HerramientaVisor** | `herramienta_visor.gd` | `Node` | base de las herramientas que publican |

  Displays concretos en `visor/displays/{3d,2d,hud}/`, herramientas en `visor/herramientas/`.
  `godot/plantillas/ros/sensor_base.gd` **no se fusiona**: es la base de los sensores simulados que *publican*
  (`sensor_base.gd:18,40-41`); los displays solo comparten sus nombres de `@export`.
- **Contrato único de display:** `@export` `habilitado`, `topic`, `tipo`, `topic_vita`, `tipo_vita`, `frame_id`,
  `hz`, `hz_vita`, `fiabilidad`, `latched`, `caducidad_s`, `persistencia_s`, `solo_pc`; método `conectar(visor)`
  (lo llama VisorRos a cada nodo del grupo `display_ros`) y ganchos `_procesar(msg)`, `_procesar_compacto(msg)`,
  `_pintar(datos)`, `_caducar()` y `_coste()`. Tipos por texto, `RosMsg` sin clases tipadas, `tf` sin anotar y QoS
  con `set_*()` (`API_PARITY.md:67-69`).
- **Mismo script en PC y Vita:** *decodificar* está separado de *pintar*. `_procesar` lee el mensaje estándar y
  `_procesar_compacto` el formato del relay; los dos entregan el mismo dato intermedio a `_pintar`. `VisorRos`
  elige la fuente: compacta si `OS.has_feature("vita")`, si el transporte es `xrce` o si se fuerza para probar en
  el PC.
- **Escenas (doc 35):** los displays son nodos del `.tscn` (escena de ejemplo `godot/visor-ros/main.tscn`), con
  posición, tamaño y pestaña editables. El código crea solo lo que depende de los datos (pools, puntos), sin
  `owner`. El prefijo compacto y los ajustes por robot siguen en `robot.json` (`prefijo_compacto`).

### 2. Primitivas y color: una biblioteca, paleta por UV

`PrimitivasViz` + `PaletaViz` son la única fuente de formas y colores: paleta 16×16 con un texel de alfa 0 y **un**
material (ADR 0011 §3). Mallas unidad cacheadas por (forma, índice de paleta), tope de 64 variantes. El material por
color con alfa 0,99 queda como opción «sombreado» detrás de la misma función. Texto: siempre `draw_string` en un
`CanvasItem` (`TextoSuperpuesto` o el `_draw()` del widget); `Label`, `RichTextLabel`, `Tree` y `Label3D` solo en
displays `solo_pc`.

### 3. TF en la Vita

Una interfaz (`visor.tf`, sin anotar): `RosTfListener` en el PC y `TfLigero` en la Vita. Por defecto `TfLigero` se
alimenta **sin tráfico extra**: cinemática local del robot horneado (`/vita/joints`) y `map|odom → base` de
`/vita/pose2d`. El módulo `tf` del relay es opcional y con lista blanca (≤ 8 marcos a 10 Hz). El `RosTfListener`
nativo sobre `modules/tf-tree` (T-W4-2) se hace con la misma API cuando se recompile la plantilla.

### 4. Presupuesto de render por display (reparto de ADR 0011 §6)

| Capa 3D | Perfil HMI (60 FPS, 80 inst.) | Perfil Viz (30 FPS, 150 inst.) |
|---|---:|---:|
| Robot | 40 | 40 |
| Mundo, mapa y rejilla | 12 | 12 |
| TF (solo ejes) | 8 | 32 |
| Marcadores | 12 | 32 |
| Poses, odometría y rastro | 4 | 16 |
| Path y otras mallas lentas | 0 (van en 2D) | 4 |
| Reserva | 4 | 14 |

- En la Vita, lo que vive en el suelo (odometría, path, scan, nube, poses, polígonos, GPS) se dibuja en **planta 2D**
  por defecto. Fantasma de trayectoria: solo con el robot oculto, o solo la cadena del brazo (≤ 8, de la reserva).
- *Quads* 2D (1 500): **HUD 400** = barra fija ≤ 120 + pestaña activa ≤ 240 + texto superpuesto ≤ 40; sensores 2D 800
  (scan ≤ 360, nube ≤ 228, path ≤ 112, poses ≤ 100); resto 300 (marcadores 2D ≤ 150, detecciones ≤ 150).
- Pestañas de `GestorHud` (una visible): Estado, Diagnóstico (8 filas), Consola (6 líneas × 40), Gráficas (3 series
  × 64 puntos), Inspector (8 filas), Cámara y Controlador. El monitor de Hz se funde con la barra fija.
- `VisorRos` lleva la cuenta: cada display reserva su cupo al conectarse; sin cupo no dibuja y lo dice una vez.

### 5. Relay: contrato VC/1 rev. 2, catálogo cerrado

- **Tamaño:** límite duro = carga XRCE ≤ 488 B (CDR sin encapsulación ⇔ 492 B medidos con rosbags). **Límite de
  diseño de todo `/vita/*`: ≤ 488 B medidos con rosbags** (4 B de margen), que es lo que ya comprueba
  `docker/scripts/vita_relay.py:115-117,183-184`, hasta medir la cabecera de recepción (gate G-W13-R0).
- **Cabecera común de lo troceado** (formatos nuevos): `[seq, trozo, n_trozos, n, …]`. Los formatos VC/1 existentes
  no cambian ni un byte. Cada formato nuevo lleva función pura en Python, copia en `plantillas/ros/vc1.gd` y prueba
  de bytes en `plantillas/pruebas/runner.gd`.
- `/vita/pose2d` **no se amplía**; la covarianza va en `pose_cov`. La `version` del mapa pasa a ser época de
  geometría (hoy sube con cada mapa, `vita_relay.py:235`).
- **Catálogo** (`<p>` = prefijo, `/vita` o `/vita/<robot>`; B con rosbags; BE = best effort, F+TL = fiable +
  TRANSIENT_LOCAL):

  | Topic `<p>/…` | Tipo | QoS | Hz | B máx. | KB/s | Módulo |
  |---|---|---|---:|---:|---:|---|
  | `scan_compacto` | Int16MultiArray | BE | 10 | 384 | 3,84 | `scan` (existe) |
  | `pose2d` | Float32MultiArray ×6 | BE | 30 | 40 | 1,20 | `pose` (existe) |
  | `joints` / `joints_orden` | Float32MultiArray / String | BE / F+TL | 25 | 132 (G1) | 3,30 | `joints` (existe) |
  | `mapa_tesela` / `mapa_meta` | UInt8MultiArray / Float32 ×8 | BE / F+TL | ≤ 20 | 276 | 5,52 | `mapa` (existe) |
  | `path_compacto` | Float32MultiArray | BE | 2 | 476 | 0,95 | `path` (existe) |
  | `relay_bw` / `relay_info` | Float32 ×2 / String | BE / F+TL | 1 | 24 | 0,02 | núcleo |
  | `rosout` | `rcl_interfaces/msg/Log` (≥ WARN, 200 car.) | fiable | ≤ 10 | ≈ 270 | 2,72 | `rosout` |
  | `diagnostics` | `DiagnosticArray` de 1 estado | BE | ≤ 10 | ≈ 160 | 1,60 | `diag` |
  | `marcadores` | Float32: 4 + 10·n, n ≤ 11 | BE | 5 × ≤ 3 trozos | 472 | 7,08 | `marcadores` |
  | `marcador_puntos` | Float32: 8 + 3·n, n ≤ 36 | BE | ≤ 4 trozos/s | 480 | 1,92 | `marcadores` |
  | `marcador_texto` | String `clave\|x\|y\|z\|texto` | fiable | ≤ 2 | ≈ 100 | 0,20 | `marcadores` |
  | `costmap_tesela` / `costmap_meta` | UInt8 (32×16 a 4 bit) / Float32 ×8 | BE / F+TL | ≤ 10 | 276 | 2,76 | `costmap` |
  | `pose_cov` | Float32 ×7 `[x,y,yaw,σxx,σxy,σyy,σyaw]` | BE | 2 | 44 | 0,09 | `pose_cov` |
  | `poses` | Float32: 4 + 3·n, n ≤ 36 | BE | 2 | 464 | 0,93 | `poses` |
  | `tf` / `tf_marcos` / `tf_estatico` | Float32: 4 + 8·n, n ≤ 8 / String / Float32 | BE / F+TL / F+TL | 10 | 288 | 2,88 | `tf` (opcional) |
  | `camara/compressed` | `CompressedImage` JPEG 160×120 q40 | fiable | 3 | ≈ 3 000 | 9,00 | `camara` |
  | `detecciones` / `det_clases` | Float32: 6 + 6·n, n ≤ 18 / String | BE / F+TL | 5 | 472 | 2,36 | `det2d` |
  | `detecciones3d` | Float32: 4 + 9·n, n ≤ 12 | BE | 5 | 464 | 2,32 | `det3d` |
  | `nube2d` | Int16: 4 + 3·n (cm), n ≤ 76 | BE | 5 × ≤ 3 trozos | 480 | 7,20 | `nube` |
  | `ritmo/<nombre>` | el tipo de entrada, limitado en Hz | BE | config. | ≤ 488 | ≤ 10 | `ritmo` |

  Descartados: `/vita/catalogo`, ampliar `pose2d`, miniaturas `mono8`, `im_poses` (marcadores interactivos en la
  Vita, aplazados). Mando y acciones siguen en VAB/1 (ADR 0012 §2).
- **Presupuesto de red por perfil** (suma nominal): HMI (`scan,pose,joints,mapa,path,rosout,diag`) ≈ 19 KB/s y
  108 datagramas/s; Viz (HMI + `marcadores,costmap,pose_cov,poses,tf`) ≈ 35 KB/s y 153; Percepción (HMI +
  `camara,det2d,det3d,nube`) ≈ 40 KB/s y 154. Todo a la vez ≈ 66 KB/s pero ≈ 229 datagramas/s: el relay **se niega a
  arrancar** si la suma nominal de sus módulos pasa de 100 KB/s o de 200 datagramas/s.

### 6. QoS

- **Suscriptores:** best effort, profundidad 1 (casa con cualquier publicador). Excepciones fiables: lo *latched*
  (`*_meta`, `*_orden`, `det_clases`, `tf_marcos`, `relay_info`, `/map`, `/tf_static`, `/robot_description`) con
  TRANSIENT_LOCAL; los eventos (`rosout`, `marcador_texto`, lifecycle, estado de acciones); y lo que no cabe en
  488 B en la Vita (`camara/compressed`).
- **Publicadores (herramientas):** fiable (casa con cualquier suscriptor). `goal_pose`, `initialpose`,
  `clicked_point` y el *feedback* de marcadores interactivos: fiable, KEEP_LAST 5 en el PC y 1 en la Vita, un
  mensaje por confirmación. Teleop: `/cmd_vel` fiable de profundidad 1 por defecto y `/vita/mando` best effort a
  20 Hz con robots reales (ADR 0012). `/vita/joy`: best effort a 20 Hz.

### 7. Descubrimiento, esquemas y módulo nativo

- **Vita sin descubrimiento:** los topics son fijos en la escena; `relay_info` dice qué módulos hay. En el PC,
  `ExploradorTopics` (`solo_pc`) añade displays por topic sin guardarlos.
- **Esquema:** un `.rsch` por app = tipos de la app + lista `TIPOS_VISOR` (≈ 30 tipos pequeños que la Vita recibe en
  directo) en `godot/plantillas/generar_esquemas.py`. No se mete todo `common_interfaces`.
- **Descarte antes de decodificar:** hoy «el último gana» en `CanalDisplay` y ritmos fijados en el relay (módulo
  `ritmo` para topics directos de más de 30 Hz). El cambio nativo va en un solo paquete «plantilla N+1»: propiedades
  de `RosQoS` (T-W4-3), cola `latest_only` con el tipo resuelto al suscribir, `RosTfListener` sobre `tf-tree`
  (T-W4-2), `viz-decode` y contadores por suscripción.

## Alternativas descartadas

- **Adoptar o portar gdviz (T-W4-4):** coste M en el núcleo más L en la interfaz y en la nube, depende de cuatro
  huecos P0/P1 de `ros2_vita`, crea los displays en ejecución desde un `.rviz` (contra doc 35) y su interfaz es de
  escritorio. Se conserva como referencia de contrato y como visor completo en el PC.
- **Una base por familia (los cinco contratos de los posts):** cinco formas de suscribir, de limitar Hz y de caducar.
- **Material por color con alfa 0,99 como regla:** más simple, pero ADR 0011 §3 ya fijó la paleta y esta permite
  varios colores por malla (ejes, listas). Queda como opción detrás de la misma API.
- **`/vita/tf` de 32 marcos a 30 Hz:** ≈ 104 KB/s, él solo pasa del presupuesto de red.
- **Subir el HUD por encima de 400 *quads*:** quita sitio a los sensores 2D; se resuelve con pestañas.
- **`/vita/catalogo` o `catalogo.json`:** más contrato para algo que la escena ya dice.
- **Ampliar `/vita/pose2d` a 10 floats:** rompe a los clientes actuales (`godot/plantillas/vita_relay.gd:87-91`).
- **Detecciones y `/rosout` crudos en best effort:** una detección ya roza el límite; un aviso perdido no se repite.
- **Addon en `addons/` o carpeta `godot/comun/`:** el enlace `comun -> ../plantillas` ya resuelve el reparto.

## Consecuencias

- **Positivas:** un solo contrato y una sola biblioteca de dibujo; la Fase 1 (núcleo, displays con el relay actual,
  HUD) no necesita plantilla nueva; cada display tiene cupo declarado y comprobable en host
  (`plantillas/pruebas/presupuesto.gd`); el relay no puede pasarse del presupuesto de red por configuración.
- **Negativas:** código propio que mantener en vez de heredar el de Ozuba; los displays del PC que usan lo que la
  Vita no tiene (nubes en GPU, imágenes con *shader*, marcadores interactivos) quedan como `solo_pc`; los
  marcadores compactos pierden alabeo y cabeceo (solo `yaw`) y las detecciones pierden hipótesis múltiples.
- **Trabajo derivado:** tareas V1–V15 del post del juez; corregir la cita `xrce_transport.cpp:411-415` en
  `docs/27:10,33` y `docs/31:157` (hoy `:147-148,678-681`); anotar en `docs/24` que T-W4-4 queda sustituida; doc
  final `docs/36-visualizacion-topics-godot.md`.
- **Riesgo asumido:** el coste por glifo y por lote del 2D, el efecto real de la paleta en la pasada de luz
  (`lit=`) y el límite de recepción no están medidos. Si un gate sale rojo se aplica el orden de ADR 0011 §8: bajar
  contenido, mover de capa, y solo después parchear.
- **Lo que no se puede verificar en el PC** (render GXM, *quads*, FPS, recepción XRCE real) lleva la marca «validar
  en hardware» en el código y en los README.

## Enmienda 2026-11-14 (juez Fable 5.2, desafíos de la fase V2)

Detalle en `docs/ia/workshops/posts/V2-juez-fable.md`; origen en `docs/ia/workshops/posts/V2-revision.md` (N3, N7).
No cambia ninguna cifra de §4 ni de §5.

1. **Marcadores: tres límites, cada uno con su papel.** Cupo de la capa (12 HMI / 32 Viz, §4) = lo que se dibuja;
   estado completo del relay ≤ 33 (§5) = lo que viaja; `TOPE_VITA` = 48 = red de seguridad del camino directo. Los
   gates G-W13-M1 (HMI, 12, ≥ 55 FPS) y G-W13-M1v (Viz, 32, ≥ 30 FPS) miden el cupo; el «48» queda solo como carga de
   estrés de G-W13-M2 (doc 36 §9.1).
2. **Escenas de prueba conmutables en la Vita.** `godot/visor-ros/` lleva tres escenas editables (doc 35):
   `main.tscn` (HMI), `main_viz.tscn` (heredada, perfil Viz) y `banco_v5.tscn` (displays directos de V5, gate V5). El
   nodo `SelectorEscena` (`selector_escena.gd`) cambia entre ellas con L + R + START y recuerda la elección en
   `user://visor_escena.txt`: una sola `.vpk` para todos los gates. Validar en hardware.
3. **HUD (§4):** los ≤ 4 *quads* de la herramienta activa cuentan dentro de la barra fija (≤ 120).
4. **TF (§3):** con `marco_pose2d` aún sin unir al marco fijo, `pose2d` cuelga del fijo; `map → odom` llega por la
   lista blanca del módulo `tf`. El relay no publica `pose2d` en `map`.
