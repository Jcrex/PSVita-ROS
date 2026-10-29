# Mensajes y tipos en rclgd

> **Dos sistemas de tipos según la versión** (comprueba cuál tienes, §4):
> - **Clases nativas** — fuente actual de `jazzy` (≥ `fb12a65`, 2026-10-28) y `rolling` (≥ `bfbda5c`);
>   CHANGELOG «Forthcoming». **Es el sistema de referencia de esta skill** (§2).
> - **Clases sombra GDScript** — rclgd **3.0.0 publicado** (apt `ros-jazzy-rclgd` 3.0.0). Obsoleto (§3).
>
> Fuentes: `docs/tutorials/custom_messages.rst`, `doc_classes/RosMsg.xml`,
> `rclgd/test/project/tests/test_native_types.gd`, `src/rclgd/ros_type_registry.{hpp,cpp}`.

## 1. `RosMsg` dinámico (siempre disponible, en ambas versiones)
```gdscript
var m := RosMsg.from_type("geometry_msgs/msg/Twist")   # con clases nativas devuelve RosGeometryMsgsTwist
m.linear.x = 0.3                     # anidado: alias del buffer del padre (la escritura se queda)
m.set_member("angular", otro_msg)     # asignar un submensaje entero (COPIA en el padre)
var t := m.get_type_name()            # "RosGeometryMsgsTwist"
var n := m.get_ros_interface_name()   # "geometry_msgs/msg/Twist"
```
- `from_type` devuelve `null` si el tipo no se resuelve (paquete no compilado o no *sourced*).
- `RosMsg.new()` + `init("pkg/msg/T")` da **siempre un `RosMsg` dinámico**, aunque el tipo tenga clase
  nativa (`test_dynamic_rosmsg_of_registered_type`); `init` no hace nada sobre un mensaje ya inicializado.
- Primitivos ↔ `Variant`; arrays primitivos ↔ `Packed*Array` (rutas rápidas con `memcpy`): bytes →
  `PackedByteArray`, float32/64 → `PackedFloat32/64Array`, int → `PackedInt32/64Array`, strings →
  `PackedStringArray`; arrays de mensajes → `Array` (tipado con clases nativas, §2).
- **Arrays: asigna el array completo** (`msg.ranges = arr`); modificar un elemento del valor leído no
  cambia el mensaje (visto en el código, `ros_msg.cpp`).
- **Asignar un submensaje copia** (`t.angular = v`; luego `t.angular.z = 4.0` no toca `v`)
  — `test_assign_nested_copies_into_parent`.
- Imagen recibida → textura: `Image.create_from_data(msg.width, msg.height, false, Image.FORMAT_RGBA8, msg.data)`
  y `ImageTexture.create_from_image(image)` (patrón `roomba_hmi`; coste alto por fotograma).
- Reutiliza el mismo mensaje para publicar a alta frecuencia (créalo una vez como miembro).

## 2. Clases tipadas NATIVAS (sistema actual en la fuente de `jazzy`/`rolling`)
Al cargar la extensión (nivel `SCENE`, con `res://` ya montado) rclgd lee **`res://package.xml`**,
resuelve sus `<depend>`, `<exec_depend>` y `<build_depend>` en el índice ament (`ros_type_registry.cpp`) y registra en el ClassDB una clase **nativa** derivada de
`RosMsg` por cada interfaz, más todos los tipos que anidan. **No se genera ningún fichero.**

| Interfaz | Clase |
|---|---|
| `geometry_msgs/msg/Twist` | `RosGeometryMsgsTwist` |
| `example_interfaces/srv/AddTwoInts` | `RosExampleInterfacesSrvAddTwoIntsRequest` / `...Response` |
| `example_interfaces/action/Fibonacci` | `RosExampleInterfacesActionFibonacciGoal` / `...Result` / `...Feedback` |

```gdscript
var cmd := RosGeometryMsgsTwist.new()     # autocompletado y tipos en el editor
cmd.linear.x = 0.3                        # cmd.linear es RosGeometryMsgsVector3
pub = node.create_publisher("/cmd_vel", RosGeometryMsgsTwist)   # nombre, clase o instancia
pub.publish(cmd)

func _on_odom(msg: RosNavMsgsOdometry) -> void:   # lo recibido llega ya con su clase
    print(msg.pose.pose.position.x)

var req: RosExampleInterfacesSrvAddTwoIntsRequest = client.create_request()  # anota el tipo:
# create_request/create_goal/create_result se declaran como RosMsg aunque devuelvan la clase tipada
```
- `create_publisher` / `create_subscription` (y servicios/acciones) aceptan como tipo **el nombre**
  (`"geometry_msgs/msg/Twist"`), **la clase** (`RosGeometryMsgsTwist`) o **una instancia** (`RosStdMsgsString.new()`).
- Todo lo que llega (suscripciones, peticiones/respuestas de servicio, goal/feedback/result de acción,
  campos anidados, `RosNode.now()`) viene como la clase tipada. Los tipos **no** registrados (no están en
  `package.xml`) siguen funcionando como `RosMsg` dinámico (`test_unregistered_type_stays_dynamic`).
- Arrays de mensajes = **arrays tipados**: `pa.poses = [pose] as Array[RosGeometryMsgsPose]`.
- Cada campo es una propiedad con **tipo estático** (el getter devuelve el tipo real).
- Un campo cuyo nombre choca con un miembro de `RosMsg` o con una palabra clave de GDScript **no** es
  propiedad: `get_member`/`set_member`. `godot --verbose` lista los campos omitidos.
- Se puede heredar: `class_name ScaledTwist extends RosGeometryMsgsTwist` (sigue siendo ese tipo ROS).
- **El conjunto de clases se fija al cargar la extensión:** tras añadir un `<depend>` o compilar un
  paquete de interfaces nuevo → **Project > Reload Current Project** (o reiniciar el juego) con el
  workspace *sourced*.
- **Juegos exportados:** añadir `package.xml` en *Resources > Filters to export non-resource files* del
  preset; si falta, no hay clases tipadas y los scripts que las usan **no cargan**.
- Un script pasado como tipo a `create_*` **ya no** se resuelve por su constante `ROS_TYPE_NAME`.

### Migrar un proyecto de clases sombra (3.0.0) a nativas
1. Borrar `addons/rclgd/gen/` (sus `class_name` chocan con las clases nativas del mismo nombre).
2. Borrar `addons/rclgd/plugin.cfg` y `addons/rclgd/rclgd.gd`, y quitar el plugin de `[editor_plugins]`
   en `project.godot` (llama a `RosMsg.gen_editor_support()`, que ya no existe). El autoload `ROS` se queda.
3. Añadir `package.xml` al filtro de no-recursos de cada preset de exportación.
4. `ros2 rclgd doctor` avisa si quedan `gen/` o el plugin. Los nombres de clase no cambian: los scripts
   que usaban `RosGeometryMsgsTwist` siguen valiendo.

## 3. Clases sombra GDScript (rclgd 3.0.0 publicado; OBSOLETO)
- El plugin del editor generaba `res://addons/rclgd/gen/Ros<Pkg><Tipo>.gd` (con `class_name` y
  `const ROS_TYPE_NAME`) para cada dependencia de `package.xml`; también **Project > Tools > Regenerate
  ROS2 Types** o `RosMsg.gen_editor_support("pkg/msg/T", "res://addons/rclgd/gen")`.
- Se versionaban (`addons/rclgd/gen` en git). Mismos nombres de clase que las nativas.
- Úsalo solo si la máquina tiene el paquete apt 3.0.0; al pasar a una versión con clases nativas, §2 «Migrar».

## 4. ¿Qué sistema tengo?
- `rclgd-docs.sh cambios 40`: si aparece «native typed message classes» en la versión instalada → nativas.
- En el editor: si existe `addons/rclgd/plugin.cfg` en un proyecto recién creado con `ros2 rclgd create`
  → 3.0.0 (sombra). La plantilla nueva ya no lo trae.
- Con Godot + rclgd instalados: `dump_api.gd` → si `RosMsg` tiene `gen_editor_support` → 3.0.0.

## 5. Mensajes propios
1. Paquete de interfaces normal de ROS 2 (`rosidl`), compilado y *sourced* en el workspace.
2. `<depend>mi_pkg_msgs</depend>` (o `exec_depend`) en el `package.xml` del proyecto Godot. Al crear:
   `ros2 rclgd create mi_hmi --dependencies geometry_msgs nav_msgs mi_pkg_msgs` (añade `exec_depend`).
3. Recargar el proyecto (nativas) o regenerar (3.0.0). Sin tipado: `RosMsg.from_type("mi_pkg_msgs/msg/Estado")`
   funciona igual con cualquier tipo *sourced*, esté o no en `package.xml`.
