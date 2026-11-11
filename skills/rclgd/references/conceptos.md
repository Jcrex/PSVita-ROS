# Conceptos de rclgd (v3.0.0) — destilado de `docs/concepts/*` y la referencia de clases

## Arquitectura
- GDExtension `librclgd.so` sobre `rclcpp` + `ros_babel_fish` (mensajes dinámicos sin recompilar).
- **Executor:** `MultiThreadedExecutor` en un hilo propio. Con
  `--ros-args -p use_separate_thread:=false` pasa a un executor de un hilo girado en el *physics tick*
  (determinista; todo en el hilo principal).
- **Nodo oculto** `rclgd_<pid>` por proceso: lleva parámetros de proceso y, si se activa, el publicador de `/clock`.
- `rclgd.shutdown()` para el executor y destruye el contexto; también se llama al descargar la
  extensión. SIGINT/SIGTERM se traducen en `SceneTree.quit()` en el hilo principal.

## Dónde corre cada callback
| Callback | Hilo |
|---|---|
| Suscripción, timer, cliente de servicio (`completed`), cliente de acción (señales), `execute_callback` del servidor de acción | **principal** (vía `call_deferred`) |
| Servidor de servicio (`create_service` callback) | **executor** — rellenar `res` y volver; escena con `call_deferred` |
| `goal_callback` de `create_action_server` | **executor** — solo inspeccionar el goal y devolver `true/false` |
| Modo `use_separate_thread:=false` | todo en el principal |

## Ciclo de vida y memoria
- Clases de fábrica (`RosPublisher`, `RosSubscriber`, `RosTimer`, `RosClient`, `RosService`,
  `RosRequest`, acciones, TF, `RosLogger`) son **abstractas**: `.new()` falla; se crean con `RosNode.create_*`.
  Instanciables: `RosNode`, `RosMsg`, `RosQoS`.
- Todo es `RefCounted`: al perder la última referencia se da de baja del grafo ROS.
- Patrón de servidor de acción: `await get_tree().physics_frame` (o `process_frame`) dentro del bucle
  del `execute_callback` para repartir el trabajo entre fotogramas; terminar con `succeed/abort/canceled`.

## Tiempo
- `node.now()` devuelve un `RosMsg` `builtin_interfaces/msg/Time` (`sec`, `nanosec`).
- `-p use_sim_time:=true`: relojes y `RosTimer` siguen `/clock`.
- `-p publish_sim_time:=true`: Godot **es** la fuente de tiempo; el physics tick publica `/clock`
  escalado por `Engine.time_scale` (0 = pausa). Un Godot que es el simulador usa ambos.

## Señales frente a Callables
- Topics usan `Callable` (menos coste que señales a 100+ Hz). Si quieres señal, emítela desde el callback.
- Señales existentes: `rclgd.ros_ready`, `RosNode.parameter_changed(name, value)`,
  `RosRequest.completed(response)`, `RosClient.service_available(available)`,
  `RosActionClient.server_available(available)` y en `RosGoalHandle`: `accepted`, `rejected`,
  `feedback(msg)`, `completed(result, status)` (constantes `STATUS_*` en `api/RosGoalHandle.md`).

## QoS (`RosQoS`)
- Por defecto: KEEP_LAST, depth 10, RELIABLE, VOLATILE.
- Propiedades: `reliability`, `history`, `depth`, `durability`, `deadline_seconds`, `lifespan_seconds`,
  `liveliness`, `lease_duration_seconds` (con `set_*`). Constantes: `RosQoS.RELIABLE/BEST_EFFORT`,
  `VOLATILE/TRANSIENT_LOCAL`, `KEEP_LAST/KEEP_ALL`, `AUTOMATIC/MANUAL_BY_TOPIC/SYSTEM_DEFAULT`.
- Datos de sensor (como `rclcpp::SensorDataQoS`): BEST_EFFORT, KEEP_LAST 5, VOLATILE. El suscriptor
  también debe ser BEST_EFFORT o no casa. Mapas/estáticos: TRANSIENT_LOCAL.

## TF y ejes
- Godot: -Z adelante, +X derecha, +Y arriba. ROS REP-103: +X adelante, +Y izquierda, +Z arriba.
  `ros = Vector3(-g.z, -g.x, g.y)`; el cuaternión se baraja igual (rotación propia).
- `RosTfBroadcaster.send_transform(t: Transform3D, frame_id, parent_frame_id, is_static=false, timestamp=null)`
  — convierte ejes solo.
- `RosTfListener.lookup_transform(target, source, time=null, timeout_sec=0.0)` → `Transform3D` en ejes
  Godot o `null` (motivo en `get_last_error()`). `time`: `null` (último), `float` (s desde epoch) o
  `RosMsg` Time (p. ej. `msg.header.stamp`, interpolado). Buffer: `create_tf_listener(cache_time_sec=10.0)`.
- Inspección: `get_frame_names()`, `get_frame_parent(f)`, `get_frame_latest_time(f)`, `frame_exists`,
  `all_frames_as_yaml()` (como `view_frames`), `can_transform`, variantes `_full`.

## Parámetros
- `declare_parameter(name, default)` antes de usar; `get_parameter`, `set_parameter`; señal
  `parameter_changed` para `ros2 param set`.
- Los `-p` de la línea de órdenes o de `ros/parameters/*` ganan sobre el valor por defecto: **declara y
  vuelve a leer** (patrón de roomba).
- Tipos: bool, int, float, String, PackedByteArray, PackedInt32/64Array, PackedFloat32/64Array, PackedStringArray.

## Nombres
- Topics relativos y `~` se resuelven con el nodo (`"~/marker"` → `/<ns>/<nodo>/marker`).
- `node.resolve_frame("~lidar")` antepone el namespace a frames TF.
