# W13 · Sentencia del juez (Fable 5.2, 2026-11-13)

> Juez: Fable 5.2. Entrada: los cinco posts de W13 (107 fichas), `W13-revision.md` / `.json` (contradicciones
> C1–C10, decisiones D1–D15) y el contexto obligatorio (ADR 0011 y 0012, docs 24, 27, 31 y 35, `plantillas/ros/`,
> `vita_relay.gd`, `docker/scripts/vita_relay.py`, `API_PARITY.md`). Decisión formal: **ADR 0013**
> (`docs/adr/0013-visualizacion-topics-godot.md`). Por regla del usuario (2026-11-13) estas decisiones no se le
> preguntan.
> No se ha tocado código ni otros docs. No se ha ejecutado nada nuevo: lo marcado [V] se ha leído en el archivo
> citado; las cifras de la Vita son [I] hasta sus gates. Marcas: [V] verificado · [I] inferencia · [?] sin confirmar.

## 0. Resumen de la sentencia

1. **Arquitectura propia** en `godot/plantillas/visor/` (`res://comun/visor/`), con gdviz como modelo de contrato y
   no como dependencia. T-W4-4 queda sustituida.
2. **Un contrato de display** (`VisorRos` + `CanalDisplay` + `DisplayRos3D/2D/Hud`), una biblioteca de dibujo
   (`PrimitivasViz` + `PaletaViz`) y un texto (`draw_string`).
3. **TF en la Vita sin tráfico extra por defecto** (`TfLigero` alimentado por cinemática local y `/vita/pose2d`).
4. **Presupuesto ADR 0011 repartido por display**, con dos perfiles (HMI y Viz), planta 2D por defecto en la Vita y
   un HUD de barra fija más una pestaña.
5. **Relay VC/1 rev. 2**: cabecera común, catálogo cerrado de topics `/vita/*`, límite de diseño de 488 B medidos
   con rosbags y un tope de red que el relay comprueba al arrancar.
6. **QoS por regla:** quien suscribe, best effort; quien publica, fiable; con las excepciones listadas.
7. **Lo nativo de `ros2_vita` va en un solo paquete** («plantilla N+1») y no bloquea nada de las fases V1–V12.

---

## 1. Pregunta previa: ¿adoptar o portar gdviz?

**Decisión: no. Arquitectura propia con el contrato de gdviz como modelo.**

Lo que dice el estudio ya hecho (`docs/24-portabilidad-ozuba.md`) [V]:

| Pieza de gdviz | Qué necesita | Estado en la Vita |
|---|---|---|
| `viz_topic_display.gd` | `qos.reliability =` (propiedades) y `count_publishers` | sin propiedades (`godot/ros2_vita/ros_runtime.cpp:76-92`); sin grafo (`docs/24:103`) |
| `viz_context.gd` | `get_topic_names_and_types()` cada segundo | no existe en XRCE (`docs/24:104`, `API_PARITY.md:38`) |
| `viz_frame_manager.gd` | `RosTfListener` con enumeración, padre y sello | nada registrado (`docs/24:105`, `godot/ros2_vita/register_types.cpp:16-22`) |
| `viz_registry.gd` | `GDScript.new()` + `reload()` y rutas de ament | compilar en ejecución en la Vita, sin comprobar (`docs/24:107`) |
| `viz_shapes`, `viz_materials`, `viz_pose_visuals` | líneas, color por vértice, MultiMesh | invisibles o ignorados (`docs/24:109-111`) |
| `viz_point_cloud.gd` | textura + `VERTEX_ID` en *shader* | inviable; reescritura L (`docs/24:112`) |
| `ui/viz_main.gd` | vista 3D en SubViewport, paneles de escritorio | sin SubViewport; adaptación L (`docs/24:147`) |

Motivos:

- **Coste:** M (tres archivos del núcleo) + L (interfaz) + L (nube) + cuatro huecos P0/P1 del módulo nativo antes de
  ver el primer display en la Vita. La arquitectura propia da displays en la Vita con el relay actual y sin
  plantilla nueva.
- **Doc 35:** gdviz crea los displays en ejecución desde una configuración tipo `.rviz` y un panel de propiedades.
  La regla del usuario pide que estén en el `.tscn` (`docs/35-regla-escenas-editables.md:33-35`).
- **Formatos compactos:** la mitad de los displays de la Vita leen `*MultiArray` del relay con significado por topic
  (`docker/scripts/vita_relay.py:10-19`). El registro de gdviz es por tipo de mensaje; aquí hace falta por (tipo,
  patrón de topic).
- **En el PC no se pierde nada:** quien quiera un RViz completo abre gdviz tal cual, sin portarlo.

Qué se toma de gdviz (MIT, © Miguel Oroz Zubasti; conservar el aviso si se copia código, `docs/24:19,271`):

- el contrato de plugin como modelo: estáticos de identidad y ganchos de mensaje (`docs/24:233-236`). Equivalencias:
  `viz_name()` → `nombre_display()`, `viz_message_types()` → `tipos_ros()`, `_viz_message(msg)` → `_procesar(msg)`,
  `_viz_reset()` → `_caducar()`;
- lógica pura reutilizable si hace falta: `viz_convert.gd`, `viz_urdf.gd` y la tabla de codificaciones de
  `viz_image_codec.gd` (`docs/24:106,113,115`).

Alternativas descartadas: (b) adoptar gdviz con capa GXM-safe; (c) una base por familia. Riesgo: duplicar trabajo
que Ozuba ya mantiene. Reversión: como los ganchos tienen equivalente uno a uno, un adaptador `VizTopicDisplay` →
`DisplayRos3D` es un archivo; si gdviz llega a ser seguro para la Vita, se cambia la base sin tocar `_pintar`.

---

## 2. Decisiones D1–D15

Formato: decisión · motivo · descartado · riesgo · cómo se revierte.

### D1 — Contrato único de display (resuelve C1)

- **Decisión:** opción (a) corregida. Piezas en `godot/plantillas/visor/`:

  | Pieza | Archivo | Base | Papel |
  |---|---|---|---|
  | VisorRos | `visor_ros.gd` | `Node` | contexto: `contexto` (ContextoRos), `tf`, `marco_fijo`, `prefijo_compacto`, `perfil`, cupos |
  | RegistroDisplays | `registro_displays.gd` | estático | tabla (tipo, patrón de topic) → guion, capa, coste |
  | CanalDisplay | `canal_display.gd` | `RefCounted` | `abrir/cerrar`, QoS, «el último gana», `hz_medido`, `caducado()` |
  | DisplayRos3D | `display_ros_3d.gd` | `Node3D` | resuelve marco → `transform` → `_pintar` |
  | DisplayRos2D | `display_ros_2d.gd` | `Node2D` | igual en planta; el `transform` del nodo hace de cámara |
  | DisplayRosHud | `display_ros_hud.gd` | `Control` | **sin TF**; `_draw()` propio; redibuja solo si llegó algo |
  | GestorHud | `gestor_hud.gd` | `Control` | barra fija, pestañas, cupo de *quads* |
  | HerramientaVisor | `herramienta_visor.gd` | `Node` | herramientas que publican (D-QoS, §3 C9) |

- **`@export` comunes** (nombres de `godot/plantillas/ros/sensor_base.gd:6-14` donde existen):
  `habilitado`, `topic`, `tipo`, `topic_vita` (sufijo bajo el prefijo compacto), `tipo_vita`, `frame_id` («» = el
  de la cabecera), `hz`, `hz_vita`, `fiabilidad` (AUTO / BEST_EFFORT / FIABLE), `latched`, `caducidad_s`,
  `persistencia_s`, `solo_pc`. Se descartan los nombres `hz_max`, `hz_dibujo`, `decay_s` y `decaimiento_s`.
- **Ganchos:** `conectar(visor)`, `desconectar()`, `_procesar(msg)`, `_procesar_compacto(msg)`, `_pintar(datos)`,
  `_caducar()`, `_coste() -> Dictionary` (`instancias`, `triangulos`, `quads`), y los estáticos `nombre_display()`
  y `tipos_ros()`.
- **Correcciones a los posts:**
  - `DisplayRosHud` no es «igual salvo `extends`»: con `Control` falla `transform = t`
    (`W13-revision.md:64-65`). Lleva su propio `_al_mensaje` sin TF.
  - `widget_hud.gd` (HMI) desaparece: es `DisplayRosHud`.
  - `sensor_base.gd` **no se fusiona**. El revisor lo propuso, pero es la base de los sensores simulados que
    *publican* (`sensor_base.gd:18,40-41`). Solo se comparten nombres.
  - Los cuatro fallos de `check-only` se corrigen como dice `W13-revision.md:57-60` (tipos explícitos, `tf` sin
    anotar, `preload` de la fábrica).
- **Motivo:** ya era portable (`create_subscription` con tipo por texto y `RosQoS.set_*()`,
  `W13-revision.md:49-50`), casa con doc 35 y la composición resuelve que Godot no tenga herencia múltiple.
- **Descartado:** (b) gdviz (§1); (c) una base por familia.
- **Riesgo:** tres bases delgadas con código parecido. Se acota dejando toda la lógica ROS en `CanalDisplay`.
- **Reversión:** los displays solo dependen de los ganchos; cambiar la base es mecánico.

### D2 — Una biblioteca de primitivas y color (resuelve C2)

- **Decisión:** opción (a). `primitivas_viz.gd` + `paleta_viz.gd`. Se funden `primitivas.gd` (geom),
  `fabrica.gd` + `paletas.gd` (mapas) y `color_ros` / `indice_paleta` (nucleo#14). `fabrica_marcadores.gd` queda
  solo como traductor `Marker` / `shape_msgs` → llamadas a `PrimitivasViz`.
- **API mínima** (cubre lo que las fichas llaman y nadie definía, `W13-revision.md:66-69`):
  - `PrimitivasViz.malla(forma, indice_color) -> ArrayMesh`, con formas CUBO, ESFERA, CILINDRO, CONO, FLECHA, EJES,
    DISCO, ANILLO; `instancia(forma, color)`; `cinta(puntos, ancho)`; `pose_godot(pose)`; `escala_ros(v)`.
  - `PaletaViz.indice(color)`, `uv(indice)`, `color(indice)`, `material()`, `de_ros(color_rgba)` y las constantes
    de estado OK / WARN / ERROR / STALE (colores de rqt_robot_monitor, borrador HMI §3).
  - Triángulos por forma en la Vita [I]: cubo 12, esfera 8 (octaedro), cilindro 32, cono 16, flecha 24, ejes 36,
    disco 12, anillo 56. Todos por debajo de lo previsto en `docs/31-render-visualizacion-vita.md:134`.
- **Motivo:** ADR 0011 §3 ya decidió «un material, una superficie y un *draw* por malla»
  (`docs/adr/0011-presupuesto-render-vita.md:36-37`); la paleta es además la única forma de tener varios colores
  en una malla (ejes RGB, listas horneadas). Un mismo camino de código en PC y Vita.
- **Matiz que los posts no vieron** [I]: para una instancia de un solo color, paleta y «material por color con alfa
  0,99» cuestan lo mismo en *draws* (una instancia = un *draw*, H2). La paleta cambia materiales por variantes de
  malla en el arena (≈ 60 B por triángulo, H3): por eso el tope de **64 variantes** (forma, color) en caché.
- **Descartado:** (b) material por color como regla; (c) `viz_shapes` de gdviz adaptado.
- **Riesgo:** que la textura con texel de alfa no saque la malla de la pasada de luz (H8 leído en código, sin medir).
  Gate E-W8-1 con `lit=` = 0.
- **Reversión:** la elección vive dentro de `PrimitivasViz.instancia()`; pasar a material por color es un cambio
  de un archivo (queda ya como opción «sombreado»).

### D3 — TF en la Vita (resuelve C8)

- **Decisión:** (c) por defecto, con `TfLigero` como interfaz única, y (b) cuando se recompile.
  - `visor.tf` (sin anotar tipo): en el PC `nodo.create_tf_listener()` si `has_method`; en la Vita `TfLigero`.
  - `TfLigero` (GDScript, ≤ 32 marcos, último valor, sin historial: la semántica de `modules/tf-tree`,
    `modules/tf-tree/include/tf_tree.h:12,39`) expone el subconjunto de `RosTfListener` que usan los displays:
    `lookup_transform(destino, origen)`, `can_transform`, `frame_exists`, `get_frame_names`, `get_frame_parent`.
    Devuelve `Transform3D` en ejes de Godot o `null`.
  - Fuentes por defecto, **0 B extra**: los nodos de los links del robot horneado (movidos por `/vita/joints`) y
    `map|odom → base` de `/vita/pose2d`.
  - Módulo `tf` del relay: **opcional**, lista blanca de ≤ 8 marcos dinámicos a 10 Hz (288 B, 2,9 KB/s); nombres y
    padres en `tf_marcos` y estáticos en `tf_estatico`, los dos *latched*.
  - Sin transformada: el display se oculta y marca «sin TF» (como RViz). Si `tf` es `null`, se supone que el marco
    del mensaje ya es el fijo.
- **Motivo:** el G1 ya funciona así (`docs/27-xrce-limites-y-relay.md:73`); `/vita/tf` de 32 marcos a 30 Hz son
  ≈ 104 KB/s (`W13-revision.md:161-162`). Hace falta una sola interfaz para que mapas#10 compile en la Vita.
- **Descartado:** «marco fijo y nada más» (nucleo): deja sin sitio a marcadores en `base_link`; `tf: RosTfListener`
  anotado (mapas): no compila; «display hijo del nodo del marco» (sensores): se admite como caso particular de la
  fuente local, no como contrato.
- **Riesgo:** dos implementaciones de TF (GDScript ahora, C después). Se acota con una prueba común contra los
  casos de `modules/tf-tree/tests/parity_test.c`.
- **Reversión:** al registrar el `RosTfListener` nativo, `VisorRos` lo elige con `has_method` y `TfLigero` queda de
  respaldo para el host.

### D4 — Convención de tamaño (resuelve C6)

- **Decisión:** dos números, cada uno con su nombre.
  - **Límite duro de envío** [V]: carga XRCE = CDR **sin** los 4 B de encapsulación ≤ 488 B
    (`godot/ros2_vita/xrce_transport.cpp:12-13,147,678`). Equivale a ≤ 492 B medidos con rosbags.
  - **Límite de diseño de todo `/vita/*`:** ≤ 488 B **medidos con rosbags** (carga ≤ 484 B). Es lo que ya hace el
    relay: `cdr_multiarray` suma la encapsulación y `_pub` compara con `MAX_BE = 488`
    (`docker/scripts/vita_relay.py:30,115-117,183-184`).
  - Las tablas de los docs siguen en bytes de rosbags (como `docs/27` §1) y lo dicen en la cabecera.
- **Motivo:** la cabecera del DATA que manda el agente en recepción no está medida [?] (`W13-revision.md:182`);
  4 B de margen no cuestan nada en formatos que diseñamos nosotros.
- **Consecuencias:** «Detection3DArray no cabe por 1 B» era un artefacto, pero da igual: va por el relay (D12). El
  scan directo de 106 o 107 rayos no se usa: va `scan_compacto`.
- **Descartado:** apurar a 492 B.
- **Riesgo:** ninguno funcional; se pierden 4 B por datagrama.
- **Reversión:** si G-W13-R0 confirma 488 B de carga también en recepción, se sube `MAX_BE` a 492 en un solo sitio.
- **Trabajo de docs** (no hecho aquí): `docs/27:10,33` y `docs/31:157` citan `xrce_transport.cpp:411-415`, que hoy
  es la reconexión; lo correcto es `:147-148,678-681`.

### D5 — Contrato del relay (resuelve C4)

- **Decisión:** contrato **VC/1 rev. 2**, aditivo.
  1. **Cabecera común** de todo formato nuevo troceado: `[seq & 0x7FFF, trozo, n_trozos, n, …]`, con `n` =
     elementos de este trozo. Los campos propios van detrás (por ejemplo `ancho, alto` en detecciones). Las teselas
     comparten la cabecera `[ver_lo, ver_hi, tx, ty]` del mapa.
  2. **Los formatos existentes no cambian** (`scan_compacto`, `pose2d`, `joints`, `mapa_*`, `path_compacto`): los
     consumen `godot/plantillas/vita_relay.gd` y `godot/g1-unitree/`.
  3. **Registro obligatorio:** función pura en Python (referencia), copia en `godot/plantillas/ros/vc1.gd`, prueba
     de bytes en `godot/plantillas/pruebas/runner.gd` (como las de `runner.gd:59-82`) y en
     `docker/scripts/test_vita_relay.py`. Un formato sin prueba de bytes no entra.
  4. **`/vita/pose2d` no se amplía.** La covarianza sale en `pose_cov` (7 floats, 2 Hz).
  5. **Época del mapa:** `version` solo sube cuando cambian resolución, tamaño u origen. Hoy sube con cada
     `OccupancyGrid` (`vita_relay.py:235`), lo que con un costmap a 1–5 Hz invalida todo cada vez.
  6. **Prefijo:** `/vita` o `/vita/<robot>` (`vita_relay.py:21`); los displays guardan solo el sufijo.
  7. **Tope de red comprobado al arrancar:** cada módulo declara Hz y bytes máximos; si la suma pasa de 100 KB/s o
     de 200 datagramas/s (`docs/27:42-43`), el relay no arranca y dice qué módulo sobra.
  8. **`relay_info`** (String *latched*): `VC/1.2;` + lista de módulos activos. Sirve de saludo de versión y para
     que el HUD distinga «sin datos» de «módulo apagado».
  9. **Módulo `ritmo`:** republica topics pequeños de tipo estándar a Hz fija en `<p>/ritmo/<nombre>` (Imu a 100 Hz
     → 20 Hz). Comprueba el tamaño serializado de cada mensaje.
- **Catálogo definitivo** (bytes con rosbags; `<p>` = prefijo):

  | Topic `<p>/…` | Tipo | Formato | QoS | Hz | B máx. | KB/s | dgr/s | Fase |
  |---|---|---|---|---:|---:|---:|---:|---|
  | `scan_compacto` | Int16MultiArray | `[seq, ang_min_cdeg, inc_cdeg, n, r…]` cm, n ≤ 180 | BE | 10 | 384 | 3,84 | 10 | existe |
  | `pose2d` | Float32MultiArray | `[x, y, yaw, vx, vy, wz]` | BE | 30 | 40 | 1,20 | 30 | existe |
  | `joints` | Float32MultiArray | posiciones, ≤ 118 (G1: 29) | BE | 25 | 132 (G1) | 3,30 | 25 | existe |
  | `joints_orden` | String | nombres con comas | F+TL | al cambiar | — | — | — | existe |
  | `mapa_meta` | Float32MultiArray | `[res, ancho, alto, ox, oy, tx, ty, época]` | F+TL | al cambiar | 48 | — | — | existe |
  | `mapa_tesela` | UInt8MultiArray | `[ver_lo, ver_hi, tx, ty]` + 32×32 a 2 bit | BE | ≤ 20 | 276 | 5,52 | 20 | existe |
  | `path_compacto` | Float32MultiArray | `[n, x0, y0, …]`, ≤ 57 puntos | BE | 2 | 476 | 0,95 | 2 | existe |
  | `relay_bw` | Float32MultiArray | `[bytes/s, mensajes/s]` | BE | 1 | 24 | 0,02 | 1 | existe |
  | `relay_info` | String | `VC/1.2;módulos` | F+TL | al arrancar | — | — | — | V6 |
  | `rosout` | `rcl_interfaces/msg/Log` | ≥ WARN, sin `file`/`function`, `msg` ≤ 200 car. | fiable | ≤ 10 | ≈ 270 [I] | 2,72 | 10 | V6 |
  | `diagnostics` | `diagnostic_msgs/msg/DiagnosticArray` | 1 estado, ≤ 3 pares, textos ≤ 40 car.; cambios + repaso 1 Hz | BE | ≤ 10 | ≈ 160 [I] | 1,60 | 10 | V6 |
  | `marcadores` | Float32MultiArray | cab. + `[clave, tipo, x, y, z, yaw, sx, sy, sz, color]`·n, n ≤ 11; estado completo, ≤ 33 | BE | 5 × ≤ 3 | 472 | 7,08 | 15 | V8 |
  | `marcador_puntos` | Float32MultiArray | cab. + `[clave, tipo, color, ancho]` + xyz·n, n ≤ 36 | BE | ≤ 4/s | 480 | 1,92 | 4 | V8 |
  | `marcador_texto` | String | `clave\|x\|y\|z\|texto` (≤ 80 car.) | fiable | ≤ 2 | ≈ 100 | 0,20 | 2 | V8 |
  | `pose_cov` | Float32MultiArray | `[x, y, yaw, σxx, σxy, σyy, σyaw]` (de `/amcl_pose`) | BE | 2 | 44 | 0,09 | 2 | V9 |
  | `poses` | Float32MultiArray | cab. + `[x, y, yaw]`·n, n ≤ 36 (diezmado) | BE | 2 | 464 | 0,93 | 2 | V9 |
  | `tf` | Float32MultiArray | cab. + `[idx, x, y, z, qx, qy, qz, qw]`·n, n ≤ 8 | BE | 10 | 288 | 2,88 | 10 | V9 (opc.) |
  | `tf_marcos` / `tf_estatico` | String / Float32MultiArray | `padre>hijo,…` / mismo formato que `tf` | F+TL | al cambiar | ≤ 1 100 | — | — | V9 (opc.) |
  | `camara/compressed` | `sensor_msgs/msg/CompressedImage` | JPEG 160×120 q40 | fiable | 3 | ≈ 3 000 | 9,00 | ≈ 21 | V10 |
  | `detecciones` | Float32MultiArray | cab. + `[ancho, alto]` + `[clase, score, cx, cy, w, h]`·n, n ≤ 18 | BE | 5 | 472 | 2,36 | 5 | V10 |
  | `det_clases` | String | nombres con comas | F+TL | al cambiar | — | — | — | V10 |
  | `detecciones3d` | Float32MultiArray | cab. + `[clase, score, x, y, z, yaw, sx, sy, sz]`·n, n ≤ 12 | BE | 5 | 464 | 2,32 | 5 | V10 |
  | `nube2d` | Int16MultiArray | cab. + xyz en cm·n, n ≤ 76; vóxel 10 cm, ≤ 228 puntos | BE | 5 × ≤ 3 | 480 | 7,20 | 15 | V10 |
  | `costmap_meta` | Float32MultiArray | como `mapa_meta` (teselas de 32×16) | F+TL | al cambiar | 48 | — | — | V11 |
  | `costmap_tesela` | UInt8MultiArray | `[ver_lo, ver_hi, tx, ty]` + 32×16 a 4 bit | BE | ≤ 10 | 276 | 2,76 | 10 | V11 |
  | `ritmo/<nombre>` | el de entrada | sin cambios, limitado en Hz | BE | config. | ≤ 488 | ≤ 10 | ≤ 30 | V6 |

  Cuentas de tamaño [V cálculo, con `16 + 4N`, `16 + 2N` y `16 + N` de `docs/27:84-86`]:
  marcadores 4 + 110 = 114 floats → 472 B; puntos 8 + 108 = 116 → 480 B; detecciones 6 + 108 = 114 → 472 B;
  detecciones 3D 4 + 108 = 112 → 464 B; poses 4 + 108 = 112 → 464 B; tf 4 + 64 = 68 → 288 B; nube 4 + 228 = 232
  int16 → 480 B. La propuesta de sensores (78 puntos más cabecera) daba 492 B y se baja a 76.

  **Corrección al revisor y a docs/27:** `nube2d` con 78 puntos cabía solo sin cabecera (`docs/27:106`).

- **Presupuesto de red** (nominal; límite 100 KB/s y 200 datagramas/s):

  | Perfil del relay | Módulos | KB/s | dgr/s |
  |---|---|---:|---:|
  | `hmi` | `scan,pose,joints,mapa,path` + `rosout,diag` | 19,2 | 108 |
  | `viz` | `hmi` + `marcadores,pose_cov,poses,tf,costmap` | 35,0 | 153 |
  | `percepcion` | `hmi` + `camara,det2d,det3d,nube` | 40,0 | 154 |
  | todo + `ritmo` | — | 65,9 | 229 → **rechazado** |

  Para activar todo hay que bajar ritmos (por ejemplo `pose2d` a 20 Hz y `joints` a 15 Hz, como ya pide
  `godot/g1-sensores/robot.json` con `hz_vita`).
- **Fuera del catálogo:** `/vita/catalogo` (D9); ampliar `pose2d`; `im_poses` y el cliente de marcadores
  interactivos en la Vita (aplazados, V14); miniaturas `mono8`. Mando y acciones (`/vita/mando`, `/vita/orden`,
  `/vita/accion/*`) siguen siendo del puente VAB/1 (ADR 0012 §2), no del relay.
- **Motivo:** un contrato con prueba de bytes es lo que hizo fiable VC/1; el tope de red comprobado evita que
  activar módulos rompa los FPS sin avisar.
- **Descartado:** cabeceras por formato (los posts); ampliar `pose2d`; un relay por familia.
- **Riesgo:** `vita_relay.py` (290 líneas) crece mucho. Se parte: funciones puras en
  `docker/scripts/vita_relay_formatos.py` y el nodo en `vita_relay.py`.
- **Reversión:** al ser aditivo, quitar un módulo es quitar su entrada; nada existente depende de lo nuevo.

### D6 — Presupuesto HUD (resuelve C5)

- **Decisión:** (a) `GestorHud`: barra fija + **una** pestaña visible. HUD = 400 *quads* (`docs/31:255`):

  | Zona | *Quads* | Contenido |
  |---|---:|---|
  | Barra fija (arriba, 24 px) | ≤ 120 | batería, enlace y Hz (`get_transport_info()`), estado de meta, herramienta activa |
  | Pestaña activa (derecha, 320 × 496 px) | ≤ 240 | una de las de abajo |
  | Texto superpuesto al 3D | ≤ 40 | nombres de marcos, textos de marcadores, clases de detección |

  | Pestaña | Límite en la Vita | Display |
  |---|---|---|
  | Estado | 6 medidores o filas | medidor, batería, lifecycle, meta |
  | Diagnóstico | 8 filas × 30 caracteres, «solo problemas» | tabla de diagnósticos |
  | Consola | 6 líneas × 40 caracteres | `rosout` |
  | Gráficas | 3 series × 64 puntos + ejes | trazador |
  | Inspector | 8 filas × 30 caracteres, 4 Hz | inspector de texto |
  | Cámara | 1 imagen + ≤ 18 cajas | imagen y detecciones 2D |
  | Controlador | 14 juntas, solo barras | estado del controlador |

- El monitor de nucleo#16 **no es una pieza aparte**: enlace y Hz van en la barra fija; el detalle por display es
  una vista de la pestaña Estado.
- El resto del 2D (`docs/31:255`): sensores 800 (scan ≤ 360, nube ≤ 228, path ≤ 112, poses y odometría ≤ 100) y
  resto 300 (marcadores 2D ≤ 150, detecciones ≤ 150).
- Reglas de dibujo: una fuente, sin contorno (el contorno multiplicó los lotes: 222 *draws* para 305 *quads*,
  `docs/34-perfil-vita-ligero.md:52`), un `_draw()` por panel.
- En el PC los cupos no se aplican y se pueden ver varios paneles; el código es el mismo.
- **Motivo:** ni la consola (≈ 600) ni la tabla (≈ 500) de HMI caben solas en 400 (`W13-revision.md:163-176`).
- **Descartado:** (b) subir el HUD a costa de los sensores 2D.
- **Riesgo:** el coste real es por lote y por glifo y no está separado [?]. Gate **G-W13-H0** antes de fijar filas.
  Los límites de la tabla son los de partida.
- **Reversión:** los límites son constantes de `GestorHud`; se ajustan con la medida.

### D7 — Instancias 3D (resuelve C7)

- **Decisión:** (a) + (c), con (b) como perfil.

  | Capa 3D | HMI (60 FPS, 80) | Viz (30 FPS, 150) |
  |---|---:|---:|
  | Robot | 40 | 40 |
  | Mundo, mapa y rejilla | 12 | 12 |
  | TF (solo ejes) | 8 | 32 |
  | Marcadores | 12 | 32 |
  | Poses, odometría y rastro | 4 | 16 |
  | Path y mallas lentas | 0 (en 2D) | 4 |
  | Reserva | 4 | 14 |

  La columna Viz reproduce `docs/31:237-246` (marcadores + poses + rastro = 48). La columna HMI es nueva.
- En la Vita, **planta 2D por defecto** para lo que vive en el suelo (odometría, path, scan, nube, poses,
  covarianza, polígonos, GPS, sector de `Range`). La orbital 3D queda para robot, TF, Imu, fuerzas y marcadores.
- Flechas hijo → padre del display TF: apagadas en la Vita (o líneas 2D superpuestas).
- Fantasma de trayectoria: sustituye al robot (robot oculto) o solo la cadena del brazo (≤ 8, de la reserva).
- `VisorRos` reparte los cupos: cada display llama a `visor.reservar(capa, n)` al conectarse y dimensiona su pool
  con lo concedido. Lo que no cabe no se crea.
- **Motivo:** la suma de los posts era 172–204 (`W13-revision.md:183-195`).
- **Descartado:** subir el tope de instancias; solo vista 2D.
- **Riesgo:** 12 marcadores en HMI es poco para Nav2. Quien necesite más cambia a perfil Viz (30 FPS).
- **Reversión:** el reparto es una tabla de `VisorRos` por perfil.

### D8 — Descartar antes de decodificar

- **Decisión:** ahora, «el último gana» en `CanalDisplay` y ritmos fijados en origen (relay a Hz fija; módulo
  `ritmo` para topics directos de más de 30 Hz). El cambio nativo se **aprueba** y va en el paquete «plantilla N+1»
  (V13) junto a TF nativo (D3), propiedades de `RosQoS` (T-W4-3), `viz-decode` y contadores.
- **Motivo:** el relay ya entrega al ritmo que se dibuja, así que la decodificación sobrante solo afecta a topics
  directos rápidos; recompilar la plantilla cuesta 1–2 h y conviene hacerlo una vez (`docs/31:200`).
- **Descartado:** recompilar ya solo por esto.
- **Riesgo:** un topic directo a 100 Hz suscrito por error llena la cola de 256 (`API_PARITY.md:109-110`).
  `CanalDisplay` avisa si `hz_medido` > 2 × `hz`.
- **Reversión:** no aplica; es orden de trabajo.

### D9 — Descubrimiento en la Vita

- **Decisión:** ninguno. Topics fijos en la escena (doc 35) + `relay_info`. En el PC, `explorador_topics.gd`
  (`solo_pc`, con `get_topic_names_and_types()`) permite añadir displays en ejecución, sin guardarlos.
- **Motivo:** en la Vita solo llega lo que el relay publica y eso ya está en el catálogo de D5.
- **Descartado:** `/vita/catalogo`; `res://ros/catalogo.json`.
- **Riesgo:** un topic mal escrito no da error. El display muestra «sin datos» o «módulo apagado» con `relay_info`.
- **Reversión:** `relay_info` puede crecer a catálogo sin cambiar de topic.

### D10 — Esquema de visor

- **Decisión:** un `.rsch` por app (el esquema es único y global, `W13-revision.md:83`), generado con los tipos de
  la app más la lista **`TIPOS_VISOR`** en `godot/plantillas/generar_esquemas.py`. Lista inicial (lo que la Vita
  recibe o publica en directo):
  - `std_msgs`: `Float32`, `Float64`, `Int32`, `UInt8`, `ColorRGBA`;
  - `geometry_msgs`: `PointStamped`, `Vector3Stamped`, `PoseArray`, `PoseWithCovarianceStamped`, `WrenchStamped`,
    `AccelStamped`, `QuaternionStamped`, `PolygonStamped`;
  - `sensor_msgs`: `Temperature`, `Illuminance`, `RelativeHumidity`, `Joy`;
  - `nav_msgs`: `MapMetaData`, `GridCells`;
  - `visualization_msgs`: `Marker`, `ImageMarker`, `InteractiveMarkerFeedback`;
  - `diagnostic_msgs/DiagnosticArray`, `rcl_interfaces/Log`, `lifecycle_msgs/TransitionEvent`,
    `action_msgs/GoalStatusArray`.
- `vision_msgs`, `map_msgs`, `nav2_msgs`, `grid_map_msgs` y `octomap_msgs` **no entran**: en la Vita llegan
  compactados y en el PC rclgd los resuelve por ament.
- **Motivo:** ≈ 137 B por tipo (borrador nucleo §1.3) no pesa; lo que cuesta es la búsqueda lineal por mensaje, que
  crece con la lista. Con ≈ 55 tipos en total el coste es de decenas de µs [I].
- **Descartado:** todo `common_interfaces`; fusionar esquemas en ejecución.
- **Riesgo:** `std_msgs/Empty` puede no entrar en el `.rsch` [?]; se deja fuera hasta probarlo.
- **Reversión:** la lista es un array de Python.

### D11 — Texto superpuesto (resuelve C3)

- **Decisión:** `draw_string` en un único `CanvasItem`. `texto_superpuesto.gd` recibe de los displays 3D pares
  (posición, texto, color), proyecta con `Camera3D.unproject_position` y pinta todo en un `_draw()`, con tope de 40
  glifos en la Vita. Los widgets HUD pintan su texto en su propio `_draw()`.
- **Motivo:** un `Label` por texto multiplica elementos y lotes del lienzo (`W13-revision.md:144-145`).
- **Descartado:** `Label` por marcador (mapas#21); `Label3D` (prohibido, ADR 0011 §4).
- **Riesgo:** reproyectar con la cámara en movimiento cuesta CPU. ≤ 10 textos y ≤ 20 Hz.
- **Reversión:** `TextoSuperpuesto` es el único sitio que cambia.

### D12 — Detecciones

- **Decisión:** en la Vita, relay compacto `detecciones` (n ≤ 18) y `detecciones3d` (n ≤ 12) en Float32. En el PC,
  el tipo estándar en directo. El mismo display con los dos decodificadores (D1).
- **Motivo:** una sola detección ya ocupa 449–474 B (`W13-revision.md:118`): en directo solo cabría una.
- **Se pierde:** `id` e hipótesis múltiples (se envía la mejor clase). Aceptado para un HUD.
- **Descartado:** fiable directo a ≤ 5 Hz: exige el esquema de `vision_msgs` en la Vita y decodificar una
  `PoseWithCovariance` por hipótesis.
- **Reversión:** añadir campos al final de cada elemento sube la revisión del contrato.

### D13 — Imagen en la Vita

- **Decisión:** `<p>/camara/compressed`, `sensor_msgs/msg/CompressedImage` con JPEG 160×120 q40 (≤ 3 KB), fiable,
  3 Hz por defecto (parámetro `camara_hz`, máximo 5). Decodifica el motor (`Image.load_jpg_from_buffer`, H22).
- **Motivo:** el tipo es estándar y su esquema ya está (`godot/plantillas/generar_esquemas.py:25`): el display del
  PC y el de la Vita son el mismo script con otro topic. La recepción fiable no bloquea el hilo principal; la que
  bloquea es la emisión (`docs/27:13-15`).
- **Descartado:** miniaturas `mono8` (80×60 = 4 848 B, más grande y peor); trocear en best effort.
- **Riesgo:** el módulo necesita OpenCV en la estación docker [?] y el coste de decodificar es [I]. Gate E-W8-5.
- **Reversión:** `camara_hz:=0` apaga el módulo.

### D14 — Marcadores en la Vita

- **Decisión:** el formato de mapas: **estado completo**, 10 floats por marcador y 11 por datagrama, con tope de 33
  marcadores (3 trozos) por ciclo de 5 Hz. `clave = (id ⊕ hash(ns)) & 0xFFFFFF` (exacta en float32);
  `color = índice de paleta + 256 · alfa(0–15)`.
- **Motivo:** escala anisótropa (paredes, cilindros) y alfa hacen falta. Con el tope de 33 marcadores, los 8
  floats de `docs/27:105` (14 por datagrama) también necesitan 3 trozos: no se ahorra ningún datagrama. El estado
  completo evita marcadores fantasma si se pierde un DELETE en best effort.
- **Se pierde:** alabeo y cabeceo (solo `yaw`).
- **Descartado:** 8 floats (`docs/27`); enviar acciones ADD / DELETE.
- **Riesgo:** 7 KB/s y 15 datagramas/s con 33 marcadores. Gate G-W13-M3.
- **Reversión:** el relay puede bajar a 2 Hz o a 22 marcadores por parámetro.

### D15 — Ubicación (resuelve C10)

- **Decisión:** `godot/plantillas/visor/`, visible como `res://comun/visor/`. Árbol:

  ```
  godot/plantillas/visor/
    visor_ros.gd  registro_displays.gd  canal_display.gd
    display_ros_3d.gd  display_ros_2d.gd  display_ros_hud.gd
    gestor_hud.gd  texto_superpuesto.gd  herramienta_visor.gd
    tf_ligero.gd  primitivas_viz.gd  paleta_viz.gd  fabrica_marcadores.gd
    introspeccion_ros.gd  tiempo_ros.gd  explorador_topics.gd (solo PC)
    displays/3d/   displays/2d/   displays/hud/   herramientas/
    README.md
  godot/visor-ros/            proyecto de ejemplo y de pruebas (comun -> ../plantillas)
    main.tscn  project.godot  robot.json  ros/schema.rsch
  ```

- **Motivo:** el enlace `comun -> ../plantillas` ya existe en cada proyecto (`godot/g1-sensores/comun`) y las
  pruebas ya viven en `plantillas/pruebas/`. `godot/comun/` se fusionó en `plantillas/` el 2026-11-12
  (`godot/plantillas/vita_relay.gd:2`) y solo conserva un `.uid` huérfano. La ruta `plantillas/comun/hmi/` del
  borrador HMI daría `res://comun/comun/hmi/`.
- Esta carpeta absorbe la tarea T-W8-4, que apuntaba a `godot/comun/viz/` (`docs/31:358`).
- **Descartado:** addon en `addons/` (necesita `plugin.cfg` y no aporta nada sin plugin de editor);
  `godot/comun/viz/`; repartir en `comun/{visor,viz,hmi}/`.
- **Riesgo:** `plantillas/` crece. Se acota con el README propio y las subcarpetas.
- **Reversión:** mover una carpeta y cambiar los `preload`.

---

## 3. Contradicciones C1–C10

| # | Contradicción | Resolución |
|---|---|---|
| C1 | cinco contratos de display | D1: `VisorRos` + `CanalDisplay` + tres bases; `widget_hud` = `DisplayRosHud`; `sensor_base` no se toca |
| C2 | dos bibliotecas de primitivas, tres de color | D2: `PrimitivasViz` + `PaletaViz` |
| C3 | `draw_string` frente a `Label` | D11: `draw_string` en un `CanvasItem` |
| C4 | ~18 topics sin contrato | D5: VC/1 rev. 2, cabecera común, catálogo y tope de red |
| C5 | > 1 000 *quads* de HUD contra 400 | D6: barra ≤ 120 + pestaña ≤ 240 + texto ≤ 40 |
| C6 | 488 B con o sin encapsulación | D4: duro = 488 B de carga; diseño = 488 B con rosbags |
| C7 | 172–204 instancias contra 80 | D7: reparto por perfil y planta 2D por defecto |
| C8 | cuatro enfoques de TF | D3: `visor.tf` sin anotar; `TfLigero` con fuentes locales |
| C9 | QoS de lo que publica la Vita | abajo |
| C10 | tres árboles de rutas | D15: `godot/plantillas/visor/` |

### C9 y QoS por tipo de herramienta

- **Decisión:** gana HMI. El *feedback* de marcadores interactivos va **fiable**: el servidor suscribe con
  `rclcpp::QoS(1)` y un publicador best effort no casa (`W13-revision.md:203-205`).
- **Regla general** [I: compatibilidad de QoS de ROS 2 / DDS, no releída en esta sesión]: un suscriptor best effort casa con cualquier publicador; un
  publicador fiable casa con cualquier suscriptor. Por eso:

  | Qué | Fiabilidad | Historial | Durabilidad | Nota |
  |---|---|---|---|---|
  | Display de estado periódico (relay o sensor) | best effort | 1 | volátil | lo normal |
  | Display de dato *latched* (`*_meta`, `*_orden`, `det_clases`, `tf_marcos`, `relay_info`, `/map`, `/tf_static`, `/robot_description`) | fiable | 1 | TRANSIENT_LOCAL | llega aunque se conecte tarde |
  | Display de eventos (`rosout`, `marcador_texto`, lifecycle) | fiable | 10 (PC) / 5 (Vita) | volátil | un evento perdido no se repite |
  | Estado de acciones (`GoalStatusArray`) | fiable | 1 | TRANSIENT_LOCAL [I] | el servidor lo publica *latched* |
  | Imagen comprimida en la Vita | fiable | 1 | volátil | no cabe en 488 B |
  | Meta, pose inicial, punto (`goal_pose`, `initialpose`, `clicked_point`) | fiable | 5 (PC) / 1 (Vita) | volátil | como RViz (`goal_tool.cpp:67,78`); un mensaje por confirmación con ✕ |
  | *Feedback* de marcador interactivo | fiable | 1 | volátil | ≤ 20 Hz al arrastrar, 149–157 B |
  | Teleop directo (`/cmd_vel`) | fiable por defecto | 1 | volátil | validado en hardware (`godot/g6-hmi/main.gd:65`); configurable a best effort |
  | Teleop con robot real (`/vita/mando`) | best effort | 1 | volátil | 20 Hz, puerta en el PC (ADR 0012 §3) |
  | `/vita/joy` | best effort | 1 | volátil | 20 Hz, 128 B |

- En la Vita la emisión fiable bloquea el hilo principal solo cuando fragmenta (`docs/27:13-15,34`); todo lo que
  publican las herramientas ocupa ≤ 364 B y no fragmenta.
- Siempre con `RosQoS.set_*()`; nunca `qos.reliability =` hasta T-W4-3 (`ros_runtime.cpp:76-92`). La QoS se pide a
  `contexto.qos(best_effort, profundidad, latched)` (`godot/plantillas/ros/contexto_ros.gd:25-31`).
- **Riesgo:** `/cmd_vel` fiable hacia un suscriptor best effort casa, pero en un enlace con pérdidas acumula
  reintentos. Con el G1 se usa best effort, como hoy (`godot/plantillas/robots/humanoide_g1.gd:163-164`).
- **Reversión:** `fiabilidad` es un `@export` de cada display y de cada herramienta.

### Reparto PC / Vita con el mismo script

1. **Fuente:** `visor.usa_compactos()` es verdadero si `OS.has_feature("vita")`, si `contexto.transporte == "xrce"`
   (`contexto_ros.gd:7,11`) o si se fuerza con un argumento (`compacto=1`). Verdadero → suscribe
   `prefijo + topic_vita` con `tipo_vita` y llama a `_procesar_compacto`; falso → `topic` / `tipo` y `_procesar`.
2. **Dato intermedio:** los dos decodificadores entregan lo mismo a `_pintar` (por ejemplo `PackedVector2Array` de
   puntos del scan). Así el camino compacto se prueba en el host contra el relay real.
3. **Dibujo:** `_pintar` usa solo `PrimitivasViz`, `PaletaViz` y llamadas de lienzo en lote. Sin MultiMesh, líneas
   3D, color por vértice ni `Label`.
4. **Lo que solo puede el PC** (nube en GPU, imágenes con *shader*, árbol del inspector, marcadores interactivos,
   explorador de topics) va en scripts aparte con `solo_pc = true`: en la Vita el nodo se desactiva solo, como hace
   `sensor_base.gd:28-30`.
5. **Escena:** los mismos nodos en `main.tscn`. En la Vita, `VisorRos` aplica cupos y perfil; no se guardan mallas
   de PC en la escena (`docs/35-regla-escenas-editables.md:45-47`).
6. **Configuración por robot:** `prefijo_compacto` y, si hace falta, una sección `visor` de `robot.json` que cambia
   `topic` o `hz` por nombre de nodo. Lo que se ve y dónde sigue en el `.tscn`.

---

## 4. Tareas de implementación, por prioridad

Comando de host (`$GH` = `toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64`, como en
`godot/plantillas/README.md:92-108`). Las pruebas de hardware las lanza el usuario; criterio general de verde en la
Vita: ≥ 55 FPS en perfil HMI o ≥ 30 en Viz, `avg_canvas_us` ≤ 2 000 / 3 000 y `avg_submit_us` ≤ 6 000 / 9 000
(`docs/31:226-228`).

| # | Tarea | Archivos a crear o tocar | Depende de | Verde en host | Verde en hardware |
|---|---|---|---|---|---|
| **V1** | Núcleo del visor | `visor/{visor_ros,canal_display,display_ros_3d,display_ros_2d,display_ros_hud,registro_displays,tiempo_ros}.gd`; proyecto `godot/visor-ros/`; `plantillas/pruebas/visor.gd` | nada | `--check-only` de todos; prueba en `loopback`: recibe, «el último gana», caduca, reserva de cupo y `solo_pc` | la app arranca vacía a 60 FPS; reconecta con el agente |
| **V2** | Primitivas y paleta | `visor/{primitivas_viz,paleta_viz,texto_superpuesto}.gd`; prueba en `pruebas/visor.gd` | V1 | cada forma: solo `PRIMITIVE_TRIANGLES`, triángulos = tabla de D2, un material, ≤ 64 variantes | 80 instancias: `lit=` = 0 y `drawn` = 80 (E-W8-1); captura con colores exactos |
| **V3** | Displays con el relay que ya existe | `visor/displays/2d/{scan,path,pose,mapa}.gd`, `displays/3d/{robot_joints,pose,mapa}.gd`; arreglos de `docs/31` §4.4 en `plantillas/vita_relay.gd` (LUT + `blit_rect`, tabla de direcciones) | V1, V2; relay `scan,pose,joints,mapa,path` | con `docker/vita-ros.sh relay` y `compacto=1`: los cinco displays con datos; bytes VC/1 intactos (`pruebas/runner.gd`) | escena tipo E-W8-6 sin marcadores: ≥ 55 FPS, `process` ≤ 4 ms, tesela ≤ 1,5 ms |
| **V4** | HUD | `visor/gestor_hud.gd`; `displays/hud/{barra_estado,medidor,bateria,joy,estado_meta}.gd` | V1 | la prueba cuenta glifos por pestaña ≤ 240 y barra ≤ 120 | **G-W13-H0**: `[gxm2d-perf] quads=` ≤ 400 y `draws` ≤ 30 con la pestaña Estado; anotar µs por glifo |
| **V5** | Esquema de visor y displays directos pequeños | `plantillas/generar_esquemas.py` (`TIPOS_VISOR`); `displays/3d/{punto,vector,ejes,imu,fuerza,rango,marcador_simple}.gd`, `displays/2d/{poligono,covarianza,gps}.gd` | V2; D10 | `RosMsg.from_type` de cada tipo de `TIPOS_VISOR` ≠ `null`; ida y vuelta `serialize` / `deserialize` | cada tipo publicado desde el PC con `ros2 topic pub` se ve; sin `ERR_FAIL` de esquema |
| **V6** | Relay rev. 2: base + `rosout`, `diag`, `ritmo` | `docker/scripts/vita_relay_formatos.py` (nuevo), `vita_relay.py` (cabecera común, `relay_info`, tope de red, época del mapa), `test_vita_relay.py`; `plantillas/ros/vc1.gd`; `displays/hud/{consola,diagnostico}.gd` | V4; esquemas `Log` y `DiagnosticArray` (V5) | pruebas de bytes Python = GDScript; el relay se niega a arrancar con «todo»; `ros2 topic bw` ≤ 20 KB/s en perfil `hmi` | 20 avisos/s durante 5 min: FPS sin bajar de escalón; `reliable_dropped` = 0 |
| **V7** | Herramientas que publican | `visor/herramienta_visor.gd`; `herramientas/{teleop,meta,pose_inicial,punto}.gd` | V1, V4; esquemas `PoseWithCovarianceStamped` y `PointStamped` (V5) | en `loopback`: un mensaje por confirmación, QoS de la tabla, covarianza de `initialpose` como RViz | un toque = un evento; meta con ✕ llega a Nav2 (`ros2 topic echo /goal_pose`); panel trasero no disponible [V, `docs/28:59`] |
| **V8** | Marcadores | `visor/fabrica_marcadores.gd`; `displays/3d/marcadores.gd`, `displays/2d/marcadores_2d.gd`; módulo `marcadores` del relay | V2, V6 | estado completo: sin fantasmas tras DELETE; 33 marcadores = 3 trozos de ≤ 472 B | G-W13-M1 (pool lleno a 10 Hz) y G-W13-M3 (10 % de pérdida, sin fantasmas > 0,4 s) |
| **V9** | TF y poses | `visor/tf_ligero.gd`; `displays/3d/tf.gd`, `displays/2d/{poses,covarianza}.gd`; módulos `tf`, `pose_cov`, `poses` | V2, V3, V6 | `TfLigero` pasa los casos de `modules/tf-tree/tests/parity_test.c`; mismo resultado que `RosTfListener` en el PC (± 1 mm) | 8 marcos a 10 Hz: `process` +≤ 0,5 ms; ejes en su sitio frente a RViz |
| **V10** | Percepción | módulos `camara`, `det2d`, `det3d`, `nube` del relay; `displays/hud/{imagen,cajas_2d}.gd`, `displays/2d/{cajas_3d,nube}.gd` | V4, V6; OpenCV en la estación [?] | tamaños ≤ 488 B; JPEG ≤ 3 KB; perfil `percepcion` ≤ 40 KB/s | E-W8-5 (JPEG ≤ 6 ms); nube de 228 puntos: `process` ≤ 2 ms por trozo |
| **V11** | Costmap | módulo `costmap`; composición sobre la textura del mapa en `displays/2d/mapa.gd` | V3, V6 | prueba de bytes de la tesela de 4 bit | G-W13-M5: repaso completo ≤ 3 s, ≥ 30 FPS |
| **V12** | Inspector y trazador | `visor/introspeccion_ros.gd`; `displays/hud/{inspector_texto,trazador}.gd`; `visor/explorador_topics.gd` (solo PC) | V4 | `campos_de_tipo` en prototipo vacío; trazador de 3 × 64 puntos = 3 comandos de dibujo | pestaña Gráficas: `draws` +≤ 3 y `avg_canvas_us` +≤ 300 |
| **V13** | Paquete nativo «plantilla N+1» | `godot/ros2_vita/ros_runtime.cpp` (propiedades de `RosQoS`, `latest_only`, tipo resuelto al suscribir, contadores), `RosTfListener` sobre `modules/tf-tree`, `modules/viz-decode/` | T-W4-2, T-W4-3, T-W8-7; solo PC | `tools/run-parity-tests.sh`; pruebas de `godot/test/` | `verify_runtime.py` PASS; mismos displays sin cambios de GDScript |
| **V14** | Extras solo PC y aplazados | nube en GPU, imágenes con *shader*, cliente de marcadores interactivos, octomap, grid_map; marcadores interactivos en la Vita (`im_poses`) | V8; T-W4-9 | `--check-only` con rclgd (no instalado en la máquina del revisor [V, `W13-revision.md:47`]) | no aplica hasta tener servicios en la Vita |
| **V15** | Documentación | `docs/36-visualizacion-topics-godot.md` con las fichas VERIFICADO; cita corregida en `docs/27:10,33` y `docs/31:157`; nota en `docs/24` (T-W4-4) y `docs/31` (T-W8-4); `API_PARITY.md` (regla `set_*`, choque de `reference`); README de `visor/` | V1–V12 | enlaces y citas comprobados | — |

Orden y cortes:

- **Fase 1 (sin plantilla nueva):** V1 → V2 → V3 → V4. Ya da un visor útil en la Vita con el relay de hoy.
- **Fase 2 (relay rev. 2):** V5 → V6 → V7 → V8 → V9.
- **Fase 3:** V10 → V11 → V12.
- **Aparte:** V13 cuando toque recompilar la plantilla; V14 después; V15 al cerrar cada fase.

Dependencias externas resumidas:

- **Esquemas `.rsch`:** `TIPOS_VISOR` (D10) antes de V6 y V7.
- **Módulos del relay:** V3 usa los cinco actuales; V6 añade la base; V8–V11 añaden un módulo cada una.
- **Huecos de `ros2_vita`:** ninguno bloquea V1–V12. P0 ya registrados: `RosTfListener` (T-W4-2) y propiedades de
  `RosQoS` (T-W4-3). P1: `latest_only`, tipo resuelto al suscribir, `viz-decode`. P2: servicios (T-W4-9).

---

## 5. Gates de hardware nuevos

| Gate | Qué mide | Verde | Lo necesita |
|---|---|---|---|
| **G-W13-R0** | recepción best effort con N ∈ {484, 488, 489, 492, 493} B de carga (banco de `docs/27` §4) | corte en 488 / 489 de carga | D4 (subir `MAX_BE` a 492) |
| **G-W13-H0** | coste del HUD: 100, 200 y 400 glifos en 1 y en 4 `CanvasItem`, con `[gxm2d-canvas]` y `[gxm2d-perf]` | µs por glifo y por lote separados; 400 glifos ≤ 2 ms | D6 (filas por pestaña) |
| **E-W8-1** (existente) | paleta fuera de la pasada de luz | `lit=` = 0 | D2 |
| **G-W13-M1, M3, M5** (de mapas) | marcadores y costmap | ver borrador de mapas §6 | D14, V8, V11 |
| **E-W8-5** (existente) | JPEG 160×120 | ≤ 6 ms | D13 |

Comandos para el PC (fish), cuando exista el proyecto:

```fish
set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor.gd
docker/vita-ros.sh up
docker/vita-ros.sh relay scan,pose,joints,mapa,path
$GH --path godot/visor-ros -- transporte=xrce compacto=1
```

---

## 6. Lo que queda sin confirmar

- [?] Cabecera real del DATA del agente en recepción (G-W13-R0).
- [?] Coste por glifo frente a coste por lote en el lienzo (G-W13-H0). Los límites de filas de D6 son de partida.
- [?] Que el agente acepte un DataReader de un tipo que no conoce (pregunta abierta de nucleo; no afecta a nada de
  lo decidido).
- [?] OpenCV en la imagen docker de la estación (V10).
- [?] `std_msgs/Empty` en el `.rsch` (fuera de `TIPOS_VISOR` hasta probarlo).
- [I] Todos los tiempos de GDScript en la Vita (hipótesis de 1,5 µs por instrucción, `docs/31:162`) hasta E-W8-0.
- [I] Tamaños de `rosout` (≈ 270 B) y `diagnostics` (≈ 160 B): extrapolados de la tabla del borrador HMI §1; el
  relay los comprueba mensaje a mensaje y recorta.
- No se ha compilado nada contra rclgd: sigue pendiente del revisor (`W13-revision.md:47`).
