# W13 · `nucleo-generico` — borrador (ronda 1, 2026-11-13)

> Investigador: `nucleo-generico` (Opus 5.5). Fichas en `W13-nucleo-generico.json` (18). Este borrador resume
> la arquitectura propuesta, la tabla tipo → visualizador de mi familia, los huecos de `ros2_vita` y las preguntas
> abiertas. Marcas: [V] verificado en código/docs, [I] inferencia, [?] hipótesis. Nada se ha ejecutado: el código
> GDScript de las fichas está escrito contra la API real, pero sin pasar por el analizador.

## 1. Lo que dice el código (base de todo lo demás)

### 1.1 Cómo enumerar los campos de un mensaje desconocido

- **rclgd no tiene `to_dict()` ni una lista de campos explícita** [V]. API pública de `RosMsg`: `from_type`, `init`,
  `get_member`, `set_member`, `get_type_name`, `get_ros_interface_name`, `_to_string`
  (`godot/rclgd/rclgd/src/rclgd/ros_msg.cpp:122-149`).
- **Hay dos caminos según la clase** [V]:
  - Un `RosMsg` **dinámico** responde a `get_property_list()` con los campos del esquema BabelFish. Para saber el
    tipo Variant **convierte cada miembro** (`ros_msg.cpp:285-301`).
  - Una **clase tipada** (`RosGeometryMsgsTwist`, registrada a partir de `package.xml`) no añade nada en
    `_get_property_list` (`typed_`). Sus campos son propiedades de ClassDB (`ros_type_registry.cpp:245-330`).
    Los submensajes y los arrays de mensajes llevan `PROPERTY_USAGE_NONE` (`:284`, `:306`), pero aun así aparecen
    en `get_property_list()` (`test_native_types.gd:40-44`).
  - Consecuencia: **no se puede filtrar por `PROPERTY_USAGE_STORAGE`**. La receta portable
    (`introspeccion_ros.gd`, ficha 1) es:
    - clase tipada → `ClassDB.class_get_property_list(clase, true)`;
    - dinámica → `get_property_list()` menos categorías, grupos y `script`;
    - en los dos casos, calcularlo **una vez por tipo sobre un prototipo vacío** de `RosMsg.from_type(tipo)`,
      para no convertir un `Image.data` de 1 MB.
- **Campos reservados** [V]. Un campo cuyo nombre es una palabra clave de GDScript o un miembro de `RosMsg`/Object
  no se registra como propiedad de la clase tipada (`ros_type_registry.cpp:217-240,268-273`). No sale en la lista
  y solo se lee con `get_member`. En los paquetes comunes el riesgo es bajo [I].
- **ros2_vita solo tiene `RosMsg` dinámico** (T3.2.4 ⏳, `API_PARITY.md`). `_get_property_list` recorre el `.rsch`
  y no cuesta nada, porque el mensaje ya llegó decodificado entero (`ros_msg.cpp:303-316`, H25).
  - Extra que solo existe en la Vita: `RosMsg.list_types()` (`ros_msg.cpp:34-46`) y un esquema con el tipo
    primitivo exacto (`msg_field_info`), que no se expone a GDScript.
- **Mapeo de tipos idéntico en las dos plataformas** [V] (`ros_type_utils.hpp:46-148,456-513`;
  `ros_msg.cpp:432-488`):

  | Tipo ROS | Tipo Godot |
  |---|---|
  | `uint8[]` | `PackedByteArray` |
  | `float32[]` | `PackedFloat32Array` |
  | `float64[]` | `PackedFloat64Array` |
  | `int8[]`, `int16[]`, `uint16[]`, `int32[]` | `PackedInt32Array` |
  | `uint32[]`, `int64[]`, `uint64[]` | `PackedInt64Array` |
  | `string[]` | `PackedStringArray` |
  | `bool[]`, arrays de mensajes | `Array` |

  Se pierde el primitivo exacto (no se distingue `int8` de `int16`). Las constantes de los `.msg` no existen en
  ninguna de las dos.

### 1.2 Entrega de mensajes

- **rclgd** entrega **cada** mensaje con `call_deferred` desde el ejecutor, sin límite (`ros_subscriber.cpp:22-37`).
- **ros2_vita** acota su cola a 256 descartando el más antiguo (`ros_runtime.cpp:473-484`). Pero decodifica el
  mensaje entero **antes** del callback (`ros_runtime.cpp:118-133`). Por eso un límite de Hz en GDScript no ahorra
  la decodificación en la Vita.

### 1.3 Descubrimiento de topics

- **PC:** `get_topic_names_and_types()` devuelve `{topic: [tipos]}` (`ros_node.cpp:361-381`). No hay eventos de
  grafo, así que hay que sondear.
- **Vita:** no hay API de grafo (❌ en `API_PARITY.md`).
- **Suscribirse en la Vita a un tipo sin esquema:** la suscripción XRCE **sí se crea**, porque el transporte solo
  usa el nombre DDS (`xrce_transport.cpp:152,637-653`).
  - Cada muestra falla en `from_type` con `ERR_FAIL_COND`, y el callback nunca se llama
    (`ros_runtime.cpp:122-123`) [V].
  - No he comprobado si el agente acepta un tipo desconocido [?].
- **El esquema es único y global:** `load_schema_file` lo reemplaza (`ros_msg.cpp:14-24`).
  - Tamaño medido: ≈ 137 B por tipo (`dron-mapeo/ros/schema.rsch`: 44 tipos y 182 campos en 6 030 B, según la
    cabecera).
  - Un esquema con «todo common_interfaces» ocuparía decenas de KB, que en la Vita no es un problema [I].
  - Lo que sí cuesta: `msg_schema_find_type` es lineal y se llama **en cada mensaje** recibido
    (`impl-c:125-139`, vía `from_type`).

## 2. Arquitectura propuesta

Decisión central: **composición** en lugar de una única jerarquía. Godot no tiene herencia múltiple, y un display
3D, uno 2D (planta) y uno HUD tienen que heredar de `Node3D`, `Node2D` y `Control` respectivamente. La parte ROS
común vive en un `RefCounted` (`CanalDisplay`), y tres bases delgadas con los mismos `@export` la envuelven.
Equivalencias con RViz2 (`rviz_common`):

| RViz2 | Aquí | Dónde |
|---|---|---|
| `DisplayContext` / `VisualizationManager` (frame fijo, TF, nodo) | `VisorRos` (Node en la escena) | ficha 3 |
| `RosTopicDisplay` + `MessageFilterDisplay<T>` (Topic, QoS, Filter size, estado, `processMessage`, `reset`) | `display_ros_{3d,2d,hud}.gd` + `canal_display.gd` | fichas 4–5 |
| `plugins_description.xml` (`<message_type>`) + «Add → By topic» | `registro_displays.gd` (tipo y patrón de topic → escena) | ficha 2 |
| archivo `.rviz` | subárbol de displays dentro de `main.tscn` (regla de doc 35) | ficha 6 |
| línea de estado «N messages, X Hz» | `canal.hz_medido` + monitor | fichas 5 y 17 |

### 2.1 Diagrama de clases (texto)

```
VisorRos (Node, en la escena)                       ≈ rviz_common::DisplayContext
  ├─ contexto: ContextoRos (plantillas/ros/contexto_ros.gd)  → RosNode, qos(best_effort, depth, latched)
  ├─ tf: RosTfListener | null   (solo rclgd; por call(), sin anotar tipo)
  ├─ frame_fijo: String
  ├─ transformada(frame) -> Transform3D | null       (lookup_transform ya en ejes Godot)
  └─ _ready(): conecta a todo descendiente del grupo "display_ros"

CanalDisplay (RefCounted)                            ≈ RosTopicDisplay (suscripción) + estado
  ├─ abrir(nodo, topic, tipo, qos) / cerrar()
  ├─ coalescer (el último gana) | entregar todos (trazador)
  ├─ hz_max, hz_medido (ventana 1 s), recibidos, mostrados, caducado(s)
  └─ señal mensaje(msg)

DisplayRos3D (Node3D) / DisplayRos2D (Node2D) / DisplayRosHud (Control)   ≈ MessageFilterDisplay<T>
  ├─ @export habilitado, topic, tipo, frame_id, hz_max, hz_max_vita, best_effort, profundidad,
  │          decaimiento_s, solo_pc        (mismos nombres que sensor_base.gd:6-14)
  ├─ canal: CanalDisplay
  ├─ conectar(visor)                       ← lo llama VisorRos
  ├─ _al_mensaje(msg): frame → TF → transform → _procesar(msg)   (la variante HUD se salta el TF)
  ├─ _procesar(msg)   [virtual]            ≈ processMessage()
  └─ _caducar()       [virtual]            ≈ reset()/decay
       ├─ DisplayValor (HUD)        std_msgs escalares
       ├─ DisplayMultiArray (HUD)   *MultiArray
       ├─ DisplayColor (HUD)        ColorRGBA
       ├─ DisplayDesconocido (HUD)  tipo sin esquema / sin display
       └─ (otras familias: LaserScan, Odometry, Marker… — otros investigadores)

InspectorTree (Tree, PC) · InspectorTexto (Control, Vita y PC) · TrazadorSeries (Control)
  └─ consumen CanalDisplay; usan IntrospeccionRos

IntrospeccionRos (utilidad estática)   campos_de_tipo(tipo), campos(msg), leer_ruta(msg, ruta)
TiempoRos (utilidad estática)          segundos(t), a_texto(t), latencia(nodo, msg)
RegistroDisplays (utilidad estática)   candidatos(topic, tipo, en_vita), crear(...)
ExploradorTopics (RefCounted)          sondear() [PC: grafo] | aplicar(dict) [Vita: catálogo]
```

### 2.2 Decisiones no evidentes (para el juez)

1. **«El último gana» en GDScript por defecto.** Un display de estado solo necesita el último valor. Así se evita
   procesar 100 mensajes por segundo que rclgd encolaría con `call_deferred`. El trazador lo desactiva, porque
   necesita todas las muestras.
2. **Rutas del trazador con la sintaxis de Foxglove** (`/odom.twist.twist.linear.x`). El punto no puede aparecer en
   un nombre de topic, así que no hay ambigüedad y funciona en la Vita sin grafo. La sintaxis de rqt_plot
   (`/odom/twist/...`) se acepta solo en el PC, resolviendo el prefijo más largo con el grafo.
3. **Trazador sin bucles por punto al dibujar.** Los puntos se guardan en unidades de datos y
   `draw_set_transform` hace el mapeo a píxeles en C++. Cada serie es una `draw_polyline(..., -1)` fina = 1 comando
   (H17). El búfer circular se ordena con `slice()` en C++.
4. **Registro con clave (tipo, patrón de topic).** El relay de la Vita reutiliza `Int16MultiArray` y
   `Float32MultiArray` con un significado distinto en cada topic (`vita_relay.py:10-19`).
5. **Registro como tabla GDScript, no como plugins cargables.** godot4-vita no tiene GDExtension, y el catálogo
   de displays es pequeño y versionado.
6. **Displays fijos = nodos del `.tscn` con `@export`** (doc 35: el panel tiene posición y tamaño). Lo que se
   genera con los datos no se guarda en la escena. Los displays añadidos en ejecución no se guardan.
7. **En la Vita, inspector de texto plano en lugar de `Tree`.**
   - Cada glifo es un *quad* recalculado en cada fotograma (H16). Referencia medida: HUD de 305 *quads* ≈ 1,85 ms
     (doc 34).
   - Un árbol de 20 filas superaría el presupuesto 2D de ADR 0011 §6 [I].
8. **Descubrimiento en la Vita por un catálogo publicado por el relay** (`/vita/catalogo`: String fiable con
   TRANSIENT_LOCAL, el mismo patrón que `/vita/joints_orden`).
   - Respaldo: `res://ros/catalogo.json` generado al exportar.
   - Las entradas se filtran con `RosMsg.from_type(t) != null`, que es portable. `list_types()` no compilaría en
     rclgd.

## 3. Tabla tipo → visualizador (familia `nucleo-generico`)

| Tipo | Display | Capa (ADR 0011) | PC | Vita | Ficha |
|---|---|---|---|---|---|
| **cualquiera** | `InspectorTree` | HUD (`Tree`) | ✅ perezoso, ≤ 5 Hz, arrays ≤ 32 | ✗ por coste de glifos → `InspectorTexto` | 7 |
| **cualquiera** | `InspectorTexto` | HUD (`draw_string`) | ✅ | ✅ ≤ 12 filas, 4 Hz, solo si cambia | 8 |
| campos numéricos de cualquier tipo | `TrazadorSeries` | HUD 2D (polilínea fina) | ✅ | ✅ 3 × 300 puntos, ≤ 15 Hz | 9 |
| `std_msgs/{Bool, Byte, Char, Int*, UInt*, Float*, String}` | `DisplayValor` (Label, LED para Bool) + trazador opcional | HUD | ✅ | ✅; añadir los tipos a `generar_esquemas.py` (hoy solo Bool y String) | 13 |
| `std_msgs/Empty` | `DisplayValor` (contador de eventos) | HUD | ✅ | [?] depende de que el `.rsch` acepte el miembro de relleno | 13 |
| `std_msgs/*MultiArray` (11 tipos) + `MultiArrayLayout` / `MultiArrayDimension` | `DisplayMultiArray`: perfil 1D o mapa de calor 2D | HUD 2D / textura | ✅ | ✅ (formato base del relay; diezmar a 128 puntos; textura ≤ 4 Hz) | 14 |
| formatos compactos del relay (`/vita/*`) | display específico por topic (registro) | según el dato | ✅ | ✅ | 2 |
| `std_msgs/ColorRGBA` | `DisplayColor` + utilidad `color_ros` / `indice_paleta` | HUD | ✅ | ✅ (paleta en 3D, H3) | 15 |
| `std_msgs/Header` | sin display: frame → TF en la base; stamp → latencia | — | ✅ | ✅ (sin TF ⏳) | 16 |
| `builtin_interfaces/{Time, Duration}` | utilidad `TiempoRos` | — | ✅ | ✅ (`now()` = hora del agente) | 16 |
| tipo sin esquema (Vita) | `DisplayDesconocido` («sin esquema»; no suscribe) | HUD | n/a | ✅ | 12 |
| (todos) | monitor Hz / latencia / estado | HUD | ✅ | ✅ + `get_transport_info()` | 17 |

## 4. Huecos de `ros2_vita` (priorizados)

| P | Hueco | Evidencia | Propuesta |
|---|---|---|---|
| P0 | Sin `RosTfListener` | `API_PARITY.md` | ya conocido (tf-tree) |
| P1 | Decodifica todo antes de que el script pueda descartar | `ros_runtime.cpp:118-133`, H25 | `RosSubscriber.set_max_rate(hz)` o `latest_only` en la cola, **antes** de `from_type` / `deserialize` |
| P1 | `from_type` por mensaje (búsqueda lineal de tipo) e `init_idx` doble | `ros_runtime.cpp:122`, `impl-c:125-139`, `ros_msg.cpp:134-147,387-392,524` | resolver `type_idx` en `setup()`; no construir los valores por defecto antes de decodificar |
| P1 | `_find_field` lineal en cada `set_member` del decodificador ⇒ O(campos²) por mensaje | `ros_msg.cpp:173-188` desde `d_prim` `:414-418` | asignar por índice de campo |
| P2 | Sin contadores por suscripción (muestras, bytes, errores CDR, sin esquema) | `ros_runtime.h:90-108` | `RosSubscriber.get_stats()` |
| P2 | El tipo exacto del esquema no se expone | `msg_schema.h:60-65` | `RosMsg.describe_type(tipo)`; también sería un PR posible a rclgd |
| P3 | Un solo esquema, que se reemplaza al cargar otro | `ros_msg.cpp:14-24` | fusionar esquemas o generar un «esquema de visor» grande |
| P3 | Clases tipadas | T3.2.4 | portabilidad: anotar con `RosMsg` y tipos como texto |
| — | Grafo | inherente a XRCE | catálogo del relay |

Regla de portabilidad mientras tanto: lo que no exista en las dos plataformas se llama con `has_method` +
`call()`, sin anotar `RosTfListener` ni clases tipadas. Si no, el script no compila en la Vita [I].

## 5. Preguntas abiertas

1. **[?]** ¿Acepta el agente micro-ROS (modo XML) un DataReader cuyo tipo no conoce? Determina si un modo «crudo»
   (Hz y bytes sin esquema) es posible en la Vita.
2. **[I]** ¿Devuelve `ClassDB.class_get_property_list(clase, true)` exactamente los campos de las clases tipadas
   registradas por la interfaz C de GDExtension? Hay que probarlo en `rclgd/test/project`.
3. **[I]** ¿Sigue siendo de 1 px la polilínea fina (ancho -1) con `draw_set_transform` escalado, y la dibuja el port
   en un solo lote?
   - Gate: 3 series en g1-sensores con el perfil ligero.
   - Criterio: `draws` +≤ 3 y `avg_canvas_us` +≤ 300.
4. **[?]** ¿Entra `std_msgs/Empty` en el `.rsch`? Depende de cómo genere rosbags el miembro de relleno
   (`structure_needs_at_least_one_member`).
5. **¿Esquema de visor grande?** Un `.rsch` con todo common_interfaces + visualization_msgs + nav_msgs + tf2_msgs +
   diagnostic_msgs para las apps de visualización: antes hay que cerrar los huecos P1 de búsqueda lineal. Lo decide
   el juez o el orquestador.
6. **Coherencia con el resto del W13:** ¿adoptan los otros investigadores la base `DisplayRos*` y el registro? Si
   alguno propone heredar directamente de `Node3D` con su propia suscripción, se unifica en la integración.
7. **Coste por glifo** (≈ 6 µs/quad, extrapolado de doc 34): hay que medirlo con `[gxm2d-canvas]` (H18) antes de
   fijar los límites de filas de los inspectores y del monitor.
