# Paridad de API: `rclgd` (PC, Godot 4.7) ↔ `ros2_vita` (Vita)

> Fuente: código y documentación de [Ozuba/rclgd](https://github.com/Ozuba/rclgd)
> (commit `4d0a8b3`, v3.0.0), estudiados en `docs/17`. Objetivo: **el mismo
> script GDScript corre en el PC (rclgd) y en la Vita (`ros2_vita`)**.
> **Godot 4 decidido (2026-10-27, `docs/18`).** Estado de la columna Vita:
> ✅ = *implementado en `godot/ros2_vita/` pero SIN COMPILAR* (validar en el PC,
> puerta G1); ⏳ = no implementado. El transporte real (`XrceTransport`) es
> aún un stub: hoy solo funciona el `LoopbackTransport` (pruebas en host,
> `godot/test/`).
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
| `create_publisher(topic, type, qos)` | ✅ | `type` = `String` o clase sombra con `ROS_TYPE_NAME` |
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

## `RosMsg` (RefCounted) y clases sombra
| rclgd | Vita | Nota |
|---|---|---|
| `RosMsg.from_type("pkg/msg/T")`, `init(type)` | ✅ | requiere el esquema `.rsch` del tipo en el `.pck` (módulo `msg-schema`) |
| propiedades dinámicas anidadas (`msg.pose.position.x`) | ✅ | `_get/_set` + conversión perezosa y caché, como rclgd |
| `get_member`, `set_member`, `get_type_name()`, `get_ros_interface_name()`, `_to_string()` | ✅ | |
| arrays primitivos ⇄ `Packed*Array` | ✅ | `memcpy` (CDR little-endian = memoria de la Vita) |
| `RosMsg.gen_editor_support(type, dir)` | ❌ en la Vita | **se ejecuta en el PC** (rclgd) y las clases `Ros*` generadas se copian al proyecto |
| clases `RosGeometryMsgsTwist`... con `ROS_TYPE_NAME` | ✅ | idénticas (GDScript puro) |
| semántica "los arrays se copian: asignar el array entero" | ✅ | mantener igual |

### Próximo cambio de rclgd: clases tipadas nativas (rama `feature/native-msg-classes`, 2026-10-26)
| rclgd (próximo) | Vita | Nota |
|---|---|---|
| Clases `RosXxx` nativas registradas al arrancar desde `res://package.xml` | ⏳ (T3.2.4) | registrar desde `schema.rsch` con `ClassDB::register_extension_class` **[I]**; esquema cargado antes de analizar scripts |
| Se eliminan `addons/rclgd/gen`, el plugin y `RosMsg.gen_editor_support` | ⏳ | mientras no se fusione, mantener ambas vías |
| `create_publisher(topic, RosGeometryMsgsTwist)` acepta clase o instancia | ⏳ | — |
| `package.xml` en el filtro de no-recursos al exportar | ⏳ (T5.2.3) | igual en la Vita: `package.xml` + `*.rsch` |

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
- Argumentos: `rclgd.init(["-p","agent_ip:=…","-p","transport:=loopback"])`.
- Entrega de mensajes: cola acotada (256, descarta el más antiguo) volcada al hilo
  principal en `process_frame`.

## Ejes y tipos
- Mismos helpers de conversión y mismo sentido (`Transform3D` de Godot ⇄ REP-103).
- Tipos prioritarios: `std_msgs/String|Bool`, `geometry_msgs/Twist|PoseStamped`,
  `nav_msgs/Odometry`, `sensor_msgs/Joy|Imu|CompressedImage`, `tf2_msgs/TFMessage`,
  `visualization_msgs/Marker`.
