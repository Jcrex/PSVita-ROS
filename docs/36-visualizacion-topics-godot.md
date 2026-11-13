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

### 4.0 Tabla maestra

Columnas: **Display** = archivo bajo `visor/displays/` (o `visor/herramientas/`); **PC / Vita** = capa (3D orbital,
2D planta, 2D superpuesto, HUD, textura); **¿488?** = ¿cabe el mensaje estándar en un datagrama best effort de la
Vita? (B con rosbags); **Ruta Vita** = directo (tipo estándar, con su esquema en `TIPOS_VISOR`) o relay
`<p>/…` (§5); **Hz** = ritmo en la Vita; **Veredicto** = de `W13-revision.json` (V = VERIFICADO, D = DESAFÍO,
A = ALTERNATIVA, M = Por medir) y cómo entra aquí. «`solo_pc`» = el display se desactiva en la Vita.

| # | Tipo ROS | Display | PC | Vita | ¿488? | Ruta Vita | Hz | Veredicto |
|---|---|---|---|---|---|---|---:|---|
| 1 | cualquiera | `hud/inspector_arbol.gd` (`solo_pc`) | HUD `Tree` | — | — | — | — | V nucleo#6 |
| 2 | cualquiera | `hud/inspector_texto.gd` | HUD | HUD pestaña Inspector | según tipo | directo | 4 | M nucleo#7 → G-W13-H0; ⚖ 8 filas × 30 car. |
| 3 | campos numéricos | `hud/trazador.gd` | HUD | HUD pestaña Gráficas | según tipo | directo o `ritmo/<n>` | ≤ 15 | M nucleo#8 → gate de V12; ⚖ 3 × 64 puntos |
| 4 | `std_msgs` escalares (Bool…Float64, String, Empty) | `hud/valor.gd` | HUD | HUD | sí (≤ 12 B + cadena) | directo | 10 | V nucleo#12 (`Empty` [?]) |
| 5 | `std_msgs/*MultiArray` | `hud/multiarray.gd` | HUD (perfil / calor) | HUD | ≤ 118 f32 / 236 i16 | directo | 10 (calor ≤ 4) | V nucleo#13 |
| 6 | `std_msgs/ColorRGBA` | `hud/color.gd` + `PaletaViz.de_ros` | HUD | HUD | sí | directo | — | D nucleo#14 → ⚖ D2 |
| 7 | `std_msgs/Header`, `builtin_interfaces/{Time,Duration}` | `tiempo_ros.gd` (utilidad) | — | — | — | — | — | V nucleo#15 |
| 8 | tipo sin esquema (Vita) | `hud/desconocido.gd` | — | HUD | — | no suscribe | — | V nucleo#11 |
| 9 | (todos) monitor Hz/enlace | `hud/barra_estado.gd` | barra fija | barra fija | — | — | 2 | D nucleo#16 → ⚖ D6 |
| 10 | descubrimiento | `explorador_topics.gd` (`solo_pc`) | grafo cada 2 s | ninguno | — | `relay_info` | — | V nucleo#9; A nucleo#10 → ⚖ D9 |
| 11 | `geometry_msgs/Point(Stamped)` | `3d/punto.gd` | 3D esfera + historial | 3D (pool ≤ cupo) | sí (44) | directo | 10 | V geom#1 |
| 12 | `Vector3(Stamped)` | `3d/vector.gd` | 3D flecha | 3D | sí (52) | directo | 10 | V geom#2 |
| 13 | `Pose(Stamped)` | `3d/pose.gd` · `2d/pose.gd` | 3D flecha/ejes | 2D triángulo (3D opc.) | sí (76) | directo | 10 | V geom#3 |
| 14 | `PoseArray` | `3d/poses.gd` (`solo_pc`) · `2d/poses.gd` | 3D pool | 2D triángulos, 1 lote | n ≤ 8 (28+56n) | relay `poses` (n ≤ 36) | 2 | V geom#4; ⚖ D5 |
| 15 | `PoseWithCovariance(Stamped)` | `3d/covarianza.gd` · `2d/covarianza.gd` | 3D flecha + elipsoide | 2D elipse + abanico | sí (364) | directo o relay `pose_cov` | 2 | V geom#5; ⚖ D5.4 |
| 16 | `Twist`, `Accel`, `Wrench` (+`Stamped`, `WithCovariance`) | `3d/tornillo.gd` | 3D 2 flechas + anillo | 3D (o barras HUD) | sí (52–364) | directo | 10 | V geom#6–8 (código común) |
| 17 | `Quaternion(Stamped)` | `3d/orientacion.gd` | 3D ejes + RPY | igual | sí (60) | directo | 10 | V geom#9 |
| 18 | `Transform(Stamped)` | `3d/transformada.gd` | 3D ejes + flecha | igual | sí (100) | directo | 10 | V geom#10 |
| 19 | `Polygon(Stamped)` | `3d/poligono.gd` (`solo_pc`) · `2d/poligono.gd` | 3D cinta | 2D polilínea | n ≤ 38 (28+12n) | directo | 2 | V geom#11 |
| 20 | `Inertia(Stamped)` | `3d/inercia.gd` | 3D caja + CoM | igual (depuración) | sí (108) | directo | 1 | D geom#12 → `lados: Vector3` |
| 21 | `nav_msgs/Odometry` | `3d/odometria.gd` · `2d/odometria.gd` | 3D flechas (keep) | 2D rastro + triángulo | no (724) | relay `pose2d` | 30 | V geom#13; ⚖ D5.4 |
| 22 | `nav_msgs/Path` | `3d/path.gd` · `2d/path.gd` | 3D cinta | 2D polilínea | no (28+72n) | relay `path_compacto` | 2 | V geom#14 |
| 23 | `tf2_msgs/TFMessage` (display TF) | `3d/tf.gd` | 3D ejes + flechas + nombres | 3D ejes (flechas no) | n ≤ 4 (108·n) | `TfLigero` local; relay `tf` opc. | 10 | D geom#15 → ⚖ D3/D7 |
| 24 | TF en la Vita | `tf_ligero.gd` | — | — | — | local + `tf` opc. | — | A geom#16 → ⚖ D3 |
| 25 | `sensor_msgs/JointState` + URDF | `3d/robot_joints.gd` | 3D robot horneado | igual (LOD Vita) | no (1 668, G1) | relay `joints` + `joints_orden` | 25 | V geom#17 |
| 26 | `Imu` | `3d/imu.gd` | 3D ejes + 2 flechas | igual; 2D brújula | sí (316–324) | directo; `ritmo/imu` si > 30 Hz | 20 | V geom#18 |
| 27 | `MagneticField` | `3d/magnetico.gd` | 3D flecha + rumbo | igual | sí (124) | directo | 10 | V geom#19 |
| 28 | `NavSatFix` | `2d/gps.gd` | 2D rastro ENU (+teselas OSM) | 2D | sí (125) | directo | 5 | V geom#20 |
| 29 | `Range` | `3d/rango.gd` · `2d/rango.gd` | 3D cono α 0,5 | 3D cono opaco o sector 2D | sí (52) | directo | 10 | V geom#21 |
| 30 | `Temperature`, `FluidPressure`, `Illuminance`, `RelativeHumidity` | `hud/medidor.gd` | HUD | HUD pestaña Estado | sí (44) | directo | 4 | V hmi#3–6 |
| 31 | `BatteryState` | `hud/bateria.gd` | barra fija | barra fija | sí (89–133) | directo | ≤ 1 | V hmi#2 |
| 32 | `Joy` | `hud/joy.gd` (+ fuente `/vita/joy`) | HUD | HUD | sí (128) | directo | 20 | V hmi#1 |
| 33 | `LaserScan` | `3d/scan_puntos.gd` (`solo_pc`) · `2d/scan.gd` | 3D puntos | 2D 1 lote | ≤ 107 rayos | relay `scan_compacto` | 10 | V sens#0; D sens#1 → ⚖ D4 |
| 34 | `MultiEchoLaserScan` | `3d/scan_multieco.gd` (`solo_pc`) | aplanar a LaserScan | — | no | relay `scan_compacto` (eco elegido en el relay) | 10 | V sens#2 |
| 35 | `PointCloud2` | `3d/nube_puntos.gd` (`solo_pc`) · `2d/nube.gd` | 3D puntos (GPU si > 50 k) | 2D por bandas | no | relay `nube2d` (n ≤ 76 × 3) | 5 | V sens#3; A sens#4 → ⚖ D5 |
| 36 | `PointCloud` (obsoleto) | convertir fuera de Godot | — | — | no | relay | — | V sens#5 |
| 37 | `Image` 8 bit (rgb8, rgba8, bgr8, bgra8, mono8, 8UC1/3, bayer_*8) | `hud/imagen.gd` (`solo_pc`) | textura + *shader* | — | no | relay `camara/compressed` | 3 | V sens#6 |
| 38 | `Image` profundidad (16UC1, mono16, 32FC1) | `hud/imagen.gd` (`solo_pc`) | R16/RF + *shader* | — | no | relay `camara/compressed` | 3 | D sens#7 → sin código propio; 16SC1 por resolver |
| 39 | `Image` yuv422/uyvy/yuyv | `hud/imagen_yuv.gd` (`solo_pc`) | RGBA8 w/2 + *shader* | — | no | relay | 3 | V sens#8 |
| 40 | `Image` en la Vita | — | — | HUD pestaña Cámara | no | relay `camara/compressed` | 3 | D sens#9 → ⚖ D13 |
| 41 | `CompressedImage` jpeg/png | `hud/imagen_comprimida.gd` | HUD | HUD | solo JPEG ≤ 452 | relay `camara/compressed` (fiable) | 3 | V sens#10 |
| 42 | `CompressedImage` compressedDepth | republicar fuera de Godot | — | — | no | relay | — | V sens#11 |
| 43 | `CameraInfo` | `3d/camara_info.gd` | 3D frustum líneas | 3D prismas o 2D | sí (357–381) | directo | 1 | D sens#12 → corrección |
| 44 | «Camera» (imagen + escena) | `hud/camara.gd` (`solo_pc`) | SubViewport | «modo cámara» | — | — | — | M sens#13 |
| 45 | DepthCloud | `3d/nube_profundidad.gd` (`solo_pc`) | GPU (*vertex shader*) | — | no | relay `nube2d` | — | V sens#14 |
| 46 | `OccupancyGrid` «map» | `3d/mapa.gd` · `2d/mapa.gd` | 3D quad + *shader* | textura (planta o quad) | no | relay `mapa_meta` + `mapa_tesela` | ≤ 20 teselas/s | V mapas#0 |
| 47 | `OccupancyGrid` «costmap» | mismo, paleta costmap | 3D *shader* | compuesto sobre el mapa | no | relay `costmap_meta` + `costmap_tesela` | ≤ 10 | V mapas#1 (V11) |
| 48 | `OccupancyGrid` «raw» | mismo, paleta gris (`solo_pc`) | 3D | — | no | — | — | V mapas#2 |
| 49 | `map_msgs/OccupancyGridUpdate` | en `mapa.gd` | `blit_rect` | teselas sucias del relay | ≤ 21×21 | relay (época fija) | — | D mapas#3 → ⚖ D5.5 |
| 50 | `nav_msgs/GridCells` | `3d/celdas.gd` (`solo_pc`) · `2d/celdas.gd` | MultiMesh | 2D 1 lote | n ≤ 18 | directo | 2 | V mapas#4 |
| 51 | `nav_msgs/MapMetaData` | `hud/meta_mapa.gd` | HUD | HUD | sí (84) | directo F+TL | — | V mapas#5 |
| 52 | `nav2_msgs/Costmap` (raw) | en `mapa.gd` (`solo_pc`) | R8 + paleta | — | no | relay `costmap` | — | V mapas#6 |
| 53 | `nav2_msgs/VoxelGrid` | `3d/voxeles.gd` (`solo_pc`) | MultiMesh | — | no | relay `nube2d` | — | V mapas#7 |
| 54 | `grid_map_msgs/GridMap` | `3d/grid_map.gd` (`solo_pc`, V14) | malla de alturas | — | no | relay (por diseñar) | — | V mapas#8 |
| 55 | `octomap_msgs/Octomap` | `3d/octomap.gd` (`solo_pc`, V14) | MultiMesh | — | no | relay (por diseñar) | — | V mapas#9 |
| 56 | `visualization_msgs/Marker` (gestor) | `3d/marcadores.gd` | 3D/2D | 3D sólidos, 2D líneas | ≤ 10 puntos (229–469) | directo o relay `marcadores` | 5 | D mapas#10 → `var tf = null` |
| 57 | Marker ARROW (pose/puntos), CUBE, SPHERE, CYLINDER | `fabrica_marcadores.gd` | 3D instancia | 3D instancia + paleta | sí (229/277) | directo / `marcadores` | 5 | V mapas#11–15 |
| 58 | Marker LINE_STRIP / LINE_LIST | `2d/marcadores_2d.gd` (Vita) · cinta/prisma (PC) | 3D prismas | 2D superpuesto | ≤ 10 puntos | `marcador_puntos` | ≤ 4 trozos/s | V mapas#16–17 |
| 59 | Marker CUBE_LIST / SPHERE_LIST | PC MultiMesh (`solo_pc`); Vita horneado ≤ 64 o 2D | 3D | 3D horneado / 2D | ≤ 10 | `marcador_puntos` | ≤ 1 | V mapas#18–19 |
| 60 | Marker POINTS | `2d/marcadores_2d.gd` | 2D o MultiMesh | 2D 1 lote | ≤ 10 | `marcador_puntos` | — | V mapas#20 |
| 61 | Marker TEXT_VIEW_FACING | `TextoSuperpuesto` | `draw_string` (o `Label3D` `solo_pc`) | `draw_string` | sí (249) | `marcador_texto` | ≤ 2 | D mapas#21 → ⚖ D11 |
| 62 | Marker MESH_RESOURCE | `fabrica_marcadores.gd` | tabla `package://`→`res://`, GLTF en caliente | solo horneadas | sí (URI) | directo | — | V mapas#22 (gltf Vita [?]) |
| 63 | Marker TRIANGLE_LIST | `fabrica_marcadores.gd` | ArrayMesh | ArrayMesh + paleta | ≤ 3 tri | relay | ≤ 1 | V mapas#23 |
| 64 | Marker ARROW_STRIP (12, Jazzy) | `fabrica_marcadores.gd` | tira + punta | igual | — | — | — | V mapas#24 (semántica [?]) |
| 65 | `MarkerArray` | `3d/marcadores.gd` + cliente compacto | gestor | estado completo | no (50 CUBE = 11 605) | relay `marcadores` (≤ 33) | 5 | A mapas#25 → ⚖ D14 |
| 66 | `InteractiveMarker(Update)` | `3d/im_cliente.gd` (`solo_pc`, V14) | asas | aplazado | update 132 | — | — | D mapas#26 → preload + sin tipo |
| 67 | `InteractiveMarkerFeedback` | `herramientas/im_feedback.gd` (`solo_pc` hasta V14) | ratón | (aplazado) | sí (149–157) | directo **fiable** | ≤ 20 | D mapas#27 → `pulsado: bool` + ⚖ C9 |
| 68 | `ImageMarker` | `hud/marcas_imagen.gd` | HUD sobre imagen | igual | ≤ 15 puntos | directo | 5 | V mapas#28 |
| 69 | `shape_msgs/{SolidPrimitive,Mesh,Plane}` | `fabrica_marcadores.gd` | 3D | 3D estático | depende | relay / horneado | — | V mapas#29–31 |
| 70 | `diagnostic_msgs/DiagnosticArray` | `hud/diagnostico.gd` | HUD (o `Tree`) | pestaña Diagnóstico | 1–2 estados | relay `diagnostics` | ≤ 10 | M hmi#7 → G-W13-H0; ⚖ 8 filas |
| 71 | `rcl_interfaces/Log` | `hud/consola.gd` | HUD | pestaña Consola | casi siempre | relay `rosout` (fiable) | ≤ 10 | M hmi#8 → G-W13-H0; ⚖ 6 líneas × 40 |
| 72 | `lifecycle_msgs/TransitionEvent` | `hud/lifecycle.gd` | HUD | pestaña Estado | sí (65) | directo fiable | evento | V hmi#9 |
| 73 | `vision_msgs/Detection2DArray` | `hud/cajas_2d.gd` | HUD sobre imagen | pestaña Cámara | 1 det. (449–474) | relay `detecciones` (n ≤ 18) | 5 | D hmi#10 → ⚖ D12 |
| 74 | `vision_msgs/Detection3DArray` | `2d/cajas_3d.gd` (superpuesto) | 2D superpuesto | igual | no (485–505) | relay `detecciones3d` (n ≤ 12) | 5 | D hmi#11 → ⚖ D12 |
| 75 | `trajectory_msgs/JointTrajectory` | `3d/fantasma.gd` | 3D 2.º robot | robot oculto o brazo ≤ 8 | 1 punto (228) | puente `/vita/accion/trayectoria` | — | M hmi#12 → ⚖ D7 |
| 76 | `control_msgs/JointTrajectoryControllerState` | `hud/controlador.gd` | HUD | pestaña Controlador (14 juntas) | no (1 340–2 404) | directo fiable | ≤ 5 | V hmi#13 (`get_member("reference")`) |
| 77 | `nav_msgs/Path` plan frente a real | `2d/plan_real.gd` | 2D | 2D | no | relay `path_compacto` + `pose2d` | 2 / 30 | D hmi#14 → ⚖ D5.4 (+ marco por resolver) |
| 78 | `action_msgs/GoalStatusArray` + feedback Nav2 | `hud/estado_meta.gd` | barra fija | barra fija | sí (33–453 / 116) | nivel 0 directo o `/vita/accion/estado` | 5 | V hmi#15 |
| 79 | Nav2 Goal → `PoseStamped` `/goal_pose` | `herramientas/meta.gd` | ratón | táctil + ✕ | sí (76) | publica directo fiable | evento | V hmi#16 |
| 80 | 2D Pose Estimate → `PoseWithCovarianceStamped` `initialpose` | `herramientas/pose_inicial.gd` | ratón | táctil + ✕ | sí (364) | publica directo fiable | evento | V hmi#17 |
| 81 | Publish Point → `PointStamped` `/clicked_point` | `herramientas/punto.gd` | ratón | táctil | sí (44) | publica directo fiable | evento | V hmi#18 |
| 82 | Teleop → `Twist` `/cmd_vel` | `herramientas/teleop.gd` | teclado | stick + R | sí (52) | directo fiable; `/vita/mando` con robots reales | 20 | V hmi#19 |

Correcciones de cifras que aplica la tabla (⚖ D4/C6): «LaserScan: 106 rayos» y «Detection3DArray no cabe por 1 B»
eran artefactos de contar o no la encapsulación; da igual en la práctica porque los dos van por el relay. CameraInfo
plumb_bob = 357 B con frame `camera` (no 381; depende del frame). Detection2DArray de 1 detección = 449/465/474 B
según frame y clase (el post decía 481) (`W13-revision.md` §3.2) [V].

Plantilla de cada subsección: **Representación** · **Campos** (campo ROS → dato Godot) · **`@export` propios**
(además de los comunes, §2.3) · **Vita** · **Veredicto** · esqueleto. Los esqueletos solo muestran lo propio del
display (los `@export` comunes y la mecánica vienen de la base). Ruta de `extends`: `res://comun/visor/display_ros_3d.gd`
(3D), `…/display_ros_2d.gd` (2D), `…/display_ros_hud.gd` (HUD).

### 4.1 Genéricos y `std_msgs` (familia `nucleo-generico`)

#### 4.1.1 Introspección (`introspeccion_ros.gd`) — V nucleo#0

Representación: utilidad estática; lista de campos por tipo, calculada **una vez** sobre un prototipo vacío; lectura
de rutas con `get_member`. Coste por mensaje 0 (caché). Se copia de la ficha cambiando solo la ruta.

```gdscript
extends RefCounted
## Campos de un RosMsg, portable rclgd (dinámico o tipado) ↔ ros2_vita (dinámico).
const _OMITIR := {"script": true}
const _NO_CAMPO := PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP
static var _cache := {}

static func campos_de_tipo(tipo: String) -> PackedStringArray:
	if _cache.has(tipo):
		return _cache[tipo]
	var out := PackedStringArray()
	var proto = RosMsg.from_type(tipo)
	if proto == null:
		return out
	var clase: String = proto.get_class()
	var lista: Array = ClassDB.class_get_property_list(clase, true) if clase != "RosMsg" else proto.get_property_list()
	for p in lista:
		if p.usage & _NO_CAMPO or _OMITIR.has(p.name):
			continue
		out.append(p.name)
	_cache[tipo] = out
	return out

static func campos(msg) -> PackedStringArray:
	return campos_de_tipo(msg.get_ros_interface_name())

## Ruta troceada: ["twist", "twist", "linear", "x"] o ["poses", "3", "pose"].
static func leer_ruta(msg, ruta: PackedStringArray):
	var v = msg
	for paso in ruta:
		if v is RosMsg:
			v = v.get_member(StringName(paso))
		elif typeof(v) >= TYPE_ARRAY and paso.is_valid_int() and paso.to_int() < v.size():
			v = v[paso.to_int()]
		else:
			return null
	return v
```

#### 4.1.2 Inspector en árbol (`hud/inspector_arbol.gd`, `solo_pc`) — V nucleo#6

Representación: `Tree` de dos columnas (campo, valor), construido **perezosamente** (solo baja a lo desplegado),
actualizado en sitio por ruta a ≤ 5 Hz; arrays truncados a `limite_array` con fila «… N elementos»; `uint8[]` como
tamaño + primeros bytes. `@export`: `limite_array` (32), `hz` = 5. Vita: no (cada glifo es un *quad* recalculado cada
fotograma, H16; 20 filas × 30 car. ≈ 600 *quads* > HUD entero) [I]. El código de la ficha se usa tal cual con dos
cambios: `extends Tree` pasa a ser un `Tree` **hijo** de un `DisplayRosHud` con `solo_pc = true` (la base no puede
ser `Tree` y `Control` a la vez), y `mostrar(msg)` se llama desde `_pintar(datos)` con `datos = msg`. Limitación
conocida: si un array encoge, las filas sobrantes no se ocultan (barrer `_filas` por prefijo).

#### 4.1.3 Inspector de texto (`hud/inspector_texto.gd`) — M nucleo#7 → G-W13-H0

Representación: filas planas «sangría campo: valor» con `draw_string` en `_draw()`, solo si cambia el texto; cruceta
arriba/abajo = desplazar, derecha/izquierda = desplegar/plegar. ⚖ D6: en la Vita, **8 filas × 30 caracteres** a
4 Hz (pestaña Inspector), no 12 × 32 como proponía la ficha; los límites son de partida hasta G-W13-H0.

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## Inspector de texto (Vita y PC): filas planas con draw_string, ≤ 4 Hz, solo si cambian.
const Intro = preload("res://comun/visor/introspeccion_ros.gd")
@export var filas := 8
@export var ancho_max := 30
var desplegados := {}
var _lineas := PackedStringArray()
var _primera := 0

func _init() -> void:
	hz = 4.0
	hz_vita = 4.0
	caducidad_s = 0.0

func _procesar(msg):
	var out := PackedStringArray()
	_aplanar(msg, "", 0, out)
	return null if out == _lineas else out          # null = no redibujar

func _pintar(d) -> void:
	_lineas = d
	queue_redraw()

func _aplanar(m, ruta: String, nivel: int, out: PackedStringArray) -> void:
	for c in Intro.campos(m):
		var v = m.get_member(c)
		var r := ruta + "/" + c
		out.append(("  ".repeat(nivel) + "%s: %s" % [c, _corto(v)]).left(ancho_max))
		if v is RosMsg and desplegados.has(r):
			_aplanar(v, r, nivel + 1, out)

func _corto(v) -> String:
	if v is RosMsg:
		return "{…}"
	if typeof(v) >= TYPE_ARRAY:
		return "%s[%d] %s" % [type_string(typeof(v)), v.size(), str(v.slice(0, 4))]
	return "%.3f" % v if v is float else str(v)

func _draw() -> void:
	var f := get_theme_default_font()
	for i in mini(filas, _lineas.size() - _primera):
		draw_string(f, Vector2(4, 16 + 16 * i), _lineas[_primera + i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				color_estado(Color.WHITE))

func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": filas * ancho_max}   # 240 = una pestaña entera
```

`slice(0, 4)` evita convertir arrays grandes en GDScript (en rclgd el array ya se copió entero al hacer
`get_member`) [I].

#### 4.1.4 Trazador de series (`hud/trazador.gd`) — M nucleo#8 → gate de V12

Representación: hasta 3 series (rutas de campo del **mismo** topic) en búferes circulares `PackedVector2Array` de
(t, y) en unidades de datos; el dibujo no recorre puntos en GDScript: `draw_set_transform` hace el mapeo a píxeles en
el C++ del lienzo y cada serie es una `draw_polyline(..., -1)` = 1 comando (H17). ⚖ D6: **3 series × 64 puntos** en
la Vita (la ficha proponía 300). Rutas con la sintaxis de Foxglove (`/odom.twist.twist.linear.x`: el punto no
puede aparecer en un nombre de topic); la de rqt_plot (`/odom/twist/...`) solo en el PC resolviendo el prefijo más
largo con el grafo. Para series de varios topics: un trazador por topic, superpuestos en la pestaña.
Gate (ficha y V12): pestaña Gráficas con 3 series → `draws` +≤ 3 y `avg_canvas_us` +≤ 300; duda [I]: que la
polilínea fina siga siendo de 1 px con `draw_set_transform` escalado y que el port la dibuje en un lote.

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## Trazador (rqt_plot / Foxglove Plot). `campos` = rutas dentro del mensaje de `topic`. Sin bucles por punto al dibujar.
const Intro = preload("res://comun/visor/introspeccion_ros.gd")
@export var campos: PackedStringArray = ["twist.twist.linear.x"]
@export var ventana_s := 10.0
@export var capacidad := 64
@export var colores := PackedColorArray([Color.ORANGE, Color.CYAN, Color.LIME])
var _series := []                 # {ruta: PackedStringArray, pts: PackedVector2Array, cab: int, n: int}
var _y_min := INF
var _y_max := -INF

func conectar(v) -> void:
	canal.coalescer = false       # el trazador necesita todas las muestras
	for c in campos.slice(0, 3):
		var pts := PackedVector2Array()
		pts.resize(capacidad)
		_series.append({"ruta": c.replace("[", ".").replace("]", "").split("."), "pts": pts, "cab": 0, "n": 0})
	super.conectar(v)

func _procesar(msg):
	var t := Time.get_ticks_msec() * 0.001
	for s in _series:
		var v = Intro.leer_ruta(msg, s.ruta)
		if not (v is float or v is int or v is bool):
			continue
		var y := float(v)
		s.pts[s.cab] = Vector2(t, y)
		s.cab = (s.cab + 1) % capacidad
		s.n = mini(s.n + 1, capacidad)
		_y_min = minf(_y_min, y)
		_y_max = maxf(_y_max, y)
	return true

func _draw() -> void:
	var ahora := Time.get_ticks_msec() * 0.001
	var esc := Vector2(size.x / ventana_s, -size.y / maxf(_y_max - _y_min, 1e-6))
	draw_set_transform(Vector2(size.x - ahora * esc.x, size.y - _y_min * esc.y), 0.0, esc)
	for k in _series.size():
		var s = _series[k]
		var orden: PackedVector2Array = s.pts.slice(s.cab) + s.pts.slice(0, s.cab) if s.n == capacidad else s.pts.slice(0, s.n)
		if orden.size() > 1:
			draw_polyline(orden, color_estado(colores[k % colores.size()]), -1.0)

func _coste() -> Dictionary:
	return {"instancias": 0, "triangulos": 0, "quads": 3 * capacidad + 20}   # [I] hasta G-W13-H0
```

El tiempo relativo al arranque en `Vector2` (float32) tiene resolución ≈ 0,25 ms a 1 h [I].

#### 4.1.5 Escalares de `std_msgs` (`hud/valor.gd`) — V nucleo#12

Representación: texto «nombre: valor unidad»; `Bool` → cuadro verde/rojo; `Empty` → contador de eventos; `Char` →
número y carácter; `String` recortado a 64. Campos: `data` → bool/int/float/String; `std_msgs` no lleva unidades
(`@export unidad`). `@export`: `unidad`, `decimales` (3). Vita: ≤ 12 B + cadena; en `generar_esquemas.py:13-14` solo
están `Bool` y `String` [V]: el resto entra por `TIPOS_VISOR` (D10). `Empty` [?]: msg-schema rechaza tipos sin campos;
depende del miembro de relleno de rosbags → fuera de `TIPOS_VISOR` hasta probarlo (§9.3).

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## Valor escalar de std_msgs (Bool, Int*, UInt*, Float*, Byte, Char, String, Empty).
@export var unidad := ""
@export var decimales := 3
var _eventos := 0

func _procesar(msg):
	if tipo == "std_msgs/msg/Empty":
		_eventos += 1
		return ["%d eventos" % _eventos, null]
	var v = msg.data
	if v is bool:
		return ["", Paleta.OK if v else Paleta.ERROR]
	if v is float:
		return [String.num(v, decimales) + " " + unidad, null]
	if tipo == "std_msgs/msg/Char":
		return ["%d '%s'" % [v, String.chr(v)], null]
	return [str(v).left(64) + " " + unidad, null]

func _draw() -> void:
	if datos == null:
		return
	var x := 4.0
	if datos[1] != null:
		draw_rect(Rect2(2, 2, 12, 12), color_estado(datos[1]))
		x = 18.0
	draw_string(get_theme_default_font(), Vector2(x, 13), "%s: %s" % [topic.get_file(), datos[0]],
			HORIZONTAL_ALIGNMENT_LEFT, size.x - x, 12, color_estado(Color.WHITE))

func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 30}
```

#### 4.1.6 `*MultiArray` (`hud/multiarray.gd`) — V nucleo#13

Representación: 0–1 dimensiones → perfil (polilínea fina de `data` frente al índice, 1 comando, escala por
`draw_set_transform`); 2 dimensiones → mapa de calor como textura (`Image L8`, filtro POINT) a ≤ 4 Hz; ≥ 3 →
inspector. Si el topic es un formato del relay, el registro elige antes el display específico. Campos:
`layout.dim[k].size/stride/label`, `layout.data_offset`, `data` (Packed*); 2D fila-mayor:
`data[ofs + r·dim[1].stride + c]`. `@export`: `max_puntos` (128), `mapa: TextureRect`. Vita: formato base del relay,
el más barato de recibir (H25); convertir a puntos es un bucle GDScript acotado por `max_puntos` (≈ 0,8 ms [I]); el
calor reutiliza `ImageTexture.update` (H19), no crea textura por mensaje (corrección de la propia ficha). El esqueleto
de la ficha vale con `_procesar` devolviendo `[_pts, _min, _max]` (o el `Image` en 2D) y `_draw()` sin cambios.

#### 4.1.7 `ColorRGBA` (`hud/color.gd`) — D nucleo#14 → ⚖ D2

Muestra de color + `#rrggbbaa`. Las utilidades `color_ros`/`indice_paleta` de la ficha **no** van aquí: son
`PaletaViz.de_ros(c)` y `PaletaViz.indice(c)` (§3.3), que usan Marker, MarkerArray y todo lo 3D. En la Vita el
color 3D sale de la paleta (H3); en 2D el color por primitiva es gratis (H16).

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
func _procesar(msg): return Paleta.de_ros(msg)
func _draw() -> void:
	if datos == null: return
	draw_rect(Rect2(2, 2, size.y - 4, size.y - 4), datos)
	draw_string(get_theme_default_font(), Vector2(size.y + 2, 13), "#" + (datos as Color).to_html(true))
```

#### 4.1.8 `Header`, `Time`, `Duration` (`tiempo_ros.gd`) — V nucleo#15

Sin display propio: el `frame_id` lo consumen las bases (TF) y el `stamp`, la latencia de la barra fija. En la Vita
`now()` es la hora del agente tras `uxr_sync_session`; si falla, reloj local y la latencia no tiene sentido. Sin
`use_sim_time` (⏳): con `/clock` de simulación la latencia es basura → se oculta si |latencia| > 1 h [I].

```gdscript
extends RefCounted
## Tiempo ROS (builtin_interfaces/Time y Duration) y Header, portable rclgd ↔ ros2_vita.
static func segundos(t) -> float:
	return float(t.sec) + float(t.nanosec) * 1e-9

static func a_texto(t) -> String:
	return "%d.%09d" % [t.sec, t.nanosec]

## Latencia (now − header.stamp) en s; NAN si el sello es 0 o absurdo (sim_time, sin sincronía).
static func latencia(nodo, msg) -> float:
	if not ("header" in msg):
		return NAN
	var st = msg.header.stamp
	if st.sec == 0 and st.nanosec == 0:
		return NAN
	var l := segundos(nodo.now()) - segundos(st)
	return l if absf(l) < 3600.0 else NAN

static func escribir_tiempo(t, s: float) -> void:
	t.sec = int(floor(s))
	t.nanosec = int((s - floor(s)) * 1e9)
```

#### 4.1.9 Tipo sin esquema (`hud/desconocido.gd`) — V nucleo#11

La base ya no suscribe si `RosMsg.from_type(tipo) == null` (estado «sin esquema: …», §2.9.2). Este widget solo
pinta `topic`, `tipo` y el `estado` con la pista «añadir a `TIPOS_VISOR` en `generar_esquemas.py`». Coste 0 si no
suscribe; con suscripción y sin esquema, hoy sería un `ERR_FAIL_COND` por muestra (spam de log).

#### 4.1.10 Monitor de topics → barra fija (`hud/barra_estado.gd`) — D nucleo#16 → ⚖ D6

⚖ El monitor de nucleo#16 **no es una pieza aparte**: enlace y Hz van en la barra fija (≤ 120 *quads* con batería,
meta y herramienta activa); el detalle por display es una vista de la pestaña Estado. Fuentes: `canal.hz_medido` y
`estado` de cada display del grupo `display_ros`; `rclgd.get_transport_info()` (solo `ros2_vita`: `be_pending`,
`be_dropped`, reconexiones…) por `has_method` + `call`; `<p>/relay_bw` (existe) para los bytes del relay. Sin
contadores por suscripción hasta V13 (P2). Refresco 2 Hz.

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## Barra fija: enlace XRCE + Hz del display vigilado + herramienta activa (la batería y la meta son widgets hermanos).
@export var vigilado: Node                 # display cuyo Hz se muestra (p. ej. el scan)
var herramienta := ""
var _t := 0.0
var _texto := ""

func _process(dt: float) -> void:
	_t += dt
	if _t < 0.5 or visor == null:
		return
	_t = 0.0
	var enlace := "PC"
	if rclgd.has_method("get_transport_info"):
		var info: Dictionary = rclgd.call("get_transport_info")
		enlace = "XRCE perd %s" % str(info.get("be_dropped", "?"))
	var hz_txt := "" if vigilado == null else "%s %.0f Hz" % [vigilado.name, vigilado.canal.hz_medido]
	var nuevo := "%s · %s · %s" % [enlace, hz_txt, herramienta]
	if nuevo != _texto:
		_texto = nuevo
		queue_redraw()

func _draw() -> void:
	draw_string(get_theme_default_font(), Vector2(4, 16), _texto, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 12)

func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 50}
```

#### 4.1.11 Descubrimiento — V nucleo#9 (PC) · A nucleo#10 → ⚖ D9 (Vita)

PC: `explorador_topics.gd` (`solo_pc`) de la ficha nucleo#9 tal cual: sondea `get_topic_names_and_types()` cada 2 s
(con `RosTimer`), emite `topic_nuevo`/`topic_perdido`, y `RegistroDisplays.crear()` añade displays **sin guardarlos**.
Vita: ninguno. El cliente de `/vita/catalogo` de nucleo#10 se descarta (⚖ D9); `relay_info` (`VC/1.2;módulos`)
basta para distinguir «sin datos» de «módulo apagado».

### 4.2 `geometry_msgs` (familia `geometria-tf-robot`)

Representación común: un `Node3D` por display, visuales creados **una vez** en `conectar()` (pool del tamaño del
cupo), movidos por `transform`. La base ya coloca el nodo en el marco del mensaje (`transform = marco`), así que
los visuales llevan transformaciones **locales** al frame del header. Capa por defecto `"poses"` (cupo HMI 4 /
Viz 16) salvo que se diga. Lo que vive en el suelo tiene además versión 2D (planta), la de por defecto en la Vita.
Esquemas: `PointStamped`, `Vector3Stamped`, `PoseArray`, `PoseWithCovarianceStamped`, `WrenchStamped`,
`AccelStamped`, `QuaternionStamped`, `PolygonStamped` entran en `TIPOS_VISOR` (D10); `Pose(Stamped)`, `Twist(Stamped)`,
`TransformStamped`, `Imu`, `MagneticField`, `NavSatFix`, `Range`, `TFMessage` ya están en `generar_esquemas.py:12-40`
[V].

#### 4.2.1 `Point` / `PointStamped` (`3d/punto.gd`) — V geom#1

Esfera (octaedro en la Vita) por punto con historial circular (RViz *History Length*); `Point` sin header se pinta
en `frame_id`. Campos: `point.x/y/z` (m) → `ros_to_godot_vector`. `@export`: `radio` (0,1; RViz 0,2), `historial`
(10), `color`. 44 B; contraparte que publica: herramienta Publish Point (§4.8).

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var radio := 0.1
@export var historial := 10
@export var color := Color(1.0, 0.0, 1.0)
var _pool: Array[MeshInstance3D] = []
var _i := 0

func _init() -> void:
	capa = "poses"

func conectar(v) -> void:
	super.conectar(v)
	for k in cupo:
		var e := Prim.instancia(Prim.ESFERA, color)
		e.visible = false
		e.top_level = true                       # el historial se queda en el mundo aunque el marco se mueva
		add_child(e)
		_pool.append(e)

func _procesar(msg):
	var p = msg.point
	return rclgd.ros_to_godot_vector(Vector3(p.x, p.y, p.z))

func _pintar(pos) -> void:
	if _pool.is_empty():
		return
	var e := _pool[_i]
	_i = (_i + 1) % _pool.size()
	e.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * radio * 2.0), global_transform * (pos as Vector3))
	e.visible = true

func _coste() -> Dictionary: return {"instancias": historial, "triangulos": 8 * historial, "quads": 0}
```

#### 4.2.2 `Vector3` / `Vector3Stamped` (`3d/vector.gd`) — V geom#2

Flecha desde el origen del frame, largo = |v| × `escala`; oculta si |v| < umbral (`looking_at` con vector nulo da
error). Sin display en RViz de serie [V]. Serie temporal opcional con el trazador. `@export`: `escala`, `color`.
52 B, 24 tri, 1 *draw*.

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var escala := 1.0
@export var color := Color(0.2, 0.6, 1.0)
var _f: MeshInstance3D
func conectar(v) -> void:
	super.conectar(v)
	_f = Prim.instancia(Prim.FLECHA, color)
	add_child(_f)
func _procesar(msg):
	return rclgd.ros_to_godot_vector(Vector3(msg.vector.x, msg.vector.y, msg.vector.z)) * escala
func _pintar(v) -> void:
	var t = Prim.flecha_hacia(v)
	_f.visible = t != null
	if t != null:
		_f.transform = t
func _coste() -> Dictionary: return {"instancias": 1, "triangulos": 24, "quads": 0}
```

#### 4.2.3 `Pose` / `PoseStamped` (`3d/pose.gd`, `2d/pose.gd`) — V geom#3

3D: flecha (o ejes) en la pose, escalada por `largo` (RViz *Shaft Length* 1 + *Head* 0,3). 2D: triángulo orientado
por el yaw (`draw_colored_polygon`, patrón validado de `godot/g6-hmi/main.gd:182` y del minimapa). 76 B, 60 Hz posibles
(`docs/27:81`). La Vita también **publica** `PoseStamped` (meta, §4.8).

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export_enum("flecha", "ejes") var forma := "flecha"
@export var largo := 1.0
@export var color := Color(1.0, 0.1, 0.0)
var _vis: MeshInstance3D
func conectar(v) -> void:
	super.conectar(v)
	_vis = Prim.instancia(Prim.FLECHA if forma == "flecha" else Prim.EJES, color)
	add_child(_vis)
func _procesar(msg): return Prim.pose_godot(msg.pose)
func _pintar(t) -> void: _vis.transform = (t as Transform3D).scaled_local(Vector3.ONE * largo)
func _coste() -> Dictionary: return {"instancias": 1, "triangulos": 36, "quads": 0}
```

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## Pose en planta: triángulo orientado (g6-hmi/main.gd:182). datos = [Vector2 m, yaw].
@export var lado_px := 10.0
@export var color := Color(1.0, 0.1, 0.0)
var _p := Vector2.ZERO
var _yaw := 0.0
func _procesar(msg):
	var o = msg.pose.orientation
	var yaw := atan2(2.0 * (o.w * o.z + o.x * o.y), 1.0 - 2.0 * (o.y * o.y + o.z * o.z))   # util_ros.gd yaw_de_quat
	return [Vector2(msg.pose.position.x, msg.pose.position.y), yaw]
func _pintar(d) -> void:
	_p = px(d[0])
	_yaw = d[1]
	queue_redraw()
func _draw() -> void:
	var f := Vector2(cos(_yaw), -sin(_yaw))            # yaw ROS en la planta (y hacia abajo)
	var l := Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([_p + f * lado_px, _p - f * lado_px * 0.6 + l * lado_px * 0.6,
			_p - f * lado_px * 0.6 - l * lado_px * 0.6]), color)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 1}
```

#### 4.2.4 `PoseArray` (`3d/poses.gd` `solo_pc`, `2d/poses.gd`) — V geom#4 → relay `poses` (⚖ D5)

PC: pool de flechas reutilizado (las sobrantes se ocultan). Vita: 28 + 56·n B ⇒ n ≤ 8 en directo; ⚖ D5: lo normal es
el relay `<p>/poses` = cabecera común + `[x, y, yaw]·n`, **n ≤ 36** (464 B, diezmado; la ficha decía ≤ 39 sin
cabecera), 2 Hz, pintado en 2D como triángulos en **un** lote (H16–H17). Nota [I]: la nube de AMCL en Jazzy es
`nav2_msgs/ParticleCloud` (con pesos), no `PoseArray`: el módulo `poses` del relay acepta los dos.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## PoseArray en planta: un triángulo por pose en UNA llamada. datos = PackedVector3Array (x, y, yaw) en m.
@export var lado_px := 6.0
@export var color := Color(1.0, 0.1, 0.0)
var _v := PackedVector2Array()
var _c := PackedColorArray()
var _idx := PackedInt32Array()
func _init() -> void:
	capa = "sensores_2d"
func _procesar(msg):
	var out := PackedVector3Array()
	for p in msg.poses:
		var o = p.orientation
		out.append(Vector3(p.position.x, p.position.y, atan2(2.0 * (o.w * o.z + o.x * o.y), 1.0 - 2.0 * (o.y * o.y + o.z * o.z))))
	return out
func _procesar_compacto(msg):                       # <p>/poses: [seq, trozo, n_trozos, n, (x, y, yaw)·n]
	var d: PackedFloat32Array = msg.data
	var out := PackedVector3Array()
	if d.size() < 4:
		return null
	for i in mini(int(d[3]), (d.size() - 4) / 3):
		out.append(Vector3(d[4 + 3 * i], d[5 + 3 * i], d[6 + 3 * i]))
	return out                                      # n ≤ 36 cabe en un trozo: sin ensamblar
func _pintar(poses) -> void:
	_v.resize(0)
	_c.resize(0)
	for q in poses:
		var p := px(Vector2(q.x, q.y))
		var f := Vector2(cos(q.z), -sin(q.z)) * lado_px
		var l := Vector2(-f.y, f.x) * 0.5
		_v.append_array([p + f, p - f * 0.5 + l, p - f * 0.5 - l])
		_c.append_array([color, color, color])
	if _idx.size() != _v.size():
		_idx = PackedInt32Array(range(_v.size()))
	queue_redraw()
func _draw() -> void:
	if _v.size() > 0:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _v, _c)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 100}   # «poses y odometría ≤ 100»
```

La versión 3D del PC es el código de geom#4 (pool de `Prim.instancia(Prim.FLECHA, color)`, `transform =
Prim.pose_godot(poses[i]).scaled_local(Vector3.ONE * largo)`), con `@export maximo` (200).

#### 4.2.5 `PoseWithCovariance(Stamped)` (`3d/covarianza.gd`, `2d/covarianza.gd`) — V geom#5; relay `pose_cov` (⚖ D5.4)

Representación (algoritmo de `covariance_visual.cpp`): flecha de la pose + elipse/elipsoide de posición con semiejes
**2·√λ** (bloque 3×3; 2×2 si `c[14] ≤ 0` y `c[21] ≤ 0` y `c[28] ≤ 0`) + abanico de yaw ±2σ (`σ = √c[35]`). Campos:
`covariance` float64[36] por filas (x, y, z, rotX, rotY, rotZ) → `PackedFloat64Array`; bloque 2D `c[0], c[1], c[7]`;
la elipse vive en los ejes del `header.frame_id` y no gira con la pose [I]. `@export`: `escala_pos`, `escala_ori`,
`color`. Vita: 364 B, cabe en directo; **sin elipsoide translúcido** (sin orden de transparencias y profundidad
siempre escrita, `docs/31` §2.4): (a) planta 2D = elipse `draw_polyline` de 24 lados + abanico `draw_colored_polygon`
(dos comandos), por defecto; (b) orbital 3D = `DISCO` opaco escalado por `transform`. ⚖ D5.4: `/vita/pose2d` **no se
amplía** a 10 floats (rompería `godot/plantillas/vita_relay.gd:87-91`, contra geom#13); la covarianza de AMCL llega
por `<p>/pose_cov` = `[x, y, yaw, σxx, σxy, σyy, σyaw]` (7 floats, 44 B, 2 Hz). Autovalores 2D en forma cerrada:

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## Covarianza 2D en planta: elipse 2σ (24 lados) + abanico de yaw ±2σ. datos = [centro m, yaw, l1, l2, th, s_yaw].
@export var escala_pos := 1.0
@export var color := Color(1.0, 0.4, 1.0)
var _d = null
func _init() -> void:
	capa = "sensores_2d"
func _procesar(msg):
	var c: PackedFloat64Array = msg.pose.covariance
	var o = msg.pose.pose.orientation
	var yaw := atan2(2.0 * (o.w * o.z + o.x * o.y), 1.0 - 2.0 * (o.y * o.y + o.z * o.z))
	return _elipse(Vector2(msg.pose.pose.position.x, msg.pose.pose.position.y), yaw, c[0], c[1], c[7], c[35])
func _procesar_compacto(msg):                  # <p>/pose_cov = [x, y, yaw, σxx, σxy, σyy, σyaw]
	var d: PackedFloat32Array = msg.data
	return null if d.size() < 7 else _elipse(Vector2(d[0], d[1]), d[2], d[3], d[4], d[5], d[6])
func _elipse(p: Vector2, yaw: float, a: float, b: float, dd: float, var_yaw: float) -> Array:
	var h := sqrt(((a - dd) * 0.5) ** 2 + b * b)
	var l1 := maxf((a + dd) * 0.5 + h, 0.0)
	var l2 := maxf((a + dd) * 0.5 - h, 0.0)
	return [p, yaw, l1, l2, 0.5 * atan2(2.0 * b, a - dd), sqrt(maxf(var_yaw, 0.0))]
func _pintar(d) -> void:
	_d = d
	queue_redraw()
func _draw() -> void:
	if _d == null:
		return
	var pts := PackedVector2Array()
	var ejes := Vector2(2.0 * sqrt(_d[2]), 2.0 * sqrt(_d[3])) * escala_pos
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(px(_d[0] + Vector2(cos(a) * ejes.x, sin(a) * ejes.y).rotated(_d[4])))
	draw_polyline(pts, color, -1.0)
	var r := 0.5 * visor.px_por_m
	var c0 := px(_d[0])
	var abanico := PackedVector2Array([c0])
	for k in 7:
		var a: float = _d[1] - 2.0 * _d[5] + 4.0 * _d[5] * k / 6.0
		abanico.append(c0 + Vector2(cos(a), -sin(a)) * r)
	draw_colored_polygon(abanico, Color(color, 0.5))
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 30}
```

El 3D del PC (elipsoide `C·(V·diag(2√λ))·Cᵀ` + discos de orientación) es el de geom#5 con `Prim.instancia(Prim.DISCO,
…)` y `Prim.a_godot(b_ros)` en lugar de `C * b_ros * C.transposed()`.

#### 4.2.6 `Twist`, `Accel`, `Wrench` (+`Stamped`, `WithCovariance(Stamped)`) (`3d/tornillo.gd`) — V geom#6–8

Display «screw» de RViz (`TwistStamped`/`AccelStamped`/`Wrench`): flecha lineal (o fuerza, roja) + flecha angular
(o par, amarilla) con `ANILLO` abierto de 315° de radio L/4 a mitad del eje (`wrench_visual.cpp`). Las tres fichas
traían el mismo código (`W13-revision.md:70-72`): un único script con `tipo`. El angular es pseudovector: la flecha
va por el eje de giro (regla de la mano derecha; la conversión es una rotación propia, `transforms.rst:37-48`).
`Twist` sin header (p. ej. `/cmd_vel`) se pinta en `frame_id` (por defecto `base_link`). NaN → descartar (RViz
*Accept NaN* = false). `@export`: `escala_lineal`, `escala_angular` (RViz *Force/Torque Arrow Scale* 2),
`ocultar_pequenos` (RViz *Hide Small Values*). Coste: 3 instancias (24 + 24 + 56 tri). En la Vita el `Twist` típico
es el que **ella** publica (teleop); verlo = flecha de mando en la planta (`g6-hmi/main.gd:185`) y barras HUD.

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var escala_lineal := 1.0
@export var escala_angular := 1.0
@export var ocultar_pequenos := true
var _lin: MeshInstance3D
var _ang: MeshInstance3D
var _anillo: MeshInstance3D
func conectar(v) -> void:
	super.conectar(v)
	_lin = Prim.instancia(Prim.FLECHA, Color(0.8, 0.2, 0.2))
	_ang = Prim.instancia(Prim.FLECHA, Color(0.8, 0.8, 0.2))
	_anillo = Prim.instancia(Prim.ANILLO, Color(0.8, 0.8, 0.2))
	for n in [_lin, _ang, _anillo]:
		add_child(n)
func _procesar(msg):
	var t: String = msg.get_ros_interface_name()
	var w := t.contains("Wrench")
	var c = msg
	if "Stamped" in t:                      # TwistStamped.twist / AccelStamped.accel / WrenchStamped.wrench
		c = msg.get_member("wrench" if w else ("twist" if t.contains("Twist") else "accel"))
	if "WithCovariance" in t:               # …WithCovariance.twist / .accel
		c = c.get_member("twist" if t.contains("Twist") else "accel")
	var a = c.get_member("force" if w else "linear")
	var b = c.get_member("torque" if w else "angular")
	var vl := Vector3(a.x, a.y, a.z)
	var va := Vector3(b.x, b.y, b.z)
	if not (vl.is_finite() and va.is_finite()):
		return null
	return [rclgd.ros_to_godot_vector(vl) * escala_lineal, rclgd.ros_to_godot_vector(va) * escala_angular]
func _pintar(d) -> void:
	var umbral := 0.01 if ocultar_pequenos else 1e-6
	var tl = Prim.flecha_hacia(d[0]) if (d[0] as Vector3).length() > umbral else null
	var ta = Prim.flecha_hacia(d[1]) if (d[1] as Vector3).length() > umbral else null
	_lin.visible = tl != null
	_ang.visible = ta != null
	_anillo.visible = ta != null
	if tl != null:
		_lin.transform = tl
	if ta != null:
		_ang.transform = ta
		var largo: float = (d[1] as Vector3).length()
		var r := largo * 0.25
		_anillo.transform = (ta as Transform3D).translated_local(Vector3(0, 0, -0.5)).scaled_local(Vector3(r, r, 1.0 / largo))
func _coste() -> Dictionary: return {"instancias": 3, "triangulos": 104, "quads": 0}
```

Esquemas: `Twist` y `TwistStamped` ya están; `AccelStamped` y `WrenchStamped` entran por `TIPOS_VISOR`; las
variantes `WithCovariance` no (se añaden si una app las usa).

#### 4.2.7 `Quaternion(Stamped)` (`3d/orientacion.gd`) — V geom#9

`EJES` girados por el cuaternión en el origen del frame + RPY en grados para el HUD (a ≤ 10 Hz, O1 de G7c,
`docs/31:139`). Cuaternión nulo → se ignora; no unitario → normalizar. Sin display en RViz [V]. 60 B, 36 tri.

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var largo := 0.5
var rpy_grados := Vector3.ZERO
var _ejes: MeshInstance3D
func conectar(v) -> void:
	super.conectar(v)
	_ejes = Prim.instancia(Prim.EJES, Color.WHITE)
	add_child(_ejes)
func _procesar(msg):
	var o = msg.quaternion
	var q := Quaternion(o.x, o.y, o.z, o.w)
	if q.length_squared() < 1e-6:
		return null
	q = q.normalized()
	rpy_grados = Vector3(atan2(2.0 * (q.w * q.x + q.y * q.z), 1.0 - 2.0 * (q.x * q.x + q.y * q.y)),
			asin(clampf(2.0 * (q.w * q.y - q.z * q.x), -1.0, 1.0)),
			atan2(2.0 * (q.w * q.z + q.x * q.y), 1.0 - 2.0 * (q.y * q.y + q.z * q.z))) * (180.0 / PI)
	return rclgd.ros_to_godot_quat(q)
func _pintar(q) -> void:
	_ejes.transform = Transform3D(Basis(q as Quaternion).scaled(Vector3.ONE * largo), Vector3.ZERO)
func _coste() -> Dictionary: return {"instancias": 1, "triangulos": 36, "quads": 0}
```

#### 4.2.8 `Transform(Stamped)` (`3d/transformada.gd`) — V geom#10

Ejes del hijo (`child_frame_id`) en el marco del padre (`header.frame_id`) + flecha hijo → padre; nombre del hijo por
`visor.texto.poner(...)`. En el PC se puede reemitir con `RosTfBroadcaster.send_transform` si el topic no es `/tf`.
100 B; 60 tri, 2 *draws*. Esqueleto = el de geom#10 con `_procesar` → `Transform3D(Basis(ros_to_godot_quat(q)),
ros_to_godot_vector(t))` y `_pintar` que coloca `_ejes` (escala 0,3) y la flecha
`Prim.flecha_hacia(-hijo.origin)` en `hijo.origin` (el padre es el origen del nodo).

#### 4.2.9 `Polygon(Stamped)` (`2d/poligono.gd`; `3d/poligono.gd` `solo_pc`) — V geom#11

Contorno cerrado: planta 2D `draw_polyline` cerrada (+ relleno opcional `draw_colored_polygon`), 1 comando (H17), por
defecto en la Vita; en el PC, `Prim.cinta(pts, ancho, ic, true)` reconstruida **solo si cambia la forma** (la huella
de Nav2 es casi estática) y a ≤ 2 Hz. Campos: `polygon.points[i]` (Point32) → `Vector2(x, y)`; marco una vez por
mensaje. 28 + 12·n B ⇒ n ≤ 38. `@export`: `ancho` (0,02), `color`, `relleno`. Topic típico
`/local_costmap/published_footprint`.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
@export var color := Color(0.2, 0.9, 0.3)
@export var relleno := false
var _pts := PackedVector2Array()
func _procesar(msg):
	var out := PackedVector2Array()
	for p in msg.polygon.points:
		out.append(Vector2(p.x, p.y))
	return null if out == _pts else out           # sin cambio de forma: no redibujar
func _pintar(pts) -> void:
	_pts = pts
	queue_redraw()
func _draw() -> void:
	if _pts.size() < 2:
		return
	var p := PackedVector2Array()
	for q in _pts:
		p.append(px(q))
	if relleno and p.size() >= 3:
		draw_colored_polygon(p, Color(color, 0.3))
	p.append(p[0])
	draw_polyline(p, color, -1.0)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 40}
```

#### 4.2.10 `Inertia(Stamped)` (`3d/inercia.gd`) — D geom#12 → corrección aplicada

Caja de inercia equivalente (densidad uniforme) en el CoM, ejes principales por Jacobi cíclico 3×3; uso de
depuración del URDF horneado (raro en la Vita: Jacobi ≈ 1 ms [I] por mensaje). Campos: `m`, `com`, `ixx…izz` →
tensor → autovalores `I1..I3` → lados `a = √(6(I2+I3−I1)/m)`… **Corrección de check-only** (`W13-revision.md:57`):
`var lados := Vector3(...) * (6.0 / i.m)` no compila («Cannot infer the type of "lados"», `Vector3 * Variant`) →
`var lados: Vector3 = …`. El resto del código de geom#12 se conserva:

```gdscript
func _procesar(msg):
	var i = msg.inertia
	if i.m <= 0.0:
		return null
	var a := [[i.ixx, i.ixy, i.ixz], [i.ixy, i.iyy, i.iyz], [i.ixz, i.iyz, i.izz]]
	var v := Basis()                                  # columnas = autovectores (ejes ROS)
	for _barrido in 10:                               # Jacobi cíclico 3×3
		for pq in [[0, 1], [0, 2], [1, 2]]:
			var p: int = pq[0]
			var q: int = pq[1]
			if absf(a[p][q]) < 1e-12:
				continue
			var th := 0.5 * atan2(2.0 * a[p][q], a[q][q] - a[p][p])
			var c := cos(th)
			var s := sin(th)
			for k in 3:
				var akp: float = a[k][p]
				var akq: float = a[k][q]
				a[k][p] = c * akp - s * akq
				a[k][q] = s * akp + c * akq
			for k in 3:
				var apk: float = a[p][k]
				var aqk: float = a[q][k]
				a[p][k] = c * apk - s * aqk
				a[q][k] = s * apk + c * aqk
			var vp := v[p]
			var vq := v[q]
			v[p] = c * vp - s * vq
			v[q] = s * vp + c * vq
	var l := Vector3(a[0][0], a[1][1], a[2][2])
	var lados: Vector3 = Vector3(l.y + l.z - l.x, l.x + l.z - l.y, l.x + l.y - l.z) * (6.0 / i.m)   # ← corrección
	lados = Vector3(sqrt(maxf(lados.x, 0.0)), sqrt(maxf(lados.y, 0.0)), sqrt(maxf(lados.z, 0.0)))
	return Transform3D(Prim.a_godot(v.scaled_local(lados)), rclgd.ros_to_godot_vector(Vector3(i.com.x, i.com.y, i.com.z)))

func _pintar(t) -> void:
	_caja.transform = t                               # _caja = Prim.instancia(Prim.CUBO, …) creada en conectar()
```

Prueba de host pendiente: Jacobi contra una caja de inercia conocida (borrador de geom §4.6).

### 4.3 Odometría, Path, TF y robot

#### 4.3.1 `nav_msgs/Odometry` (`2d/odometria.gd`; `3d/odometria.gd`) — V geom#13

Representación (RViz): rastro de flechas; se añade una **solo si** la pose se aleja de la **última flecha dibujada**
más de `tol_pos` o `tol_ang` (`Quaternion.angle_to` ≈ `ogreQuaternionAngularDistance`); pool circular de `keep`,
nunca se crean nodos por mensaje. Covarianza opcional (§4.2.5). En la Vita: 724 B no cabe en best effort (fiable
llega en 2 fragmentos, G6 a 20–30 Hz, `docs/27:80`); se usa el relay `<p>/pose2d` = `[x, y, yaw, vx, vy, wz]`, 40 B,
30 Hz (`vita_relay.py:11`) y la **planta 2D** (rastro `draw_polyline` + triángulo, validado en G6 y en el minimapa
del G1). 3D en la Vita solo con cupo (`poses`: HMI 4, Viz 16 ⇒ `keep` ≤ cupo; la ficha decía ≤ 20). `@export`:
`tol_pos` (0,1 m), `tol_ang` (0,1 rad), `keep` (100 PC), `color`; `topic_vita = "pose2d"`, `tipo_vita =
"std_msgs/msg/Float32MultiArray"`. Marco fijo `odom`: sin TF. La velocidad (`twist.twist` en `child_frame_id`: vx,
wz) va a la barra o a un medidor.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## Odometry en planta: rastro + triángulo. datos = Vector3(x, y, yaw) en el marco del mensaje (odom).
@export var tol_pos := 0.1
@export var max_rastro := 300
@export var color := Color(0.3, 0.7, 1.0)
var _rastro := PackedVector2Array()
var _yaw := 0.0
func _init() -> void:
	capa = "sensores_2d"
	hz = 30.0
func _procesar(msg):
	var o = msg.pose.pose.orientation
	return Vector3(msg.pose.pose.position.x, msg.pose.pose.position.y,
			atan2(2.0 * (o.w * o.z + o.x * o.y), 1.0 - 2.0 * (o.y * o.y + o.z * o.z)))
func _procesar_compacto(msg):
	var d: Dictionary = VitaRelay.pose2d(msg)          # vita_relay.gd:87-92
	return null if d.is_empty() else Vector3(d.pos.x, d.pos.y, d.yaw)
func _pintar(p) -> void:
	var q := Vector2(p.x, p.y)
	_yaw = p.z
	if _rastro.is_empty() or _rastro[-1].distance_to(q) > tol_pos:
		_rastro.append(q)
		if _rastro.size() > max_rastro:
			_rastro.remove_at(0)
	queue_redraw()
func _draw() -> void:
	if _rastro.size() < 2:
		return
	var pts := PackedVector2Array()
	for q in _rastro:
		pts.append(px(q))
	draw_polyline(pts, color, -1.0)
	var f := Vector2(cos(_yaw), -sin(_yaw)) * 10.0
	var c := pts[-1]
	draw_colored_polygon(PackedVector2Array([c + f, c - f * 0.6 + Vector2(-f.y, f.x) * 0.6, c - f * 0.6 - Vector2(-f.y, f.x) * 0.6]), color)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 100}
```

(`const VitaRelay = preload("res://comun/vita_relay.gd")` en la cabecera de los displays que lo usan.) El 3D es el de
geom#13 con el pool creado en `conectar()` del tamaño de `cupo` y `_pintar(t)` aplicando la tolerancia.

#### 4.3.2 `nav_msgs/Path` (`2d/path.gd`; `3d/path.gd`) — V geom#14

Polilínea transformada al marco fijo **una vez por mensaje** (como RViz). PC: `Prim.cinta` (2 tri/segmento) o líneas;
Vita: `draw_polyline` 2D por defecto, o cinta 3D reconstruida a ≤ 2 Hz (≤ 112 tri, `docs/31:133`; ADR 0011 §4; cupo
`lento` 0 en HMI, 4 en Viz). Path de 100 poses = 7 228 B: no cabe ni en fiable de forma estable (`docs/27:67`) →
relay `<p>/path_compacto` = `[n, x0, y0, …]`, Douglas-Peucker ε 5 cm, ≤ 57 puntos, 476 B, 2 Hz
(`vita_relay.py:18,87-110`). `Path` no hace falta en el `.rsch` de la Vita. Dato intermedio común:
`PackedVector2Array` en metros del marco del mensaje.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
@export var color := Color(0.1, 1.0, 0.0)          # RViz Path por defecto
var _pts := PackedVector2Array()
func _init() -> void:
	hz = 2.0
func _procesar(msg):
	var out := PackedVector2Array()
	for ps in msg.poses:
		out.append(Vector2(ps.pose.position.x, ps.pose.position.y))
	return out
func _procesar_compacto(msg): return VitaRelay.path_puntos(msg)   # vita_relay.gd:112-121
func _pintar(pts) -> void:
	_pts.resize(0)
	for q in pts:
		_pts.append(px(q))
	queue_redraw()
func _draw() -> void:
	if _pts.size() > 1:
		draw_polyline(_pts, color, -1.0)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 112}
```

#### 4.3.3 Display TF (`3d/tf.gd`) — D geom#15 → ⚖ D3 y D7

Representación: **no se suscribe a `/tf`**: consulta `visor.tf` a 10 Hz (`RosTfListener` en el PC, `TfLigero` en la
Vita), dibuja `EJES` por marco en el marco fijo, una flecha de cada hijo a su padre y los nombres con
`TextoSuperpuesto` (nunca `Label3D`); oculta los marcos sin actualizar en `timeout_s` (los estáticos no caducan).
**Corrección de la revisión y ⚖ sentencia**: (1) el relay `/vita/tf` de la ficha (trozos de 4 transforms a 30 Hz,
32 marcos) son ≈ 104 KB/s, más que todo el presupuesto de red (`W13-revision.md:161-162`): en la Vita los marcos del
robot salen de la cinemática local (`/vita/joints`) y `map|odom → base` de `/vita/pose2d`; el módulo `tf` del relay
es opcional y con lista blanca de **≤ 8 marcos a 10 Hz** (288 B, 2,9 KB/s); (2) ejes + flechas de 32 marcos = 64
instancias, por encima de las 32 de TF: **flechas hijo → padre apagadas en la Vita** (o líneas 2D superpuestas) y
cupo `tf` = 8 (HMI) / 32 (Viz). `@export`: `escala` (0,3; RViz *Marker Scale*), `timeout_s` (15), `periodo` (0,1),
`mostrar_nombres`, `mostrar_flechas` (por defecto `not en_vita`), `filtro` (lista blanca). En el PC
`get_frame_latest_time` existe en `RosTfListener` [V geom#15]; `TfLigero` no guarda sello (último valor), así que en
la Vita no hay caducidad por marco [I].

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
## Display TF: ejes por marco (+ flecha al padre en el PC) consultando visor.tf; sin suscripción propia.
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var escala := 0.3
@export var periodo := 0.1
@export var mostrar_nombres := false
@export var mostrar_flechas := true
@export var filtro: PackedStringArray = []          # vacío = todos
var _ejes := {}
var _flechas := {}
var _t := 0.0
func _init() -> void:
	capa = "tf"
func conectar(v) -> void:
	super.conectar(v)                                 # topic = "": no suscribe; reserva el cupo
	if v.en_vita:
		mostrar_flechas = false
func _process(dt: float) -> void:
	_t += dt
	if visor == null or visor.tf == null or _t < periodo:
		return
	_t = 0.0
	for f in visor.tf.get_frame_names():
		if filtro.size() > 0 and not filtro.has(f):
			continue
		if not _ejes.has(f):
			if _ejes.size() >= cupo:
				continue                                  # sin cupo: no se crea (lo avisó reservar())
			_ejes[f] = Prim.instancia(Prim.EJES, Color.WHITE)
			add_child(_ejes[f])
			if mostrar_flechas:
				_flechas[f] = Prim.instancia(Prim.FLECHA, Color(1.0, 0.9, 0.2))
				add_child(_flechas[f])
		var t = visor.transformada(f)
		_ejes[f].visible = t != null
		if t == null:
			continue
		_ejes[f].transform = (t as Transform3D).scaled_local(Vector3.ONE * escala)
		if mostrar_nombres and visor.texto:
			visor.texto.poner("tf/" + f, (t as Transform3D).origin, f)
		if mostrar_flechas:
			var padre: String = visor.tf.get_frame_parent(f)
			var tp = visor.transformada(padre) if padre != "" else null
			var fl = Prim.flecha_hacia((tp as Transform3D).origin - (t as Transform3D).origin) if tp != null else null
			_flechas[f].visible = fl != null
			if fl != null:
				_flechas[f].transform = Transform3D((fl as Transform3D).basis, (t as Transform3D).origin)
func _coste() -> Dictionary: return {"instancias": 32, "triangulos": 32 * 36, "quads": 0}
```

#### 4.3.4 `TfLigero` — A geom#16 → ⚖ D3

Código en §2.9.6. Cambios frente a la ficha: fuentes locales por defecto (no `/tf` crudo); `can_transform` añadido;
`get_frame_latest_time` fuera (sin sellos). Riesgo asumido: dos implementaciones de TF (GDScript ahora, C en V13) →
prueba común con los casos de `modules/tf-tree/tests/parity_test.c`. Cuando se registre el `RosTfListener` nativo,
`VisorRos` lo elige por `has_method` y `TfLigero` queda de respaldo en el host.

#### 4.3.5 `JointState` + URDF = RobotModel (`3d/robot_joints.gd`) — V geom#17

Representación: escena horneada en el PC por `tools/urdf2godot` (ADR 0009) con nombres de link/junta; el display
aplica `set_joints(nombres, posiciones)` (cinemática local, sin TF de links; `godot/g1-unitree/robot/urdf_robot.gd:80`)
y coloca la base con TF (PC) o `/vita/pose2d` (Vita). Campos: `name[i]` ↔ `position[i]`; `velocity`/`effort`
opcionales; *mimic* lo resuelve `urdf_robot.gd`. Vita: JointState de 29 juntas = 1 668 B (pos+vel+eff) / 1 196 B
(solo pos), no cabe (`docs/27:76-77`) → relay `<p>/joints` (Float32 en el orden de `<p>/joints_orden`, String
F+TL), 25 Hz, ≤ 118 juntas (`vita_relay.py:12-13`); JointState pequeño (2 ruedas ≈ 120 B) cabe en directo. LOD Vita
~12 k tri; G1 a 60 FPS en hardware (ADR 0009). `/robot_description` descartado en la Vita (XML + STL, `docs/25` §5).
Cupo `robot` = 40 instancias. `@export`: `escena_robot` (LOD), `link_raiz` (`base_link`), `marco_mundo` (`odom`).
Al conectar registra los links en `TfLigero` (`registrar_robot`), que así resuelve los marcos del robot sin tráfico.
Pendiente de la ficha (sin código): *Effort display* (esfuerzo por junta en color/anillo) y modo «TF por link» del PC.

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
## RobotModel: escena horneada (ADR 0009) + JointState → set_joints. En la Vita: joints + joints_orden + pose2d.
@export var escena_robot: PackedScene
@export var link_raiz := "base_link"
@export var marco_mundo := "odom"
var robot                                             # urdf_robot.gd: set_joints(nombres, posiciones)
var _orden := PackedStringArray()
var _subs: Array = []
func _init() -> void:
	capa = "robot"
	hz = 25.0
	frame_id = "base_link"
func conectar(v) -> void:
	super.conectar(v)
	if cupo == 0:
		return
	robot = escena_robot.instantiate()
	add_child(robot)                                   # sin owner: no se guarda en la escena (doc 35)
	if v.tf != null and v.tf.has_method("registrar_robot"):
		v.tf.registrar_robot(robot, link_raiz)       # TfLigero: marcos de los links sin tráfico (D3)
	if canal.compacto:                                 # suscripciones auxiliares del relay
		var n = v.contexto.nodo
		_subs.append(n.create_subscription(v.prefijo_compacto + "/joints_orden", "std_msgs/msg/String",
				func(m): _orden = String(m.data).split(","), v.contexto.qos(false, 1, true)))
		_subs.append(n.create_subscription(v.prefijo_compacto + "/pose2d", "std_msgs/msg/Float32MultiArray",
				func(m): v.tf.desde_pose2d(m.data, marco_mundo, link_raiz), v.contexto.qos(true, 1, false)))
func _procesar(msg): return [PackedStringArray(msg.name), msg.position]
func _procesar_compacto(msg): return null if _orden.is_empty() else [_orden, msg.data]
func _pintar(d) -> void:
	robot.set_joints(d[0], d[1])
func _coste() -> Dictionary: return {"instancias": 40, "triangulos": 12000, "quads": 0}
```

`frame_id = "base_link"`: la base del robot se coloca con `visor.transformada("base_link")` (TF del PC o, en la Vita,
`TfLigero` alimentado por `pose2d`). [I] `Callable` lambda como callback de `create_subscription` en `ros2_vita`:
comprobar en V1 (la ficha geom#16 ya lo marcaba con `Callable.bind`).

### 4.4 Sensores pequeños, HUD de estado y mando

#### 4.4.1 `Imu` (`3d/imu.gd`) — V geom#18

`EJES` con la orientación **absoluta** en la posición del IMU (no se compone con TF, como `rviz_imu_plugin`) [I] +
flecha de aceleración lineal (amarilla, m/s² × `escala_acel`; en reposo +9,81 en Z) + flecha de velocidad angular
(cian). `orientation_covariance[0] == -1` ⇒ sin orientación (Imu.msg) → ejes ocultos. Planta 2D: brújula de yaw +
burbuja. Vita: 316–324 B, cabe a 30–60 Hz (`docs/27:83`); si el IMU publica a 100 Hz → `<p>/ritmo/imu` a 20 Hz
(módulo `ritmo`, D8). La Vita es sobre todo **publicadora** de su Imu (`godot/plantillas/sensores/imu.gd`).
`@export`: `escala_acel` (0,05 m por m/s²), `escala_giro` (0,5 m por rad/s). 3 instancias ≈ 84 tri.

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
const Prim = preload("res://comun/visor/primitivas_viz.gd")
@export var escala_acel := 0.05
@export var escala_giro := 0.5
var _ejes: MeshInstance3D
var _acel: MeshInstance3D
var _giro: MeshInstance3D
func conectar(v) -> void:
	super.conectar(v)
	_ejes = Prim.instancia(Prim.EJES, Color.WHITE)
	_acel = Prim.instancia(Prim.FLECHA, Color(1, 0.8, 0))
	_giro = Prim.instancia(Prim.FLECHA, Color(0, 0.8, 1))
	for n in [_ejes, _acel, _giro]:
		add_child(n)
func _procesar(msg):
	var o = msg.orientation
	var q = null
	if msg.orientation_covariance[0] != -1.0:
		q = rclgd.ros_to_godot_quat(Quaternion(o.x, o.y, o.z, o.w).normalized())
	var a = msg.linear_acceleration
	var w = msg.angular_velocity
	return [q, rclgd.ros_to_godot_vector(Vector3(a.x, a.y, a.z)) * escala_acel,
			rclgd.ros_to_godot_vector(Vector3(w.x, w.y, w.z)) * escala_giro]
func _pintar(d) -> void:
	_ejes.visible = d[0] != null
	if d[0] != null:                                   # orientación absoluta: se anula la rotación del marco
		_ejes.transform = Transform3D(transform.basis.inverse() * Basis(d[0] as Quaternion), Vector3.ZERO)
	for par in [[_acel, d[1]], [_giro, d[2]]]:
		var t = Prim.flecha_hacia(par[1])
		par[0].visible = t != null
		if t != null:
			par[0].transform = t
func _coste() -> Dictionary: return {"instancias": 3, "triangulos": 84, "quads": 0}
```

#### 4.4.2 `MagneticField` (`3d/magnetico.gd`) — V geom#19

Flecha del campo en µT × `escala` (m por µT) en el marco del sensor + rumbo para una brújula 2D: `atan2(−By, Bx)` en
sensor nivelado, ENU [I: signos según montaje]; |B| (25–65 µT en la Tierra) como validez. Campos: `magnetic_field`
(T) ×1e6 → µT; `magnetic_field_covariance[0] = 0` ⇒ desconocida. 124 B. Magnetómetro de la Vita no accesible por la
API usada en G7 [?]. Esqueleto = el de vector (§4.2.2) con `_procesar` que además guarda `rumbo_grados` y
`modulo_ut`; `@export declinacion_grados` para rumbo verdadero.

#### 4.4.3 `NavSatFix` (`2d/gps.gd`) — V geom#20

Planta 2D: rastro ENU local (plano tangente desde el primer fix) con `draw_polyline` + círculo de 2σ coloreado por
estado (rojo `NO_FIX`, verde `FIX`, azul SBAS/GBAS). PC: fondo opcional de teselas OSM por `HTTPRequest` y caché
(respetar la política de uso de OSM [I]); Vita: teselas prehorneadas en el `.pck` (≤ 9 a la vez: ≥ 256 KiB de CDRAM
cada una y ≤ 48 texturas, H19) o ninguna. **Trampa**: no guardar grados en `Vector2` (float32: 1e-5° ≈ 1 m); origen
en dos `float` de GDScript (64 bit) y conversión a metros antes del `Vector2`. Campos: `latitude/longitude` (°,
WGS84), `status.status` (−1…2), `position_covariance` (ENU, m²) y `position_covariance_type`. 125 B.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
const R_TIERRA := 6378137.0
@export var max_puntos := 300
var _lat0 := NAN                                       # float de GDScript = 64 bit; NO Vector2
var _lon0 := 0.0
var _rastro := PackedVector2Array()                   # metros ENU (este, norte)
var _sigma := 0.0
var _estado := -1
func _init() -> void:
	hz = 5.0
func _procesar(msg):
	_estado = int(msg.status.status)
	if _estado < 0 or is_nan(msg.latitude):
		return null
	if is_nan(_lat0):
		_lat0 = msg.latitude
		_lon0 = msg.longitude
	var este: float = deg_to_rad(msg.longitude - _lon0) * R_TIERRA * cos(deg_to_rad(_lat0))
	var norte: float = deg_to_rad(msg.latitude - _lat0) * R_TIERRA
	var c: PackedFloat64Array = msg.position_covariance
	_sigma = sqrt(maxf(c[0], c[4])) if int(msg.position_covariance_type) > 0 else 0.0
	return Vector2(este, norte)
func _pintar(p) -> void:
	_rastro.append(p)
	if _rastro.size() > max_puntos:
		_rastro.remove_at(0)
	queue_redraw()
func _draw() -> void:
	if _rastro.is_empty():
		return
	var pts := PackedVector2Array()
	for q in _rastro:
		pts.append(px(q))
	if pts.size() >= 2:
		draw_polyline(pts, Color(0.2, 0.8, 1.0), -1.0)
	var col := Paleta.ERROR if _estado < 0 else (Paleta.OK if _estado == 0 else Color.DODGER_BLUE)
	draw_arc(pts[-1], maxf(2.0 * _sigma * visor.px_por_m, 3.0), 0.0, TAU, 24, col, -1.0)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 60}
```

(`const Paleta = preload("res://comun/visor/paleta_viz.gd")` en la cabecera.) El marco del display es el fijo
(`frame_id = visor.marco_fijo`): el GPS no tiene TF a `map` salvo `navsat_transform` [I].

#### 4.4.4 `Range` (`3d/rango.gd`, `2d/rango.gd`) — V geom#21

`CONO` unidad (vértice en el origen, base en z = −1, radio 0,5) escalado por `transform` a (ancho, ancho, r) con
`ancho = 2·r·tan(fov/2)`; r fuera de `[min_range, max_range]` ⇒ oculto, salvo `−Inf` en sensor de distancia fija
(`min = max`) ⇒ `min_range` (`range_display.cpp getDisplayedRange`). **Filtro con NaN** (§8): `r >= min and r <= max`.
Vita: cono opaco (sin orden de transparencias) de 16 tri o sector 2D `draw_colored_polygon` (3–6 vértices). 52 B a
60 Hz. Color por `radiation_type` (0 ultrasonido, 1 infrarrojo).

```gdscript
func _procesar(msg):
	var r: float = msg.range
	if r >= msg.min_range and r <= msg.max_range:
		pass
	elif msg.min_range == msg.max_range and is_inf(r) and r < 0.0:
		r = msg.min_range
	else:
		return 0.0                                        # fuera de rango: ocultar
	return Vector2(r, 2.0 * r * tan(msg.field_of_view * 0.5))
func _pintar(d) -> void:                                # d = 0.0 o Vector2(largo, ancho)
	_cono.visible = d is Vector2
	if d is Vector2:
		_cono.transform = Transform3D(Basis.from_scale(Vector3(d.y, d.y, d.x)), Vector3.ZERO)
```

#### 4.4.5 Medidores ambientales (`hud/medidor.gd`): `Temperature`, `FluidPressure`, `Illuminance`, `RelativeHumidity` — V hmi#3–6

Barra con umbrales verde/amarillo/rojo (colores de rqt_robot_monitor), valor con unidades y *sparkline* (una
polilínea fina = 1 comando). Un solo script; cada tipo es configuración:

| Tipo | `campo` | `escala` | `unidad` | `minimo`–`maximo` (`aviso`) | Fuente de prueba |
|---|---|---:|---|---|---|
| `Temperature` | `temperature` | 1 | °C | −10–60 (45) | — |
| `FluidPressure` | `fluid_pressure` | 0,01 | hPa | 950–1 050 (1 040) | `plantillas/sensores/barometro.gd` (5 Hz XRCE, `:14-20`) |
| `Illuminance` | `illuminance` | 1 | lx | 0–2 000 (1 500) | `ros2 topic pub` |
| `RelativeHumidity` | `relative_humidity` | 100 | % | 0–100 (80) | `ros2 topic pub` |

44 B cada uno; `FluidPressure` ya está en `generar_esquemas.py:32`, los otros tres entran por `TIPOS_VISOR` [V].

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
@export var campo := "temperature"
@export var escala := 1.0
@export var unidad := "°C"
@export var minimo := -10.0
@export var maximo := 60.0
@export var aviso := 45.0
@export var muestras := 60
var _serie := PackedFloat32Array()
func _procesar(msg):
	var v := float(msg.get_member(campo)) * escala
	_serie.append(v)
	if _serie.size() > muestras:
		_serie.remove_at(0)
	return v
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.12))
	if datos == null:
		return
	var v: float = datos
	var c := color_estado(Paleta.OK if v < aviso else (Paleta.WARN if v < maximo else Paleta.ERROR))
	draw_rect(Rect2(0, size.y - 6, size.x * clampf(inverse_lerp(minimo, maximo, v), 0.0, 1.0), 6), c)
	draw_string(get_theme_default_font(), Vector2(4, 14), "%.1f %s" % [v, unidad], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, c)
	var pts := PackedVector2Array()
	for i in _serie.size():
		var f := clampf(inverse_lerp(minimo, maximo, _serie[i]), 0.0, 1.0)
		pts.append(Vector2(size.x * i / maxf(1.0, muestras - 1), 18.0 + (size.y - 26.0) * (1.0 - f)))
	if pts.size() > 1:
		draw_polyline(pts, c, -1.0)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 30}
```

#### 4.4.6 `BatteryState` (`hud/bateria.gd`, barra fija) — V hmi#2

Icono con relleno = `percentage` (NaN = no medido → `charge/capacity`), rojo si la salud es mala
(`power_supply_health` 2–8) o < `umbral_bajo` (0,2); texto «V A estado». Hz bajo (0,2–1 Hz,
`plantillas/sensores/bateria.gd:15-16`) ⇒ `caducidad_s = 15`. 89 B (sin celdas) / 133 B (6 celdas); esquema ya en
`generar_esquemas.py:30`. ≈ 40 *quads*. El esqueleto de hmi#2 vale cambiando `extends` a `display_ros_hud.gd`,
`_recibir(m)` por `_procesar(msg)` que **devuelve** `[pct, texto, alarma]`, y `caducado()` por `gris`.

#### 4.4.7 `Joy` (`hud/joy.gd`) y fuente `/vita/joy` — V hmi#1

Visor: dos sticks (arco + punto) y fila de botones; ≈ 70 *quads*; 128 B (8 ejes, 17 botones) a 20 Hz. Fuente: la Vita
publica `/vita/joy` (best effort, 20 Hz, 128 B; ⚖ §6) desde `Input.get_joy_axis` / `is_joy_button_pressed` **negando X
e Y** (en Godot el eje Y del stick es positivo hacia abajo, `godot/g6-hmi/main.gd:85-86`; en `joy`, arriba e
izquierda = +1 [I]). Esqueleto de hmi#1 con el mismo cambio de `extends`/`_procesar`; `@export pares_sticks`,
`invertir_x`.

### 4.5 Sensores densos (familia `sensores-densos`)

Regla de corte (`docs/31` §4.1): relay si el CDR pasa de 488 B → C++ del motor (JPEG/PNG, `blit_rect`) → GDScript si
≤ 2 ms por mensaje → C en `viz-decode` (V13). **Ningún bucle por píxel en GDScript** (14–35 ms por 640×480 en el
host de pruebas [V]: inviable incluso en el PC a 30 Hz). Código de sensores probado en headless con mensajes reales
(esquema `godot/g1-sensores/ros/schema.rsch`, ida y vuelta `serialize()`/`deserialize()`); tiempos en un Ryzen 7
5800X; la Vita, 20–40× más lenta en GDScript [I] (1,5 µs/instrucción, `docs/31:162`).

#### 4.5.1 `LaserScan` (`2d/scan.gd`; `3d/scan_puntos.gd` `solo_pc`) — V sens#0; D sens#1 → ⚖ D4

Vita (y planta en el PC): **un** triángulo por punto en **una** llamada `canvas_item_add_triangle_array`, redibujado
solo al llegar mensaje (H16–H17). Tabla de direcciones cos/sin recalculada solo si cambian `angle_min`,
`angle_increment` o n (`docs/31:210`; 720 rayos: 711 → 263–340 µs en host [V]). **Filtro REP-117 con NaN** (§8):
`if not (r >= range_min and r <= range_max): continue`. Cifra corregida (D4): un LaserScan con frame `base_scan` y sin
intensidades cabe hasta 107 rayos (488 B con rosbags = 484 B de carga), no 106; da igual: los escáneres reales
(360–720 rayos, 1 504–5 824 B) van por `<p>/scan_compacto` (Int16 cm, ≤ 180 rayos, 384 B, 10 Hz; `docs/27:61-64,98`).
El simulador de plantillas publica 60 rayos (`plantillas/sensores/lidar_2d.gd:6`), que sí caben en directo. Cupo
2D: scan ≤ 360 *quads*. `@export`: `lado_px` (3), `color`; `frame_id` del sensor (p. ej. `base_scan`) para el
compacto, que no trae header.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## LaserScan en planta: UN lote por mensaje. datos = PackedVector2Array (m, marco del sensor).
const VitaRelay = preload("res://comun/vita_relay.gd")
@export var lado_px := 3.0
@export var color := Color(1, 0.2, 0.2)
var _dirs := PackedVector2Array()
var _clave := Vector3.INF
var _v := PackedVector2Array()
var _c := PackedColorArray()
var _idx := PackedInt32Array()
func _init() -> void:
	hz = 10.0
func _procesar(msg):
	var r: PackedFloat32Array = msg.ranges
	var clave := Vector3(msg.angle_min, msg.angle_increment, r.size())
	if clave != _clave:                                   # cos/sin solo si cambia la geometría
		_clave = clave
		_dirs.resize(r.size())
		for i in r.size():
			_dirs[i] = Vector2.from_angle(msg.angle_min + i * msg.angle_increment)
	var out := PackedVector2Array()
	for i in r.size():
		if not (r[i] >= msg.range_min and r[i] <= msg.range_max):   # ±Inf y NaN fuera (REP-117)
			continue
		out.append(_dirs[i] * r[i])
	return out
func _procesar_compacto(msg): return VitaRelay.scan_puntos(msg)   # vita_relay.gd:95-109 (0 = sin dato)
func _pintar(puntos) -> void:
	var n: int = mini(puntos.size(), cupo)               # cupo en quads = puntos
	_v.resize(n * 3)
	_c.resize(n * 3)
	for i in n:
		var p := px(puntos[i])
		_v[3 * i] = p + Vector2(0, -lado_px)
		_v[3 * i + 1] = p + Vector2(lado_px, lado_px)
		_v[3 * i + 2] = p + Vector2(-lado_px, lado_px)
		_c[3 * i] = color
		_c[3 * i + 1] = color
		_c[3 * i + 2] = color
	if _idx.size() != n * 3:
		_idx = PackedInt32Array(range(n * 3))
	queue_redraw()
func _draw() -> void:
	if _v.size() > 0:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), _idx, _v, _c)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 360}
```

`VitaRelay.scan_puntos` tiene su propio bucle cos/sin por rayo (`vita_relay.gd:95-109`); el arreglo de
`docs/31` §4.4 (tabla de direcciones) entra en V3. PC (`3d/scan_puntos.gd`, `solo_pc`): `ArrayMesh`
`PRIMITIVE_POINTS` con color por intensidad (LUT arcoíris de 256, `Color.from_hsv(0.8333·(1 − k/255), 1, 1)`),
`use_point_size`; *decay* (`persistencia_s`) = una `MeshInstance3D` congelada (`top_level`) por barrido liberada con
un temporizador. Código de sens#0 cambiando `iniciar(nodo, topic)` por la base y `decay_s` por `persistencia_s`.

#### 4.5.2 `MultiEchoLaserScan` — V sens#2

Aplanar a LaserScan eligiendo eco (`primero` / `ultimo` / `mas_fuerte` / `todos`) y reutilizar el display de scan
(PC). 360 haces × 3 ecos + intensidades = 11 584 B: no cabe ni en fiable; en la Vita el relay elige el eco y emite
`scan_compacto`. Coste PC dominado por envolver 2·N `RosMsg` (`LaserEcho`, camino lento de arrays compuestos;
360 haces ≈ 1–2 ms [I]). Esqueleto de sens#2 con `_procesar` que devuelve el `PackedVector2Array`; con `todos`, los
ecos de un haz comparten ángulo (mejor que repartir el incremento, hueco anotado en la ficha).

#### 4.5.3 `PointCloud2` (`2d/nube.gd`; `3d/nube_puntos.gd` `solo_pc`) — V sens#3; A sens#4 → ⚖ D5

PC: decodificador genérico por `fields[].name/offset/datatype` con `decode_float(i·point_step + off)` sobre el
`PackedByteArray`, diezmado uniforme hasta `max_puntos`, color por campo (LUT arcoíris), `rgb` empaquetado
(`decode_u32` → `Color8`), NaN fuera con `Vector3.is_finite()`; `ArrayMesh PRIMITIVE_POINTS` bajo un nodo con
`basis = C` (sin conversión por punto). `is_bigendian` → `data.bswap32()` **solo si todos los campos son de 4 B**
(RViz no lo trata). Coste ≈ 0,2 µs/punto en GDScript (10 k = 1,9 ms) [V host]; ruta rápida si xyz(i) float32
contiguos: `to_vector3_array()`/`to_vector4_array()` (36–48 µs/10 k, Godot ≥ 4.7) [V]; > 50 k puntos a 10 Hz →
textura + *vertex shader* con `VERTEX_ID` (hueco V14).
Vita: no cabe (20 puntos xyzi = 461 B; 100 = 1 741 B). ⚖ D5: relay `<p>/nube2d` = Int16 **cabecera común**
`[seq, trozo, n_trozos, n]` + xyz en cm·n, **n ≤ 76** (480 B; la ficha proponía 78 con cabecera de 3, 486/492 B según
convención), vóxel 10 cm, ≤ 228 puntos (3 trozos), 5 Hz. Planta 2D con un lote por trozo y color por banda de altura
(paleta de 16, como el «Axis color» de RViz). Cupo: nube ≤ 228 *quads*. GDScript ≈ 1,7 ms por trozo en la Vita [I]
(`docs/31:184`); `vizd_cloud_cm` en C cuando exista (V13). Recomendado [I]: que el relay transforme la nube a `map`
(la Vita no tiene `/tf` completo) y la mande con el marco fijo.

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## PointCloud2 en la Vita: <p>/nube2d (Int16, cm). datos = [trozo, PackedVector2Array px, PackedColorArray].
const Vc1 = preload("res://comun/ros/vc1.gd")
@export var alturas := Vector2(-0.2, 2.0)
@export var lado_px := 2.0
var _trozos := {}
var _seq := -1
var _lut := PackedColorArray(range(16).map(func(k): return Color.from_hsv(0.66 * (1.0 - k / 15.0), 1, 1)))
func _init() -> void:
	hz = 0.0                                            # todos los trozos: no coalescer por tiempo
	topic_vita = "nube2d"
	tipo_vita = "std_msgs/msg/Int16MultiArray"
func conectar(v) -> void:
	canal.coalescer = false                             # cada trozo cuenta
	super.conectar(v)
func _procesar_compacto(msg):
	var d: PackedInt32Array = msg.data                  # int16[] llega como PackedInt32Array (H25)
	var cab: Dictionary = Vc1.cabecera(d)               # {seq, trozo, n_trozos, n} (§5.3)
	if cab.is_empty():
		return null
	if cab.seq != _seq:
		_seq = cab.seq
		_trozos.clear()                                 # nueva nube
	var v := PackedVector2Array()
	var c := PackedColorArray()
	var esc := 15.0 / (alturas.y - alturas.x)
	for i in cab.n:
		var b := 4 + 3 * i
		var p := px(Vector2(d[b], d[b + 1]) / 100.0)
		var col := _lut[clampi(int((d[b + 2] / 100.0 - alturas.x) * esc), 0, 15)]
		v.append_array([p + Vector2(0, -lado_px), p + Vector2(lado_px, lado_px), p + Vector2(-lado_px, lado_px)])
		c.append_array([col, col, col])
	return [cab.trozo, v, c]
func _pintar(t) -> void:
	_trozos[t[0]] = [t[1], t[2]]
	queue_redraw()
func _draw() -> void:                                  # un lote por trozo (≤ 3); color plano → se funde (H16)
	for t in _trozos.values():
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(range(t[0].size())), t[0], t[1])
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 228}
```

El esqueleto PC (`3d/nube_puntos.gd`) es el de sens#3 con `_procesar` devolviendo `[pts, col]` y `_pintar` creando
la `ArrayMesh`; `@export campo_color` («» | `intensity` | `z` | `rgb`), `rango_color`, `max_puntos` (60 000),
`tam_px` (3). Orden exacto del arcoíris de RViz (`getRainbowColor`) [?] → `@export invertir_arcoiris`.

#### 4.5.4 `PointCloud` (obsoleto) — V sens#5

Como RViz: convertir a PointCloud2 **fuera de Godot** (`point_cloud_converter` o el relay). Respaldo GDScript en sens#5
(un `RosMsg` por `Point32`: ≈ 1–3 µs por punto [I], solo nubes pequeñas). Sin esquema en la Vita.

#### 4.5.5 `Image` (`hud/imagen.gd`, `solo_pc`) — V sens#6, V sens#8, D sens#7

PC: `Image.create_from_data` con el formato equivalente (cero conversión) + `ImageTexture.update` reutilizando la
textura; intercambio de canales y profundidad en un *shader* `canvas_item`:

| `encoding` | `Image.Format` | Modo del *shader* | Nota |
|---|---|---|---|
| `rgb8`, `8UC3` | `FORMAT_RGB8` | 0 directo | |
| `rgba8` | `FORMAT_RGBA8` | 0 | |
| `bgr8` / `bgra8` | `RGB8` / `RGBA8` | 1 (`.bgr`) | |
| `mono8`, `8UC1`, `bayer_*8` | `FORMAT_L8` | 0 | bayer en gris, como RViz (sin demosaico) |
| `mono16`, `16UC1` | `FORMAT_R16` (unorm) | 2: `z = r·65,535` m | 16UC1 en mm (REP-118) [I] |
| `32FC1` | `FORMAT_RF` | 3: `z = r` m | 0/NaN/Inf transparentes |
| `yuv422`(=uyvy), `uyvy`, `yuyv`, `yuv422_yuy2` | `RGBA8` de ancho/2 | YUV→RGB (BT.601 completo [I]) | script aparte `imagen_yuv.gd` (sens#8) |

Profundidad (D sens#7): la ficha no traía código propio — el bloque es el de sens#6, que **sí** cubre R16 y RF con
los modos 2 y 3 del *shader*; lo que queda sin código va a «Por resolver» (§9.3): `16SC1` (`FORMAT_R16I` +
`usampler` [?]), `64FC1`, `nv21`/`nv24`, codificaciones de color de 16 bit, filas con relleno (`step ≠ w·bpp`: hoy se
rechazan), auto-rango (Normalize Range + mediana de 5 fotogramas). `FORMAT_R16`, `to_vector*_array` y `bswap*`
existen en Godot 4.7 (rclgd) y 4.8-dev7 (Vita), **no en 4.4** [V]. `Image.convert(R16→L8)` existe pero escala
0–65 535 → 0–255 (5 m = 0,08 → casi negro) [V medido]. El esqueleto es el de sens#6 tal cual (constantes `FMT`,
`SH`) con `_procesar` → `[img, modo]` y `_pintar` que hace `create_from_image` la primera vez o `update` si coinciden
tamaño y formato.

#### 4.5.6 Imagen en la Vita y `CompressedImage` (`hud/imagen_comprimida.gd`) — V sens#10; D sens#9 → ⚖ D13

⚖ D13: la Vita **nunca** recibe imagen cruda. Relay `<p>/camara/compressed` = `sensor_msgs/msg/CompressedImage`
JPEG **160×120 q40** (≤ 3 KB), **fiable**, **3 Hz** por defecto (parámetro `camara_hz`, máximo 5; la ficha decía 5).
Mismo script en PC y Vita (el tipo estándar ya está en `generar_esquemas.py:25`): decodifica el motor
(`Image.load_jpg_from_buffer`/`load_png_from_buffer`, H22; libjpeg sin SIMD en la Vita). La recepción fiable no
bloquea el hilo principal (la que bloquea es la emisión, `docs/27:13-15`). Coste Vita [I]: 1–2 ms decodificar +
1–3 ms `update` ≈ 3–6 ms por imagen (`docs/31:183`) → gate **E-W8-5** (≤ 6 ms). Profundidad: el relay la entrega ya
coloreada en JPEG. Descartados: miniaturas `mono8` (80×60 = 4 848 B, más grande y peor) y trocear en best effort.
`format` de image_transport: `"rgb8; jpeg compressed bgr8"` → Godot ya da RGB tras decodificar. PNG de 16 bit:
el cargador de Godot lo baja a 8 bit (`png_driver_common.cpp:72-106`) [V] → `compressedDepth` se descarta aquí.

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## CompressedImage jpeg/png (PC y Vita: decodifica el motor, H22). Pestaña Cámara.
@export var rect: TextureRect                         # en la escena; stretch KEEP_ASPECT_CENTERED
var _tex: ImageTexture
var _img := Image.new()
func _init() -> void:
	topic_vita = "camara/compressed"
	tipo = "sensor_msgs/msg/CompressedImage"
	tipo_vita = "sensor_msgs/msg/CompressedImage"
	fiabilidad = 2                                      # FIABLE: ≈ 3 KB no cabe en 488 B (§6)
	profundidad = 1
	hz = 15.0
	hz_vita = 3.0
	caducidad_s = 2.0
func _procesar(msg):
	var f := String(msg.format)
	if "compressedDepth" in f:
		return null                                     # PNG de 16 bit: se perdería precisión (§8)
	var data: PackedByteArray = msg.data
	var err := _img.load_png_from_buffer(data) if "png" in f else _img.load_jpg_from_buffer(data)
	return _img if err == OK else null
func _pintar(img) -> void:
	if _tex == null or _tex.get_size() != Vector2(img.get_size()):
		_tex = ImageTexture.create_from_image(img)
		rect.texture = _tex
	else:
		_tex.update(img)                                # mismo tamaño y formato: sin realojar (H19)
func _caducar() -> void:
	rect.modulate = Color(1, 1, 1, 0.4) if gris else Color.WHITE
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 1}
```

`compressedDepth` (V sens#11): no se decodifica en Godot; `ros2 run image_transport republish compressedDepth raw`
(PC) o el relay, y se usa §4.5.5. Formato: `ConfigHeader` (12 B [I]) + PNG 16 bit o RVL; 32FC1 cuantizado como
inversa `D = A/(v − B)`.

#### 4.5.7 `CameraInfo` (`3d/camara_info.gd`) — D sens#12 → corrección

Frustum desde K, `width`, `height` (rehecho solo si cambia K) y, opcionalmente, óptica aplicada a una `Camera3D` con
`set_frustum` (tamaño y desplazamiento del plano cercano desde fy, cx, cy). Marco óptico (x der, y abajo, z delante)
→ Godot local (x, −y, −z). **Correcciones**: (1) tamaño 357 B con frame `camera` (no 381; depende del frame), cabe
igual; (2) `ImmediateMesh`/`PRIMITIVE_LINES` **solo vale en el PC** (H1): en la Vita, 4 prismas finos
(6 tri/segmento, `docs/31` §2.2, cupo `reserva`) o el frustum en 2D superpuesto; no hay SubViewport 3D en el port
(G7c). Pendiente [I]: usar P (`p[0], p[5], p[2], p[6]`) en vez de K para imágenes rectificadas, como el display Camera
de RViz; signo del desplazamiento (convención de centro de píxel) por comparar con una imagen real. El esqueleto de
sens#12 vale en el PC con `_procesar` → `[k, w, h]` (o `null` si no cambia).

#### 4.5.8 Display «Camera» (`hud/camara.gd`, `solo_pc`) — M sens#13

PC: `SubViewport` con fondo transparente y `world_3d` compartido, `Camera3D` en el frame óptico con la óptica de
`camara_info.gd`, superpuesto con alfa a la imagen. Vita: sin SubViewport 3D → «modo cámara»: la cámara principal
se mueve al frame óptico, `set_frustum`, y la imagen va como `TextureRect` HUD semitransparente encima (fondo
transparente por defecto [?]); coste = el del 3D principal. **Por medir** (sin ejecutar [I]); sincronizar imagen y
TF por `stamp` necesita `lookup_transform` con tiempo (en la Vita no hay) → §9.3. Esqueleto de sens#13 sin cambios
salvo `extends` de un `DisplayRosHud` contenedor con `solo_pc = true`.

#### 4.5.9 DepthCloud (`3d/nube_profundidad.gd`, `solo_pc`) — V sens#14

Todo en GPU: profundidad como textura R16/RF y una malla de w×h puntos (creada una vez) desproyectada en el *vertex
shader* con fx, fy, cx, cy (`VERTEX_ID` → píxel): cero bucles GDScript (RViz lo hace en CPU). Vita: no (sin
*shaders*); el relay desproyecta y reduce a `nube2d`. Esqueleto de sens#14 tal cual (dos suscripciones: `CameraInfo`
y `Image`; la segunda es la del canal, la primera auxiliar con `contexto.qos(true, 1, false)`).

### 4.6 Mapas y rejillas (familia `mapas-marcadores`, primera mitad)

#### 4.6.1 `OccupancyGrid` «map», «costmap», «raw» (`2d/mapa.gd`; `3d/mapa.gd`) — V mapas#0–2

PC (`3d/mapa.gd`): *quad* en el suelo con dos texturas — datos crudos (`m.data.to_byte_array()` → `RGBA8` con el byte
en R, **sin bucles GDScript**) y paleta 256×1 — y un *shader* de tres líneas que busca el color (`texelFetch`), como
RViz. Paletas = ports literales de `palette_builder.cpp:87-152` (map: gris invertido; costmap: 0 transparente,
1–98 azul→rojo, 99 cian inscrito, 100 magenta letal, −1 `0x708986`; raw: gris lineal), en `PaletaViz.rampa_mapa()`
(§3.3). Campos: `info.resolution`, `info.width/height`, `info.origin` (pose de la **esquina** de la celda (0,0), no
del centro) → `Transform3D`; celda (i,j) = `data[j·width + i]`, fila 0 en el origen. `@export`: `esquema`
(map|costmap|raw), `alfa`, `binaria` + `umbral`; QoS *latched* (fiable + TRANSIENT_LOCAL); `update_topic` = `topic +
"_updates"` (`map_display.cpp:222-225`).
Vita: un mapa no cabe (384² = 147 560 B, `docs/27:65`): relay VC/1 `<p>/mapa_meta` (F+TL) + `<p>/mapa_tesela`
(32×32 a 2 bit, best effort, ≤ 20/s), que ya consume `godot/plantillas/vita_relay.gd`. **Arreglo de V3**
(`docs/31` §4.4): decodificar cada tesela con LUT de 256 entradas (byte → 4 celdas RGBA) + `Image.create_from_data` +
`blit_rect` en vez de los 1 024 `set_pixel` actuales (`vita_relay.gd:56-67`): ≈ 1–1,5 ms por tesela frente a ≈ 20 ms
[I]; textura troceada en sub-texturas de 128² y subida de **una sucia por fotograma** a ≤ 4 Hz (`HZ_TEXTURA`,
`vita_relay.gd:16`; H19). Sin *shaders* la paleta «map» se reduce a 3 colores (2 bit). Capa: textura en la planta
(por defecto) o 2–18 tri / 1–9 *draws* en 3D (cupo `mundo` = 12). Gate **G-W13-M4** (mapa 384² por relay con
LUT + `blit_rect`: `process` ≤ 4 ms, textura estable 5 min).

```gdscript
extends "res://comun/visor/display_ros_2d.gd"
## Mapa en planta (Vita y PC). Estándar: OccupancyGrid entero; compacto: teselas VC/1 vía vita_relay.gd.
const VitaRelay = preload("res://comun/vita_relay.gd")
var relay = VitaRelay.new()                           # mantiene mapa_img/mapa_tex y la época
var _sub_meta
func _init() -> void:
	latched = true
	topic_vita = "mapa_tesela"
	tipo_vita = "std_msgs/msg/UInt8MultiArray"
	hz = 0.0                                          # teselas: entregar todas
func conectar(v) -> void:
	canal.coalescer = false
	super.conectar(v)
	if canal.compacto:                                # la meta es latched aparte (F+TL)
		_sub_meta = v.contexto.nodo.create_subscription(v.prefijo_compacto + "/mapa_meta",
				"std_msgs/msg/Float32MultiArray", relay.on_mapa_meta, v.contexto.qos(false, 1, true))
func _procesar(msg):                                  # PC/planta: el OccupancyGrid entero (latched)
	return msg                                        # _pintar lo pasa a textura con la LUT (sin set_pixel)
func _procesar_compacto(msg):
	relay.on_mapa_tesela(msg)                         # V3: LUT + blit_rect dentro de vita_relay.gd
	return true
func _process(dt: float) -> void:
	super._process(dt)
	relay.actualizar_textura()                        # ≤ HZ_TEXTURA
	queue_redraw()                                    # [I] solo si cambió la textura: señal mapa_cambiado
func _draw() -> void:
	if relay.mapa_tex == null:
		return
	var o := px(relay.origen)
	var tam := Vector2(relay.ancho, relay.alto) * relay.resolucion * visor.px_por_m
	draw_texture_rect(relay.mapa_tex, Rect2(o - Vector2(0, tam.y), tam), false)   # norte arriba
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 1}
```

`_pintar` del camino estándar (no mostrado): `Image.create_from_data(w, h, false, FORMAT_RGBA8, data.to_byte_array())`
y, en planta sin *shader*, paso por la LUT de la paleta; en 3D (PC), el material de mapas#0 tal cual.

#### 4.6.2 Costmap en la Vita — V mapas#1 → módulo `costmap` (V11)

Sin *shaders* ni orden de transparencias (`docs/31` §2.4): el costmap se **compone en CPU sobre la imagen del mapa**
(una textura). El 2 bit de VC/1 pierde el degradado → formato nuevo ⚖ D5: `<p>/costmap_tesela` = `UInt8MultiArray`
`[ver_lo, ver_hi, tx, ty]` + tesela **32×16 a 4 bit** (0 desconocido, 1 libre = transparente, 2–13 degradado, 14
inscrito, 15 letal), 260 B (276 con rosbags), BE ≤ 10/s; `<p>/costmap_meta` como `mapa_meta`. El relay baja la
resolución por máximo a ≥ 10 cm. LUT de 16 colores sacada de la misma paleta (`PaletaViz.lut16_costmap()`, índices
`[255, 0, 8, 16, …, 88, 98, 99, 100]` de mapas#1). Costmap global de 10 cm 200×200 = 91 teselas ≈ 24 KB por repaso [I].
Gate **G-W13-M5**: costmap 4 bit (Nav2 + TB3), repaso completo ≤ 3 s, ≥ 30 FPS. Riesgo [?]: el costmap **local**
rodante (origen que se mueve con el robot) genera meta y teselas nuevas continuamente → §9.3.

#### 4.6.3 `map_msgs/OccupancyGridUpdate` — D mapas#3 → ⚖ D5.5

PC: parche con `Image.blit_rect` sobre la `Image` persistente y subida limitada a ≤ 10 Hz (`hz_subida`); se ignoran
updates sin mapa o fuera de límites (`map_display.cpp:353-410`). Código de mapas#3 tal cual (QoS
`contexto.qos(false, 5)`, como `rclcpp::QoS(5)` de RViz). `map_msgs` no está en el *typestore* de rosbags (habría que
registrar el `.msg`); 40 B + w·h ⇒ solo parches ≤ 21×21 caben. **Corrección del contrato** (⚖ D5.5): hoy el relay
sube `version` con cada `OccupancyGrid` (`vita_relay.py:235`), así que un costmap a 1–5 Hz invalidaría todas las
teselas cada vez: `version` pasa a ser **época de geometría** (solo sube si cambian resolución, tamaño u origen) y
los updates marcan teselas sucias sin tocarla.

#### 4.6.4 `GridCells` (`2d/celdas.gd`; `3d/celdas.gd` `solo_pc`) — V mapas#4

Celdas planas del mismo color. PC: `MultiMeshInstance3D` de losas (código de mapas#4). Vita: 36 + 24·n B ⇒ ≤ 18
celdas en directo (`TIPOS_VISOR`); planta 2D con `canvas_item_add_triangle_array` (1 llamada, 1 *quad* por celda,
cupo `resto_2d`), o fundidas en la tesela del costmap por el relay. Campos: `cell_width/height` (m), `cells[]`
(centros).

#### 4.6.5 `MapMetaData` (`hud/meta_mapa.gd`) — V mapas#5

Solo HUD: resolución, tamaño, origen, hora de carga; sirve para pre-dimensionar la imagen. 84 B: directo con
TRANSIENT_LOCAL (`TIPOS_VISOR`). Equivale a `<p>/mapa_meta`. Esqueleto de mapas#5 con `_procesar` → texto.

#### 4.6.6 `nav2_msgs/Costmap`, `VoxelGrid`; `grid_map_msgs/GridMap`; `octomap_msgs/Octomap` — V mapas#6–9 (`solo_pc`)

- **Costmap raw** (`<costmap>_raw`): preferir el `OccupancyGrid` `costmap` + `costmap_updates`. Si hace falta el coste
  exacto: textura `R8` directa (`uint8[]` → `PackedByteArray`) y paleta con la tabla de traducción de Nav2 ya aplicada
  (0→0, 1–252→1–98, 253→99, 254→100, 255→−1; `costmap_2d_publisher.cpp:101-109`). Código de mapas#6.
- **VoxelGrid**: solo vóxeles **marcados** (`(col >> (16+z)) & 1`, `voxel_grid.hpp:95-150`) a MultiMesh; mejor
  suscribir la PointCloud2 que ya genera Nav2. 200×200 columnas = 40 000 iteraciones GDScript ≈ 5–15 ms [I] → ≤ 2 Hz.
  `data` es `uint32[]` → `PackedInt64Array` en la Vita; en rclgd [?] (§9.3). Vita: relay → `nube2d`.
- **GridMap** (V14): malla de alturas (2 tri por celda) de una capa coloreada por otra; matriz *column-major* con búfer
  circular (`outer/inner_start_index`); `info.pose` = **centro** del mapa; índice (0,0) en la esquina +x,+y [I]. 100×100
  ≈ 30–60 ms en GDScript [I] → ≤ 1 Hz. Vita: relay a raster 2D (reutilizando el formato de `costmap_tesela` como
  rampa de altura); malla 3D ≤ 64×64 solo tras verde de E-W8-2.
- **Octomap** (V14): decodificador binario (2 B por nodo, 2 bit por hijo: 01 ocupado, 11 con hijos; raíz de lado
  `res·2^16`) viable en GDScript en el PC (mapa de habitación a 5 cm ≈ 25–100 k nodos ≈ 50–300 ms [I] → hilo o
  ≤ 0,2 Hz). Vita: relay → lista de vóxeles ocupados a `nube2d`. Código de mapas#9.

Ninguno de `map_msgs`, `nav2_msgs`, `grid_map_msgs`, `octomap_msgs` entra en `TIPOS_VISOR` (⚖ D10): en la Vita
llegan compactados y en el PC rclgd los resuelve por ament.

### 4.7 Marcadores (familia `mapas-marcadores`, segunda mitad)

Regla de capa en la Vita (ADR 0011, `docs/31` §0): **sólido rígido → 3D por instancia** (mover = cambiar
`transform`, 0 B de arena); **líneas, puntos, texto → 2D** en un comando por display (H16–H17); **raster →
textura**. Cupo `marcadores`: HMI 12 / Viz 32 (⚖ D7; la ficha proponía 48).

#### 4.7.1 Gestor de `Marker` (`3d/marcadores.gd`) — D mapas#10 → corrección aplicada

Semántica de RViz2 Jazzy (`marker_common.cpp:205-310`, `marker_base.cpp:84-115`):

- **Clave** ns → {id → entrada}; DELETEALL con `ns` no vacío borra solo ese ns (`marker_common.cpp:224-229`) [V].
- **Acciones**: 0 ADD = MODIFY; 2 DELETE; 3 DELETEALL. Si cambia `type`, se recrea (`:282-287`). NaN/Inf ⇒ se rechaza
  (`:195-213`).
- **Caducidad**: si `lifetime` > 100 µs, `expira = ahora + lifetime` con el reloj **de recepción** (`:305`,
  `marker_base.cpp:84`) → `Time.get_ticks_msec()`, barrido a 4 Hz.
- **frame_locked**: sin él, el marco se resuelve una vez; con él, cada fotograma (`marker_base.cpp:100-115`).
- **Reciclado**: los nodos borrados se ocultan y vuelven a un pool por tipo; nunca `queue_free` en régimen estable.
  Tope = `cupo`.
- **Corrección de check-only** (`W13-revision.md:58`): `var tf: RosTfListener` **no compila en `ros2_vita`** («Could
  not find type "RosTfListener"») → sin anotar; además el marco ya lo resuelve la base / `visor.transformada()`.
- API extra para otros displays: `poner_compacto(clave, tipo, t, escala, color)` y `retener_solo(claves)` (cliente del
  relay), `mover_ns(ns, t)` y `borrar_ns(ns)` (marcadores interactivos, PC).

```gdscript
extends "res://comun/visor/display_ros_3d.gd"
## Gestor de Marker/MarkerArray (marker_common.cpp:205-310). Directo (PC) o estado completo del relay (Vita).
const Fab = preload("res://comun/visor/fabrica_marcadores.gd")
const Prim = preload("res://comun/visor/primitivas_viz.gd")
var _ns := {}                                   # ns → {id → {n, tipo, expira, frame, pose, locked}}
var _pool := {}                                 # tipo → Array de nodos ocultos
var _total := 0
var _t_barrido := 0
func _init() -> void:
	capa = "marcadores"
	hz = 0.0                                    # cada mensaje cuenta (acciones)
	topic_vita = "marcadores"
	tipo_vita = "std_msgs/msg/Float32MultiArray"
func conectar(v) -> void:
	canal.coalescer = false
	super.conectar(v)
func _procesar(msg):                            # Marker o MarkerArray
	var lista: Array = msg.markers if "markers" in msg else [msg]
	for m in lista:
		match int(m.action):
			0: _add(m)
			2: _borrar(m.ns, m.id)
			3:
				for ns in ([m.ns] if m.ns != "" else _ns.keys()):
					for id in _ns.get(ns, {}).keys():
						_borrar(ns, id)
	return null                                 # el gestor pinta él mismo; la base no mueve el nodo raíz
func _add(m) -> void:
	var tabla: Dictionary = _ns.get_or_add(m.ns, {})
	var e = tabla.get(m.id)
	if e != null and e.tipo != m.type:
		_borrar(m.ns, m.id)
		e = null
	if e == null:
		if _total >= cupo:
			return
		var libres: Array = _pool.get_or_add(m.type, [])
		e = {"n": libres.pop_back() if libres.size() > 0 else Fab.crear(m.type), "tipo": m.type}
		if e.n.get_parent() == null:
			add_child(e.n)
		tabla[m.id] = e
		_total += 1
	var vida: float = m.lifetime.sec + m.lifetime.nanosec * 1e-9
	e.expira = Time.get_ticks_msec() + int(vida * 1000.0) if vida > 1e-4 else -1
	e.frame = String(m.header.frame_id).trim_prefix("/")
	e.locked = m.frame_locked
	e.pose = Prim.pose_godot(m.pose)
	var t = visor.transformada(e.frame)
	e.n.visible = t != null and Fab.aplicar(e.n, m, visor)     # Fab fija malla, color y escala; false = no dibujar
	if t != null:
		e.n.transform = (t as Transform3D) * (e.pose as Transform3D)
func _borrar(ns: String, id: int) -> void:
	var e = _ns.get(ns, {}).get(id)
	if e != null:
		e.n.visible = false
		_pool.get_or_add(e.tipo, []).append(e.n)
		_ns[ns].erase(id)
		_total -= 1
func _process(dt: float) -> void:
	super._process(dt)
	var ahora := Time.get_ticks_msec()
	if ahora - _t_barrido < 250:                # caducidad y frame_locked a 4 Hz
		return
	_t_barrido = ahora
	for ns in _ns.keys():
		for id in _ns[ns].keys():
			var e = _ns[ns][id]
			if e.expira >= 0 and ahora > e.expira:
				_borrar(ns, id)
			elif e.locked:
				var t = visor.transformada(e.frame)
				if t != null:
					e.n.transform = (t as Transform3D) * (e.pose as Transform3D)
func _coste() -> Dictionary: return {"instancias": 32, "triangulos": 32 * 24, "quads": 0}
```

Detalle: `_procesar` devuelve `null`, así que la base no recoloca el nodo raíz (cada marcador lleva su marco). El
cliente compacto (§4.7.4) sobreescribe `_procesar_compacto`. En la Vita un `Marker` suelto cabe en directo hasta 10
puntos (229 B sin puntos, 469 con 10, 493 con 11 [V recalculado]); `visualization_msgs/Marker` entra en
`TIPOS_VISOR`.

#### 4.7.2 `FabricaMarcadores` (`fabrica_marcadores.gd`) y tipos de Marker — V mapas#11–24, D mapas#21

⚖ D2: la fábrica **solo traduce** `Marker.type` / `shape_msgs` → `PrimitivasViz`; no define mallas ni colores.

| `type` | Representación | Campos | Vita | Tri / *draws* |
|---|---|---|---|---|
| 0 ARROW (pose) | `FLECHA` escalada por `scale` (largo, ancho, alto); x·y·z = 0 ⇒ oculto | `pose`, `scale`, `color` | 3D instancia | 24 / 1 |
| 0 ARROW (2 `points`) | `CILINDRO` (cuerpo) + `CONO` (cabeza 0,23·d o `scale.z`) orientados con `looking_at`; 1 punto ⇒ error | `points[0..1]`, `scale.x/y/z` | 3D, 2 instancias | ≈ 48 / 2 |
| 1 CUBE · 2 SPHERE · 3 CYLINDER | malla unidad + `escala_ros(scale)` (SPHERE: diámetros; CYLINDER: diámetros x,y y altura z) | `pose`, `scale`, `color` | 3D instancia + paleta | 12 / 8 / 32 |
| 4 LINE_STRIP · 5 LINE_LIST | Vita: superposición 2D `draw_polyline_colors` / `draw_multiline_colors` reproyectada ≤ 20 Hz; PC: prismas de 3 caras (6 tri/seg) con color por vértice | `points`, `colors` (si `size == points.size`), `scale.x` = ancho | 2D (`2d/marcadores_2d.gd`) | 1 comando |
| 6 CUBE_LIST · 7 SPHERE_LIST | PC: MultiMesh con color por instancia (`solo_pc`); Vita: **una** malla horneada con UV a paleta (12 tri/cubo, octaedro 8 tri/esfera) si ≤ 64 y ≤ 1 Hz; si no, 2D | `points`, `scale`, `colors` | horneado o 2D | 768 / 1 (64 cubos) |
| 8 POINTS | 2D: un *quad* por punto en **una** `canvas_item_add_triangle_array`, tamaño en px por la focal (522 px con fov 55°, `docs/31` §2.2) | `points`, `scale.x/y`, `colors` | 2D | 1 comando |
| 9 TEXT_VIEW_FACING | ⚖ D11: `visor.texto.poner(clave, pos, text, color)`; `Label3D` solo `solo_pc` | `pose.position`, `text`, `scale.z` (alto) | 2D `draw_string` | ≤ 40 glifos |
| 10 MESH_RESOURCE | tabla `package://` → `res://` de mallas horneadas (como el URDF, ADR 0009); PC: `GLTFDocument` en caliente; si falta, cubo + aviso | `mesh_resource`, `mesh_use_embedded_materials`, `scale` | solo horneadas | ≤ 1 000 tri (H5) |
| 11 TRIANGLE_LIST | `ArrayMesh`; Vita con UV a paleta por triángulo; reconstruir solo si cambia el *hash*; ≤ 1 000 tri | `points` (×3), `colors` | 3D estático | 60 B/tri (H9) |
| 12 ARROW_STRIP (Jazzy) | LINE_STRIP + punta ARROW en el último segmento; `marker_factory.cpp:71-103` no lo dibuja [V] | `points ≥ 2` | 2D + 3D | semántica [?] |

**Corrección D mapas#21** (⚖ D11): el post usaba un `Label` del HUD por texto; un `Label` por texto multiplica
elementos y lotes del lienzo (doc 34: 222 *draws* con 305 *quads*) → `TextoSuperpuesto`. Esqueleto de la fábrica:

```gdscript
extends RefCounted
## FabricaMarcadores (ADR 0013 §1): Marker / shape_msgs → instancias de PrimitivasViz. No define mallas.
const Prim = preload("res://comun/visor/primitivas_viz.gd")
const Paleta = preload("res://comun/visor/paleta_viz.gd")
const ARROW := 0
const TEXT := 9

static func crear(tipo: int) -> Node3D:
	var n := MeshInstance3D.new()
	if tipo == ARROW:                                # cuerpo y cabeza para el modo «2 puntos»
		for h in ["cuerpo", "cabeza"]:
			var c := MeshInstance3D.new()
			c.name = h
			n.add_child(c)
	return n

## Devuelve false si el marcador no se dibuja (escala nula, puntos inválidos…).
static func aplicar(n: Node3D, m, visor) -> bool:
	var col := Paleta.indice(Paleta.de_ros(m.color))
	match int(m.type):
		0:
			if m.points.size() == 2:
				return _flecha_puntos(n, m, col)
			n.mesh = Prim.malla(Prim.FLECHA, col)
			n.scale = Vector3(m.scale.y, m.scale.z, m.scale.x)
			return m.scale.x * m.scale.y * m.scale.z != 0.0
		1, 2, 3:
			n.mesh = Prim.malla(int(m.type), col)
			n.scale = Prim.escala_ros(m.scale)
			return m.scale.x * m.scale.y * m.scale.z != 0.0
		TEXT:
			if visor.texto:
				visor.texto.poner("%s/%d" % [m.ns, m.id], n.global_position, String(m.text), Paleta.de_ros(m.color))
			return false                                  # nada 3D que dibujar
	return false                                          # 4–8, 10–12: ver la tabla (2D, horneado, recursos)

static func _flecha_puntos(n: Node3D, m, col: int) -> bool:   # arrow_marker.cpp:108-152
	var a := rclgd.ros_to_godot_vector(Vector3(m.points[0].x, m.points[0].y, m.points[0].z))
	var b := rclgd.ros_to_godot_vector(Vector3(m.points[1].x, m.points[1].y, m.points[1].z))
	var d := b - a
	var dist := d.length()
	if dist < 1e-6 or m.scale.x + m.scale.y == 0.0:
		return false
	var cabeza: float = clampf(m.scale.z, 0.0, dist) if m.scale.z != 0.0 else 0.23 * dist
	var arriba := Vector3.UP if absf(d.normalized().y) < 0.99 else Vector3.RIGHT
	var base := Basis.looking_at(d, arriba)
	var c := n.get_node("cuerpo") as MeshInstance3D
	var h := n.get_node("cabeza") as MeshInstance3D
	c.mesh = Prim.malla(Prim.CILINDRO, col)
	h.mesh = Prim.malla(Prim.CONO, col)
	c.transform = Transform3D(base.scaled_local(Vector3(m.scale.x, m.scale.x, dist - cabeza)), a)
	h.transform = Transform3D(base.scaled_local(Vector3(m.scale.y, m.scale.y, cabeza)), a + d.normalized() * (dist - cabeza))
	return true
```

[I] El `CILINDRO` de `PrimitivasViz` va sobre +Y (eje Z de ROS, para `CYLINDER`); para el cuerpo de la flecha hace
falta la variante sobre −Z (`CILINDRO_Z` de mapas#12): añadir la forma o rotar 90° en `_flecha_puntos` (decidir en
V8). El horneado de listas (`hornear_lista`, tablas `OCTA_CARAS`/`CUBO_CARAS`), `lineas_3d` (prismas, PC),
`malla_triangulos`, `resolver`/`cargar_malla` (MESH_RESOURCE) y `aplicar_arrow_strip` se copian de mapas#17, #19,
#22, #23 y #24 cambiando `Paleta.uv(color)` por `Paleta.uv(Paleta.indice(color))` y `material()` por
`Paleta.material()`.

Superposición 2D de LINE_STRIP / LINE_LIST / POINTS (`2d/marcadores_2d.gd`, `en_pantalla = true`, capa `resto_2d`
≤ 150): el `_draw()` de mapas#16 (líneas) y mapas#20 (puntos) tal cual, con `cam = visor.camara`; reproyección ≤ 20 Hz
(≈ 10–15 µs por punto en GDScript [I], `docs/31` §3). Gate **G-W13-M7**: LINE_STRIP 50 puntos y POINTS 180 en 2D con
la cámara orbitando, `process + canvas` ≤ 2–3 ms.

#### 4.7.3 `shape_msgs` — V mapas#29–31

`SolidPrimitive` → (malla unidad, escala Godot); **SPHERE = radio** (Marker usa diámetro); CYLINDER/CONE
`[altura, radio]` sobre Z; PRISM = extrusión ±altura/2 de un polígono CCW (`4n − 4` tri). `Mesh` → `ArrayMesh`
indexada en el PC (la Vita la aplana sola, H3: 60 B/tri; solo estáticas ≤ 1 000 tri); sentido de las caras no fijado
por ROS (invertir 1-2 si se ve por dentro). `Plane` → `PlaneMesh` de 4×4 m en el punto `−d·n/|n|²` (2 tri). Código de
mapas#29–31 dentro de `fabrica_marcadores.gd` (`primitiva(sp)`, `prisma`, `malla_shape`, `plano`), con mallas de
`PrimitivasViz` y material de `PaletaViz`.

#### 4.7.4 `MarkerArray` en la Vita — A mapas#25 → ⚖ D14

50 CUBE = 11 605 B (`docs/27:79`): nunca directo. ⚖ D14: el relay aplica él la semántica (ADD/DELETE/DELETEALL/
lifetime) y publica a 5 Hz el **estado completo** en trozos best effort de `<p>/marcadores` = cabecera común
`[seq, trozo, n_trozos, n]` + **10 floats** por marcador `[clave, tipo, x, y, z, yaw, sx, sy, sz, color]`, **n ≤ 11**
por datagrama (114 floats = 472 B), tope de **33** marcadores (3 trozos) por ciclo. `clave = (id ⊕ hash(ns)) & 0xFFFFFF`
(exacta en float32); `color = índice de paleta + 256·alfa(0–15)`. Al completar un `seq`, la Vita **recicla lo que no
llegó** (un DELETE perdido en best effort no deja fantasmas). Se pierde alabeo y cabeceo (solo `yaw`). Se descartan
los 8 floats de `docs/27:105` (con el tope de 33 también necesitan 3 trozos: no se ahorra ningún datagrama) y enviar
acciones. Puntos de líneas/listas: `<p>/marcador_puntos` = cabecera + `[clave, tipo, color, ancho]` + xyz·n, n ≤ 36
(480 B), ≤ 4 trozos/s; textos: `<p>/marcador_texto` = String `clave|x|y|z|texto` (≤ 80 car.), **fiable**, ≤ 2 Hz.
Gates **G-W13-M1** (pool lleno a 10 Hz: `drawn` +cupo, `avg_submit_us` ≤ 9 000, ≥ 30 FPS) y **G-W13-M3** (10 % de
pérdida con netem: sin fantasmas > 0,4 s, `process` ≤ 4 ms, ≤ 15 KB/s).

```gdscript
## En 3d/marcadores.gd: cliente de <p>/marcadores (estado completo por trozos).
const POR_MARCADOR := 10
var _seq := -1
var _vistos := {}
var _trozos := 0

func _procesar_compacto(msg):
	var d: PackedFloat32Array = msg.data
	var cab: Dictionary = Vc1.cabecera(d)           # {seq, trozo, n_trozos, n}
	if cab.is_empty():
		return null
	if cab.seq != _seq:
		_seq = cab.seq
		_vistos.clear()
		_trozos = 0
	_trozos += 1
	for i in cab.n:
		var b := 4 + i * POR_MARCADOR
		if b + POR_MARCADOR > d.size():
			break
		var clave := int(d[b])
		var col := int(d[b + 9])
		_vistos[clave] = true
		poner_compacto(clave, int(d[b + 1]),
				Transform3D(Basis(Vector3.UP, d[b + 5]), rclgd.ros_to_godot_vector(Vector3(d[b + 2], d[b + 3], d[b + 4]))),
				Vector3(d[b + 7], d[b + 8], d[b + 6]),               # escala en ejes Godot (sy, sz, sx)
				col & 0xFF)
	if _trozos == cab.n_trozos:
		retener_solo(_vistos)                       # estado completo: lo no visto vuelve al pool
	return null
```

(`poner_compacto` crea o reutiliza la entrada `_ns[""][clave]` con `Prim.malla(tipo, indice)` y `retener_solo` borra
las claves ausentes; `const Vc1 = preload("res://comun/ros/vc1.gd")`.) El yaw ROS alrededor de +Z es un giro
alrededor de +Y en Godot con el mismo signo (rotación propia) [I: comprobar con un marcador girado en V8].

#### 4.7.5 Marcadores interactivos — D mapas#26, D mapas#27 → correcciones; Vita aplazado (V14)

- **Cliente** (`3d/im_cliente.gd`, `solo_pc`): estado inicial por el servicio `<ns>/get_interactive_markers`, luego
  `<ns>/update` con `seq_num` (hueco ⇒ pedir el estado otra vez); cada control se dibuja con sus Marker (gestor) y un
  asa `Area3D` según `interaction_mode`. **Corrección de check-only** (`W13-revision.md:59`): `RosClient` no existe en
  `ros2_vita` y faltaba el `preload` de la fábrica → `const Fab = preload("res://comun/visor/fabrica_marcadores.gd")`,
  `var _cli` **sin anotar** y el script marcado `solo_pc`. En la Vita los servicios cliente están ⏳
  (`API_PARITY.md:31`): ⚖ los marcadores interactivos en la Vita (`im_poses`, relay como cliente) quedan **aplazados**
  a V14 / T-W4-9.
- **Feedback** (`herramientas/im_feedback.gd`): arrastre con ratón (PC) o táctil frontal (Vita, cuando se active):
  rayo de cámara ∩ plano del control → pose; POSE_UPDATE limitado a 20 Hz entre MOUSE_DOWN y MOUSE_UP. 149 B
  (157 con nombres reales). **Dos correcciones**: (1) check-only (`W13-revision.md:60`): `var pulsado := (… or …)`
  no compila («Cannot infer the type», operandos `Variant`) → `var pulsado: bool = …`; (2) ⚖ C9: el servidor IM
  suscribe el feedback con `rclcpp::QoS(1)` = **fiable** (`interactive_marker_server.hpp:87-88`, jazzy) y un
  publicador best effort no casa → **fiable**, profundidad 1.

```gdscript
extends "res://comun/visor/herramienta_visor.gd"
## Feedback de marcador interactivo (MOVE_PLANE). Publica FIABLE (C9): el servidor suscribe con rclcpp::QoS(1).
@export var hz_feedback := 20.0
var im_nombre := ""
var control := ""
var objetivo: Node3D                                  # nodo del control que se arrastra
var _plano: Plane
var _activo := false
var _t := 0
func _init() -> void:
	tipo = "visualization_msgs/msg/InteractiveMarkerFeedback"
	fiabilidad = 0                                    # FIABLE (antes BE en mapas#27)
func _unhandled_input(ev: InputEvent) -> void:
	var pulsado: bool = (ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT) or ev is InputEventScreenTouch   # ← corrección
	if pulsado and ev.pressed and not _activo:
		_activo = true
		_plano = Plane(objetivo.global_basis.x, objetivo.global_position)
		_enviar(4)                                    # MOUSE_DOWN
	elif pulsado and not ev.pressed and _activo:
		_activo = false
		_enviar(5)                                    # MOUSE_UP
	elif _activo and (ev is InputEventMouseMotion or ev is InputEventScreenDrag):
		var cam: Camera3D = visor.camara
		var p = _plano.intersects_ray(cam.project_ray_origin(ev.position), cam.project_ray_normal(ev.position))
		if p != null:
			objetivo.global_position = p
			if Time.get_ticks_msec() - _t >= int(1000.0 / hz_feedback):
				_t = Time.get_ticks_msec()
				_enviar(1)                            # POSE_UPDATE
func _enviar(evento: int) -> void:
	var f := RosMsg.from_type(tipo)
	f.header.frame_id = visor.marco_fijo
	f.header.stamp = visor.contexto.nodo.now()
	f.client_id = "/vita" if OS.has_feature("vita") else "/godot"
	f.marker_name = im_nombre
	f.control_name = control
	f.event_type = evento
	var p := rclgd.godot_to_ros_vector(objetivo.global_position)
	var q := rclgd.godot_to_ros_quat(objetivo.global_basis.get_rotation_quaternion())
	f.pose.position.x = p.x
	f.pose.position.y = p.y
	f.pose.position.z = p.z
	f.pose.orientation.x = q.x
	f.pose.orientation.y = q.y
	f.pose.orientation.z = q.z
	f.pose.orientation.w = q.w
	publicar(f)
```

`topic` = `<ns>/feedback`. La HerramientaVisor usa profundidad 1 en la Vita y 5 en el PC; ⚖ la tabla de C9 pide 1 para
el feedback IM en los dos: fijarlo en V14.

#### 4.7.6 `ImageMarker` (`hud/marcas_imagen.gd`) — V mapas#28

Superposición 2D sobre la imagen de cámara (pestaña Cámara): un `Control` con `_draw` que escala de píxeles de la
imagen **original** a píxeles de pantalla (si el relay reduce la imagen a 160×120, escalar con el ancho real de
`CameraInfo`); mismo gestor ns+id+lifetime, en 2D (círculo, LINE_STRIP, LINE_LIST, POLYGON, POINTS). 124 B + 24 por
punto ⇒ ≤ 15 puntos directo (`TIPOS_VISOR`). Esqueleto de mapas#28 con `extends display_ros_hud.gd` y
`_procesar` → actualizar `_m` y devolver `true`.

### 4.8 HMI, percepción, acciones y herramientas (familia `hmi-percepcion-acciones`)

Kit común: todos los widgets son `DisplayRosHud` (⚖ D1: `widget_hud.gd` desaparece), dibujan en su `_draw()` con
`draw_string`/`draw_rect`/polilíneas finas, usan los colores de estado de `PaletaViz` (rqt_robot_monitor) y viven en
una pestaña de `GestorHud` o en la barra fija. Caducidad por widget: 2 s por defecto, 15 s batería, 10 s por fila en
diagnósticos (`timeline.py:161-163`) [V]; los widgets de eventos (lifecycle, estado de acción, `/rosout`) no caducan.

#### 4.8.1 `DiagnosticArray` (`hud/diagnostico.gd`) — M hmi#7 → G-W13-H0

Tabla tipo rqt_robot_monitor: cuadro de color + nivel + nombre + mensaje, de peor a mejor, STALE por fila a 10 s,
filtro «solo problemas»; detalle de `KeyValue` al tocar una fila. Campos: `status[].level` (byte: 0 OK, 1 WARN,
2 ERROR, 3 STALE; llega como entero [I] → `int(...)` defensivo), `name`, `message`, `values[]`. ⚖ D6: pestaña
Diagnóstico de **8 filas × 30 caracteres**, «solo problemas» por defecto en la Vita (la ficha: 12 filas ≈ 500 *quads*
[I] > 400 del HUD entero). Vita: 1 estado = 76 B; 1×3 KV = 157; 5×3 = 685 ⇒ con > 2 estados ya no cabe en BE →
relay `<p>/diagnostics` = `DiagnosticArray` de **1 estado** por mensaje, ≤ 3 pares, textos ≤ 40 car. (≈ 160 B [I]),
solo los que cambian + repaso 1 Hz, BE, ≤ 10 Hz (el tipo estándar se conserva: el widget no cambia, solo el topic).
Diagnósticos pequeños (≤ 7,5 KiB a 1 Hz) pueden ir directos en fiable. Gate **G-W13-H0** antes de fijar filas.

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
const TEXTO := ["OK", "WARN", "ERROR", "STALE"]
@export var max_filas := 8
@export var ancho_max := 30
@export var caducidad_fila_s := 10.0
@export var solo_problemas := false
var _filas := {}                                      # nombre -> [nivel, mensaje, t_ms]
func _init() -> void:
	topic = "/diagnostics_agg"
	tipo = "diagnostic_msgs/msg/DiagnosticArray"
	topic_vita = "diagnostics"
	tipo_vita = tipo
	caducidad_s = 0.0
func conectar(v) -> void:
	canal.coalescer = false                           # cada estado del relay llega en su mensaje
	if v.en_vita:
		solo_problemas = true
	super.conectar(v)
func _procesar(msg):
	var ahora := Time.get_ticks_msec()
	for st in msg.status:
		_filas[String(st.name)] = [int(st.level), String(st.message), ahora]
	return true
func _draw() -> void:
	var fuente := get_theme_default_font()
	var ahora := Time.get_ticks_msec()
	var claves := _filas.keys()
	claves.sort_custom(func(a, b): return _filas[a][0] > _filas[b][0])
	var y := 14.0
	var n := 0
	for k in claves:
		var nivel: int = 3 if ahora - _filas[k][2] > caducidad_fila_s * 1000.0 else clampi(_filas[k][0], 0, 3)
		if (solo_problemas and nivel == 0) or n >= max_filas:
			continue
		draw_rect(Rect2(2, y - 10, 10, 10), [Paleta.OK, Paleta.WARN, Paleta.ERROR, Paleta.STALE][nivel])
		draw_string(fuente, Vector2(16, y), ("%s %s: %s" % [TEXTO[nivel], k, _filas[k][1]]).left(ancho_max),
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 18, 12)
		y += 14.0
		n += 1
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": max_filas * (ancho_max + 1)}
```

#### 4.8.2 `rcl_interfaces/Log` = `/rosout` (`hud/consola.gd`) — M hmi#8 → G-W13-H0

Consola de N líneas coloreadas por nivel (10 D, 20 I, 30 W, 40 E, 50 F), filtro por nivel mínimo y subcadena de
nodo, pausa. ⚖ D6: **6 líneas × 40 caracteres** en la Vita (la ficha: 10 líneas ≈ 600 *quads*). Vita: relay
`<p>/rosout` = **mismo tipo `Log`**, solo nivel ≥ WARN, `file`/`function` vaciados, `msg` ≤ 200 car. (≈ 270 B [I]),
≤ 10 msg/s; ⚖ QoS **fiable** (la ficha decía best effort: un aviso perdido no se repite). En el PC: `/rosout` es
RELIABLE + TRANSIENT_LOCAL en el emisor; aquí VOLATILE (sin historial). Escribir desde la Vita: `RosLogger` ❌ (§1.4);
un publicador propio de `Log` sería posible añadiendo el esquema. Esqueleto de hmi#8 con el cambio de base, `_init`
con `fiabilidad = 2`, `topic_vita = "rosout"`, `tipo_vita = tipo`, `caducidad_s = 0`, `canal.coalescer = false` y
`max_lineas = 6 if en_vita`; `_procesar` añade la línea y devuelve `true`. Prueba de hardware (V6): 20 avisos/s durante
5 min, FPS sin bajar de escalón, `reliable_dropped` = 0.

#### 4.8.3 `lifecycle_msgs/TransitionEvent` (`hud/lifecycle.gd`) — V hmi#9

Fila por nodo gestionado: verde activo, amarillo inactivo/transitorio, rojo error, gris desconocido. Campos:
`goal_state.id` (1 sin configurar, 2 inactivo, 3 activo, 4 finalizado; 10–15 transitorios, 15 error),
`transition.label`. 65 B; **fiable** (solo hay mensaje al cambiar). `topic = <nodo>/transition_event`. Sin servicios en
la Vita: estado inicial «desconocido» hasta la primera transición o por el proxy `srv` del puente (`docs/32` §12).
`caducidad_s = 0` (evento). Esqueleto de hmi#9 con el cambio de base y `fiabilidad = 2`.

#### 4.8.4 `Detection2DArray` (`hud/cajas_2d.gd`) — D hmi#10 → ⚖ D12

Rectángulos con etiqueta y % de score sobre el `TextureRect` de la cámara, escalados de píxeles de la imagen
**original** al widget. Campos: `detections[].bbox` (`center` Pose2D + `size_x/y` px; `theta` se ignora [I]),
`results[0].hypothesis.class_id/score`. ⚖ D12: una detección ya ocupa 449–474 B (la covarianza 6×6 de
`ObjectHypothesisWithPose` son 288 B) → relay `<p>/detecciones` = Float32 cabecera común + `[ancho, alto]` +
`[clase, score, cx, cy, w, h]·n`, **n ≤ 18** (472 B; la ficha daba n ≤ 19 con otra cabecera) + `<p>/det_clases`
(String F+TL con los nombres), 5 Hz. Se pierden `id` e hipótesis múltiples (se envía la mejor clase). Cupo
`resto_2d`: detecciones ≤ 150 *quads*. `vision_msgs` no entra en `TIPOS_VISOR` (D10).

```gdscript
extends "res://comun/visor/display_ros_hud.gd"
## Cajas 2D sobre la imagen. datos = [Vector2 tamaño imagen, Array de [Rect2 px imagen, etiqueta, score]].
@export var ancho_imagen := 640.0
@export var alto_imagen := 480.0
@export var umbral_score := 0.3
var clases := PackedStringArray()                     # de <p>/det_clases
func _init() -> void:
	tipo = "vision_msgs/msg/Detection2DArray"
	topic_vita = "detecciones"
	tipo_vita = "std_msgs/msg/Float32MultiArray"
	fiabilidad = 2                                    # en el PC: 1 det. ≈ 470 B, 3 = 1 377 B
	hz_vita = 5.0
func _procesar(msg):
	var cajas := []
	for d in msg.detections:
		var etiqueta := String(d.id)
		var score := 1.0
		if d.results.size() > 0:
			etiqueta = String(d.results[0].hypothesis.class_id)
			score = float(d.results[0].hypothesis.score)
		if score >= umbral_score:
			var s := Vector2(d.bbox.size_x, d.bbox.size_y)
			cajas.append([Rect2(Vector2(d.bbox.center.position.x, d.bbox.center.position.y) - s * 0.5, s), etiqueta, score])
	return [Vector2(ancho_imagen, alto_imagen), cajas]
func _procesar_compacto(msg):                         # [seq, trozo, n_trozos, n, ancho, alto, (clase, score, cx, cy, w, h)·n]
	var d: PackedFloat32Array = msg.data
	if d.size() < 6:
		return null
	var cajas := []
	for i in mini(int(d[3]), (d.size() - 6) / 6):
		var b := 6 + 6 * i
		var k := int(d[b])
		if d[b + 1] >= umbral_score:
			var s := Vector2(d[b + 4], d[b + 5])
			cajas.append([Rect2(Vector2(d[b + 2], d[b + 3]) - s * 0.5, s), clases[k] if k < clases.size() else str(k), d[b + 1]])
	return [Vector2(d[4], d[5]), cajas]
func _draw() -> void:
	if datos == null:
		return
	var k: Vector2 = size / (datos[0] as Vector2)
	var fuente := get_theme_default_font()
	for c in datos[1]:
		var r: Rect2 = c[0]
		var col := color_estado(Color.from_hsv(float(absi(hash(c[1])) % 360) / 360.0, 0.8, 1.0))
		draw_rect(Rect2(r.position * k, r.size * k), col, false, -1.0)
		draw_string(fuente, r.position * k + Vector2(2, -2), "%s %d%%" % [c[1], roundi(c[2] * 100.0)],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)
func _coste() -> Dictionary: return {"instancias": 0, "triangulos": 0, "quads": 150}
```

(`det_clases` se suscribe en `conectar()` como suscripción auxiliar *latched*, igual que `joints_orden` en §4.3.5.)

#### 4.8.5 `Detection3DArray` (`2d/cajas_3d.gd`, superpuesto) — D hmi#11 → ⚖ D12

Cajas de alambre: 12 aristas por caja proyectadas al lienzo con **una** `draw_multiline` (H17), idéntico en PC y Vita
(no hay líneas 3D sin *shaders*; precio: no se ocultan tras el robot, `docs/31` §3); etiqueta en el centro con
`TextoSuperpuesto`. Alternativa con oclusión: `CUBO` de la paleta (12 tri) del cupo de marcadores. Campos:
`bbox.center` (Pose) y `bbox.size` (m) en `header.frame_id`. ⚖ D12: «1 detección = 489 B, no cabe por 1 B» era un
artefacto de convención (485 B de carga), pero con nombres reales son 505 B → relay `<p>/detecciones3d` = cabecera
común + `[clase, score, x, y, z, yaw, sx, sy, sz]·n`, **n ≤ 12** (464 B; la ficha daba 13), 5 Hz. Coste: 12 cajas × 8
`unproject` ≈ 1–1,5 ms por fotograma de reproyección [I] → reproyectar a ≤ 20 Hz, no cada fotograma. Base
`DisplayRos2D` con `en_pantalla = true`; `_procesar`/`_procesar_compacto` → `Array` de 8 esquinas (Godot, marco del
mensaje) por caja; `_draw()` = el de hmi#11 multiplicando por `marco` (Transform3D de la base) en vez de
`marco_fijo.global_transform`.

#### 4.8.6 `JointTrajectory` → fantasma (`3d/fantasma.gd`) — M hmi#12 → ⚖ D7

Segunda instancia del robot horneado que recorre los puntos en bucle según `time_from_start` (interpolación lineal,
pausa final 0,5 s), con `set_joints`. ⚖ D7: en la Vita **solo con el robot oculto** (sustituye al robot en el cupo
`robot`) **o solo la cadena del brazo (≤ 8 instancias, de la reserva)**; color plano distinto (sin transparencia fiable
en 3D, `docs/31` §2.4). 6 juntas × 1 punto = 228 B (cabe, patrón *fire-and-forget*); planes de MoveIt por el puente
`/vita/accion/trayectoria` (Int16MultiArray ≤ 32 puntos, 476 B, `docs/32:81`). Por medir: `[gxm3d] drawn=` con el
fantasma del brazo junto al robot. Esqueleto de hmi#12 con `_procesar` → `[nombres, tiempos, posiciones]` y el
bucle en `_process`; `capa = "reserva"` y `_coste().instancias = 8`.

#### 4.8.7 `JointTrajectoryControllerState` (`hud/controlador.gd`) — V hmi#13

Barras por junta: real (azul), referencia (marca naranja), |error| en rojo si pasa `tolerancia` (0,05 rad). 7 juntas =
1 340 B, 14 = 2 404 B → **fiable** a ≤ 5 Hz (la plantilla ya lo publica fiable a 2 Hz con XRCE,
`plantillas/sensores/estado_controlador.gd:9-13`); esquema propio en `plantillas/ros/msg/control_msgs`. Pestaña
Controlador: 14 juntas, solo barras. **Trampa** (verificada con check-only): `m.reference` resuelve a
`RefCounted.reference()` → `m.get_member("reference").positions` (como `estado_controlador.gd:36-41`). Esqueleto de
hmi#13 con el cambio de base (`_procesar` → `[nombres, ref, real, err]`).

#### 4.8.8 Plan frente a real (`2d/plan_real.gd`) — D hmi#14 → corrección parcial

Dos polilíneas en planta: plan (verde) y rastro real (azul), mismo script en PC (`Path` + `Odometry`) y Vita
(`path_compacto` + `pose2d`). ⚖ D5.4: se usa `/vita/pose2d` de **6 floats** (no la ampliación a 10 de geom#13). Ojo
marcos: el plan va en `map` y la odometría en `odom` [V]; en la Vita `TfLigero` solo conoce `map → odom` si se activa
el módulo `tf` del relay con ese marco en la lista blanca; si no, se dibujan los dos en el marco fijo suponiendo
`map ≈ odom` (deriva visible) [I] → §9.3. Implementación: **dos displays** del contrato (el `2d/path.gd` de §4.3.2 y
el `2d/odometria.gd` de §4.3.1, con `frame_id` = `map` y `odom`), no un script con dos suscripciones; la base resuelve
cada marco con `visor.transformada()`.

#### 4.8.9 `GoalStatusArray` + feedback de `NavigateToPose` (`hud/estado_meta.gd`, barra fija) — V hmi#15

Línea «Meta: fase · distancia · ETA · recuperaciones» con color por fase (0 sin meta … 4 LLEGÓ, 6 ABORTADA). Nivel 0
de ADR 0012 (topics ocultos `<acción>/_action/status` y `/_action/feedback`): status 33–453 B (**fiable**, profundidad
1, TRANSIENT_LOCAL [I]: el servidor lo publica *latched*), feedback 116 B; pero el feedback puede llegar a ~100 msg/s
(bt_loop 10 ms) → en la Vita mejor nivel 1, `/vita/accion/estado` 112 B a 5 Hz (`docs/32:51`). La Vita no conoce el
UUID de su meta: se elige la de `goal_info.stamp` más reciente. Cancelar: solo por el puente (nivel 1) o, en el PC,
con `RosActionClient`. [?] Que rclgd y `ros2_vita` acepten `nav2_msgs/action/NavigateToPose_FeedbackMessage` por texto
en una suscripción normal → §9.3. Esqueleto de hmi#15 con el cambio de base (`latched = true`, suscripción auxiliar
del feedback en `conectar()`).

#### 4.8.10 Herramientas que publican (`herramientas/*.gd`) — V hmi#16–19

RViz publica con `rclcpp::QoS(5)` (KEEP_LAST 5, fiable, volátil), `header.frame_id` = marco fijo y sello
`clock->now()` (`goal_tool.cpp:67,78`) [V]. Aquí: **fiable**, profundidad 5 (PC) / 1 (Vita), un mensaje por
confirmación, sello `nodo.now()` (hora del agente en la Vita). Todo ≤ 364 B: en la Vita no fragmenta y la emisión
fiable no bloquea el hilo principal (`docs/27:13-15,34`).

| Herramienta | Mensaje → topic | Gesto PC | Gesto Vita | Detalles |
|---|---|---|---|---|
| Nav2 Goal (`meta.gd`) | `PoseStamped` → `goal_pose` (relativo, 76 B) | pulsar = posición, arrastrar = rumbo, soltar = publicar | táctil delantero (como ratón); meta «pendiente» naranja hasta **✕** | rumbo `atan2(Δy, Δx)` (`pose_tool.cpp:151`) → `(0, 0, sin θ/2, cos θ/2)` (`:154-161`); umbral de arrastre 5 cm |
| 2D Pose Estimate (`pose_inicial.gd`) | `PoseWithCovarianceStamped` → `initialpose` (364 B) | igual | igual + ✕ | cov[0] = cov[7] = 0,25, cov[35] = (π/12)² = 0,0685 (`initial_pose_tool.cpp:62-70`); asignar el array entero |
| Publish Point (`punto.gd`) | `PointStamped` → `/clicked_point` (44 B) | al **soltar**: rayo de física contra las colisiones del mundo editable (doc 35), si no, el suelo | toque | «Single click»: se desactiva tras publicar (`point_tool.cpp:65-68,111-114`); el robot horneado no tiene colisiones (`urdf_robot.gd:2`) |
| Teleop (`teleop.gd`) | `Twist` → `/cmd_vel` (52 B), 20 Hz | flechas + Mayús (hombre muerto) | stick izq. + **R mantenido**; △/✕ escala | fiable por defecto (validado en G6, `godot/g6-hmi/main.gd:65`); al soltar, **un** Twist cero y silencio; con robots reales `/vita/mando` best effort 20 Hz + puerta en el PC (ADR 0012 §3); con el G1, best effort (`humanoide_g1.gd:163-164`) |

Mapeo de controles de la Vita (decisión de diseño de hmi, sin cambio en la sentencia): SELECT recorre Teleop → Meta →
Pose inicial → Punto (nombre en la barra fija); START abre/cierra el panel; L + cruceta o toque cambian de pestaña;
el panel trasero **no** está disponible (`docs/28:59`): giro de la cámara orbital en el stick derecho; sin táctil,
cursor con el stick derecho, rumbo con L/R y ✕. [I] Emulación de ratón desde táctil: comprobar que un toque produce un
solo evento (§9.3).

```gdscript
extends "res://comun/visor/herramienta_visor.gd"
## Nav2 Goal (goal_tool.cpp): pulsar = posición, arrastrar = rumbo, soltar = publicar (Vita: ✕ confirma).
var _inicio = null                                    # Vector3 ROS o null
var _yaw := 0.0
var _pendiente = null                                 # [Vector3, yaw] en la Vita hasta ✕
func _init() -> void:
	topic = "goal_pose"
	tipo = "geometry_msgs/msg/PoseStamped"
func _unhandled_input(e: InputEvent) -> void:
	if not activa:
		return
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_inicio = suelo_ros(e.position)
		elif _inicio != null:
			if visor.en_vita and confirmar_en_vita:
				_pendiente = [_inicio, _yaw]          # flecha naranja en el HUD
			else:
				_publicar(_inicio, _yaw)
			_inicio = null
	elif e is InputEventMouseMotion and _inicio != null:
		var p = suelo_ros(e.position)
		if p != null and Vector2(p.x - _inicio.x, p.y - _inicio.y).length() > 0.05:
			_yaw = atan2(p.y - _inicio.y, p.x - _inicio.x)
	elif e.is_action_pressed("ui_accept") and _pendiente != null:   # ✕ en la Vita
		_publicar(_pendiente[0], _pendiente[1])
		_pendiente = null
func _publicar(p: Vector3, yaw: float) -> void:
	var m := RosMsg.from_type(tipo)
	m.header.frame_id = visor.marco_fijo
	m.header.stamp = visor.contexto.nodo.now()
	m.pose.position.x = p.x
	m.pose.position.y = p.y
	m.pose.orientation.z = sin(yaw * 0.5)
	m.pose.orientation.w = cos(yaw * 0.5)
	publicar(m)
```

`pose_inicial.gd` hereda de `meta.gd` y solo cambia `topic`, `tipo` y `_publicar` (código de hmi#17, con
`m.pose.covariance = cov` asignando el `PackedFloat64Array` entero, `API_PARITY.md:49`). `punto.gd` y `teleop.gd` son
los de hmi#18 y hmi#19 con `extends herramienta_visor.gd`, `conectar(n)` → la base y `_pub.publish` → `publicar`;
en teleop, `+ 0.0` evita publicar `-0.0` (`g6-hmi/main.gd:98`) y el `RosTimer` de 0,05 s se crea en `conectar()`
tras `super.conectar(v)`.

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
| **G-W13-M1** | 48 (cupo) CUBE/SPHERE/CYLINDER moviéndose a 10 Hz | `drawn` +cupo, `avg_submit_us` ≤ 9 000, `invalidations` sin cambio, ≥ 30 FPS | V8 |
| **G-W13-M2** | 48 marcadores con `lifetime` 2 s y DELETEALL por ns, 5 min | nº de hijos constante, `[vita-memory]` estable | V8 |
| **G-W13-M3** | `<p>/marcadores` con 10 % de pérdida (netem) | sin fantasmas > 0,4 s, `process` ≤ 4 ms, ≤ 15 KB/s | D14, V8 |
| **G-W13-M4** | mapa 384² por relay con LUT + `blit_rect` | `process` ≤ 4 ms, textura estable 5 min | V3 |
| **G-W13-M5** | costmap 4 bit (Nav2 + TB3) | repaso completo ≤ 3 s, ≥ 30 FPS | V11 |
| **G-W13-M6** | arrastre táctil de `basic_controls` | POSE_UPDATE ≈ 20 Hz, latencia < 150 ms | V14 |
| **G-W13-M7** | LINE_STRIP 50 puntos y POINTS 180 en 2D con la cámara orbitando | `process` + `canvas` ≤ 2–3 ms | V8 |

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
3. **Marco de plan frente a real** (hmi#14): el plan va en `map`, `pose2d` sale de `/odom` (`odom`); sin el módulo `tf`
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
| **V5** | Esquema de visor y displays directos pequeños | `plantillas/generar_esquemas.py` (`TIPOS_VISOR`); `displays/3d/{punto,vector,ejes,imu,fuerza,rango,marcador_simple}.gd`, `displays/2d/{poligono,covarianza,gps}.gd` | V2; D10 | `RosMsg.from_type` de cada tipo de `TIPOS_VISOR` ≠ `null`; ida y vuelta `serialize`/`deserialize` | cada tipo publicado desde el PC con `ros2 topic pub` se ve; sin `ERR_FAIL` de esquema |
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
