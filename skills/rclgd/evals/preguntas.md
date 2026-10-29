# Batería de comprobación para una IA «limpia» (skills rclgd + godot4-ros-scripting + ros2-vita-godot)

Uso: lanzar una sesión nueva sin contexto, darle solo las skills y pedirle que responda/ejecute.
Se aprueba si contesta bien **y** cita de dónde lo sacó (fichero de la skill o comando de documentación).

| # | Pregunta / tarea | Respuesta esperada (resumen) | Fuente |
|---|---|---|---|
| 1 | Mi suscripción a `/odom` no recibe nada y no hay errores. | No guardó la referencia (`RefCounted`) o QoS/dominio no casan | rclgd SKILL §1, errores-comunes |
| 2 | ¿En qué hilo corre el callback de `create_service`? ¿Puedo mover un nodo ahí? | Executor; no: `call_deferred` | conceptos.md |
| 3 | Escribe un nodo que publique `geometry_msgs/Twist` a 10 Hz. | `RosNode` + `create_publisher` + `create_timer(0.1, …)` guardados | SKILL §2 |
| 4 | Convierte la posición Godot `(1,2,3)` a ROS. | `(-3,-1,2)` | conceptos.md (ejes) |
| 5 | ¿Cómo sé qué versión de rclgd y Godot hay en la rama `jazzy`? | `rclgd-docs.sh sync jazzy && rclgd-docs.sh version` | SKILL §0 |
| 6 | ¿Cómo instalo rclgd y Godot? | apt `ros-jazzy-rclgd` o fuente; Godot lo trae la build | tooling.md |
| 7 | Un suscriptor de cámara no recibe del simulador. | BEST_EFFORT en la suscripción | errores-comunes / patrones-roomba |
| 8 | Haz un servidor de acción que no bloquee el juego. | bucle con `await get_tree().physics_frame`, `succeed/canceled/abort` | conceptos.md, patrones-roomba |
| 9 | ¿Sigue existiendo `RosMsg.gen_editor_support`? | No en la fuente actual (clases nativas); sí en el apt 3.0.0. Comprobar con `cambios` | mensajes-y-tipos.md §3–§4, versiones.md |
| 10 | Busca un ejemplo real de `lookup_transform` con sello. | `rclgd-docs.sh ejemplos lookup_transform` o `buscar` | SKILL §0 |
| 11 | ¿Qué tipos ROS puede usar un juego en la Vita? | Solo los del `schema.rsch` generado en el PC | ros2-vita-godot §2 |
| 12 | ¿Funcionan los servicios en la Vita hoy? | No (pendiente, T3.4.3) | ros2-vita-godot §2 |
| 13 | ¿Con qué editor exporto a la Vita? | 4.8-dev7 Linux + addon psvita; el 4.7.1 de rclgd no exporta | ros2-vita-godot §4 |
| 14 | ¿Dónde se crea un `RosMsg` para que funcione en PC y en Vita? | En `_ready`, tras `rclgd.init` | ros2-vita-godot §2, plantillas |
| 15 | Regenera la referencia de la API para una versión nueva. | `rclgd-docs.sh api skills/rclgd/references/api` + actualizar versiones.md | versiones.md |
| 16 | Añadí `<depend>mis_msgs</depend>` y `RosMisMsgsEstado` no existe. | El conjunto se fija al cargar: recargar el proyecto con el workspace *sourced* | mensajes-y-tipos.md §2 |
| 17 | Mi juego exportado falla al cargar scripts que usan `RosGeometryMsgsTwist`. | Falta `package.xml` en el filtro de no-recursos del preset | mensajes-y-tipos.md §2, errores-comunes |
| 18 | Migra un proyecto 3.0.0 con `addons/rclgd/gen` a la versión actual. | Borrar `gen/`, `plugin.cfg`, `rclgd.gd`, quitar `[editor_plugins]`; el autoload `ROS` se queda; `doctor` | mensajes-y-tipos.md §2 «Migrar» |
