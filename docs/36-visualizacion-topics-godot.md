# 36 — Visualizar topics ROS 2 en Godot 4 (PC con rclgd, Vita con `ros2_vita`): visor portable y catálogo por tipo (W13)

> **Estado:** workshop W13 cerrado (diseño) el 2026-11-13. Decisión formal en **ADR 0013**
> (`docs/adr/0013-visualizacion-topics-godot.md`); sentencia detallada (D1–D15, tareas V1–V15, gates) en
> `docs/ia/workshops/posts/W13-juez-fable.md`. **Nada está implementado**: este documento es la especificación para
> escribir `godot/plantillas/visor/` y los módulos nuevos del relay.
> Marcas: [V] verificado (archivo:línea, medida o `--check-only`) · [I] inferencia · [?] sin confirmar. Las cifras de
> la Vita son de diseño [I] hasta sus gates (§9).
> **Tamaños:** en bytes de CDR **con** los 4 B de encapsulación, medidos con rosbags (convención de `docs/27` §1),
> salvo que se diga otra cosa. Límite duro del transporte = 488 B de carga XRCE **sin** encapsulación
> (`godot/ros2_vita/xrce_transport.cpp:12-13,147,678`); límite de diseño de todo `/vita/*` = 488 B con rosbags (§5.1).
> **Código:** los esqueletos de las fichas originales pasaron `--check-only` contra la API de `ros2_vita` (101 PASA,
> 4 FALLA, 2 NO APLICA; `W13-revision.md` §1). Los de **este documento** están **reescritos** al contrato del ADR 0013
> (nombres definitivos, `_procesar` / `_pintar`, QoS por `set_*`) y llevan aplicadas las cuatro correcciones de la
> revisión, pero **no se han pasado por el analizador** [I]: es lo primero que comprueba V1 (§10).
> **Fuentes:** `docs/ia/workshops/W13-visualizacion-topics.md` (tablero); fichas `posts/W13-{nucleo-generico,
> geometria-tf-robot,sensores-densos,mapas-marcadores,hmi-percepcion-acciones}.json` y sus `-borrador.md`; revisión
> `posts/W13-revision.{json,md}`; sentencia `posts/W13-juez-fable.md`; ADR 0013. **Si una ficha contradice la
> sentencia, gana la sentencia** y se dice en el texto («⚖ sentencia»).

## 0. Resumen: decisiones clave

1. **Visor propio y pequeño** en `godot/plantillas/visor/` (los proyectos lo ven como `res://comun/visor/` por el
   enlace `comun -> ../plantillas`). gdviz (Ozuba, MIT) es el **modelo de contrato**, no una dependencia: no corre en
   la Vita sin portar (`docs/24-portabilidad-ozuba.md:102-112,147`). Sustituye a T-W4-4 (ADR 0013 §1).
2. **Un solo contrato de display**: `VisorRos` (contexto) + `CanalDisplay` (toda la lógica ROS) + tres bases delgadas
   (`DisplayRos3D` / `DisplayRos2D` / `DisplayRosHud`) con los mismos `@export` y los ganchos `_procesar(msg)`,
   `_procesar_compacto(msg)`, `_pintar(datos)`, `_caducar()`, `_coste()` (§2).
3. **El mismo GDScript en PC y Vita**: *decodificar* (estándar o compacto del relay) está separado de *pintar*; los
   dos decodificadores entregan el mismo dato intermedio. `VisorRos.usa_compactos()` elige la fuente (§2.5).
4. **Una biblioteca de dibujo**: `PrimitivasViz` (mallas unidad, solo triángulos) + `PaletaViz` (textura 16×16, un
   material, un texel con alfa 0 que saca la malla de la pasada de luz). Texto siempre `draw_string` en un
   `CanvasItem` (`TextoSuperpuesto` o el `_draw()` del widget) (§3).
5. **TF en la Vita sin tráfico extra**: `TfLigero` (GDScript, ≤ 32 marcos, último valor) con la API de
   `RosTfListener`, alimentado por la cinemática local del robot horneado (`/vita/joints`) y por `/vita/pose2d`.
   El módulo `tf` del relay es opcional (≤ 8 marcos a 10 Hz) (§2.9.6).
6. **Planta 2D por defecto en la Vita** para lo que vive en el suelo (scan, nube, odometría, path, poses,
   covarianza, polígonos, GPS); la orbital 3D queda para robot, TF, IMU, fuerzas y marcadores (§7).
7. **HUD = barra fija + una pestaña visible** (`GestorHud`): 400 *quads* = barra ≤ 120 + pestaña ≤ 240 + texto
   superpuesto ≤ 40 (§7.2).
8. **Relay VC/1 rev. 2**: cabecera común `[seq, trozo, n_trozos, n, …]` para todo lo troceado nuevo, catálogo
   cerrado de `/vita/*`, formatos registrados con prueba de bytes Python = GDScript y un tope de red (100 KB/s,
   200 datagramas/s) que el relay comprueba al arrancar (§5).
9. **QoS por regla**: quien suscribe, best effort; quien publica, fiable; excepciones: lo *latched*, los eventos y
   la imagen en la Vita (§6). Siempre `RosQoS.set_*()`, nunca `qos.reliability =` (no existe en la Vita).
10. **Nada nativo bloquea la Fase 1**: los huecos de `ros2_vita` (propiedades de `RosQoS`, `latest_only`, TF nativo,
    `viz-decode`, contadores) van juntos en el paquete «plantilla N+1» (V13).

---

## 1. Qué resuelve rclgd, qué no, y qué le falta a `ros2_vita`

### 1.1 Introspección de `RosMsg` (base del inspector y del trazador)

- **rclgd no tiene `to_dict()` ni lista de campos** [V]. API pública de `RosMsg`: `from_type`, `init`,
  `get_member`, `set_member`, `get_type_name`, `get_ros_interface_name`, `_to_string`
  (`godot/rclgd/rclgd/src/rclgd/ros_msg.cpp:122-149`).
- **Dos caminos según la clase** [V]:
  - `RosMsg` **dinámico** (rclgd y `ros2_vita`): `get_property_list()` devuelve los campos del esquema; en rclgd
    **convierte cada miembro** para dar su tipo (`ros_msg.cpp:285-301`), así que se llama sobre un **prototipo
    vacío**, nunca sobre un mensaje con un `Image.data` de 1 MB.
  - **Clase tipada** de rclgd (`RosGeometryMsgsTwist`…): `_get_property_list` no añade nada; los campos son
    propiedades de ClassDB (`ros_type_registry.cpp:245-330`). Submensajes y arrays de mensajes llevan
    `PROPERTY_USAGE_NONE` (`:284,306`) pero salen igual en `get_property_list()` (`test_native_types.gd:40-44`): **no
    se puede filtrar por `PROPERTY_USAGE_STORAGE`**.
  - Receta portable (`introspeccion_ros.gd`, §4.1): tipada → `ClassDB.class_get_property_list(clase, true)`;
    dinámica → `get_property_list()` menos categorías, grupos y `script`; cacheado por tipo [V API; I que ClassDB
    devuelva exactamente los campos de una clase registrada por GDExtension, por probar en `rclgd/test/project`].
- **Campos reservados** [V]: un campo cuyo nombre es palabra clave de GDScript o miembro de `RosMsg`/`Object` no se
  registra como propiedad tipada (`ros_type_registry.cpp:217-240,268-273`) y solo se lee con `get_member`. **Choque
  comprobado** con `RefCounted.reference()`: `m.reference` de `JointTrajectoryControllerState` es un `Callable` y el
  analizador falla; hay que escribir `m.get_member("reference")` (hmi#13, §8).
- **`ros2_vita` solo tiene `RosMsg` dinámico** (T3.2.4 ⏳, `godot/ros2_vita/API_PARITY.md:67-69`). Su
  `_get_property_list` recorre el `.rsch` sin coste porque el mensaje ya llegó decodificado
  (`godot/ros2_vita/ros_msg.cpp:303-316`, H25). Extra solo de la Vita: `RosMsg.list_types()` (`ros_msg.cpp:34-46`)
  — no compila en rclgd, así que no se usa en código común.
- **Mapeo de arrays idéntico en las dos plataformas** [V] (rclgd `ros_type_utils.hpp:46-148,456-513`; Vita
  `ros_msg.cpp:432-488`):

  | ROS | Godot |
  |---|---|
  | `uint8[]` | `PackedByteArray` |
  | `float32[]` / `float64[]` | `PackedFloat32Array` / `PackedFloat64Array` |
  | `int8[]`, `int16[]`, `uint16[]`, `int32[]` | `PackedInt32Array` |
  | `uint32[]`, `int64[]`, `uint64[]` | `PackedInt64Array` (en la Vita, `ros_msg.cpp:461-467`; en rclgd [?]) |
  | `string[]` | `PackedStringArray` |
  | `bool[]`, arrays de mensajes | `Array` |

  Se pierde el primitivo exacto (`int8` ≡ `int16`); las constantes de los `.msg` no existen en ninguna de las dos.

### 1.2 Entrega de mensajes

- **rclgd** entrega **cada** mensaje con `call_deferred` desde el ejecutor, sin límite
  (`rclgd/src/rclgd/ros_subscriber.cpp:20-37`) [V]: sin «el último gana» en GDScript, un topic a 100 Hz cuesta 100
  callbacks por segundo.
- **`ros2_vita`** acota la cola a 256 descartando la más antigua (`godot/ros2_vita/ros_runtime.cpp:473-484`), pero
  **decodifica el mensaje entero antes del callback** (`ros_runtime.cpp:118-133`, H25) [V]. Un límite de Hz en
  GDScript no ahorra la decodificación en la Vita; por eso el ritmo se fija en origen (relay) y el descarte nativo
  va a V13 (D8).
- Tipo sin esquema en la Vita: la suscripción XRCE **se crea** (el transporte solo usa el nombre DDS,
  `xrce_transport.cpp:152,637-653`), pero cada muestra falla en `RosMsg.from_type` con `ERR_FAIL_COND` y el callback
  no se llama (`ros_runtime.cpp:122-123`) [V]. Regla: **no suscribir** si `RosMsg.from_type(tipo) == null` (§2.9.2).
- El esquema `.rsch` es **único y global**: `load_schema_file` lo reemplaza (`ros_msg.cpp:14-24`) [V]. Coste ≈ 137 B
  por tipo (`godot/dron-mapeo/ros/schema.rsch`: 44 tipos, 6 030 B) [V]; lo que cuesta es `msg_schema_find_type`,
  lineal y llamado **por mensaje** (`modules/msg-schema/impl-c:125-139` vía `from_type`) [V].

### 1.3 Descubrimiento de topics

- **PC:** `RosNode.get_topic_names_and_types()` → `{topic: [tipos]}` (`rclgd/src/rclgd/ros_node.cpp:361-381`), sin
  eventos de grafo: hay que sondear (2 s) [V].
- **Vita:** no hay API de grafo en XRCE (`API_PARITY.md:38`) [V]. ⚖ sentencia D9: **ningún descubrimiento**; los
  topics son fijos en la escena (doc 35) y `relay_info` dice qué módulos hay. Se descartan `/vita/catalogo` (ficha
  nucleo#10) y `res://ros/catalogo.json`.

### 1.4 Paridad de API que condiciona el código común [V]

| Pieza | rclgd | `ros2_vita` | Regla en el código del visor |
|---|---|---|---|
| `create_subscription(topic, tipo_texto, cb, qos)` | ✅ | ✅ (`ros_runtime.cpp:265-279`) | tipos siempre por texto |
| `RosQoS` | propiedades + métodos | **solo métodos** `set_*` (`ros_runtime.cpp:76-92`) | `contexto.qos(best_effort, profundidad, latched)` (`godot/plantillas/ros/contexto_ros.gd:25-31`); nunca `qos.reliability =` |
| `RosTfListener` / `create_tf_listener` | ✅ | ❌ (`register_types.cpp:16-22`) | `var tf = null` sin anotar; `has_method("create_tf_listener")` |
| `RosClient`, servicios, acciones | ✅ | ⏳ (`API_PARITY.md:31-34`) | scripts que los usan = `solo_pc` |
| `RosLogger` / `get_logger` | ✅ | ❌ (`API_PARITY.md:20,39,85`) | no usar en código común |
| clases tipadas | ✅ | ⏳ T3.2.4 | anotar `RosMsg` o nada |
| `rclgd.ros_to_godot_vector/quat`, `godot_to_ros_*` | ✅ | ✅ (`API_PARITY.md:19`) | la única conversión de ejes |
| `nodo.now()` | reloj ROS | hora del agente tras `uxr_sync_session` (`API_PARITY.md:31`) | sello de lo que se publica |
| `rclgd.get_transport_info()` | ❌ | ✅ (`ros_runtime.cpp:357-366`) | `rclgd.has_method(...)` + `call` |
| asignar un array a un campo | copia | copia (`API_PARITY.md:49`) | construir el array y asignarlo entero |

### 1.5 Huecos de `ros2_vita` que afectan a la visualización (prioridad de la sentencia)

| P | Hueco | Evidencia | Qué se hace mientras | Dónde se cierra |
|---|---|---|---|---|
| P0 | Sin `RosTfListener` | `register_types.cpp:16-22` | `TfLigero` (§2.9.6) | T-W4-2 → V13 (sobre `modules/tf-tree`) |
| P0 | `RosQoS` sin propiedades | `ros_runtime.cpp:76-92` | `set_*()` siempre | T-W4-3 → V13 |
| P1 | Decodifica todo antes de que el script pueda descartar | `ros_runtime.cpp:118-133`, H25 | ritmo fijado en el relay; módulo `ritmo` para directos > 30 Hz; aviso si `hz_medido > 2·hz` | `latest_only` / `set_max_rate` en la cola, V13 |
| P1 | `from_type` (búsqueda lineal) por mensaje e `init_idx` doble | `ros_runtime.cpp:122`; `impl-c:125-139`; `ros_msg.cpp:134-147,387-392,524` | `TIPOS_VISOR` corta (≈ 30 tipos) | tipo resuelto al suscribir, V13 |
| P1 | `_find_field` lineal en cada `set_member` del decodificador ⇒ O(campos²) | `ros_msg.cpp:173-188` desde `:414-418` | — | asignar por índice, V13 |
| P1 | Decodificadores densos en GDScript (scan, nube, proyección) | `docs/31` §4.3 | relay primero, GDScript ≤ 2 ms | `modules/viz-decode/` (T-W8-7), V13 |
| P2 | Sin contadores por suscripción | `ros_runtime.h:90-108` | `CanalDisplay.recibidos/hz_medido` y `get_transport_info()` globales | `RosSubscriber.get_stats()`, V13 |
| P2 | Servicios cliente | `API_PARITY.md:31` | proxy `srv` del puente (`docs/32` §12) | T-W4-9 (V14 depende) |
| P2 | Tipo exacto del esquema no expuesto | `msg_schema.h:60-65` | — | `RosMsg.describe_type(tipo)` (propuesta nucleo#17) |
| P3 | Un solo esquema que se reemplaza | `ros_msg.cpp:14-24` | un `.rsch` por app con `TIPOS_VISOR` (D10) | — |
| — | Grafo | inherente a XRCE | topics fijos + `relay_info` (D9) | — |

---

## 2. Arquitectura

### 2.1 Decisión y equivalencias

Arquitectura propia con el contrato de gdviz como modelo (⚖ sentencia §1; revisión: ALTERNATIVA en nucleo#1, #2 y
hmi#0). Motivos: gdviz necesita en la Vita propiedades de `RosQoS`, `RosTfListener`, grafo, compilar scripts en
ejecución, SubViewport, MultiMesh, color por vértice y `Label3D` (`docs/24:102-112,147`); crea los displays en
ejecución desde un `.rviz` (contra doc 35); y su registro es por tipo, cuando aquí hace falta por (tipo, patrón de
topic) porque el relay reutiliza `*MultiArray` con significado por topic (`docker/scripts/vita_relay.py:10-19`).

| RViz2 (`rviz_common`) | gdviz | Aquí (ADR 0013) |
|---|---|---|
| `DisplayContext` / `VisualizationManager` | `viz_context.gd` | `VisorRos` (`visor_ros.gd`) |
| `RosTopicDisplay` + `MessageFilterDisplay<T>` | `viz_topic_display.gd` | `CanalDisplay` + `DisplayRos3D/2D/Hud` |
| `plugins_description.xml` (`<message_type>`) | `viz_registry.gd` | `RegistroDisplays` (tipo, patrón de topic) |
| `getName()` / tipos del plugin | `viz_name()` / `viz_message_types()` | `nombre_display()` / `tipos_ros()` |
| `processMessage()` | `_viz_message(msg)` | `_procesar(msg)` / `_procesar_compacto(msg)` → `_pintar(datos)` |
| `reset()` | `_viz_reset()` | `_caducar()` |
| archivo `.rviz` | configuración en ejecución | subárbol de displays en `main.tscn` (doc 35) |
| `Tool` | `viz_tool` | `HerramientaVisor` |
| `FrameManager` + `tf2_ros::Buffer` | `viz_frame_manager.gd` | `visor.tf`: `RosTfListener` (PC) / `TfLigero` (Vita) |

Reversión prevista: los ganchos tienen equivalente uno a uno con gdviz, así que un adaptador `VizTopicDisplay` →
`DisplayRos3D` es un archivo si gdviz llega a ser seguro para la Vita (sentencia §1).

### 2.2 Diagrama de clases (texto)

```
VisorRos (Node, en main.tscn)                                 ≈ rviz_common::DisplayContext
  ├─ contexto: ContextoRos  (res://comun/ros/contexto_ros.gd) → nodo: RosNode, qos(be, prof, latched)
  ├─ tf          (sin anotar) RosTfListener (PC, si has_method) | TfLigero (Vita y respaldo)
  ├─ marco_fijo, prefijo_compacto, perfil (HMI|VIZ), px_por_m, camara, texto (TextoSuperpuesto)
  ├─ usa_compactos() → vita | transporte xrce | compacto=1 | forzar_compacto
  ├─ transformada(frame) → Transform3D (ejes Godot, en el marco fijo) | null
  ├─ planta_desde(t3d) → Transform2D (px de la planta, norte arriba)
  ├─ reservar(capa, n, quien) → n concedido   /  liberar(capa, n)
  └─ _ready(): contexto.iniciar → tf → conectar() a cada nodo del grupo "display_ros" que desciende de él

CanalDisplay (RefCounted)  — TODA la lógica ROS                ≈ RosTopicDisplay (suscripción + estado)
  ├─ abrir_para(display, visor) → "ok" | "sin esquema" | …   (elige estándar/compacto, QoS, Hz)
  ├─ abrir(nodo, topic, tipo, qos) / cerrar()
  ├─ bombear()  (cada fotograma: «el último gana», tope hz, hz_medido, aviso hz_medido > 2·hz)
  ├─ caducado(s), compacto, recibidos, mostrados, hz_medido
  └─ señal mensaje(msg)

DisplayRos3D (Node3D)  /  DisplayRos2D (Node2D)  /  DisplayRosHud (Control, SIN TF)
  ├─ @export habilitado, topic, tipo, topic_vita, tipo_vita, frame_id, hz, hz_vita, fiabilidad,
  │          latched, caducidad_s, persistencia_s, solo_pc
  ├─ canal: CanalDisplay; visor; estado; marco (Transform3D del frame, 3D/2D); cupo; capa
  ├─ conectar(visor) / desconectar()
  ├─ _al_mensaje(msg): datos = _procesar_compacto(msg) | _procesar(msg) → [frame→TF] → _pintar(datos)
  ├─ _procesar(msg) → datos | null            ≈ processMessage(), parte «decodificar»
  ├─ _procesar_compacto(msg) → datos | null   (por defecto = _procesar)
  ├─ _pintar(datos)                            parte «dibujar» (solo PrimitivasViz/PaletaViz/lienzo)
  ├─ _caducar()                                ≈ reset() / dato viejo
  ├─ _coste() → {instancias, triangulos, quads}
  └─ static nombre_display(), tipos_ros()
        ├─ displays/3d/*.gd   (robot_joints, pose, punto, vector, ejes, imu, tornillo, rango, tf, marcadores…)
        ├─ displays/2d/*.gd   (scan, nube, path, odometria, poses, covarianza, poligono, gps, mapa, marcadores_2d…)
        └─ displays/hud/*.gd  (barra_estado, medidor, bateria, joy, consola, diagnostico, inspector_texto, trazador…)

GestorHud (Control)       barra fija + pestañas (una visible) + cupo de quads por zona
TextoSuperpuesto (Control) todo el texto anclado al 3D en un _draw()
HerramientaVisor (Node)   base de meta, pose_inicial, punto, teleop (publican)
TfLigero (RefCounted)     lookup_transform, can_transform, frame_exists, get_frame_names, get_frame_parent
PrimitivasViz / PaletaViz / FabricaMarcadores / RegistroDisplays / IntrospeccionRos / TiempoRos  (estáticos)
ExploradorTopics (RefCounted, solo PC)
```

`godot/plantillas/ros/sensor_base.gd` **no se fusiona** (⚖ sentencia D1, contra la propuesta del revisor): es la base
de los sensores simulados que *publican* (`sensor_base.gd:18,40-41`); los displays solo comparten sus nombres de
`@export` (`sensor_base.gd:6-14`).

### 2.3 Contrato del display

**`@export` comunes** (nombres de `sensor_base.gd:6-14` donde existen; ⚖ se descartan `hz_max`, `hz_max_vita`,
`hz_dibujo`, `decay_s`, `decaimiento_s`, `best_effort` y `profundidad` de las fichas):

| `@export` | Tipo | Defecto | Significado |
|---|---|---|---|
| `habilitado` | bool | true | apagado = no suscribe ni dibuja |
| `topic` / `tipo` | String | "" | topic y tipo estándar (`pkg/msg/T`), los del PC |
| `topic_vita` / `tipo_vita` | String | "" | **sufijo** bajo `visor.prefijo_compacto` y su tipo; "" = la Vita usa `topic`/`tipo` en directo |
| `frame_id` | String | "" | "" = el `header.frame_id` del mensaje; en el camino compacto, "" = marco fijo |
| `hz` / `hz_vita` | float | según display / 0 | tope de entrega al display; `hz_vita` = 0 ⇒ el mismo |
| `fiabilidad` | enum AUTO / BEST_EFFORT / FIABLE | AUTO | AUTO = best effort salvo `latched` (§6) |
| `latched` | bool | false | fiable + TRANSIENT_LOCAL, profundidad 1 |
| `caducidad_s` | float | 0 | sin mensajes en este tiempo ⇒ `_caducar()` (0 = nunca) |
| `persistencia_s` | float | 0 | *decay* de RViz, para los displays que acumulan |
| `solo_pc` | bool | false | en la Vita el nodo se desactiva solo (como `sensor_base.gd:28-30`) |

**Ganchos:**

| Gancho | Lo llama | Qué hace | Lo implementa |
|---|---|---|---|
| `conectar(visor)` | `VisorRos._ready()` | reserva cupo, abre el canal, crea pools (`super.conectar(v)` primero) | base; las subclases lo amplían |
| `desconectar()` | quien quite el display | cierra el canal y libera el cupo | base |
| `_procesar(msg)` | base, camino estándar | lee el mensaje ROS → dato intermedio (o `null` = ignorar) | cada display |
| `_procesar_compacto(msg)` | base, camino del relay | lee el formato `/vita/*` → **el mismo** dato intermedio | displays con relay |
| `_pintar(datos)` | base | dibuja con `PrimitivasViz`, `PaletaViz` y lienzo en lote | cada display |
| `_caducar()` | base, `caducidad_s` | oculta (3D/2D) o atenúa (HUD) | base; opcional |
| `_coste()` | base al conectar; `pruebas/presupuesto.gd` | `{instancias, triangulos, quads}` máximos | cada display |
| `nombre_display()`, `tipos_ros()` | `RegistroDisplays`, `ExploradorTopics` | identidad (estáticos) | cada display |

### 2.4 Ciclo de vida

```
VisorRos._ready()
  contexto.iniciar(nombre_nodo, "", transporte)            # rclgd.init si hace falta (contexto_ros.gd:10-22)
  tf = nodo.create_tf_listener(10.0) si existe, si no TfLigero.new()
  para cada d del grupo "display_ros" bajo VisorRos:  d.conectar(self)
      ├─ solo_pc y Vita → desactivado
      ├─ cupo = visor.reservar(capa, _coste().instancias | quads)  → 0 ⇒ «sin cupo», no dibuja (lo dice una vez)
      └─ estado = canal.abrir_para(d, visor)
             ├─ compacto = visor.usa_compactos() and topic_vita != ""
             ├─ topic = prefijo + "/" + topic_vita | topic ; tipo = tipo_vita | tipo
             ├─ RosMsg.from_type(tipo) == null → «sin esquema» (no suscribe; ros_runtime.cpp:122-123)
             ├─ hz = hz_vita en la Vita si > 0
             └─ create_subscription(topic, tipo, _al_recibir, contexto.qos(...))

cada fotograma (_process del display):
  canal.bombear()  → si hay pendiente y pasó 1/hz:  mensaje.emit(último)        («el último gana»)
      └─ display._al_mensaje(msg)
            datos = _procesar_compacto(msg) if canal.compacto else _procesar(msg)
            [3D/2D] frame = frame_id | msg.header.frame_id | marco fijo (compacto)
                    marco = visor.transformada(frame) → null ⇒ «sin TF», oculto
                    3D: transform = marco · 2D planta: transform = visor.planta_desde(marco)
            _pintar(datos)
  canal.caducado(caducidad_s) → _caducar() (una vez)

desconectar(): canal.cerrar(); visor.liberar(capa, cupo)
```

Callbacks: en rclgd llegan por `call_deferred` (`ros_subscriber.cpp:20-37`); en la Vita desde `process_frame`
(`ros_runtime.cpp:490-511`). Los dos en el hilo principal, así que el canal no necesita cerrojos [V].

### 2.5 Decodificar frente a pintar: el mismo script en PC y Vita

1. **Fuente** (sentencia, «Reparto PC / Vita»): `visor.usa_compactos()` es verdadero si `OS.has_feature("vita")`, si
   `contexto.transporte == "xrce"` (`contexto_ros.gd:7,11`), si se pasa `compacto=1` o si `forzar_compacto`. Entonces
   el canal suscribe `prefijo + topic_vita` con `tipo_vita` y llama a `_procesar_compacto`; si no, `topic`/`tipo` y
   `_procesar`. Un display sin `topic_vita` usa el tipo estándar **también en la Vita** (directo, si cabe en 488 B).
2. **Dato intermedio único**: los dos decodificadores entregan lo mismo a `_pintar` (por ejemplo `PackedVector2Array`
   de puntos del scan en metros del marco del sensor). Así el camino compacto se prueba en el **host** contra el relay
   real con `compacto=1` (V3).
3. **Dibujo**: `_pintar` usa solo `PrimitivasViz`, `PaletaViz` y llamadas de lienzo en lote. Sin MultiMesh, líneas 3D,
   color por vértice, `Label3D` ni `Label` por elemento (H1–H3, ADR 0011 §4).
4. **Lo que solo puede el PC** (nube en GPU, imágenes con *shader*, árbol del inspector, marcadores interactivos,
   explorador) va en scripts aparte con `solo_pc = true`.

Ejemplo mínimo (el scan, detalle en §4.5):

```gdscript
func _procesar(msg):            # sensor_msgs/msg/LaserScan → PackedVector2Array (m, marco del sensor)
	return _puntos(msg.ranges, msg.angle_min, msg.angle_increment, msg.range_min, msg.range_max)
func _procesar_compacto(msg):   # <p>/scan_compacto (Int16MultiArray, cm) → lo MISMO
	return VitaRelay.scan_puntos(msg)          # godot/plantillas/vita_relay.gd:95-109
func _pintar(puntos) -> void:   # un lote (H17)
	_v = puntos; queue_redraw()
```

### 2.6 Registro tipo → display

`registro_displays.gd` (estático) traduce (tipo, patrón de topic) → script del display, capa y coste. Lo usan el
`ExploradorTopics` del PC («añadir por topic», sin guardar) y las pruebas de presupuesto; **no** crea los displays de
la escena (doc 35). Orden = prioridad: las reglas con topic van antes que las genéricas (ficha nucleo#1, VERIFICADO
como mecanismo; ⚖ con el contrato de gdviz como modelo). Código en §2.9.8; la tabla completa de reglas sale de la
tabla maestra §4.0.

### 2.7 Escenas editables (regla doc 35)

Los displays son **nodos del `.tscn`** con sus `@export` (`docs/35-regla-escenas-editables.md:33-35`): posición,
tamaño y pestaña del HUD se editan en el editor. El código solo crea lo que depende de los datos (pools de
instancias, puntos, texturas) **sin `owner`**, y nunca guarda mallas de PC en la escena (`docs/35:45-47`). Los ajustes
por robot (`prefijo_compacto` y, si hace falta, una sección `visor` que cambie `topic`/`hz` por nombre de nodo) van en
`robot.json`. Escena de ejemplo `godot/visor-ros/main.tscn`:

```
Main (Node3D)
├─ Mundo                         instancia de plantillas/mundo/mundo.tscn (compartido, doc 35)
├─ Camara (Camera3D)             orbital
├─ VisorRos (visor_ros.gd)       marco_fijo="map", perfil=HMI, camara=../Camara, texto=Hud/Texto
│  ├─ Robot   (displays/3d/robot_joints.gd)   topic="/joint_states", topic_vita="joints"
│  ├─ Tf      (displays/3d/tf.gd)             (consulta visor.tf; sin suscripción propia)
│  ├─ Marcas  (displays/3d/marcadores.gd)     topic="/visualization_marker_array", topic_vita="marcadores"
│  ├─ Planta (Node2D, en un CanvasLayer)      transform = desplazamiento de la vista
│  │  ├─ Mapa  (displays/2d/mapa.gd)          topic="/map", topic_vita="mapa_tesela", latched
│  │  ├─ Scan  (displays/2d/scan.gd)          topic="/scan", topic_vita="scan_compacto", frame_id="base_scan"
│  │  ├─ Odom  (displays/2d/odometria.gd)     topic="/odom", topic_vita="pose2d"
│  │  └─ Plan  (displays/2d/path.gd)          topic="/plan", topic_vita="path_compacto"
│  ├─ Hud (CanvasLayer)
│  │  ├─ Texto  (texto_superpuesto.gd)
│  │  └─ Gestor (gestor_hud.gd)
│  │     ├─ Barra (Control)                   bateria.gd, barra_estado.gd, estado_meta.gd
│  │     └─ Pestanas
│  │        ├─ Estado      medidor.gd ×n, lifecycle.gd
│  │        ├─ Diagnostico diagnostico.gd     topic="/diagnostics_agg", topic_vita="diagnostics"
│  │        ├─ Consola     consola.gd         topic="/rosout", topic_vita="rosout"
│  │        ├─ Graficas    trazador.gd
│  │        └─ Inspector   inspector_texto.gd
│  └─ Herramientas
│     ├─ Teleop (herramientas/teleop.gd) · Meta (herramientas/meta.gd) · PoseInicial · Punto
```

### 2.8 Ubicación de archivos (⚖ D15)

```
godot/plantillas/visor/                      (= res://comun/visor/; absorbe T-W8-4 «godot/comun/viz/», docs/31:358)
  visor_ros.gd  registro_displays.gd  canal_display.gd
  display_ros_3d.gd  display_ros_2d.gd  display_ros_hud.gd
  gestor_hud.gd  texto_superpuesto.gd  herramienta_visor.gd
  tf_ligero.gd  primitivas_viz.gd  paleta_viz.gd  fabrica_marcadores.gd
  introspeccion_ros.gd  tiempo_ros.gd  explorador_topics.gd (solo PC)
  displays/3d/   displays/2d/   displays/hud/   herramientas/
  README.md
godot/plantillas/ros/vc1.gd                  (+ formatos VC/1 rev. 2, §5)
godot/plantillas/pruebas/visor.gd            (prueba de host del visor, V1)
godot/plantillas/pruebas/presupuesto.gd      (+ cupos por display)
godot/visor-ros/                             proyecto de ejemplo y de pruebas (comun -> ../plantillas)
  main.tscn  project.godot  robot.json  ros/schema.rsch
docker/scripts/vita_relay_formatos.py        funciones puras (nuevo) · vita_relay.py (nodo) · test_vita_relay.py
```

Sin `class_name` (convención de `plantillas/`: `preload`); sin addon en `addons/`; `godot/comun/` no se resucita (se
fusionó en `plantillas/` el 2026-11-12, `godot/plantillas/vita_relay.gd:2`).

### 2.9 Código del núcleo (esqueletos para V1, V2, V4 y V7)

Convenciones de todo el código de este documento: `preload` por ruta `res://comun/…`; `tf`, `visor` y los mensajes
sin anotar o anotados como `RosMsg`; tipos explícitos donde la expresión mezcla `Variant` (§8, T8); QoS solo con
`contexto.qos(...)`; ejes con `rclgd.ros_to_godot_*`.

#### 2.9.1 `visor_ros.gd`

```gdscript
extends Node
## VisorRos (ADR 0013 §1): contexto único de los displays (≈ rviz_common::DisplayContext).
const Contexto = preload("res://comun/ros/contexto_ros.gd")
const TfLigero = preload("res://comun/visor/tf_ligero.gd")
enum Perfil { HMI, VIZ }
## Cupos (ADR 0013 §4; ADR 0011 §6; docs/31:255). Solo se aplican en la Vita.
const CUPOS := {
	Perfil.HMI: {"robot": 40, "mundo": 12, "tf": 8, "marcadores": 12, "poses": 4, "lento": 0, "reserva": 4,
		"hud": 400, "sensores_2d": 800, "resto_2d": 300},
	Perfil.VIZ: {"robot": 40, "mundo": 12, "tf": 32, "marcadores": 32, "poses": 16, "lento": 4, "reserva": 14,
		"hud": 400, "sensores_2d": 800, "resto_2d": 300},
}
@export var nombre_nodo := "visor"
@export var transporte := ""                 # "" = el de la plataforma
@export var marco_fijo := "map"
@export var prefijo_compacto := "/vita"      # /vita o /vita/<robot> (vita_relay.py:21); robot.json lo cambia
@export var perfil: Perfil = Perfil.HMI
@export var px_por_m := 40.0                 # escala de la planta 2D
@export var forzar_compacto := false         # probar en el PC el camino de la Vita
@export var camara: Camera3D
@export var texto: Control                   # TextoSuperpuesto
var contexto = Contexto.new()
var tf = null                                # RosTfListener (PC) o TfLigero: SIN anotar (no existe en la Vita)
var en_vita := OS.has_feature("vita")
var _usados := {}
var _avisados := {}

func _ready() -> void:
	if contexto.iniciar(nombre_nodo, "", transporte) != OK:
		push_error("VisorRos: no arranca ROS")
		return
	if contexto.nodo.has_method("create_tf_listener"):
		tf = contexto.nodo.call("create_tf_listener", 10.0)
	else:
		tf = TfLigero.new()                      # fuentes locales: §2.9.6
	for d in get_tree().get_nodes_in_group("display_ros"):   # _ready va de hojas a raíz: los hijos ya están
		if is_ancestor_of(d):
			d.conectar(self)

func usa_compactos() -> bool:
	return forzar_compacto or en_vita or contexto.transporte == "xrce" \
			or OS.get_cmdline_user_args().has("compacto=1")

## Reserva n unidades de la capa (instancias 3D o quads 2D); devuelve lo concedido. En el PC, todo.
func reservar(capa: String, n: int, quien: String) -> int:
	if not en_vita or n <= 0:
		return n
	var tope: int = CUPOS[perfil].get(capa, 0)
	var dado := clampi(tope - int(_usados.get(capa, 0)), 0, n)
	_usados[capa] = int(_usados.get(capa, 0)) + dado
	if dado < n and not _avisados.has(quien):
		_avisados[quien] = true
		push_warning("VisorRos: %s pide %d en «%s» y recibe %d" % [quien, n, capa, dado])
	return dado

func liberar(capa: String, n: int) -> void:
	_usados[capa] = maxi(0, int(_usados.get(capa, 0)) - n)

## Pose de `frame` en el marco fijo (ejes Godot); null si TF no la conoce.
func transformada(frame: String):
	if frame == "" or frame == marco_fijo or tf == null:
		return Transform3D.IDENTITY              # D3: sin TF se supone que el frame ya es el fijo
	if not tf.can_transform(marco_fijo, frame):
		return null
	return tf.lookup_transform(marco_fijo, frame)

## Transform3D (ejes Godot) → Transform2D de la planta: x = ROS x, y = −ROS y (norte arriba), en px.
func planta_desde(t: Transform3D) -> Transform2D:
	var adelante: Vector3 = t.basis * Vector3.FORWARD          # +X de ROS = −Z de Godot
	var yaw := atan2(-adelante.x, -adelante.z)                  # yaw ROS
	return Transform2D(-yaw, Vector2(-t.origin.z, t.origin.x) * px_por_m)

func _exit_tree() -> void:
	tf = null
	contexto.cerrar()
```

`contexto.cerrar()` existe en `contexto_ros.gd` [I: el extracto leído llega a la línea 45; comprobar en V1].

#### 2.9.2 `canal_display.gd` (ficha nucleo#4, VERIFICADO, + QoS y Hz del contrato)

```gdscript
extends RefCounted
## CanalDisplay: suscripción + QoS + «el último gana» + Hz medido + caducidad (≈ RosTopicDisplay).
signal mensaje(msg)
enum { AUTO, BEST_EFFORT, FIABLE }
var hz := 0.0                    # tope de entrega (0 = sin tope)
var coalescer := true            # false = entregar todos (trazador)
var compacto := false
var recibidos := 0
var mostrados := 0
var hz_medido := 0.0
var _sub                         # RosSubscriber: guardarlo mantiene viva la suscripción
var _pendientes: Array = []
var _t_ultimo := -1000000
var _t_ventana := 0
var _n_ventana := 0
var _avisado := false

## Lee los @export comunes del display y abre la suscripción adecuada. Devuelve el estado.
func abrir_para(d, v) -> String:
	compacto = v.usa_compactos() and d.topic_vita != ""
	var t: String = (v.prefijo_compacto + "/" + d.topic_vita.trim_prefix("/")) if compacto else d.topic
	var ti: String = d.tipo_vita if compacto else d.tipo
	if t == "" or ti == "":
		return "sin topic"
	if RosMsg.from_type(ti) == null:             # sin .rsch (Vita) o sin typesupport (PC): no suscribir
		return "sin esquema: " + ti
	hz = d.hz_vita if (v.en_vita and d.hz_vita > 0.0) else d.hz
	var fiable: bool = d.fiabilidad == FIABLE or (d.fiabilidad == AUTO and d.latched)
	var prof: int = d.profundidad if d.profundidad > 0 else \
			(1 if (not fiable or d.latched) else (5 if v.en_vita else 10))    # eventos: 10 PC / 5 Vita (§6)
	var qos = v.contexto.qos(not fiable, prof, d.latched)
	return "ok" if abrir(v.contexto.nodo, t, ti, qos) else "error al suscribir"

func abrir(nodo, topic: String, tipo: String, qos) -> bool:
	_sub = nodo.create_subscription(topic, tipo, _al_recibir, qos)
	return _sub != null

func cerrar() -> void:
	_sub = null
	_pendientes.clear()

func _al_recibir(msg) -> void:
	recibidos += 1
	_n_ventana += 1
	if coalescer:
		_pendientes.clear()
	_pendientes.append(msg)

func bombear() -> void:
	var ahora := Time.get_ticks_msec()
	if ahora - _t_ventana >= 1000:
		hz_medido = _n_ventana * 1000.0 / maxi(ahora - _t_ventana, 1)
		_n_ventana = 0
		_t_ventana = ahora
		if hz > 0.0 and hz_medido > 2.0 * hz and not _avisado:   # D8: llega mucho más de lo que se dibuja
			_avisado = true
			push_warning("CanalDisplay: %.0f Hz recibidos para %.0f Hz de dibujo; fijar el ritmo en origen" % [hz_medido, hz])
	if _pendientes.is_empty() or (hz > 0.0 and ahora - _t_ultimo < 1000.0 / hz):
		return
	_t_ultimo = ahora
	for m in _pendientes:
		mostrados += 1
		mensaje.emit(m)
	_pendientes.clear()

func caducado(segundos: float) -> bool:
	return segundos > 0.0 and mostrados > 0 and Time.get_ticks_msec() - _t_ultimo > segundos * 1000.0
```

#### 2.9.3 `display_ros_3d.gd`

```gdscript
extends Node3D
## DisplayRos3D (ADR 0013 §1): base de display en la vista orbital. Resuelve marco → transform → _pintar.
const Canal = preload("res://comun/visor/canal_display.gd")
@export var habilitado := true
@export var topic := ""
@export var tipo := ""
@export var topic_vita := ""
@export var tipo_vita := ""
@export var frame_id := ""
@export var hz := 15.0
@export var hz_vita := 0.0
@export_enum("AUTO", "BEST_EFFORT", "FIABLE") var fiabilidad := 0
@export var latched := false
@export var caducidad_s := 0.0
@export var persistencia_s := 0.0
@export var solo_pc := false
var profundidad := 0                 # 0 = automática (§6); las subclases la fijan en _init si hace falta
var capa := "reserva"                # capa de ADR 0013 §4: "robot", "tf", "marcadores", "poses", "lento"…
var cupo := 0                        # instancias concedidas por el visor
var visor
var canal = Canal.new()
var estado := "sin conectar"
var marco := Transform3D.IDENTITY

static func nombre_display() -> String: return "DisplayRos3D"
static func tipos_ros() -> PackedStringArray: return PackedStringArray()

func _enter_tree() -> void:
	add_to_group("display_ros")

func conectar(v) -> void:
	visor = v
	if not habilitado or (solo_pc and v.en_vita):
		visible = false
		estado = "desactivado"
		set_process(false)
		return
	var pide: int = _coste().get("instancias", 0)
	cupo = v.reservar(capa, pide, name)
	if pide > 0 and cupo == 0:
		visible = false
		estado = "sin cupo"
		return
	canal.mensaje.connect(_al_mensaje)
	estado = canal.abrir_para(self, v)

func desconectar() -> void:
	canal.cerrar()
	if visor:
		visor.liberar(capa, cupo)
	cupo = 0
	estado = "desconectado"

func _process(_dt: float) -> void:
	canal.bombear()
	if visible and canal.caducado(caducidad_s):
		_caducar()

func _al_mensaje(msg) -> void:
	var datos = _procesar_compacto(msg) if canal.compacto else _procesar(msg)
	if datos == null:
		return
	var f: String = frame_id
	if f == "" and not canal.compacto and "header" in msg:
		f = String(msg.header.frame_id).trim_prefix("/")
	var t = visor.transformada(f)
	if t == null:
		estado = "sin TF %s→%s" % [f, visor.marco_fijo]
		visible = false
		return
	marco = t
	transform = t
	visible = true
	estado = "ok"
	_pintar(datos)

func _procesar(_msg): return null
func _procesar_compacto(msg): return _procesar(msg)
func _pintar(_datos) -> void: pass
func _caducar() -> void: visible = false
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 0}
```

#### 2.9.4 `display_ros_2d.gd`

Igual que la 3D salvo `extends Node2D`, la capa por defecto `"sensores_2d"`, que el cupo se pide en *quads* y que el
marco se aplica como `transform = visor.planta_desde(t)`. Los displays **superpuestos** (dibujan en coordenadas de
pantalla con `visor.camara`) ponen `en_pantalla = true` y usan `marco` (Transform3D) en su `_draw()`.

```gdscript
extends Node2D
## DisplayRos2D (ADR 0013 §1): base en la planta 2D (norte arriba) y en la superposición al 3D.
const Canal = preload("res://comun/visor/canal_display.gd")
# … mismos @export que display_ros_3d.gd …
var capa := "sensores_2d"            # o "resto_2d" (marcadores 2D, detecciones)
var en_pantalla := false             # true = superpuesto con la cámara: no se toca el transform del nodo
var marco := Transform3D.IDENTITY
# … profundidad, cupo, visor, canal, estado, _enter_tree, desconectar, _process: como en 3D …

func conectar(v) -> void:
	visor = v
	if not habilitado or (solo_pc and v.en_vita):
		visible = false
		estado = "desactivado"
		set_process(false)
		return
	var pide: int = _coste().get("quads", 0)
	cupo = v.reservar(capa, pide, name)
	if pide > 0 and cupo == 0:
		visible = false
		estado = "sin cupo"
		return
	canal.mensaje.connect(_al_mensaje)
	estado = canal.abrir_para(self, v)

func _al_mensaje(msg) -> void:
	var datos = _procesar_compacto(msg) if canal.compacto else _procesar(msg)
	if datos == null:
		return
	var f: String = frame_id
	if f == "" and not canal.compacto and "header" in msg:
		f = String(msg.header.frame_id).trim_prefix("/")
	var t = visor.transformada(f)
	if t == null:
		estado = "sin TF %s→%s" % [f, visor.marco_fijo]
		visible = false
		return
	marco = t
	if not en_pantalla:
		transform = visor.planta_desde(t)
	visible = true
	estado = "ok"
	_pintar(datos)

## Punto ROS (m, marco del display) → px locales de la planta.
func px(p: Vector2) -> Vector2:
	return Vector2(p.x, -p.y) * visor.px_por_m
```

#### 2.9.5 `display_ros_hud.gd` (sustituye a `widget_hud.gd`; ⚖ D1 y DESAFÍO nucleo#3)

Con `extends Control` no hay `transform` 3D: la versión «igual salvo `extends`» de nucleo#3 no compila
(`W13-revision.md:64-65`) [V]. La base HUD lleva su propio `_al_mensaje` **sin TF**, redibuja solo si llegó algo (a
≤ `hz`) y atenúa lo caducado (gris STALE). Recoge la base `widget_hud.gd` de hmi#0 (ALTERNATIVA → fusionada aquí).

```gdscript
extends Control
## DisplayRosHud (ADR 0013 §1): base de widget HUD. Sin TF; _draw() propio; redibuja solo si llegó algo.
const Canal = preload("res://comun/visor/canal_display.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
@export var habilitado := true
@export var topic := ""
@export var tipo := ""
@export var topic_vita := ""
@export var tipo_vita := ""
@export var frame_id := ""                 # sin uso en HUD (se conserva por el contrato)
@export var hz := 10.0                     # Label/HUD ≤ 10 Hz (docs/31:139)
@export var hz_vita := 4.0                 # perfil ligero: HUD a 4 Hz (doc 34)
@export_enum("AUTO", "BEST_EFFORT", "FIABLE") var fiabilidad := 0
@export var latched := false
@export var caducidad_s := 2.0
@export var persistencia_s := 0.0
@export var solo_pc := false
var profundidad := 0
var visor
var canal = Canal.new()
var estado := "sin conectar"
var datos = null                           # último dato intermedio
var gris := false

func _enter_tree() -> void:
	add_to_group("display_ros")

func conectar(v) -> void:
	visor = v
	if not habilitado or (solo_pc and v.en_vita):
		visible = false
		estado = "desactivado"
		set_process(false)
		return
	canal.mensaje.connect(_al_mensaje)
	estado = canal.abrir_para(self, v)      # el cupo de quads lo comprueba GestorHud por pestaña

func desconectar() -> void:
	canal.cerrar()
	estado = "desconectado"

func _process(_dt: float) -> void:
	canal.bombear()
	var c := canal.caducado(caducidad_s)
	if c != gris:
		gris = c
		_caducar()

func _al_mensaje(msg) -> void:
	var d = _procesar_compacto(msg) if canal.compacto else _procesar(msg)
	if d == null:
		return
	datos = d
	estado = "ok"
	_pintar(d)

func _procesar(_msg): return null
func _procesar_compacto(msg): return _procesar(msg)
func _pintar(_d) -> void: queue_redraw()   # el dibujo va en _draw() de cada widget
func _caducar() -> void: queue_redraw()    # el widget pinta en Paleta.STALE si `gris`
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 0}
func color_estado(c: Color) -> Color: return Paleta.STALE if gris else c
```

#### 2.9.6 `tf_ligero.gd` (⚖ D3; ALTERNATIVA geom#16 resuelta)

Subconjunto de `RosTfListener` que usan los displays, con semántica de `modules/tf-tree` (último valor, sin
historial, ≤ 32 marcos; `modules/tf-tree/include/tf_tree.h:12,39`). Devuelve `Transform3D` **en ejes de Godot** o
`null`. Fuentes, por defecto **0 B extra**: (1) los links del robot horneado (nodos de la escena movidos por
`/vita/joints`); (2) `map|odom → base` desde `/vita/pose2d`. Opcional: módulo `tf` del relay (≤ 8 marcos dinámicos a
10 Hz, `tf_marcos` y `tf_estatico` *latched*). Prueba común contra los casos de
`modules/tf-tree/tests/parity_test.c` (V9).

```gdscript
extends RefCounted
## TfLigero: subconjunto de RosTfListener para la Vita (último valor por marco; `time` ignorado, como tf-tree).
const MAX_MARCOS := 32
var _padre := {}                 # hijo -> padre
var _local := {}                 # hijo -> Transform3D (Godot) del hijo en el padre   (fuente «por valor»)
var _nodo := {}                  # hijo -> [Node3D raíz, Node3D link]                  (fuente «por nodo»)
var _orden_relay := PackedStringArray()     # índice -> nombre, de <p>/tf_marcos
var _error := ""

## Fuente por valor (pose2d, relay, pruebas). t_local en ejes Godot.
func poner(padre: String, hijo: String, t_local: Transform3D) -> void:
	if not _padre.has(hijo) and _padre.size() >= MAX_MARCOS:
		_error = "TfLigero: más de %d marcos" % MAX_MARCOS
		return
	_padre[hijo] = padre
	_local[hijo] = t_local

## Fuente por nodo: los links del robot horneado (ADR 0009) bajo `raiz` (que está en el marco `base`).
func registrar_robot(raiz: Node3D, base: String) -> void:
	for n in raiz.find_children("*", "Node3D", true, false):
		if _padre.size() >= MAX_MARCOS:
			break
		_padre[n.name] = base
		_nodo[n.name] = [raiz, n]

## /vita/pose2d = [x, y, yaw, vx, vy, wz] (vita_relay.gd:87-92) → mundo -> base.
func desde_pose2d(d: PackedFloat32Array, mundo: String, base: String) -> void:
	if d.size() < 3:
		return
	var q := rclgd.ros_to_godot_quat(Quaternion(Vector3(0, 0, 1), d[2]))
	poner(mundo, base, Transform3D(Basis(q), rclgd.ros_to_godot_vector(Vector3(d[0], d[1], 0.0))))

## Relay opcional <p>/tf (VC/1 rev. 2): [seq, trozo, n_trozos, n, (idx, x, y, z, qx, qy, qz, qw)·n] en ROS.
func on_tf_compacto(m) -> void:
	var d: PackedFloat32Array = m.data
	if d.size() < 4:
		return
	for i in int(d[3]):
		var b := 4 + 8 * i
		if b + 8 > d.size():
			break
		var k := int(d[b])
		if k < 0 or k >= _orden_relay.size():
			continue
		var par := _orden_relay[k].split(">")            # «padre>hijo» (tf_marcos)
		var q := Quaternion(d[b + 4], d[b + 5], d[b + 6], d[b + 7])
		q = q.normalized() if q.length_squared() > 1e-6 else Quaternion.IDENTITY
		poner(par[0], par[1], Transform3D(Basis(rclgd.ros_to_godot_quat(q)),
				rclgd.ros_to_godot_vector(Vector3(d[b + 1], d[b + 2], d[b + 3]))))

func on_tf_marcos(m) -> void:                         # String «padre>hijo,padre>hijo,…» fiable + TL
	_orden_relay = String(m.data).split(",", false)

func _local_de(f: String) -> Transform3D:
	if _nodo.has(f):
		var r: Node3D = _nodo[f][0]
		var n: Node3D = _nodo[f][1]
		return r.global_transform.affine_inverse() * n.global_transform
	return _local[f]

func _a_raiz(f: String) -> Array:                     # [Transform3D de f en la raíz, nombre de la raíz]
	var t := Transform3D.IDENTITY
	for _i in MAX_MARCOS:                             # tope de tf-tree; corta ciclos
		if not _padre.has(f):
			break
		t = _local_de(f) * t
		f = _padre[f]
	return [t, f]

func frame_exists(f: String) -> bool:
	return _padre.has(f) or _padre.values().has(f)

func can_transform(destino: String, origen: String, _time = null) -> bool:
	return frame_exists(destino) and frame_exists(origen) and _a_raiz(destino)[1] == _a_raiz(origen)[1]

func lookup_transform(destino: String, origen: String, _time = null, _timeout := 0.0):
	if not can_transform(destino, origen):
		_error = "%s y %s no están conectados" % [destino, origen]
		return null
	_error = ""
	var a := _a_raiz(origen)
	var b := _a_raiz(destino)
	return (b[0] as Transform3D).affine_inverse() * (a[0] as Transform3D)

func get_frame_names() -> PackedStringArray: return PackedStringArray(_padre.keys())
func get_frame_parent(f: String) -> String: return _padre.get(f, "")
func get_last_error() -> String: return _error
```

La versión de geom#16 se suscribía a `/tf` y `/tf_static` directamente; ⚖ en la Vita no se suscribe a `/tf` crudo
(TFMessage de un robot real no cabe: G1 ≈ 40 marcos = 4 796 B, `docs/27:73-75`). `poner()` sirve para alimentar
`TfLigero` desde `/tf` en las pruebas de host. En el PC, `VisorRos` usa el `RosTfListener` de rclgd.

#### 2.9.7 `gestor_hud.gd` y `texto_superpuesto.gd` (⚖ D6 y D11)

```gdscript
extends Control
## GestorHud: barra fija + UNA pestaña visible + cupo de quads por zona (ADR 0013 §4; docs/31:255).
const BARRA_MAX := 120
const PESTANA_MAX := 240
@export var barra: Control                 # hijos: displays HUD de la barra (24 px arriba)
@export var pestanas: Control              # cada hijo es una pestaña (Control) con sus displays
var activa := 0

func _ready() -> void:
	mostrar(0)

func mostrar(i: int) -> void:
	activa = posmod(i, pestanas.get_child_count())
	for k in pestanas.get_child_count():
		var p := pestanas.get_child(k) as Control
		p.visible = k == activa
		p.process_mode = PROCESS_MODE_INHERIT if k == activa else PROCESS_MODE_DISABLED  # oculta = sin coste
	if OS.has_feature("vita"):
		var q := _quads(pestanas.get_child(activa))
		if q > PESTANA_MAX:
			push_warning("GestorHud: la pestaña %s pide %d quads (> %d)" % [pestanas.get_child(activa).name, q, PESTANA_MAX])

func _quads(raiz: Node) -> int:
	var total := 0
	for n in raiz.find_children("*", "Control", true, false):
		if n.has_method("_coste"):
			total += int(n.call("_coste").get("quads", 0))
	return total

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_page_down"):          # L + cruceta en el mapa de entradas de la Vita [I]
		mostrar(activa + 1)
	elif e.is_action_pressed("ui_page_up"):
		mostrar(activa - 1)
```

`process_mode` desactivado en la pestaña oculta detiene `_process` y con él `canal.bombear()`: la suscripción
sigue viva pero la pestaña oculta no procesa ni dibuja [I: el callback de la Vita llega desde `process_frame`
(`ros_runtime.cpp:490-511`) y apila en `_pendientes` como mucho un mensaje por el «último gana»].

```gdscript
extends Control
## TextoSuperpuesto (D11): todo el texto anclado al 3D en UN _draw(). Tope de 40 glifos en la Vita.
const MAX_GLIFOS_VITA := 40
@export var camara: Camera3D
@export var tam := 12
@export var hz := 20.0                     # reproyección ≤ 20 Hz (docs/31 §3)
var _textos := {}                          # clave -> [Vector3 mundo (Godot), String, Color]
var _t := 0.0

func poner(clave: String, pos: Vector3, texto: String, color := Color.WHITE) -> void:
	_textos[clave] = [pos, texto, color]

func quitar(clave: String) -> void:
	_textos.erase(clave)

func _process(dt: float) -> void:
	_t += dt
	if _t >= 1.0 / hz:
		_t = 0.0
		queue_redraw()

func _draw() -> void:
	if camara == null:
		return
	var fuente := get_theme_default_font()
	var glifos := 0
	var tope := MAX_GLIFOS_VITA if OS.has_feature("vita") else 100000
	for e in _textos.values():
		var p: Vector3 = e[0]
		if camara.is_position_behind(p):
			continue
		var s: String = e[1]
		if glifos + s.length() > tope:
			break
		glifos += s.length()
		draw_string(fuente, camara.unproject_position(p), s, HORIZONTAL_ALIGNMENT_LEFT, -1, tam, e[2])
```

Una fuente, **sin contorno** (el contorno multiplicó los lotes: 222 *draws* para 305 *quads*,
`docs/34-perfil-vita-ligero.md:52`) [V].

#### 2.9.8 `registro_displays.gd`, `introspeccion_ros.gd`, `tiempo_ros.gd`

```gdscript
extends RefCounted
## RegistroDisplays: (tipo, patrón de topic) → display, capa y coste (≈ <message_type> de RViz; contrato de gdviz).
const D := "res://comun/visor/displays/"
const REGLAS := [   # orden = prioridad: primero las que llevan topic
	{"tipo": "std_msgs/msg/Int16MultiArray", "topic": "*/scan_compacto", "script": D + "2d/scan.gd", "capa": "sensores_2d"},
	{"tipo": "std_msgs/msg/Int16MultiArray", "topic": "*/nube2d", "script": D + "2d/nube.gd", "capa": "sensores_2d"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/pose2d", "script": D + "2d/odometria.gd", "capa": "sensores_2d"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/path_compacto", "script": D + "2d/path.gd", "capa": "sensores_2d"},
	{"tipo": "std_msgs/msg/Float32MultiArray", "topic": "*/marcadores", "script": D + "3d/marcadores.gd", "capa": "marcadores"},
	{"tipo": "sensor_msgs/msg/LaserScan", "script": D + "2d/scan.gd", "capa": "sensores_2d"},
	{"tipo": "nav_msgs/msg/Odometry", "script": D + "2d/odometria.gd", "capa": "sensores_2d"},
	{"tipo": "geometry_msgs/msg/PoseStamped", "script": D + "3d/pose.gd", "capa": "poses"},
	# … una regla por fila de la tabla maestra §4.0 …
	{"tipo": "std_msgs/msg/*MultiArray", "script": D + "hud/multiarray.gd", "capa": "hud"},
	{"tipo": "*", "script": D + "hud/inspector_texto.gd", "capa": "hud"},   # comodín = ros2 topic echo
]

static func candidatos(topic: String, tipo: String, en_vita: bool) -> Array:
	var out := []
	for r in REGLAS:
		if en_vita and r.get("solo_pc", false):
			continue
		if tipo.match(r.tipo) and (not r.has("topic") or topic.match(r.topic)):
			out.append(r)
	return out

static func crear(topic: String, tipo: String, en_vita: bool) -> Node:   # solo ExploradorTopics (PC)
	var r: Dictionary = candidatos(topic, tipo, en_vita)[0]
	var d: Node = load(r.script).new()
	d.topic = topic
	d.tipo = tipo
	return d
```

`introspeccion_ros.gd` (nucleo#0, VERIFICADO) y `tiempo_ros.gd` (nucleo#15, VERIFICADO) se copian tal cual de las
fichas (código en §4.1).

#### 2.9.9 `herramienta_visor.gd` (base de las herramientas que publican; ⚖ D1 y C9)

```gdscript
extends Node
## HerramientaVisor: base de meta, pose inicial, punto y teleop. Publica FIABLE por defecto (§6).
@export var habilitado := true
@export var topic := ""
@export var tipo := ""
@export_enum("FIABLE", "BEST_EFFORT") var fiabilidad := 0
@export var confirmar_en_vita := true      # ✕ confirma metas y poses (consola de mano: evita roces)
@export var marco_fijo_nodo: Node3D        # nodo de la escena alineado con visor.marco_fijo
var visor
var pub
var activa := false

func _enter_tree() -> void:
	add_to_group("display_ros")            # VisorRos también conecta las herramientas

func conectar(v) -> void:
	visor = v
	if not habilitado:
		return
	var prof := 1 if v.en_vita else 5      # RViz: rclcpp::QoS(5) (goal_tool.cpp:67,78)
	pub = v.contexto.nodo.create_publisher(topic, tipo, v.contexto.qos(fiabilidad == 1, prof, false))

func desconectar() -> void:
	pub = null

func publicar(m) -> void:
	if pub != null:
		pub.publish(m)

## Punto de pantalla → punto del suelo del marco fijo en ejes ROS (Vector3) o null.
func suelo_ros(p: Vector2):
	var cam: Camera3D = visor.camara
	var g := marco_fijo_nodo.global_transform
	var hit = Plane(g.basis.y.normalized(), g.origin).intersects_ray(cam.project_ray_origin(p), cam.project_ray_normal(p))
	return null if hit == null else rclgd.godot_to_ros_vector(g.affine_inverse() * (hit as Vector3))
```

---

## 3. Primitivas comunes y paleta (PC y Vita sin shaders)

⚖ D2: **una** biblioteca. Se funden `primitivas.gd` (geom#0, DESAFÍO: definía solo `material`, `flecha`,
`flecha_hacia`, `pose_godot`, `en_marco_fijo` y las fichas llamaban a `esfera`, `ejes`, `disco`, `anillo`, `cono`
sin definir), `fabrica.gd` + `paletas.gd` (mapas: usaban `FLECHA`, `CILINDRO_Z`, `CONO_Z`, `CUBO_CARAS`, `color()`,
`Paleta.*`, `crear`, `aplicar`, `pose` sin definir) y `color_ros`/`indice_paleta` (nucleo#14, DESAFÍO)
(`W13-revision.md:66-69`). Resultado: `PrimitivasViz` + `PaletaViz`; `FabricaMarcadores` queda **solo** como
traductor `Marker`/`shape_msgs` → llamadas a `PrimitivasViz`.

### 3.1 Reglas

1. **Mallas unidad compartidas, movidas por `transform`**: una malla por (forma, índice de color), creada una vez y
   cacheada (tope **64 variantes**); cada visual es un `MeshInstance3D` que solo cambia `transform`. Nunca se
   reconstruye geometría por mensaje: cada cambio de malla tira su caché y gasta arena, ≈ 60 B por triángulo (H3, H9).
   Excepciones con tope de Hz: cinta de path (≤ 2 Hz, ADR 0011 §4), listas horneadas (≤ 1 Hz, ≤ 64 elementos).
2. **Solo `PRIMITIVE_TRIANGLES`** (H1); sin MultiMesh (H2: N objetos = N *draws*); sin color por vértice (H3); sin
   *culling* de caras (H15: las cintas se ven por los dos lados).
3. **Color por UV a la paleta**: todos los vértices de una forma llevan la UV del centro del texel de su color; la
   textura-paleta tiene un texel con alfa 0, lo que **excluye la malla de la pasada de luz por vértice** (H8) y evita
   el riesgo H7 (luz pintada sobre geometría vieja). Un material para todo (ADR 0011 §3,
   `docs/adr/0011-presupuesto-render-vita.md:36-37`). Varios colores en una malla (ejes RGB, listas) = UV distintas.
   La opción «sombreado» (material por color con `albedo.a = 0,99`, H8, o con luz) queda detrás de la misma función
   [I]. Riesgo: que el texel de alfa no saque la malla de la luz en la práctica → gate **E-W8-1** (`lit=` = 0).
4. **Ejes**: todo en **ejes de Godot**; conversión a la entrada con `rclgd.ros_to_godot_vector/quat` (misma función en
   rclgd, `ros2_vita` y `RosTfListener`, `API_PARITY.md:19`). Una flecha de ROS (+X) cae en −Z de Godot, que es lo
   que da `Basis.looking_at`. Matrices (covarianza, inercia): `C·B·Cᵀ` con `C = BASE_ROS_A_GODOT`
   (`godot/plantillas/ros/util_ros.gd:6`). Optimización permitida: construir polilíneas largas **en ejes ROS** bajo
   un nodo hijo con `basis = C` (como el `RosFrame` del URDF horneado, `godot/g1-unitree/robot/urdf_robot.gd:6`); la
   base `Basis(Vector3(0,0,-1), Vector3(-1,0,0), Vector3(0,1,0))` equivale a `ros_to_godot_vector` (comprobado con
   (1,2,3) → (−2,3,−1), borrador de sensores §3) [V].
5. **Escala de marcadores**: ROS `(sx, sy, sz)` → ejes locales Godot `(sy, sz, sx)` (`escala_ros`, mapas#13) [V].
6. **Grosor mínimo** de cajas finas sin MSAA: `1,5·d/522` m (9 mm a 3 m, `docs/31:95`); se ajusta escalando la
   instancia por tramos de distancia, sin tocar la malla [I].
7. **Texto**: `draw_string` en un `CanvasItem` (`TextoSuperpuesto` o el `_draw()` del widget) tras
   `Camera3D.is_position_behind`; nunca `Label3D` (ADR 0011 §4); `Label`/`RichTextLabel`/`Tree` solo en displays
   `solo_pc`.
8. **2D (planta y superposición)**: color por primitiva gratis y fusión en un *draw* (H16); **una llamada por
   display** (`canvas_item_add_triangle_array`, `draw_multiline_colors`, `draw_polyline` fina con ancho −1; H17).
   Coste de CPU ∝ *quads* **cada fotograma** (H16): se redibuja solo al llegar un mensaje, nunca por fotograma, salvo
   lo superpuesto (≤ 20 Hz).

### 3.2 Formas y triángulos [I, ⚖ D2]

| Forma (`PrimitivasViz`) | Construcción | Tri Vita | Uso |
|---|---|---:|---|
| `CUBO` | caja unidad | 12 | CUBE, cajas 3D, inercia |
| `ESFERA` | octaedro (PC: icosfera 80 tri o `SphereMesh`) | 8 | Point, SPHERE, CoM |
| `CILINDRO` | 8 lados, sin tapas, eje +Y Godot = +Z ROS | 32 | CYLINDER, cuerpo de flecha por puntos |
| `CONO` | vértice en el origen, base en z = −1, radio 0,5, 8 lados | 16 | Range, cabeza de flecha por puntos |
| `FLECHA` | asta (tubo 6 lados) + punta (cono 6 lados) sobre −Z, largo 1 | 24 | Pose, Odometry, Vector3, Twist/Accel/Wrench, Imu, TF |
| `EJES` | 3 cajas finas, UV a rojo/verde/azul en la misma malla | 36 | TF, Quaternion, Transform, Pose (forma ejes) |
| `DISCO` | abanico de 12 triángulos en el plano XY de ROS | 12 | covarianza 2D en 3D, huella |
| `ANILLO` | cinta de 28 segmentos sobre 315° (como `wrench_visual.cpp`, i = 4..32) | 56 | par (Wrench), velocidad angular |

Todas por debajo de lo previsto en `docs/31-render-visualizacion-vita.md:134`. Una flecha de ARROW de Marker usa la
misma `FLECHA` escalada (cuerpo 0,77/cabeza 0,23 en mapas#11 frente a 0,75/0,25 en geom#0: se adopta la de RViz,
`arrow_marker.cpp:160-180`, para casar con lo que se ve en RViz [I]).

### 3.3 `paleta_viz.gd`

```gdscript
extends RefCounted
## PaletaViz (ADR 0013 §2): textura-paleta 16×16 (256 colores), UN material, texel 255 con alfa 0 (H8).
## Índices 0–15 con nombre; 16–231 cubo RGB 6×6×6; 232–254 grises; 255 transparente [I: reparto propuesto aquí].
const OK := Color8(85, 178, 76)            # colores de estado de rqt_robot_monitor (util_robot_monitor.py:48-54)
const WARN := Color8(222, 213, 17)
const ERROR := Color8(178, 23, 46)
const STALE := Color8(40, 23, 176)
const NOMBRADOS := [Color.WHITE, Color.BLACK, Color(0.9, 0.1, 0.1), Color(0.1, 0.8, 0.2), Color(0.15, 0.35, 1.0),
	Color.YELLOW, Color.CYAN, Color.MAGENTA, Color.ORANGE, Color.GRAY, OK, WARN, ERROR, STALE,
	Color(1.0, 0.1, 0.0), Color(0.1, 1.0, 0.0)]            # 14 = flecha RViz, 15 = path RViz
const TRANSPARENTE := 255
static var _img: Image
static var _mat: StandardMaterial3D
static var _cache := {}                    # Color.to_rgba32() -> índice

static func _imagen() -> Image:
	if _img == null:
		_img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		for i in 256:
			_img.set_pixel(i % 16, i / 16, _calcular(i))      # 256 píxeles, una vez
	return _img

static func _calcular(i: int) -> Color:
	if i < 16: return NOMBRADOS[i]
	if i < 232:
		var k := i - 16
		return Color(float(k / 36) / 5.0, float((k / 6) % 6) / 5.0, float(k % 6) / 5.0)
	if i < 255: return Color.from_hsv(0.0, 0.0, float(i - 232) / 22.0)
	return Color(0, 0, 0, 0)                                    # texel de alfa 0: fuera de la pasada de luz (H8)

static func color(i: int, alfa := 1.0) -> Color:
	var c := _calcular(clampi(i, 0, 255))
	c.a = alfa
	return c

static func uv(i: int) -> Vector2:                                # centro del texel
	return Vector2((i % 16) + 0.5, (i / 16) + 0.5) / 16.0

static func indice(c: Color) -> int:                              # el más cercano en RGB (cacheado)
	var k := c.to_rgba32()
	if _cache.has(k):
		return _cache[k]
	var mejor := 0
	var dmin := INF
	for i in 255:
		var p := _calcular(i)
		var d := Vector3(p.r - c.r, p.g - c.g, p.b - c.b).length_squared()
		if d < dmin:
			dmin = d
			mejor = i
	_cache[k] = mejor
	return mejor

static func de_ros(c) -> Color:                                    # std_msgs/ColorRGBA (nucleo#14)
	return Color(c.r, c.g, c.b, c.a)

static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.albedo_texture = ImageTexture.create_from_image(_imagen())
		_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED   # en la Vita, sin efecto verificado [?]; H8 manda
		_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	return _mat
```

Paletas de raster (⚖ D2 funde aquí `paletas.gd` de mapas#1–#2; nombres añadidos por este documento): `rampa_mapa(esquema,
binaria, umbral) -> Image 256×1` con los ports literales de `makeMapPalette`, `makeCostmapPalette` y
`makeRawPalette` (`palette_builder.cpp:87-152`, código completo en mapas#1 y #2; se copia tal cual), y
`lut16_costmap() -> PackedColorArray` para la tesela de 4 bit de la Vita (§4.6). Los paquetes con degradados
(costmap, cámara) se exportan en RGBA8888 (H20).

### 3.4 `primitivas_viz.gd` (esqueleto)

```gdscript
extends RefCounted
## PrimitivasViz (ADR 0013 §2): mallas unidad (solo triángulos, UV a PaletaViz), poses y conversiones.
const Paleta = preload("res://comun/visor/paleta_viz.gd")
enum { CUBO = 1, ESFERA = 2, CILINDRO = 3, CONO, FLECHA, EJES, DISCO, ANILLO }   # 1–3 = Marker.type
const MAX_VARIANTES := 64
const C := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))   # = util_ros.gd:6
static var _mallas := {}                    # Vector2i(forma, indice) -> ArrayMesh

static func malla(forma: int, indice_color: int) -> ArrayMesh:
	var k := Vector2i(forma, indice_color)
	if not _mallas.has(k):
		if _mallas.size() >= MAX_VARIANTES:
			push_warning("PrimitivasViz: más de %d variantes; se reutiliza el blanco" % MAX_VARIANTES)
			k = Vector2i(forma, 0)
			if _mallas.has(k):
				return _mallas[k]
		_mallas[k] = _construir(forma, indice_color)
	return _mallas[k]

static func instancia(forma: int, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = malla(forma, Paleta.indice(color))
	return mi

static func _construir(forma: int, ic: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match forma:
		FLECHA: _tubo(st, 6, 0.0, 0.77, 0.04, 0.04, ic); _tubo(st, 6, 0.77, 1.0, 0.1, 0.0, ic)
		CILINDRO: _tubo(st, 8, -0.5, 0.5, 0.5, 0.5, ic, true)
		CONO: _tubo(st, 8, 0.0, 1.0, 0.0, 0.5, ic)
		EJES: _caja(st, Vector3(0, 0, -0.5), Vector3(0.04, 0.04, 1.0), 2)    # X ROS = −Z Godot, rojo
		      # … Y ROS (−X Godot, verde = 3) y Z ROS (+Y Godot, azul = 4) igual …
		# CUBO (_caja), ESFERA (octaedro), DISCO (abanico 12), ANILLO (28 segmentos sobre 315°): igual
	st.set_material(Paleta.material())
	return st.commit()

## Tubo/cono sobre −Z entre z0 y z1 con radios r0, r1 y n lados (H15: sin tapas, sin culling).
## eje_y = true lo construye sobre +Y (cilindro de Marker, eje Z de ROS).
static func _tubo(st: SurfaceTool, n: int, z0: float, z1: float, r0: float, r1: float, ic: int, eje_y := false) -> void:
	st.set_uv(Paleta.uv(ic))
	for i in n:
		var a := Vector2.from_angle(TAU * i / n)
		var b := Vector2.from_angle(TAU * (i + 1) / n)
		var q := [Vector3(a.x * r0, a.y * r0, -z0), Vector3(a.x * r1, a.y * r1, -z1),
				Vector3(b.x * r0, b.y * r0, -z0), Vector3(b.x * r1, b.y * r1, -z1)]
		for j in [0, 1, 2, 2, 1, 3]:
			var v: Vector3 = q[j]
			st.add_vertex(Vector3(v.x, -v.z, v.y) if eje_y else v)

static func _caja(st: SurfaceTool, centro: Vector3, lados: Vector3, ic: int) -> void:
	st.set_uv(Paleta.uv(ic))
	# 12 triángulos de una caja de `lados` centrada en `centro` (tabla constante de 36 vértices ±0,5)

## geometry_msgs/Pose (RosMsg) → Transform3D Godot; cuaternión nulo → identidad (RViz lo rechaza).
static func pose_godot(p) -> Transform3D:
	var o = p.orientation
	var x = p.position
	var q := Quaternion(o.x, o.y, o.z, o.w)
	q = q.normalized() if q.length_squared() > 1e-6 else Quaternion.IDENTITY
	return Transform3D(Basis(rclgd.ros_to_godot_quat(q)), rclgd.ros_to_godot_vector(Vector3(x.x, x.y, x.z)))

## Escala de Marker/shape (ROS x, y, z) → ejes locales de Godot (mapas#13).
static func escala_ros(s) -> Vector3:
	return Vector3(absf(s.y), absf(s.z), absf(s.x))

## Transform3D que lleva la FLECHA unidad (−Z, largo 1) a apuntar a v con largo |v|. v ≈ 0 → oculto (null).
static func flecha_hacia(v: Vector3):
	if v.length() < 1e-6:
		return null
	var arriba := Vector3.UP if absf(v.normalized().y) < 0.99 else Vector3.RIGHT
	return Transform3D(Basis.looking_at(v, arriba).scaled_local(Vector3(1, 1, v.length())), Vector3.ZERO)

## Cinta plana (2 tri por segmento, perpendicular a UP). Se reconstruye solo si cambian los puntos.
static func cinta(puntos: PackedVector3Array, ancho: float, ic: int, cerrada := false) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_uv(Paleta.uv(ic))
	var n := puntos.size()
	for i in (n if cerrada else n - 1):
		var a := puntos[i]
		var b := puntos[(i + 1) % n]
		var lado := (b - a).cross(Vector3.UP).normalized() * ancho * 0.5
		for v in [a - lado, a + lado, b - lado, b - lado, a + lado, b + lado]:
			st.add_vertex(v)
	st.set_material(Paleta.material())
	return st.commit()

## Matriz simétrica 3×3 en ejes ROS (Basis por columnas) → ejes Godot.
static func a_godot(b_ros: Basis) -> Basis:
	return C * b_ros * C.transposed()
```

`flecha_hacia` devuelve `null` con vector nulo porque `Basis.looking_at` con vector nulo da error (geom#2) [V].
`Basis.diagonalize()` existe en C++ (`engine/core/math/basis.h:227`) pero **no está expuesto a GDScript**
(`variant_call.cpp:2490-2507`) [V]: los autovalores 2D tienen solución cerrada (§4.2, covarianza) y los 3D se hacen
con Jacobi cíclico (§4.2, inercia).

---

## 4. Catálogo por tipo

→ **[`36a-catalogo-displays.md`](36a-catalogo-displays.md)** (separado el 2026-11-13, ADR 0014 §4.3): tabla maestra §4.0
y fichas §4.1–§4.x de cada tipo (display, capa PC/Vita, ruta en la Vita, código GDScript). La numeración se
conserva: «doc 36 §4.x» es esa ficha del 36a.

---

## 5. Relay VC/1 rev. 2 (`docker/scripts/vita_relay.py` + `vita_relay_formatos.py`)

### 5.1 Tamaños (⚖ D4, resuelve C6)

- **Límite duro de envío** [V]: carga XRCE = CDR **sin** los 4 B de encapsulación ≤ 488 B
  (`godot/ros2_vita/xrce_transport.cpp:12-13,147,678`: `XRCE_OVERHEAD = 24`, `fits = p_len + 24 <= MTU`). Equivale a
  ≤ 492 B medidos con rosbags.
- **Límite de diseño de todo `/vita/*`**: ≤ 488 B **medidos con rosbags** (carga ≤ 484 B, 4 B de margen). Es lo que ya
  hace el relay: `cdr_multiarray` suma la encapsulación y `_pub` compara con `MAX_BE = 488`
  (`docker/scripts/vita_relay.py:30,115-117,183-184`). Motivo: la cabecera del DATA que manda el agente **en
  recepción** no está medida [?] → gate **G-W13-R0**; si confirma 488 B de carga también en recepción, `MAX_BE` sube a
  492 en un solo sitio.
- Fórmulas (`docs/27:84-86`): `Float32MultiArray` = 16 + 4N ⇒ N ≤ 118; `Int16MultiArray` = 16 + 2N ⇒ N ≤ 236;
  `UInt8MultiArray` = 16 + N ⇒ N ≤ 472.
- **Cita desfasada** (trabajo de V15): `docs/27:10,33` y `docs/31:157` citan `xrce_transport.cpp:411-415` para el tope;
  esas líneas son hoy la reconexión; lo correcto es `:147-148,678-681` (`W13-revision.md:107-109`).

### 5.2 Contrato (⚖ D5, resuelve C4)

1. **Cabecera común** de todo formato **nuevo** troceado: `[seq & 0x7FFF, trozo, n_trozos, n, …]`, con `n` =
   elementos **de este trozo**; los campos propios del formato van detrás (p. ej. `ancho, alto` en detecciones). Las
   teselas comparten la cabecera `[ver_lo, ver_hi, tx, ty]` del mapa. Sustituye a las cuatro cabeceras distintas de
   los posts (`[seq, trozo, n_trozos]` en nube2d y marcadores, `[seq, ancho, alto, n]` en det2d, `[seq, n]` en det3d).
2. **Los formatos existentes no cambian ni un byte** (`scan_compacto`, `pose2d`, `joints`, `mapa_*`, `path_compacto`):
   los consumen `godot/plantillas/vita_relay.gd` y `godot/g1-unitree/`.
3. **Registro obligatorio** de cada formato nuevo: función pura en Python (referencia) en
   `docker/scripts/vita_relay_formatos.py`, copia en `godot/plantillas/ros/vc1.gd`, prueba de bytes en
   `godot/plantillas/pruebas/runner.gd` (como las de `runner.gd:59-82`) y en `docker/scripts/test_vita_relay.py`.
   **Un formato sin prueba de bytes no entra.** `vita_relay.py` (≈ 290 líneas) se parte: funciones puras aparte y el
   nodo en `vita_relay.py`.
4. **`/vita/pose2d` no se amplía** (contra geom#13: rompería a `vita_relay.gd:87-91` y a hmi#14); la covarianza sale en
   `pose_cov` (7 floats, 2 Hz).
5. **Época del mapa**: `version` solo sube cuando cambian resolución, tamaño u origen (hoy sube con cada
   `OccupancyGrid`, `vita_relay.py:235`; con un costmap a 1–5 Hz invalidaría todo cada vez).
6. **Prefijo** `/vita` o `/vita/<robot>` (`vita_relay.py:21`); los displays guardan solo el sufijo (`topic_vita`).
7. **Tope de red comprobado al arrancar**: cada módulo declara Hz y bytes máximos; si la suma pasa de **100 KB/s** o de
   **200 datagramas/s** (`docs/27:42-43`), el relay **no arranca** y dice qué módulo sobra.
8. **`relay_info`** (String F+TL): `VC/1.2;` + lista de módulos activos. Saludo de versión y distinción entre «sin
   datos» y «módulo apagado» en el HUD.
9. **Módulo `ritmo`**: republica topics pequeños de tipo estándar a Hz fija en `<p>/ritmo/<nombre>` (p. ej. Imu a
   100 Hz → 20 Hz); comprueba el tamaño serializado de cada mensaje.

### 5.3 Catálogo cerrado (bytes con rosbags; `<p>` = prefijo; BE = best effort; F+TL = fiable + TRANSIENT_LOCAL)

| Topic `<p>/…` | Tipo | Formato | QoS | Hz | B máx. | KB/s | dgr/s | Fase |
|---|---|---|---|---:|---:|---:|---:|---|
| `scan_compacto` | Int16MultiArray | `[seq, ang_min_cdeg, inc_cdeg, n, r…]` cm, 0 = sin dato, n ≤ 180 | BE | 10 | 384 | 3,84 | 10 | existe |
| `pose2d` | Float32MultiArray | `[x, y, yaw, vx, vy, wz]` | BE | 30 | 40 | 1,20 | 30 | existe |
| `joints` | Float32MultiArray | posiciones en el orden de `joints_orden`, ≤ 118 (G1: 29) | BE | 25 | 132 (G1) | 3,30 | 25 | existe |
| `joints_orden` | String | nombres con comas | F+TL | al cambiar | — | — | — | existe |
| `mapa_meta` | Float32MultiArray | `[res, ancho, alto, ox, oy, tx, ty, época]` | F+TL | al cambiar | 48 | — | — | existe (época: V6) |
| `mapa_tesela` | UInt8MultiArray | `[ver_lo, ver_hi, tx, ty]` + 32×32 a 2 bit | BE | ≤ 20 | 276 | 5,52 | 20 | existe |
| `path_compacto` | Float32MultiArray | `[n, x0, y0, …]`, ≤ 57 puntos | BE | 2 | 476 | 0,95 | 2 | existe |
| `relay_bw` | Float32MultiArray | `[bytes/s, mensajes/s]` | BE | 1 | 24 | 0,02 | 1 | existe |
| `relay_info` | String | `VC/1.2;módulos` | F+TL | al arrancar | — | — | — | V6 |
| `rosout` | `rcl_interfaces/msg/Log` | ≥ WARN, sin `file`/`function`, `msg` ≤ 200 car. | fiable | ≤ 10 | ≈ 270 [I] | 2,72 | 10 | V6 |
| `diagnostics` | `diagnostic_msgs/msg/DiagnosticArray` | 1 estado, ≤ 3 pares, textos ≤ 40 car.; cambios + repaso 1 Hz | BE | ≤ 10 | ≈ 160 [I] | 1,60 | 10 | V6 |
| `marcadores` | Float32MultiArray | cab. + `[clave, tipo, x, y, z, yaw, sx, sy, sz, color]`·n, n ≤ 11; estado completo ≤ 33 | BE | 5 × ≤ 3 | 472 | 7,08 | 15 | V8 |
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
| `costmap_meta` | Float32MultiArray | como `mapa_meta` (teselas 32×16) | F+TL | al cambiar | 48 | — | — | V11 |
| `costmap_tesela` | UInt8MultiArray | `[ver_lo, ver_hi, tx, ty]` + 32×16 a 4 bit | BE | ≤ 10 | 276 | 2,76 | 10 | V11 |
| `ritmo/<nombre>` | el de entrada | sin cambios, limitado en Hz | BE | config. | ≤ 488 | ≤ 10 | ≤ 30 | V6 |

Cuentas [V cálculo con `16 + 4N` y `16 + 2N`]: marcadores 4 + 110 = 114 floats → 472 B; puntos 8 + 108 = 116 → 480 B;
detecciones 6 + 108 = 114 → 472 B; detecciones 3D 4 + 108 = 112 → 464 B; poses 4 + 108 = 112 → 464 B; tf 4 + 64 = 68 →
288 B; nube 4 + 228 = 232 int16 → 480 B. **Corrección al revisor y a `docs/27`**: `nube2d` con 78 puntos cabía solo
sin cabecera (`docs/27:106`).
**Fuera del catálogo** (⚖): `/vita/catalogo` (D9); ampliar `pose2d`; `im_poses` y el cliente de marcadores
interactivos en la Vita (V14); miniaturas `mono8`; `/vita/tf` de 32 marcos a 30 Hz (≈ 104 KB/s). Mando y acciones
(`/vita/mando`, `/vita/orden`, `/vita/accion/*`) siguen en el puente VAB/1 (ADR 0012 §2), no en el relay; `/vita/joy`
lo publica la Vita.

### 5.4 Perfiles de red (suma nominal; límite 100 KB/s y 200 datagramas/s)

| Perfil del relay | Módulos | KB/s | dgr/s |
|---|---|---:|---:|
| `hmi` | `scan,pose,joints,mapa,path` + `rosout,diag` | 19,2 | 108 |
| `viz` | `hmi` + `marcadores,pose_cov,poses,tf,costmap` | 35,0 | 153 |
| `percepcion` | `hmi` + `camara,det2d,det3d,nube` | 40,0 | 154 |
| todo + `ritmo` | — | 65,9 | 229 → **rechazado** |

Para activar todo hay que bajar ritmos (p. ej. `pose2d` a 20 Hz y `joints` a 15 Hz, como ya pide
`godot/g1-sensores/robot.json` con `hz_vita`). Uso: `docker/vita-ros.sh relay <módulos>` (hoy
`scan,pose,joints,mapa,path`; `vita_relay.py:21,138`).

### 5.5 Esqueletos del contrato

Python (referencia, `vita_relay_formatos.py`):

```python
MAX_BE = 488                                    # bytes con rosbags (§5.1); 492 tras G-W13-R0 verde
MAX_F32 = (MAX_BE - 16) // 4                    # 118 floats por Float32MultiArray
MAX_I16 = (MAX_BE - 16) // 2                    # 236 int16 por Int16MultiArray

def trocear(elementos, por_elemento, extra=(), seq=0, max_valores=MAX_F32, max_trozos=3):
    """VC/1 rev. 2: lista de elementos (cada uno, lista de `por_elemento` números) → lista de trozos
    [seq & 0x7FFF, trozo, n_trozos, n, *extra, *elementos_del_trozo]. Corta a max_trozos (estado completo)."""
    cab = 4 + len(extra)
    cabe = (max_valores - cab) // por_elemento
    elementos = elementos[:cabe * max_trozos]
    n_trozos = max(1, -(-len(elementos) // cabe))
    out = []
    for t in range(n_trozos):
        parte = elementos[t * cabe:(t + 1) * cabe]
        out.append([seq & 0x7FFF, t, n_trozos, len(parte), *extra, *[v for e in parte for v in e]])
    return out

# Presupuesto declarado por módulo: (ciclos/s, bytes por ciclo, datagramas por ciclo). Tabla §5.3.
# «marcadores» incluye marcadores (3 trozos) + marcador_puntos (≤ 4/s) + marcador_texto (≤ 2/s): 21 dgr/s.
PRESUPUESTO = {"nucleo": (1, 24, 1), "scan": (10, 384, 1), "pose": (30, 40, 1), "joints": (25, 132, 1),
               "mapa": (20, 276, 1), "path": (2, 476, 1), "rosout": (10, 270, 1), "diag": (10, 160, 1),
               "marcadores": (5, 3 * 472 + 384 + 40, 4.2), "pose_cov": (2, 44, 1), "poses": (2, 464, 1),
               "tf": (10, 288, 1), "costmap": (10, 276, 1), "camara": (3, 3000, 7), "det2d": (5, 472, 1),
               "det3d": (5, 464, 1), "nube": (5, 3 * 480, 3),
               "ritmo": (1, 10000, 30)}                # tope declarado del módulo ritmo (≤ 10 KB/s, ≤ 30 dgr/s)

def comprobar_presupuesto(modulos, kb_max=100.0, dgr_max=200.0):
    """Lanza ValueError (el relay no arranca) si la suma nominal se pasa; dice qué módulo pesa más."""
    modulos = ["nucleo", *modulos]                     # relay_bw siempre
    kb = sum(PRESUPUESTO[m][0] * PRESUPUESTO[m][1] for m in modulos) / 1000.0
    dgr = sum(PRESUPUESTO[m][0] * PRESUPUESTO[m][2] for m in modulos)
    if kb > kb_max or dgr > dgr_max:
        peor = max(modulos, key=lambda m: PRESUPUESTO[m][0] * PRESUPUESTO[m][2])
        raise ValueError(f"presupuesto {kb:.1f} KB/s, {dgr} dgr/s > {kb_max}/{dgr_max}: sobra «{peor}»")
    return kb, dgr
```

[I] La fila `camara` usa 7 datagramas por imagen (≈ 3 000 B fiable fragmentado) para casar con los ≈ 21 dgr/s de la
tabla; la cifra exacta depende del MTU de recepción (G-W13-R0). Con estos valores, `hmi` da 19,1 KB/s y 108 dgr/s,
`viz` 35,0 y 153, `percepcion` 40,0 y 154, y todo + `ritmo` 65,9 KB/s con 229 dgr/s → rechazado: exactamente las
sumas de §5.4 (tabla del juez), comprobadas con este diccionario; `test_vita_relay.py` debe reproducirlas.

GDScript (copia en `godot/plantillas/ros/vc1.gd`):

```gdscript
## VC/1 rev. 2: cabecera común de lo troceado [seq & 0x7FFF, trozo, n_trozos, n, …]. {} si no es válida.
static func cabecera(d) -> Dictionary:
	if d.size() < 4:
		return {}
	var c := {"seq": int(d[0]), "trozo": int(d[1]), "n_trozos": int(d[2]), "n": int(d[3])}
	if c.n_trozos < 1 or c.trozo < 0 or c.trozo >= c.n_trozos or c.n < 0:
		return {}
	return c

## Referencia de bytes: misma salida que vita_relay_formatos.trocear (prueba en pruebas/runner.gd).
static func trocear(elementos: Array, por_elemento: int, extra: Array, seq: int, max_valores: int, max_trozos: int) -> Array:
	var cab := 4 + extra.size()
	var cabe := (max_valores - cab) / por_elemento
	var lista := elementos.slice(0, cabe * max_trozos)
	var n_trozos := maxi(1, ceili(float(lista.size()) / cabe))
	var out := []
	for t in n_trozos:
		var parte := lista.slice(t * cabe, (t + 1) * cabe)
		var trozo: Array = [seq & MASCARA_SEQ, t, n_trozos, parte.size()] + extra
		for e in parte:
			trozo.append_array(e)
		out.append(trozo)
	return out
```

---

## 6. QoS por tipo (⚖ C9 y ADR 0013 §6)

Regla general [I: compatibilidad de QoS de ROS 2/DDS, no releída en la sesión del juez]: un suscriptor **best effort**
casa con cualquier publicador; un publicador **fiable** casa con cualquier suscriptor. Siempre con `RosQoS.set_*()`
vía `contexto.qos(best_effort, profundidad, latched)` (`contexto_ros.gd:25-31`); nunca `qos.reliability =` hasta
T-W4-3 (`ros_runtime.cpp:76-92`).

| Qué | Fiabilidad | Historial | Durabilidad | En el contrato | Nota |
|---|---|---|---|---|---|
| Display de estado periódico (relay o sensor) | best effort | 1 | volátil | `fiabilidad = AUTO` | lo normal |
| Display de dato *latched* (`*_meta`, `*_orden`, `det_clases`, `tf_marcos`, `relay_info`, `/map`, `/tf_static`, `/robot_description`) | fiable | 1 | TRANSIENT_LOCAL | `latched = true` | llega aunque se conecte tarde |
| Display de eventos (`rosout`, `marcador_texto`, lifecycle) | fiable | 10 (PC) / 5 (Vita) | volátil | `fiabilidad = FIABLE` | un evento perdido no se repite |
| Estado de acciones (`GoalStatusArray`) | fiable | 1 | TRANSIENT_LOCAL [I] | `latched = true` | el servidor lo publica *latched* |
| Imagen comprimida en la Vita | fiable | 1 | volátil | `FIABLE` + `profundidad = 1` | no cabe en 488 B |
| `DiagnosticArray` directo (PC), `JointTrajectoryControllerState`, detecciones directas (PC) | fiable | 1 | volátil | `FIABLE` + `profundidad = 1` | no caben en 488 B |
| Meta, pose inicial, punto (`goal_pose`, `initialpose`, `clicked_point`) | fiable | 5 (PC) / 1 (Vita) | volátil | `HerramientaVisor` | como RViz (`goal_tool.cpp:67,78`); un mensaje por confirmación con ✕ |
| *Feedback* de marcador interactivo | fiable | 1 | volátil | `HerramientaVisor` (fijar 1, V14) | ≤ 20 Hz al arrastrar, 149–157 B |
| Teleop directo (`/cmd_vel`) | fiable por defecto | 1 | volátil | `teleop.gd` | validado en hardware (`godot/g6-hmi/main.gd:65`); configurable a best effort |
| Teleop con robot real (`/vita/mando`) | best effort | 1 | volátil | puente VAB/1 | 20 Hz, puerta en el PC (ADR 0012 §3) |
| `/vita/joy` | best effort | 1 | volátil | publicador de `joy.gd` | 20 Hz, 128 B |

En la Vita la emisión fiable bloquea el hilo principal **solo cuando fragmenta** (`docs/27:13-15,34`); todo lo que
publican las herramientas ocupa ≤ 364 B. Riesgo: `/cmd_vel` fiable hacia un suscriptor best effort casa, pero en un
enlace con pérdidas acumula reintentos; con el G1 se usa best effort, como hoy
(`godot/plantillas/robots/humanoide_g1.gd:163-164`). Reversión: `fiabilidad` es un `@export` de cada display y
herramienta.

---

## 7. Presupuesto (reparto del ADR 0011 por display)

Criterio general de verde en la Vita (sentencia §4; `docs/31:226-228`): **≥ 55 FPS en perfil HMI o ≥ 30 en Viz**,
`avg_canvas_us` ≤ 2 000 / 3 000 y `avg_submit_us` ≤ 6 000 / 9 000. CPU por display (`docs/31` §4.1): ≤ 2 ms por
mensaje y ≤ 1 ms por fotograma de media [I hasta E-W8-0].

### 7.1 Instancias 3D (⚖ D7, resuelve C7: los posts sumaban 172–204 contra 80)

| Capa 3D (`capa` del display) | Perfil HMI (60 FPS, 80 inst.) | Perfil Viz (30 FPS, 150 inst.) | Displays |
|---|---:|---:|---|
| `robot` | 40 | 40 | `robot_joints`; fantasma con el robot oculto |
| `mundo` (mundo, mapa y rejilla) | 12 | 12 | `mundo.tscn`, `3d/mapa` |
| `tf` (solo ejes) | 8 | 32 | `tf` |
| `marcadores` | 12 | 32 | `marcadores` |
| `poses` (poses, odometría, rastro) | 4 | 16 | `pose`, `punto`, `vector`, `tornillo`, `imu`, `odometria` 3D… |
| `lento` (path y otras mallas lentas) | 0 (en 2D) | 4 | `3d/path`, `3d/poligono` |
| `reserva` | 4 | 14 | fantasma del brazo (≤ 8), frustum, inercia |

La columna Viz reproduce `docs/31:237-246` (marcadores + poses + rastro = 48); la HMI es nueva. En la Vita, planta 2D
por defecto para lo que vive en el suelo (odometría, path, scan, nube, poses, covarianza, polígonos, GPS, sector de
`Range`); la orbital queda para robot, TF, IMU, fuerzas y marcadores. Flechas hijo → padre de TF apagadas en la Vita.
Riesgo: 12 marcadores en HMI es poco para Nav2 → perfil Viz (30 FPS). `pruebas/presupuesto.gd` suma los `_coste()`
de la escena por capa y falla si pasa el cupo (comprobable en host).

### 7.2 *Quads* 2D (1 500 por fotograma; `docs/31:255`)

| Zona | *Quads* | Contenido |
|---|---:|---|
| **HUD** | **400** | barra fija ≤ 120 (24 px arriba: batería, enlace y Hz, meta, herramienta) + pestaña activa ≤ 240 (320 × 496 px a la derecha) + texto superpuesto ≤ 40 |
| Sensores 2D | 800 | scan ≤ 360, nube ≤ 228, path ≤ 112, poses y odometría ≤ 100 |
| Resto | 300 | marcadores 2D ≤ 150, detecciones ≤ 150 |

| Pestaña (`GestorHud`, una visible) | Límite en la Vita | Displays |
|---|---|---|
| Estado | 6 medidores o filas | `medidor`, `lifecycle`, detalle de Hz por display |
| Diagnóstico | 8 filas × 30 car., «solo problemas» | `diagnostico` |
| Consola | 6 líneas × 40 car. | `consola` |
| Gráficas | 3 series × 64 puntos + ejes | `trazador` |
| Inspector | 8 filas × 30 car., 4 Hz | `inspector_texto` |
| Cámara | 1 imagen + ≤ 18 cajas | `imagen_comprimida`, `cajas_2d`, `marcas_imagen` |
| Controlador | 14 juntas, solo barras | `controlador` |

Reglas de dibujo: una fuente, sin contorno (`docs/34:52`), un `_draw()` por panel. En el PC los cupos no se aplican y
se pueden ver varios paneles; el código es el mismo. Los límites de filas son **de partida**: el coste real es por
lote y por glifo y no está separado [?] → G-W13-H0.

### 7.3 Red

Por perfil del relay en §5.4 (HMI ≈ 19 KB/s y 108 dgr/s; Viz ≈ 35 y 153; Percepción ≈ 40 y 154). TX de la Vita:
herramientas ≤ 364 B por evento; `/vita/joy` 128 B × 20 Hz = 2,6 KB/s; feedback IM 149 B × 20 Hz ≈ 3 KB/s.

---

## 8. Trampas encontradas (todas con su arreglo en el código de este documento)

| # | Trampa | Evidencia | Arreglo |
|---|---|---|---|
| T1 | `m.reference` en `JointTrajectoryControllerState` resuelve a `RefCounted.reference()` (un `Callable`): «Cannot find member positions in base Callable» | check-only de hmi#13 [V] | `m.get_member("reference")` (como `estado_controlador.gd:36-41`); revisar otros choques (`free`, `notification`, `get`, `set` [?]) |
| T2 | Filtro de rango que deja pasar NaN: `if r < min or r > max: continue` | prueba de sensores en host [V] | `if not (r >= min and r <= max): continue` (REP-117: también descarta ±Inf) |
| T3 | `qos.reliability = …` da «Invalid assignment of property» en la Vita (rclgd lo acepta, `ros_qos.cpp:27-28`) | `ros_runtime.cpp:76-92` [V] | `set_reliability()` siempre (o `contexto.qos`); anotar en `API_PARITY.md` (V15) |
| T4 | PNG de 16 bit bajado a 8 bit por el cargador de Godot | `png_driver_common.cpp:72-106` [V] | `compressedDepth` fuera de Godot (republish / relay) |
| T5 | Bucles por píxel en GDScript: 14–35 ms por 640×480 en el host | medido [V] | formatos nativos + *shader* (PC); relay JPEG (Vita) |
| T6 | `uint32[]`, `int64[]`, `uint64[]` → `PackedInt64Array`; `int8/int16/uint16[]` → `PackedInt32Array`; se pierde el primitivo | `ros_msg.cpp:432-488` [V]; rclgd `uint32[]` [?] | indexar sin tipar y `int(...)` |
| T7 | Anotar `RosTfListener` o `RosClient` rompe la compilación en la Vita | check-only mapas#10, #26 [V] | `var tf = null`, `var _cli` sin tipo; `has_method` + `call`; scripts con servicios = `solo_pc` |
| T8 | `:=` con operandos `Variant` no infiere tipo («Cannot infer the type of "lados"», «… "pulsado"») | check-only geom#12, mapas#27 [V] | tipo explícito: `var lados: Vector3 = …`, `var pulsado: bool = …` |
| T9 | Usar una constante de otro script sin `preload` («Identifier "Fab" not declared») | check-only mapas#26 [V] | `const Fab = preload("res://comun/visor/fabrica_marcadores.gd")` |
| T10 | Base HUD «igual salvo `extends`»: `transform = t` no existe en `Control` | revisión nucleo#3 [V] | `DisplayRosHud` con `_al_mensaje` propio sin TF |
| T11 | Grados de lat/lon en `Vector2` (float32: 1e-5° ≈ 1 m) | geom#20 [V] | origen en `float` de GDScript (64 bit), metros antes del `Vector2` |
| T12 | `Basis.diagonalize()` no expuesto a GDScript | `variant_call.cpp:2490-2507` [V] | forma cerrada 2×2; Jacobi 3×3 |
| T13 | `Basis.looking_at` con vector nulo o paralelo a `UP` | geom#0/#2 [V] | `flecha_hacia` devuelve `null` si |v| ≈ 0; `UP` alternativo `RIGHT` |
| T14 | Cuaternión nulo o no unitario | `odometry_display.cpp` (messageIsValid) [V] | normalizar; nulo → identidad (pose) o descartar (orientación) |
| T15 | `Label3D`, MultiMesh, líneas/puntos 3D, color por vértice: invisibles o ignorados en la Vita | H1–H3, ADR 0011 §4 [V] | `PrimitivasViz`/`PaletaViz`; 2D; `TextoSuperpuesto` |
| T16 | Un `Label` por texto y el contorno multiplican lotes (222 *draws* para 305 *quads*) | `docs/34:52` [V] | un `_draw()` por panel, sin contorno |
| T17 | `lifetime` de Marker contado con el reloj del mensaje | `marker_base.cpp:84` [V] | reloj de recepción (`Time.get_ticks_msec()`) |
| T18 | `version` del mapa sube con cada `OccupancyGrid` | `vita_relay.py:235` [V] | época de geometría (D5.5) |
| T19 | Convención de 488 B con o sin encapsulación (106 frente a 107 rayos; «Detection3D no cabe por 1 B») | `xrce_transport.cpp:12-13` [V] | §5.1: límite de diseño 488 con rosbags |
| T20 | Esquema único global: cargar otro `.rsch` reemplaza el anterior; tipo sin esquema = `ERR_FAIL_COND` por muestra | `ros_msg.cpp:14-24`, `ros_runtime.cpp:122-123` [V] | un `.rsch` por app con `TIPOS_VISOR`; no suscribir sin esquema |
| T21 | Asignar a un campo de array copia: `m.pose.covariance[0] = …` no persiste | `API_PARITY.md:49` [V] | construir el `PackedFloat64Array` y asignarlo entero |
| T22 | Publicar `-0.0` en `Twist` | `g6-hmi/main.gd:98` [V] | `+ 0.0` |
| T23 | Eje Y del stick positivo hacia abajo en Godot | `g6-hmi/main.gd:85-86` [V] | negar X e Y al publicar `/vita/joy` |
| T24 | rclgd entrega **cada** mensaje (`call_deferred`) | `ros_subscriber.cpp:20-37` [V] | «el último gana» en `CanalDisplay` |
| T25 | `get_property_list()` de rclgd convierte cada miembro | `ros_msg.cpp:285-301` [V] | prototipo vacío y caché por tipo |
| T26 | `ImageTexture.update` en la Vita = duplicar + convertir a RGBA8 + `detect_alpha` (caro ∝ píxeles) | H19 [V] | mismo tamaño/formato; trocear el mapa; ≤ 4 Hz |
| T27 | `FORMAT_R16`, `to_vector*_array`, `bswap*` no existen en Godot 4.4 | borrador de sensores §3.5 [V] | editor 4.7 (rclgd) o 4.8-dev7 (Vita) |
| T28 | `bswap32()` en nubes *big-endian* solo vale si todos los campos son de 4 B | sens#3 [V] | comprobar `datatype`; si no, decodificar por campo |
| T29 | `PointCloud`/`MultiEchoLaserScan`: un `RosMsg` por elemento (camino lento) | sens#2, #5 [V] | convertir fuera de Godot o relay |
| T30 | ARROW_STRIP (12) está en `Marker.msg` de Jazzy pero RViz no lo dibuja | `marker_factory.cpp:71-103` [V] | semántica propia marcada [?] |
| T31 | Feedback IM publicado en best effort no llega (el servidor suscribe fiable) | `interactive_marker_server.hpp:87-88` [V] | fiable (C9) |
| T32 | `distance_darkening` y descarte por distancia del port | H12–H13 [V] | desactivarlo en apps de visualización; cámara cenital ≤ 20 m |

---

## 9. Por medir, gates y por resolver

### 9.1 Gates de hardware (las pruebas las lanza el usuario; la Vita está en sus manos)

| Gate | Qué mide | Verde | Lo necesita |
|---|---|---|---|
| **G-W13-R0** | recepción best effort con N ∈ {484, 488, 489, 492, 493} B de carga (banco de `docs/27` §4) | corte en 488 / 489 de carga | D4 (`MAX_BE` = 492) |
| **G-W13-H0** | coste del HUD: 100, 200 y 400 glifos en 1 y en 4 `CanvasItem`, con `[gxm2d-canvas]` y `[gxm2d-perf]` | µs por glifo y por lote separados; 400 glifos ≤ 2 ms | D6 (filas por pestaña), V4 |
| **E-W8-0** (existente) | coste de GDScript en la Vita (hipótesis 1,5 µs/instrucción, `docs/31:162`) | — | todos los tiempos [I] |
| **E-W8-1** (existente) | paleta fuera de la pasada de luz con 80 instancias | `lit=` = 0, `drawn` = 80 | D2, V2 |
| **E-W8-2** (existente) | mallas 3D dinámicas y reconstrucción | ver `docs/31` §6 | GridMap 3D en la Vita |
| **E-W8-5** (existente) | JPEG 160×120 | ≤ 6 ms | D13, V10 |
| **E-W8-6** (existente) | escena completa de visualización | `docs/31` §6 | V3 |
| **G-W13-M1** | perfil **HMI** (`main.tscn`): pool lleno, **12** (cupo) CUBE/SPHERE/CYLINDER/ARROW moviéndose a 10 Hz (fuente de 31; 33 en el estado del relay) | `nodos` = 12, `drawn` +12, `avg_submit_us` ≤ 6 000, `invalidations` sin cambio, ≥ 55 FPS | V8 |
| **G-W13-M1v** | perfil **Viz** (`main_viz.tscn`): lo mismo con **32** (cupo) | `nodos` = 32, `drawn` +32, `avg_submit_us` ≤ 9 000, ≥ 30 FPS | V8; da por bueno el perfil Viz |
| **G-W13-M2** | 48 marcadores publicados (más que el relay, 33, y que el cupo, 12 / 32) con `lifetime` 2 s y DELETEALL por ns, 5 min | nº de nodos = cupo y de hijos constante, `[vita-memory]` estable | V8 (opcional) |
| **G-W13-M3** | `<p>/marcadores` con 33 marcadores (3 trozos) y 10 % de pérdida (netem), perfil HMI | sin fantasmas > 0,4 s, `process` ≤ 4 ms, ≤ 15 KB/s | D14, V8 |
| **G-W13-M4** | mapa 384² por relay con LUT + `blit_rect` | `process` ≤ 4 ms, textura estable 5 min | V3 |
| **G-W13-M5** | costmap 4 bit (Nav2 + TB3) | repaso completo ≤ 3 s, ≥ 30 FPS | V11 |
| **G-W13-M6** | arrastre táctil de `basic_controls` | POSE_UPDATE ≈ 20 Hz, latencia < 150 ms | V14 |
| **G-W13-M7** | LINE_STRIP 50 puntos y POINTS 180 en 2D con la cámara orbitando | `process` + `canvas` ≤ 2–3 ms | V8 |

**Enmienda 2026-11-14** (juez, `docs/ia/workshops/posts/V2-juez-fable.md` F1 y F2): los gates de marcadores miden el
**cupo del perfil** (12 en HMI, 32 en Viz), no «48» (esa cifra era marcadores + poses + rastro de `docs/31:237-246`); el
relay sigue en 33 y los cupos de §7.1 no cambian. El gate de hardware de V5 se corre en `godot/visor-ros/banco_v5.tscn`
y el perfil Viz en `main_viz.tscn`; se cambia de escena en la Vita sin reexportar con L + R + START (`selector_escena.gd`).

### 9.2 Fichas «Por medir» y su gate

| Ficha | Qué falta medir | Gate / criterio |
|---|---|---|
| nucleo#7 inspector de texto | coste de 8 filas a 4 Hz (la extrapolación de ≈ 6 µs/*quad* de doc 34 puede ser por lote, no por *quad*) | G-W13-H0 |
| nucleo#8 trazador | que la polilínea fina siga siendo de 1 px con `draw_set_transform` escalado y vaya en un lote | pestaña Gráficas con 3 series: `draws` +≤ 3, `avg_canvas_us` +≤ 300 (V12) |
| sens#13 display Camera | sin ejecutar; fondo transparente del «modo cámara» en la Vita [?] | prueba en el PC (SubViewport) y captura en la Vita |
| hmi#7 diagnósticos | *quads* de la tabla | G-W13-H0; 20 msg/s en la pestaña visible |
| hmi#8 consola | *quads* y FPS con 20 avisos/s | G-W13-H0; V6: 5 min sin bajar de escalón, `reliable_dropped` = 0 |
| hmi#12 fantasma | *draws* del fantasma del brazo junto al robot | `[gxm3d] drawn=` dentro del cupo (`robot` + `reserva`) |

### 9.3 Por resolver (sin corrección en la revisión ni decisión en la sentencia)

1. **Imagen sin código** (D sens#7 y huecos de sensores): `16SC1` (`FORMAT_R16I` + `usampler` [?]), `64FC1`,
   `nv21`/`nv24`, codificaciones de color de 16 bit, demosaico bayer, filas con relleno (`step ≠ w·bpp`), auto-rango,
   color por imagen RGB en DepthCloud, ruta GPU de PointCloud2 > 50 k puntos y estilos Boxes/Spheres.
2. **Display «Camera»** (sens#13): sincronizar imagen y TF por `stamp` (en la Vita no hay `lookup_transform` con tiempo);
   CameraInfo con P o con K para imágenes rectificadas y signo del desplazamiento.
3. **Marco de plan frente a real** (hmi#14) — **resuelto 2026-11-14** (`V2-juez-fable.md` F3: `map → odom` por la
   lista blanca de `tf`; `pose2d` no cambia de marco; sin `tf`, pose2d cuelga del marco fijo): el plan va en `map`, `pose2d` sale de `/odom` (`odom`); sin el módulo `tf`
   (o un `pose2d` calculado con TF map→base en el relay) el rastro deriva respecto al plan. Decidir en V9 si el relay
   publica `pose2d` en `map` (parámetro `odom_in`/marco) o si `map→odom` entra siempre en la lista blanca de `tf`.
4. **ARROW_STRIP** (mapas#24): semántica propia hasta que RViz la implemente [?].
5. **MESH_RESOURCE en la Vita**: módulo gltf de la plantilla sin verificar (`docs/24:114`) [?]; hoy solo horneadas.
6. **Tipos y nombres**: `uint32[]` en rclgd [?] (VoxelGrid, `MeshTriangle`); `nav2_msgs/action/NavigateToPose_FeedbackMessage`
   por texto en una suscripción normal [?]; lista completa de choques de nombres con `Object`/`RefCounted` [?];
   `std_msgs/Empty` en el `.rsch` [?] (fuera de `TIPOS_VISOR` hasta probarlo).
7. **Agente y transporte**: ¿acepta el agente un DataReader de un tipo que no conoce? [?] (determina si un modo «crudo»
   de Hz y bytes es posible en la Vita); cabecera real del DATA en recepción (G-W13-R0).
8. **Estación**: OpenCV en la imagen docker para el módulo `camara` [?] (V10).
9. **Costmap local rodante** en la Vita (origen que se mueve con el robot) [?]: ¿global o local submuestreado?
10. **Emulación de ratón desde táctil** en el port [I]: un toque = un `InputEventMouseButton`; panel trasero sin parche
    (`docs/28:59`, T1.4.2).
11. **ClassDB en clases tipadas de rclgd** [I]: que `class_get_property_list(clase, true)` dé exactamente los campos
    (probar en `rclgd/test/project`).
12. **Forma `CILINDRO` sobre −Z** para el cuerpo de las flechas por puntos (§4.7.2) y yaw de los marcadores compactos
    (§4.7.4): fijar en V8.
13. **`SHADING_MODE_UNSHADED`** en el port [?]: irrelevante si H8 funciona con la paleta; se ve en E-W8-1.
14. **Escritura en `/rosout` desde la Vita**: `RosLogger` sin registrar (`API_PARITY.md:20,39,85`); publicador propio de
    `Log` posible, sin decidir.
15. **Profundidad del feedback IM**: la tabla de C9 pide 1 en los dos, `HerramientaVisor` da 5 en el PC (V14).
16. **No se ha compilado nada contra rclgd** (no instalado en la máquina del revisor, `W13-revision.md:47`); y los
    esqueletos de este documento no se han pasado por el analizador (V1).

---

## 10. Tareas V1–V15 (de la sentencia), dependencias y criterio de verde

Comando de host: `$GH` = `toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64` (4.8-dev7 con `ros2_vita`;
`godot/plantillas/README.md:92-108`).

| # | Tarea | Archivos a crear o tocar | Depende de | Verde en host | Verde en hardware |
|---|---|---|---|---|---|
| **V1** | Núcleo del visor | `visor/{visor_ros,canal_display,display_ros_3d,display_ros_2d,display_ros_hud,registro_displays,tiempo_ros}.gd`; proyecto `godot/visor-ros/`; `plantillas/pruebas/visor.gd` | nada | `--check-only` de todos; prueba en `loopback`: recibe, «el último gana», caduca, reserva de cupo y `solo_pc` | la app arranca vacía a 60 FPS; reconecta con el agente |
| **V2** | Primitivas y paleta | `visor/{primitivas_viz,paleta_viz,texto_superpuesto}.gd`; prueba en `pruebas/visor.gd` | V1 | cada forma: solo `PRIMITIVE_TRIANGLES`, triángulos = tabla §3.2, un material, ≤ 64 variantes | 80 instancias: `lit=` = 0 y `drawn` = 80 (E-W8-1); captura con colores exactos |
| **V3** | Displays con el relay que ya existe | `displays/2d/{scan,path,pose,mapa}.gd`, `displays/3d/{robot_joints,pose,mapa}.gd`; arreglos de `docs/31` §4.4 en `plantillas/vita_relay.gd` (LUT + `blit_rect`, tabla de direcciones) | V1, V2; relay `scan,pose,joints,mapa,path` | con `docker/vita-ros.sh relay` y `compacto=1`: los cinco displays con datos; bytes VC/1 intactos (`pruebas/runner.gd`) | escena tipo E-W8-6 sin marcadores: ≥ 55 FPS, `process` ≤ 4 ms, tesela ≤ 1,5 ms |
| **V4** | HUD | `visor/gestor_hud.gd`; `displays/hud/{barra_estado,medidor,bateria,joy,estado_meta}.gd` | V1 | la prueba cuenta glifos por pestaña ≤ 240 y barra ≤ 120 | **G-W13-H0**: `[gxm2d-perf] quads=` ≤ 400 y `draws` ≤ 30 con la pestaña Estado; anotar µs por glifo |
| **V5** | Esquema de visor y displays directos pequeños | `plantillas/generar_esquemas.py` (`TIPOS_VISOR`); `displays/3d/{punto,vector,ejes,imu,fuerza,rango,marcador_simple}.gd`, `displays/2d/{poligono,covarianza,gps}.gd` | V2; D10 | `RosMsg.from_type` de cada tipo de `TIPOS_VISOR` ≠ `null`; ida y vuelta `serialize`/`deserialize` | cada tipo publicado desde el PC con `ros2 topic pub` se ve en `visor-ros/banco_v5.tscn`; sin `ERR_FAIL` de esquema |
| **V6** | Relay rev. 2: base + `rosout`, `diag`, `ritmo` | `docker/scripts/vita_relay_formatos.py` (nuevo), `vita_relay.py` (cabecera común, `relay_info`, tope de red, época del mapa), `test_vita_relay.py`; `plantillas/ros/vc1.gd`; `displays/hud/{consola,diagnostico}.gd` | V4; esquemas `Log` y `DiagnosticArray` (V5) | pruebas de bytes Python = GDScript; el relay se niega a arrancar con «todo»; `ros2 topic bw` ≤ 20 KB/s en perfil `hmi` | 20 avisos/s durante 5 min: FPS sin bajar de escalón; `reliable_dropped` = 0 |
| **V7** | Herramientas que publican | `visor/herramienta_visor.gd`; `herramientas/{teleop,meta,pose_inicial,punto}.gd` | V1, V4; esquemas `PoseWithCovarianceStamped` y `PointStamped` (V5) | en `loopback`: un mensaje por confirmación, QoS de la tabla §6, covarianza de `initialpose` como RViz | un toque = un evento; meta con ✕ llega a Nav2 (`ros2 topic echo /goal_pose`); panel trasero no disponible [V, `docs/28:59`] |
| **V8** | Marcadores | `visor/fabrica_marcadores.gd`; `displays/3d/marcadores.gd`, `displays/2d/marcadores_2d.gd`; módulo `marcadores` del relay | V2, V6 | estado completo: sin fantasmas tras DELETE; 33 marcadores = 3 trozos de ≤ 472 B | G-W13-M1 y G-W13-M3 |
| **V9** | TF y poses | `visor/tf_ligero.gd`; `displays/3d/tf.gd`, `displays/2d/{poses,covarianza}.gd`; módulos `tf`, `pose_cov`, `poses` | V2, V3, V6 | `TfLigero` pasa los casos de `modules/tf-tree/tests/parity_test.c`; mismo resultado que `RosTfListener` en el PC (± 1 mm) | 8 marcos a 10 Hz: `process` +≤ 0,5 ms; ejes en su sitio frente a RViz |
| **V10** | Percepción | módulos `camara`, `det2d`, `det3d`, `nube` del relay; `displays/hud/{imagen,cajas_2d}.gd`, `displays/2d/{cajas_3d,nube}.gd` | V4, V6; OpenCV en la estación [?] | tamaños ≤ 488 B; JPEG ≤ 3 KB; perfil `percepcion` ≤ 40 KB/s | E-W8-5 (JPEG ≤ 6 ms); nube de 228 puntos: `process` ≤ 2 ms por trozo |
| **V11** | Costmap | módulo `costmap`; composición sobre la textura del mapa en `displays/2d/mapa.gd` | V3, V6 | prueba de bytes de la tesela de 4 bit | G-W13-M5: repaso completo ≤ 3 s, ≥ 30 FPS |
| **V12** | Inspector y trazador | `visor/introspeccion_ros.gd`; `displays/hud/{inspector_texto,trazador}.gd`; `visor/explorador_topics.gd` (solo PC) | V4 | `campos_de_tipo` en prototipo vacío; trazador de 3 × 64 puntos = 3 comandos de dibujo | pestaña Gráficas: `draws` +≤ 3 y `avg_canvas_us` +≤ 300 |
| **V13** | Paquete nativo «plantilla N+1» | `godot/ros2_vita/ros_runtime.cpp` (propiedades de `RosQoS`, `latest_only`, tipo resuelto al suscribir, contadores), `RosTfListener` sobre `modules/tf-tree`, `modules/viz-decode/` | T-W4-2, T-W4-3, T-W8-7; solo PC | `tools/run-parity-tests.sh`; pruebas de `godot/test/` | `verify_runtime.py` PASS; mismos displays sin cambios de GDScript |
| **V14** | Extras solo PC y aplazados | nube en GPU, imágenes con *shader*, cliente de marcadores interactivos, octomap, grid_map; marcadores interactivos en la Vita (`im_poses`) | V8; T-W4-9 | `--check-only` con rclgd | no aplica hasta tener servicios en la Vita |
| **V15** | Documentación | este documento (hecho); cita corregida en `docs/27:10,33` y `docs/31:157`; nota en `docs/24` (T-W4-4 sustituida) y `docs/31` (T-W8-4 absorbida); `API_PARITY.md` (regla `set_*`, choque de `reference`); README de `visor/` | V1–V12 | enlaces y citas comprobados | — |

Nombres de archivo de V5 (`ejes`, `fuerza`, `marcador_simple`) son los de la sentencia; en §4 aparecen como
`orientacion.gd`/`transformada.gd` (ejes), `tornillo.gd` (fuerza: Twist/Accel/Wrench) y el gestor de marcadores con
`Marker` directo. Al implementar, gana la sentencia o se renombra en la sentencia; no es una decisión de diseño.

**Orden y cortes:** Fase 1 (sin plantilla nueva): V1 → V2 → V3 → V4 — ya da un visor útil en la Vita con el relay de
hoy. Fase 2 (relay rev. 2): V5 → V6 → V7 → V8 → V9. Fase 3: V10 → V11 → V12. Aparte: V13 cuando toque recompilar la
plantilla; V14 después; V15 al cerrar cada fase. Dependencias externas: `TIPOS_VISOR` (D10) antes de V6 y V7; V3 usa los
cinco módulos actuales del relay, V6 añade la base y V8–V11 un módulo cada una; **ningún hueco de `ros2_vita` bloquea
V1–V12**.

`TIPOS_VISOR` inicial (⚖ D10; `godot/plantillas/generar_esquemas.py`): `std_msgs` `Float32`, `Float64`, `Int32`,
`UInt8`, `ColorRGBA`; `geometry_msgs` `PointStamped`, `Vector3Stamped`, `PoseArray`, `PoseWithCovarianceStamped`,
`WrenchStamped`, `AccelStamped`, `QuaternionStamped`, `PolygonStamped`; `sensor_msgs` `Temperature`, `Illuminance`,
`RelativeHumidity`, `Joy`; `nav_msgs` `MapMetaData`, `GridCells`; `visualization_msgs` `Marker`, `ImageMarker`,
`InteractiveMarkerFeedback`; `diagnostic_msgs/DiagnosticArray`, `rcl_interfaces/Log`, `lifecycle_msgs/TransitionEvent`,
`action_msgs/GoalStatusArray`. Con ≈ 55 tipos en total el coste de la búsqueda lineal es de decenas de µs [I].

Comandos para el PC (fish), cuando exista el proyecto:

```fish
set GH toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64
$GH --headless --path godot/visor-ros --script res://comun/pruebas/visor.gd
docker/vita-ros.sh up
docker/vita-ros.sh relay scan,pose,joints,mapa,path
$GH --path godot/visor-ros -- transporte=xrce compacto=1
```

---

## 11. Alternativas registradas

| Alternativa | Dónde se estudió | Resultado |
|---|---|---|
| **Adoptar o portar gdviz** (Ozuba, MIT; T-W4-4 «capa GXM-safe») | `docs/24` §1–§4; revisión §5; sentencia §1 | descartada: coste M + L (interfaz) + L (nube) + cuatro huecos P0/P1 antes del primer display en la Vita; crea displays desde un `.rviz` (contra doc 35); interfaz de escritorio. Se toma su contrato como modelo y, si conviene, lógica pura (`viz_convert.gd`, `viz_urdf.gd`, tabla de `viz_image_codec.gd`) con su aviso MIT. En el PC quien quiera un RViz completo usa gdviz tal cual |
| Otros addons Godot ↔ ROS con visualización (nordstream3/Godot-4-ROS2-integration GPL-3 Humble, godot_ros_pcviz, godot_ros 2018) | búsqueda del revisor | nada mantenido de estilo RViz |
| **foxglove_bridge** (WebSocket, CDR, esquemas `ros2msg`, grafo) | revisión §5 | da descubrimiento y esquemas, pero va sobre TCP/WebSocket y entrega el CDR completo: no resuelve los 488 B ni el coste de decodificar. Útil en el PC como alternativa a rclgd para paneles; no para la Vita |
| **`viz-decode`** en C (`vizd_scan_xy`, `vizd_cloud_cm`, `vizd_project`) frente a GDScript frente a relay | `docs/31` §4.3; revisión §5 | regla de corte de ADR 0011 §5: relay primero; C cuando toque recompilar (V13) |
| TF: nativo sobre `tf-tree` frente a `TfLigero` frente a cinemática local | revisión §5; D3 | `TfLigero` con fuentes locales por defecto; nativo en V13 con la misma API |
| Una base por familia (los cinco contratos de los posts) | D1 | descartada: cinco formas de suscribir, limitar Hz y caducar |
| Material por color con alfa 0,99 como regla (geom#0) | D2 | opción «sombreado» detrás de la misma API; la paleta permite varios colores por malla |
| `viz_shapes` de gdviz adaptado | D2 | descartada (líneas, color por vértice, MultiMesh) |
| `/vita/tf` de 32 marcos a 30 Hz (geom#15/#16) | D3; revisión C4 | ≈ 104 KB/s: él solo pasa del presupuesto |
| Subir el HUD por encima de 400 *quads* | D6 | quita sitio a los sensores 2D; se resuelve con pestañas |
| Subir el tope de instancias o solo vista 2D | D7 | descartado; reparto por perfil |
| Recompilar ya solo para descartar antes de decodificar | D8 | se agrupa en V13 |
| `/vita/catalogo` o `res://ros/catalogo.json` (nucleo#10) | D9 | más contrato para algo que la escena ya dice; `relay_info` puede crecer a catálogo sin cambiar de topic |
| Todo `common_interfaces` en el `.rsch`; fusionar esquemas en ejecución | D10 | descartado; `TIPOS_VISOR` |
| `Label` por marcador (mapas#21); `Label3D` | D11 | descartado; `TextoSuperpuesto` |
| Detecciones fiables directas a ≤ 5 Hz | D12 | exige `vision_msgs` en la Vita y decodificar una `PoseWithCovariance` por hipótesis |
| Miniaturas `mono8`; trocear la imagen en best effort | D13 | 80×60 = 4 848 B, más grande y peor |
| Marcadores de 8 floats (`docs/27:105`); enviar acciones ADD/DELETE | D14 | no ahorra datagramas con el tope de 33; las acciones dejan fantasmas al perderse |
| Addon en `addons/`, `godot/comun/viz/`, `comun/{visor,viz,hmi}/` | D15 | el enlace `comun -> ../plantillas` ya resuelve el reparto |
| Ampliar `/vita/pose2d` a 10 floats (geom#13) | D5.4 | rompe a los clientes actuales; `pose_cov` aparte |
| Detecciones y `/rosout` crudos en best effort | ADR 0013 | una detección ya roza el límite; un aviso perdido no se repite |
| PC: `MultiMeshInstance3D` para nubes y scans | borrador de sensores §4 | `PRIMITIVE_POINTS` + color por vértice (un vértice por punto frente a una instancia con transform); MultiMesh solo para Boxes/Spheres |
| DepthCloud en CPU (como RViz) | sens#14 | GPU con *vertex shader* (cero bucles) |

---

## 12. Autoría

- **Investigación (ronda 1, divergente, 2026-11-13):** cinco investigadores **Opus 5.5** en paralelo —
  `nucleo-generico` (18 fichas), `geometria-tf-robot` (22), `sensores-densos` (15), `mapas-marcadores` (32),
  `hmi-percepcion-acciones` (20); ≈ 107 fichas. Tres cortados por el límite de uso y reanudados sin repetir trabajo.
  `check-only` con el editor de host: HMI 20/20; sensores densos ejecutado con mensajes reales.
- **Revisión (ronda 2):** `esceptico-revisor`, **Opus 5.5** — veredictos de las 107 fichas (76 VERIFICADO,
  18 DESAFÍO, 7 ALTERNATIVA, 6 Por medir), `check-only` de todas (101 PASA, 4 FALLA con corrección comprobada),
  contradicciones C1–C10 y decisiones abiertas D1–D15 (`posts/W13-revision.{json,md}`).
- **Juez:** **Fable 5.2** — sentencia D1–D15, tareas V1–V15 y gates (`posts/W13-juez-fable.md`) y ADR 0013. **Por regla
  del usuario (2026-11-13) las decisiones no se le preguntan: las tomó Fable.**
- **Este documento:** integración (Opus 5.5, 2026-11-13) de fichas, revisión y sentencia; aplica los nombres
  definitivos del ADR 0013 y las cuatro correcciones de `check-only`; donde una ficha contradice la sentencia, se
  indica con «⚖». No se ha ejecutado código nuevo para redactarlo.
