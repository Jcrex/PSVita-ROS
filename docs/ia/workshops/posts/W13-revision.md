# W13 · Revisión del escéptico (ronda 2, 2026-11-13)

> Revisor: `esceptico-revisor` (Opus 5.5). Veredictos por ficha en `W13-revision.json` (107 entradas, una por ficha
> de los cinco posts). No se han tocado los posts ni el código del repo. Marcas: [V] verificado · [I] inferencia ·
> [?] sin confirmar.

## 1. Recuento

| Post | Fichas | VERIFICADO | DESAFÍO | ALTERNATIVA | Por medir |
|---|---:|---:|---:|---:|---:|
| nucleo-generico | 18 | 10 | 3 | 3 | 2 |
| geometria-tf-robot | 22 | 18 | 3 | 1 | 0 |
| sensores-densos | 15 | 9 | 4 | 1 | 1 (sens#13, sin ejecutar) |
| mapas-marcadores | 32 | 26 | 5 | 1 | 0 |
| hmi-percepcion-acciones | 20 | 13 | 3 | 1 | 3 |
| **Total** | **107** | **76** | **18** | **7** | **6** |

`check-only`: **101 PASA**, **4 FALLA**, **2 NO APLICA** (nucleo#5 es un árbol en comentarios y nucleo#17 es C++).
Muchas de las que pasan solo pasan con dependencias que **ninguna ficha escribe** (véase §2.2).

## 2. Código: método y fallos

### 2.1 Método [V]

- Editor de host `toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64` (4.8.dev7, `d1a5f291b`). Trae
  `ros2_vita` compilado, así que **la comprobación es contra la API de la Vita**.
- Proyecto mínimo en el scratchpad (`…/scratchpad/w13-check/proj/`). Se lanzó `--headless --check-only --script`
  sobre cada uno de los 107 bloques `codigo`.
- Las dependencias se montaron con las propias fichas:

  | Dependencia | Sale de |
  |---|---|
  | `comun/viz/primitivas.gd` | geom#0 |
  | `comun/hmi/widget_hud.gd` | hmi#0 |
  | `comun/hmi/medidor.gd` | hmi#3 |
  | `comun/hmi/herramienta_pose.gd` | hmi#16 |
  | `scan_pc.gd` | sens#0 |
  | `nube_pc2.gd` | sens#3 |
  | `canal_display.gd`, `introspeccion_ros.gd`, `tiempo_ros.gd` | nucleo#4, #0 y #15 |
  | `display_ros_hud.gd` | nucleo#3 con `extends Control` |
  | `paletas.gd` | mapas#1 + mapas#2 |
  | `fabrica.gd` | fusión de los 14 fragmentos de mapas; ningún nombre con dos definiciones distintas |
  | `contexto_ros.gd` | copia de `godot/plantillas/ros/contexto_ros.gd` |

- Los fragmentos sin `extends` o con sentencias sueltas se envolvieron en una clase o una `func`. Son hmi#4–6,
  nucleo#10, sens#11, mapas#25, y mapas#3 y #6 añadidos a mapas#0.
- **rclgd no está instalado aquí.** Las diferencias se cotejaron con `godot/rclgd/docs/classes/*.rst` y
  `API_PARITY.md`:
  - todas las fichas usan `create_subscription(topic, tipo_texto, callable, qos)` y `RosQoS.set_*()` por método,
    que es portable (`ros_runtime.cpp:77-91`, `class_rosqos.rst:301-305`);
  - ninguna usa `qos.reliability =` (el fallo de paridad que encontró sensores-densos).

### 2.2 Fallos y corrección propuesta

| Ficha | Error | Corrección (comprobada con check-only) |
|---|---|---|
| geom#12 Inertia | `Cannot infer the type of "lados"` (línea 30: `Vector3 * Variant` con `:=`), en los dos runtimes | `var lados: Vector3 = …` |
| mapas#10 gestor de Marker | `Could not find type "RosTfListener"` en ros2_vita (pasa en rclgd) | `var tf = null`, sin anotar el tipo. Así lo dice la regla de API_PARITY y de nucleo §4 |
| mapas#26 cliente IM | `RosClient` no existe en ros2_vita (sí en rclgd, `class_rosclient.rst`) y falta `Fab` (no hay preload) | añadir `const Fab := preload("res://comun/viz/fabrica.gd")` y no anotar el tipo, o marcar el script como solo PC |
| mapas#27 feedback IM | `Cannot infer the type of "pulsado"` (expresión con operandos Variant) | `var pulsado: bool = …` |

Fallos de diseño que el analizador no ve:

- **nucleo#3:** la frase «las bases 2D y HUD son idénticas salvo `extends`» es falsa. Con `extends Control` falla
  `transform = t`. La base HUD necesita su propio `_al_mensaje`, sin TF.
- **geom#0** solo define `material`, `flecha`, `flecha_hacia`, `pose_godot` y `en_marco_fijo`. Las fichas geom#1–21
  llaman a **`esfera`, `ejes`, `disco`, `anillo` y `cono`, que no existen**. Para compilar se usaron stubs.
- **fabrica.gd** (mapas) usa `FLECHA`, `CILINDRO_Z`, `CONO_Z`, `CUBO_CARAS`, `color()`, `Paleta.*`, `crear`,
  `aplicar` y `pose` sin definirlos en ninguna ficha.
- **Código repetido:** geom#6, #7 y #8 traen el mismo bloque (pantalla de tornillo, *screw display*). También se
  repiten sens#6 y #7, y sens#9 y #10. Las fichas de profundidad (sens#7) y de Image en la Vita (sens#9) no traen
  código propio.

## 3. Citas y tamaños CDR

### 3.1 Citas comprobadas [V]

Al menos dos por post, y todas las que sostienen una decisión:

- **nucleo:**
  - `ros_runtime.cpp:118-133`: decodifica antes del callback ✔;
  - `:473-484`: cola de 256 que descarta la más antigua ✔;
  - `ros_msg.cpp:14-24`: un esquema único que se reemplaza ✔;
  - `vita_relay.py:10-19` ✔;
  - `dron-mapeo/ros/schema.rsch` = 6 030 B ✔;
  - rclgd `ros_subscriber.cpp:20-37`: `call_deferred` ✔.
- **geom:**
  - `util_ros.gd:6` (`BASE_ROS_A_GODOT`) ✔;
  - `generar_esquemas.py:12-40` ✔;
  - `register_types.cpp:16-22`: sin TF ni Logger ✔;
  - módulos del relay `scan,pose,joints,mapa,path` ✔.
- **sensores:**
  - `ros_runtime.cpp:76-92`: RosQoS solo con métodos, sin `ADD_PROPERTY` ✔;
  - `docs/27:106-107`: nube2d y cámara solo diseñadas ✔;
  - `docs/31:162`: 1,5 µs/instrucción [I] ✔.
- **mapas:**
  - `vita_relay.py:234`: `version` sube con cada mapa ✔;
  - Marker.msg de Jazzy con `ARROW_STRIP` y `mesh_file` ✔ (typestore);
  - `marker_factory.cpp` (jazzy) no trata ARROW_STRIP ✔.
- **hmi:**
  - `g6-hmi/main.gd:85-86` ✔;
  - `docs/28:59`: panel trasero ✔;
  - `docs/31:255`: HUD de 400 quads ✔;
  - `goal_tool.cpp:67,78`: QoS configurable ✔.
- **Hechos H de doc 31** usados en decisiones (H1–H4, H8, H9, H16, H17, H19, H22, H25): coinciden con
  `docs/31:33-57` ✔.
- **Cita que ya no corresponde:** `docs/27:10` cita `xrce_transport.cpp:411-415` para el tope de 488 B, pero esas
  líneas son ahora la reconexión. El tope está en `xrce_transport.cpp:147-148,678-681` (`XRCE_OVERHEAD = 24`,
  `fits = p_len + 24 <= MTU`). Hay que corregirlo en docs/27 y docs/31 §4.1.

### 3.2 Tamaños recalculados

Recalculados con rosbags (ROS2_JAZZY); vision_msgs con los `.msg` de la rama `ros2`. Script en
`…/scratchpad/w13-check/cdr.py`.

| Mensaje | Post | Revisor | Nota |
|---|---:|---:|---|
| Detection2DArray, 1 detección | 481 | 449 / 465 / 474 | según frame y clase; no se reproduce 481, pero la conclusión se mantiene |
| Detection3DArray, 1 detección | 489 | 489 (cam, «1») / 505 (camera, person) | véase C6 |
| Marker sin puntos / 10 / 11 puntos | 229 / 469 / 493 | 229 / 469 / 493 | ✔ (frame `map`, ns `test`) |
| InteractiveMarkerFeedback | 149 | 149 / 157 | ✔; 157 con nombres reales |
| Odometry (odom → base_footprint) | 724 | 724 | ✔ |
| PoseWithCovarianceStamped / MapMetaData | 364 / 84 | 364 / 84 | ✔ |
| CameraInfo plumb_bob | 381 | 357 (frame `camera`) | depende del frame; cabe igual |
| LaserScan 106 rayos, `base_scan`, sin intensidades | 484 | 488 con encapsulación | véase C6 |

## 4. Contradicciones entre posts

- **C1. Cinco contratos de display.**
  - Los cinco:
    - nucleo: `VisorRos` llama a `conectar(visor)` sobre `DisplayRos3D/2D/Hud` + `CanalDisplay`;
    - geom: `configurar(nodo: RosNode, listener, qos)` en `Node3D`/`MeshInstance3D`;
    - sensores: `iniciar(nodo, topic)`, y cada display crea su `RosSubscriber`;
    - mapas: `ctx` (contexto_ros) + `gestor`;
    - HMI: `widget_hud.gd` (`Control`, `conectar(nodo)`, `hz_dibujo`).
  - Además ya existe `godot/plantillas/ros/sensor_base.gd`, con los `@export` que nucleo copia.
  - Nombres de parámetros dispares: `hz_max`/`hz_max_vita`, `hz_dibujo`, `decay_s`/`decaimiento_s`, `caducidad_s`.
- **C2. Dos bibliotecas de primitivas y tres utilidades de color.**
  - `res://comun/viz/primitivas.gd` (geom): flecha de 24 triángulos, `material(c)` con a = 0,99 por color (H8).
  - `res://comun/viz/fabrica.gd` + `paletas.gd` (mapas): flecha de 18 triángulos, `Paleta.uv` con textura 16×16
    (ADR 0011 §3: «un material»).
  - `color_ros`/`indice_paleta` (nucleo#14).
  - Las dos bibliotecas definen flecha, cono, esfera y cilindro.
- **C3. Texto superpuesto.** geom y HMI usan `draw_string` en un solo CanvasItem; mapas#21 usa un `Label` del HUD
  por marcador. Un Label por texto multiplica los items y los lotes del lienzo (doc 34: 222 draws con 305 quads).
- **C4. Relay: unos 18 topics `/vita/*` nuevos sin contrato común.**
  - Topics nuevos:
    - `catalogo` (nucleo);
    - `tf`, `tf_static`, PoseArray sin nombre y ampliar `pose2d` a 10 floats (geom);
    - `scan_compacto` (ya existe), `nube2d`, `camara` (sensores);
    - `costmap_tesela`, `marcadores`, `marcador_puntos`, `marcador_texto`, `im_poses` (mapas);
    - `rosout`, `diagnostics`, `detecciones`, `det_clases`, `detecciones3d`, `joy`, `accion/*` (HMI).
  - **Cabeceras distintas:**
    - `[seq, trozo, n_trozos]` en nube2d y marcadores;
    - `[seq, ancho, alto, n]` en det2d;
    - `[seq, n]` en det3d;
    - `[ver_lo, ver_hi, tx, ty]` en las teselas.
  - **Choque directo:** geom#13 amplía `/vita/pose2d`, que ya existe (`vita_relay.py:11`) y que hmi#14 consume con
    6 floats.
  - Ningún post registra sus formatos en VC/1 (`plantillas/ros/vc1.gd`).
  - **Ancho de banda:** `/vita/tf` con 32 frames a 30 Hz ≈ 104 KB/s, y solo eso ya pasa del presupuesto de
    100 KB/s (docs/27 §Resumen).
- **C5. Presupuesto HUD (ADR 0011 §6 / docs/31 §5.3: 1 500 quads, de ellos HUD 400).**

  | Pieza | Quads [I] |
  |---|---:|
  | Barra fija HMI | ≈ 150 |
  | Panel HMI (consola) | ≈ 600 |
  | Monitor de nucleo | — |
  | Inspector de texto (12 filas) | ≈ 200–300 |
  | Trazador (3 polilíneas) | — |
  | Etiquetas de marcadores | — |
  | **Total** | **> 1 000** |

  - El total va contra 400. Ni el panel de HMI cabe solo.
  - nucleo#16 (monitor) y la barra de HMI muestran la misma información (enlace, Hz).
- **C6. Convención de los 488 B.**
  - El transporte manda el CDR **sin** los 4 B de encapsulación (`xrce_transport.cpp:12-13,678`).
  - geom, HMI y mapas suman esos 4 B (rosbags); sensores no.
  - Efecto: «Detection3DArray no cabe por 1 B» es falso (485 B de carga), y caben 107 rayos, no 106.
  - Margen real con rosbags: ≤ 492.
  - [?] En recepción, la cabecera del DATA del agente puede no ser 24 B: hay que medirlo.
- **C7. Instancias 3D (modo HMI: 80).**

  | Pieza | Instancias |
  |---|---:|
  | Robot | 40 |
  | TF (ejes + flechas) | 32–64 |
  | Marcadores | 48 |
  | Mapa | 12 |
  | Fantasma de trayectoria | +40 |
  | **Total** | **172–204** |

  - Sin los displays de geom, ya son 172–204. Supera también las 150 del modo Viz.
  - geom propone la planta 2D por defecto en la Vita; los demás posts no lo asumen.
- **C8. TF en la Vita.**
  - Cuatro enfoques:
    - nucleo: `tf = null`, el frame se supone fijo;
    - geom: `TfLigero` en GDScript + relay `/vita/tf`;
    - mapas: `tf: RosTfListener` anotado, que rompe la compilación;
    - sensores: el display es hijo del nodo del frame.
  - API_PARITY ya fija el nativo sobre `tf-tree` como P0.
- **C9. QoS de lo que publica la Vita.** HMI §0.4 dice «las herramientas publican fiable», mapas#27 publica el
  feedback IM en BE. El servidor IM suscribe con `rclcpp::QoS(1)`, que es fiable
  (`interactive_marker_server.hpp:87-88`, jazzy): con BE no llega nada. Gana HMI.
- **C10. Rutas.** `res://comun/{visor,viz,hmi}/` frente a `plantillas/comun/hmi/` (HMI borrador §3), y `godot/comun/`
  ya existe en el repo (`vita_relay.gd.uid`). Falta decidir un solo árbol.

## 5. Alternativas buscadas (registro §4.3)

| Decisión | Alternativa buscada | Resultado |
|---|---|---|
| Arquitectura de displays (nucleo, HMI) | **Ozuba/gdviz** (MIT; estudiado en `docs/24` §1–§4) | Ya tiene `viz_registry.gd` y el contrato TopicDisplay/Tool/View, y T-W4-4 «capa GXM-safe» es P0 (`docs/24:286`). **Ningún post de W13 lo cita.** Es la alternativa principal a C1 y C2 |
| Addons Godot ↔ ROS con visualización | búsqueda web: nordstream3/Godot-4-ROS2-integration (GPL-3, Humble), godot_ros_pcviz (demo de hace unos 5 años), godot_ros (2018) | Nada mantenido de estilo RViz. gdviz sigue siendo lo único reutilizable |
| Relay propio frente a un puente genérico | foxglove_bridge (WebSocket, CDR, esquemas `ros2msg`, grafo) | Da el descubrimiento y los esquemas que faltan en la Vita, pero va sobre TCP/WebSocket y entrega el CDR completo, así que no resuelve los 488 B ni el coste de decodificar. Sirve en el PC como alternativa a rclgd para paneles; no para la Vita |
| Decodificar en GDScript frente a C frente a relay | `viz-decode` (docs/31 §4.3: `vizd_scan_xy`, `vizd_cloud_cm`, `vizd_project`…) | Se mantiene la regla de corte de ADR 0011 §5: el relay primero; C cuando toque recompilar la plantilla |
| TF en la Vita | nativo sobre `modules/tf-tree` (P0, API_PARITY) frente a TfLigero en GDScript frente a FK local con `/vita/joints` | véase D3 |
| Feedback IM en BE | código de `interactive_markers` (jazzy) | descartado: tiene que ir fiable |

## 6. DECISIONES ABIERTAS para el juez (Fable 5.2)

1. **D1 — Contrato único de display (C1).**
   - Opciones:
     - (a) VisorRos + CanalDisplay + DisplayRos3D/2D/Hud de nucleo; widget_hud y sensor_base se fusionan con
       DisplayRosHud;
     - (b) adoptar gdviz con la capa GXM-safe (T-W4-4);
     - (c) dejar una base por familia.
   - Pros:
     - (a) es ya portable y casa con doc 35;
     - (b) trae registro, herramientas y vistas hechos y hereda el mantenimiento de Ozuba.
   - Contras:
     - (a) es código nuevo que duplica gdviz;
     - (b) gdviz aún usa clases sombra `gen/` y Label3D/MultiMesh (docs/24), coste M;
     - (c) multiplica el mantenimiento.
   - Recomendación del revisor: (a) con la interfaz de plugins de gdviz (`viz_registry`) como modelo, y
     reutilizar su código donde sea MIT-compatible.
2. **D2 — Una sola biblioteca de primitivas y color (C2).**
   - Opciones:
     - (a) `fabrica.gd` (paleta UV, ADR 0011 §3) más las formas de geom;
     - (b) `primitivas.gd` con material por color a = 0,99;
     - (c) `viz_shapes` de gdviz adaptado.
   - Pros y contras:
     - (a) cumple «un material» y nunca entra en la pasada de luz;
     - (b) es más simple, pero crea N materiales y depende de H8 (a ≤ 0,99) sin medir.
   - Gate: E-W8-1, `lit=` = 0.
3. **D3 — TF en la Vita (C8).**
   - Opciones:
     - (a) TfLigero en GDScript ya;
     - (b) el nativo sobre `tf-tree` (P0, recompilar plantilla);
     - (c) sin TF: frames del robot por FK local (`/vita/joints`) y del mundo por `/vita/pose2d` (map→base).
   - Pros y contras:
     - (c) cuesta 0 B extra y ya funciona en el G1;
     - (a)/(b) dan TF genérico, pero `/vita/tf` de 32 frames come el presupuesto de red.
   - Recomendación: (c) por defecto, y (b) cuando se recompile.
4. **D4 — Convención de tamaño (C6).**
   - Fijar «carga XRCE = CDR sin encapsulación ≤ 488 B ⇔ rosbags ≤ 492 B» o mantener el margen conservador de 4 B.
   - Hay que corregir la cita `xrce_transport.cpp:411-415` y medir la cabecera en recepción.
5. **D5 — Contrato del relay (C4).**
   - Hay que decidir cinco cosas:
     - una cabecera común `[seq, trozo, n_trozos, …]` para todo lo troceado;
     - registrar los formatos en VC/1 (`vc1.gd`) con prueba de bytes (`pruebas/runner.gd`);
     - qué módulos entran en la Fase 1;
     - un presupuesto de red sumado: hoy ≈ 30 KB/s + marcadores ≈ 12 + rosout ≈ 5 + diag ≈ 3 + costmap ≈ 5 +
       det ≈ 2,4, todo ≈ 60 KB/s sin TF;
     - si `/vita/pose2d` se amplía (rompe a quien lo consume) o sale un `/vita/pose2d_cov` nuevo.
   - Recomendación: un topic nuevo.
6. **D6 — Presupuesto HUD (C5).**
   - Opciones:
     - (a) un gestor de HUD global: barra fija + **un** panel a la vez (HMI) para todos los posts;
     - (b) subir el HUD de ADR 0011 a costa de los sensores 2D.
   - Antes de fijar filas, medir el coste por glifo frente al coste por lote con `[gxm2d-canvas]`.
   - Unificar el monitor de nucleo#16 con la barra de HMI.
7. **D7 — Instancias 3D (C7).**
   - Opciones:
     - (a) planta 2D por defecto en la Vita (geom);
     - (b) la orbital 3D solo en modo Viz a 30 FPS;
     - (c) bajar los cupos de TF y marcadores (ADR 0011 §6) cuando el robot está visible.
   - El fantasma de trayectoria solo con el robot oculto.
8. **D8 — Descartar antes de decodificar en ros2_vita (nucleo#17 P1).**
   - `set_max_rate`/`latest_only` en la cola + `type_idx` resuelto en `setup()`, o seguir con «el último gana» en
     GDScript.
   - Afecta a todos los displays de alta frecuencia; requiere recompilar la plantilla. Hay que agruparlo con TF (D3b).
9. **D9 — Descubrimiento en la Vita.**
   - Opciones: `/vita/catalogo` fiable con TRANSIENT_LOCAL, o `res://ros/catalogo.json` generado al exportar, o
     ninguno (topics fijos en la escena, doc 35).
   - Los topics fijos son lo más simple y coherente con las escenas editables.
10. **D10 — Esquema de visor grande** (todos los tipos de W13 en un `.rsch`) frente a un esquema por app.
    - Depende de D8, por la búsqueda lineal que se hace en cada mensaje.
    - Hay que añadir los tipos que faltan:
      - en `generar_esquemas.py`: visualization_msgs, PoseArray, PoseWithCovarianceStamped, PointStamped, Log,
        DiagnosticArray, Temperature…;
      - además, registrar los `.msg` de vision_msgs, map_msgs y nav2_msgs.
11. **D11 — Texto superpuesto (C3):** `draw_string` en un único CanvasItem para todos (geom/HMI) frente a nodos
    `Label` (mapas#21). Recomendación: `draw_string`.
12. **D12 — Detecciones.** Relay `det2d`/`det3d` en Float32 frente a fiable directo a ≤ 5 Hz (1 detección cabe en
    BE).
    - El relay compacto pierde `id` y las hipótesis múltiples, pero cabe n ≤ 19.
13. **D13 — Imagen en la Vita (sens#9).** `/vita/camara` (JPEG 160×120 fiable ≤ 3 KB, docs/27:107) frente a miniaturas
    crudas mono8.
    - Ninguna de las dos existe todavía. Hace falta un módulo del relay con OpenCV.
14. **D14 — Marcadores en la Vita.** Estado completo `/vita/marcadores` con 10 floats y 11 por datagrama (mapas)
    frente a los 8 floats y 14 por datagrama de docs/27.
    - La versión de mapas da escala anisótropa y alfa; la de docs/27 cabe más por datagrama.
15. **D15 — Ubicación de los archivos (C10):** `godot/comun/viz/…` compartido por todas las plantillas frente a
    `godot/plantillas/comun/…`.
