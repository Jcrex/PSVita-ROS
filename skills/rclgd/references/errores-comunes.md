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
| Clases `RosXxx` duplicadas tras actualizar | restos de `addons/rclgd/gen` con clases nativas | borrar `gen/`, plugin y `rclgd.gd` (ver `mensajes-y-tipos.md` §3) |
| El juego exportado no encuentra tipos | `package.xml` no exportado (clases nativas) | añadirlo a los filtros de no-recursos |
| Godot 4.7 falla la 1.ª importación en colcon | fallo conocido de primera importación; colcon lo tolera si hay assets | volver a ejecutar o `ros2 rclgd editor --import-only` |
