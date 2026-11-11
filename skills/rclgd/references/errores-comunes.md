# Errores comunes (síntoma → causa → arreglo)

| Síntoma | Causa probable | Arreglo |
|---|---|---|
| La suscripción/timer no se dispara nunca | el objeto devuelto no se guardó (`RefCounted` liberado) | guardar en variable miembro |
| `Identifier "RosNode" not declared` / clases `Ros*` desconocidas | editor abierto sin el entorno ROS o sin la extensión | `source install/setup.bash` y `ros2 rclgd editor`; `ros2 rclgd doctor` |
| Crash o errores raros al tocar nodos desde un servicio | callback de servicio en el hilo del executor | rellenar `res` y `call_deferred` para la escena |
| Publico pero `ros2 topic echo` no ve nada | QoS incompatible, `ROS_DOMAIN_ID` distinto o nombre relativo mal resuelto | igualar reliability/durability; `ros2 topic list`; usar `/` o `~/` explícitos |
| Suscriptor a cámara/lidar no recibe | publicador BEST_EFFORT y suscriptor RELIABLE | `RosQoS` BEST_EFFORT en la suscripción |
| El robot se mueve/rota al revés en RViz | ejes Godot ↔ ROS sin convertir | `rclgd.godot_to_ros_vector/quat` o TF broadcaster |
| `lookup_transform` devuelve `null` | frame inexistente o sello fuera del buffer | `get_last_error()`; ampliar `create_tf_listener(30.0)` |
| El parámetro no toma el valor de `-p` | se leyó la variable `@export` y no el parámetro | `declare_parameter` y luego `get_parameter` |
| `.new()` de `RosPublisher` falla | clases de fábrica abstractas (3.0.0) | `node.create_publisher(...)` |
| Clases `RosXxx` duplicadas / «class_name ya existe» tras actualizar | restos de `addons/rclgd/gen` con clases nativas | borrar `gen/`, `plugin.cfg`, `rclgd.gd` y la entrada de `[editor_plugins]` (`mensajes-y-tipos.md` §2 «Migrar»); `ros2 rclgd doctor` |
| El juego exportado no carga scripts que usan `RosXxx` / no encuentra tipos | `package.xml` no exportado (clases nativas) | añadirlo a los filtros de no-recursos |
| `Identifier "RosMiPkgMsgsX" not declared` con el paquete ya compilado | el conjunto de clases se fija al cargar la extensión, o falta el `<depend>` | añadir `<depend>` a `package.xml` y **Project > Reload Current Project** con el workspace *sourced* |
| Un campo existe en el `.msg` pero no como propiedad de la clase | su nombre choca con un miembro de `RosMsg` o una palabra clave | `get_member`/`set_member` (`godot --verbose` lista los omitidos) |
| `Invalid call. Nonexistent function 'gen_editor_support'` | plugin viejo (3.0.0) con rclgd nuevo | borrar el plugin (`mensajes-y-tipos.md` §2 «Migrar») |
| `RosMsg.new(); init(...)` no da la clase tipada | `init` siempre crea un `RosMsg` dinámico | `RosMsg.from_type(...)` o `RosPkgTipo.new()` |
| `create_publisher(topic, MiScript)` falla aunque el script tenga `ROS_TYPE_NAME` | ya no se resuelve por esa constante | pasar el nombre, la clase nativa o una instancia |
| Godot 4.7 falla la 1.ª importación en colcon | fallo conocido de primera importación; colcon lo tolera si hay assets | volver a ejecutar o `ros2 rclgd editor --import-only` |
