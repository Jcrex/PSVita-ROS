# Paridad de API: `rclgd` (PC, Godot 4.7) ↔ `ros2_vita` (Vita)

> Fuente: código y documentación de [Ozuba/rclgd](https://github.com/Ozuba/rclgd)
> (commit `4d0a8b3`, v3.0.0, estudiados en `docs/17`; tipos revisados contra `jazzy@fb12a65`,
> 2026-10-29, que ya trae las **clases tipadas nativas**). Objetivo: **el mismo
> script GDScript corre en el PC (rclgd) y en la Vita (`ros2_vita`)**.
> **Godot 4 decidido (2026-10-27, `docs/18`).** Estado de la columna Vita:
> ✅ = *implementado en `godot/ros2_vita/`, compilado y probado en host* (puerta G1
> verde el 2026-10-29; G3 verde el 2026-10-30: compila para la Vita y pasa `verify_runtime.py`, falta
> corre en la Vita en loopback, G4); ⏳ = no implementado. Transportes: `LoopbackTransport` (pruebas,
> `godot/test/`) y `XrceTransport` (micro-ROS; G5 probado en host contra ROS 2 Jazzy, en la Vita: validar en
> hardware).
> Leyenda: ✅ igual · 🟡 parcial/diferente · ⏳ fase posterior · ❌ no aplica.

## Singleton `rclgd`
| rclgd | Vita | Nota |
|---|---|---|
| `init(args: PackedStringArray)` / `shutdown()` / `ok()` | ✅ | `args` incluye `-p agent_ip:=...` (IP/puerto del agente, no hay *discovery* DDS) |
| señal `ros_ready` | ✅ | tras `uxr_create_session` correcto |
| `godot_to_ros_vector/quat`, `ros_to_godot_vector/quat` | ✅ | `ros=(-g.z,-g.x,g.y)`; triviales, sin dependencias |
| `get_logger(name)`, `set_logger_level`, `get_logger_effective_level`, `get_logging_severity_from_string` | 🟡 | consola/netlog; `/rosout` ⏳ |
| `use_sim_time`, `publish_sim_time` | ⏳ | `/clock` sin prioridad |

## `RosNode` (RefCounted)
| rclgd | Vita | Nota |
|---|---|---|
| `init(node_name, namespace="")` | 🟡 | **una sesión XRCE ⇒ un participante**; varios `RosNode` comparten sesión (nombres como prefijo de topics) **[I]** |
| `get_name()`, `get_namespace()`, `resolve_frame(id)` | ✅ | `~frame` ⇒ espacio de nombres |
| `create_publisher(topic, type, qos)` | 🟡 | `type` = `String` ✅ (o script con `ROS_TYPE_NAME`, que rclgd **ya no** acepta); clase nativa o instancia ⏳ (T3.2.4) |
| `create_subscription(topic, type, callable, qos)` | ✅ | callback en el hilo principal (cola `msg-ring`) |
| `create_timer(seconds, callable)` | ✅ | reloj local (monotónico) |
| `now()` | 🟡 | `Time` local; sincronización con el agente ⏳ (`uxr_synchronize_session`) |
| `create_client(srv, type, qos)` + `await req.completed` | ⏳ | DDS-RPC del cliente XRCE **[?]** |
| `create_service(...)` | ⏳ | callback en hilo de red; misma regla que rclgd |
| `create_action_client/server` | ⏳ | no están en el cliente XRCE |
| `create_tf_broadcaster()` → `send_transform(t, child, parent, static)` | ✅ | publica `tf2_msgs/TFMessage` en `/tf` y `/tf_static` |
| `create_tf_listener(cache)` → `lookup_transform`, `can_transform`, `get_frame_names`... | 🟡 | `tf-tree`: **último valor, sin historial ni timeout**; `time` se ignora |
| `declare_parameter / get_parameter / set_parameter` + señal `parameter_changed` | 🟡 | **solo locales**; sin servicios `/param` |
| `get_topic_names_and_types()`, `count_publishers/subscribers` | ❌ | sin API de grafo en XRCE |
| `get_logger()` | 🟡 | ver arriba |

## `RosMsg` (RefCounted) y clases tipadas
| rclgd | Vita | Nota |
|---|---|---|
| `RosMsg.from_type("pkg/msg/T")` | ✅ | requiere el esquema `.rsch` del tipo en el `.pck` (módulo `msg-schema`); en rclgd devuelve la clase tipada, en la Vita un `RosMsg` dinámico hasta T3.2.4 |
| `RosMsg.new()` + `init(type)` | ✅ | en rclgd también da siempre un `RosMsg` dinámico: **igual** |
| propiedades dinámicas anidadas (`msg.pose.position.x`) | ✅ | `_get/_set` + conversión perezosa y caché, como rclgd |
| `get_member`, `set_member`, `get_type_name()`, `get_ros_interface_name()`, `_to_string()` | ✅ | |
| arrays primitivos ⇄ `Packed*Array` | ✅ | `memcpy` (CDR little-endian = memoria de la Vita) |
| semántica "los arrays se copian: asignar el array entero"; asignar un submensaje copia | ✅ | mantener igual |

### Clases tipadas nativas — **ya en rclgd** (fuente de `jazzy`/`rolling` ≥ 2026-10-28; apt 3.0.0 aún no)
rclgd registra al cargar (nivel `SCENE`) una clase nativa derivada de `RosMsg` por cada interfaz de las
dependencias (`depend`/`exec_depend`/`build_depend`) de `res://package.xml` y sus anidados, resueltas en el
índice ament (`src/rclgd/ros_type_registry.cpp`). Las clases sombra, el plugin y `gen_editor_support`
**desaparecen**. Detalle de uso: skill `rclgd`, `references/mensajes-y-tipos.md` §2.

| rclgd (actual) | Vita | Nota |
|---|---|---|
| `RosGeometryMsgsTwist.new()`, anotaciones `msg: RosNavMsgsOdometry` | ⏳ (T3.2.4) | **en la Vita hoy no existen**: un script que las nombre **no compila** allí. Registrarlas desde el `.rsch` (no hay índice ament en la Vita): el esquema debe contener el cierre transitivo y cargarse en la inicialización del módulo, antes de analizar scripts |
| `from_type`, mensajes recibidos, peticiones/respuestas y goal/feedback/result devuelven la clase tipada | ⏳ (T3.2.4) | hoy `RosMsg` dinámico (mismo acceso por propiedades) |
| `create_publisher/subscription(topic, RosXxx)` o con una instancia | ⏳ (T3.2.4) | hoy solo `String` |
| arrays de mensajes como `Array[RosXxx]` tipados | ⏳ (T3.2.4) | hoy `Array` |
| campos que chocan con miembros de `RosMsg`/palabras clave → solo `get_member` | ⏳ | replicar la misma lista (palabras clave de GDScript + miembros de `RosMsg`) |
| conjunto de clases fijo al cargar; `package.xml` en el filtro de no-recursos al exportar | ⏳ (T5.2.3) | en la Vita: `package.xml` + `*.rsch` |
| ~~`RosMsg.gen_editor_support`~~, ~~clases sombra con `ROS_TYPE_NAME`~~ | — | **eliminado en rclgd**; la Vita no lo implementará |

**Regla para scripts portables PC ↔ Vita hasta T3.2.4:** tipos por **texto**
(`create_publisher("/cmd_vel", "geometry_msgs/msg/Twist")`), mensajes con `RosMsg.from_type(...)` y
anotaciones `RosMsg`. Así el mismo `.gd` corre en el editor de rclgd (nativas) y en la Vita (dinámico).

**Notas de diseño para T3.2.4 (de leer el código de rclgd):** registra con la interfaz C de GDExtension
(`classdb_register_extension_class6` + getter/setter tipados por campo, para que GDScript vea el tipo
estático) y usa un `thread_local` durante la construcción; en el módulo en árbol se usará `ClassDB`
directamente y **sin `thread_local`** (el TLS del port está a medias, `docs/18` §2.1).

## Otras clases
| rclgd | Vita | Nota |
|---|---|---|
| `RosQoS` (history, depth, reliability, durability, deadline, lifespan, liveliness) | 🟡 | XRCE solo soporta *reliable/best-effort*, *keep-last* y *volatile/transient-local* **[?]**; el resto se ignora con aviso |
| `RosPublisher.publish(msg)`; `RosSubscriber` (sin métodos) | ✅ | |
| `RosTimer` (`cancel/reset/is_canceled/is_ready/get_remaining_time`) | ✅ | |
| `RosClient`, `RosRequest`, `RosService` | ⏳ | |
| `RosActionClient`, `RosGoalHandle`, `RosActionServer`, `RosServerGoalHandle` | ⏳ | |
| `RosTfBroadcaster`, `RosTfListener` | ✅ / 🟡 | ver arriba |
| `RosLogger` (debug/info/warning/error/fatal, filtros `once`/`throttle`/`skip_first`, `get_child`) | 🟡 | sin `/rosout` al principio |

## Reglas de hilos (idénticas a rclgd)
- Suscripciones, timers y acciones: **hilo principal**.
- Servicios servidor y aceptación de goal: **hilo de red** (no tocar el árbol de escena; `call_deferred`).
- Todos los objetos `Ros*` son `RefCounted`: **guardar la referencia** o se cancelan.
- `Callable` y `await` ⇒ **Godot 4** (decidido, `docs/18`).

## Notas del módulo nativo (Godot 4 en árbol, no GDExtension)
- `godot4-vita` **no soporta GDExtension**: el módulo se compila dentro del motor
  (`custom_modules=<repo>/godot`). Las clases se registran con `GDREGISTER_CLASS`.
- Cada `RosMsg` necesita su esquema `.rsch` (generado en el PC con
  `tools/gen_msg_schema.py`) dentro del `.pck`; el filtro de exportación debe
  incluir `*.rsch` (M10).
- Argumentos: `rclgd.init(["-p","agent_ip:=…","-p","transport:=loopback"])`. También `agent_port` y `domain_id`;
  por defecto salen de los ajustes de proyecto `ros/agent_ip`, `ros/agent_port` (8888) y `ros/domain_id` (0).
  Transporte por defecto: `xrce` en la Vita, `loopback` en el host.
- XRCE: `RosQoS` se traduce a XML de Fast DDS (reliability, durability, history/depth). Mensajes > ~490 bytes
  se fragmentan solo en el stream fiable; en *best effort* se rechazan (MTU 512).
- Entrega de mensajes: cola acotada (256, descarta el más antiguo) volcada al hilo
  principal en `process_frame`.

## Ejes y tipos
- Mismos helpers de conversión y mismo sentido (`Transform3D` de Godot ⇄ REP-103).
- Tipos prioritarios: `std_msgs/String|Bool`, `geometry_msgs/Twist|PoseStamped`,
  `nav_msgs/Odometry`, `sensor_msgs/Joy|Imu|CompressedImage`, `tf2_msgs/TFMessage`,
  `visualization_msgs/Marker`.
