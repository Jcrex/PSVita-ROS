# Mensajes y tipos en rclgd

## 1. `RosMsg` dinámico (siempre disponible)
```gdscript
var m := RosMsg.from_type("geometry_msgs/msg/Twist")   # o: var m := RosMsg.new(); m.init("...")
m.linear.x = 0.3                     # anidado: devuelve otro RosMsg (alias, no copia)
m.set_member("angular", otro_msg)     # asignar un submensaje entero
var t := m.get_type_name()            # "RosGeometryMsgsTwist"
var n := m.get_ros_interface_name()   # "geometry_msgs/msg/Twist"
```
- Primitivos ↔ `Variant`; arrays primitivos ↔ `Packed*Array` (rutas rápidas con `memcpy`): bytes →
  `PackedByteArray`, float32/64 → `PackedFloat32/64Array`, int → `PackedInt32/64Array`, strings →
  `PackedStringArray`; arrays de mensajes → `Array` de `RosMsg`.
- **Arrays: asigna el array completo** (`msg.ranges = arr`); modificar un elemento del valor leído no
  cambia el mensaje (visto en el código, `ros_msg.cpp`).
- Campos que chocan con miembros de `RosMsg` o palabras clave de GDScript: `get_member/set_member`.
- Imagen recibida → textura: `Image.create_from_data(msg.width, msg.height, false, Image.FORMAT_RGBA8, msg.data)`
  y `ImageTexture.create_from_image(image)` (patrón `roomba_hmi`; coste alto por fotograma).
- Reutiliza el mismo `RosMsg` para publicar a alta frecuencia (se crea una vez como miembro).

## 2. Clases sombra GDScript (v3.0.0, actual en `jazzy`/`rolling`)
- El plugin del editor genera `res://addons/rclgd/gen/Ros<Pkg><Tipo>.gd` (con `class_name`) para cada
  dependencia de `package.xml` y sus anidados; también **Project > Tools > Regenerate ROS2 Types** o
  `RosMsg.gen_editor_support("pkg/msg/T", "res://addons/rclgd/gen")`.
- **Se versionan** (`addons/rclgd/gen` en git). Dan autocompletado y tipos:
  `var cmd := RosGeometryMsgsTwist.new()`; `func _on(msg: RosNavMsgsOdometry)`.
- `create_publisher(topic, "pkg/msg/T")` acepta el nombre o la clase.

## 3. Clases tipadas NATIVAS (rama `feature/native-msg-classes`, 2026-10-26; aún no publicada)
- Al cargar la extensión se registran como clases reales del motor (derivan de `RosMsg`) todas las
  interfaces de las dependencias de `res://package.xml` (msg, srv Request/Response, action
  Goal/Result/Feedback) y sus anidados. Mismos nombres: `RosGeometryMsgsTwist`,
  `RosExampleInterfacesSrvAddTwoIntsRequest`, `...ActionFibonacciGoal`.
- **Incompatible con lo anterior:** borrar `addons/rclgd/gen`, `plugin.cfg`, `rclgd.gd` y la entrada en
  `[editor_plugins]` (el autoload `ROS` se queda); `gen_editor_support` desaparece; un script pasado como
  tipo ya no se resuelve por `ROS_TYPE_NAME`; el conjunto de tipos se fija al cargar (recargar el proyecto
  tras añadir dependencias); **juegos exportados necesitan `package.xml` en el filtro de no-recursos**.
- Arrays de mensajes son arrays tipados (`Array[RosGeometryMsgsPose]`). `ros2 rclgd doctor` avisa de restos.
- Cómo saber si ya está en tu versión: `rclgd-docs.sh cambios` (busca "native typed message classes") o
  comprobar si existe `RosMsg.gen_editor_support` con `dump_api.gd`.

## 4. Mensajes propios
1. Paquete de interfaces normal de ROS 2 (`rosidl`), compilado y *sourced* en el workspace.
2. `<depend>mi_pkg_msgs</depend>` en el `package.xml` del proyecto Godot.
3. Reabrir el editor (o regenerar). Sin tipado: `RosMsg.from_type("mi_pkg_msgs/msg/Estado")` funciona igual.
