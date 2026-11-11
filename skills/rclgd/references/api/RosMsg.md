# RosMsg

Hereda de: `RefCounted`

A ROS 2 message, with native typed subclasses for the interfaces a project depends on.

`RosMsg` provides a flexible way to handle ROS 2 messages within Godot. It uses **BabelFish** to dynamically translate ROS 2 message buffers into Godot-friendly `Variant` data and vice versa.
Fields can be accessed dynamically using `get_member` and `set_member`, or via Godot's property system if the message has been initialized.
**Typed classes:** when the extension loads, rclgd registers a native class deriving from `RosMsg` for every interface type provided by the packages listed as dependencies in the project's `res://package.xml` (and every type they nest). Messages (`msg/`), service requests and responses (`srv/`, e.g. `RosExampleInterfacesSrvAddTwoIntsRequest`) and action goals, results and feedback (`action/`) are covered. `geometry_msgs/msg/Twist` becomes `RosGeometryMsgsTwist`, with one typed property per field: nested messages are typed objects and arrays of messages are typed arrays (`Array`RosGeometryMsgsPose``). These classes give editor autocomplete and type checking, can be created with `new()`, and are what `from_type` and every received message (subscriptions, services, actions) return for their type.
Types not registered this way keep working as plain dynamic `RosMsg` instances. A field whose name clashes with a `RosMsg` member or a GDScript keyword is not exposed as a property of the typed class; reach it with `get_member` and `set_member`.
**Note:** the set of typed classes is fixed when the extension loads. After adding a dependency to `package.xml`, or building a new interface package, reload the project (or restart the game). Exported games need `package.xml` in the export preset's non-resource include filter.

## Métodos

### `from_type(ros_type_name: String) -> RosMsg` *(static)*

Factory method that creates and returns a new message for the given `ros_type_name` (e.g., `"std_msgs/msg/String"`). If the type has a registered typed class, the returned instance is of that class (e.g. `RosStdMsgsString`); otherwise it is a dynamic `RosMsg`. Returns `null` if the type cannot be resolved.

### `get_member(p_name: StringName) -> Variant` *(const)*

Returns the value of the message field specified by `p_name`. If the field is a nested message, it returns another `RosMsg` instance.

### `get_ros_interface_name() -> String` *(const)*

Returns the original ROS 2 interface name (e.g., `"std_msgs/msg/String"`).

### `get_type_name() -> String` *(const)*

Returns the Godot-formatted name of the message type (e.g., `"RosStdMsgsString"`). This is the name of the typed class registered for the type, whether or not this instance is of that class.

### `init(ros_type_name: String) -> void`

Initializes a `RosMsg` created with `RosMsg.new()` to represent a message of the specified `ros_type_name`, allocating a new ROS 2 message buffer. Does nothing on an already initialized message (e.g. any typed class instance). The instance stays a dynamic `RosMsg` even when the type has a typed class; use `from_type` or the class's `new()` to get a typed one.

### `set_member(p_name: StringName, p_value: Variant) -> void`

Sets the value of the message field specified by `p_name` to `p_value`. The value is automatically converted to the appropriate ROS 2 type. If the field is a nested message, `p_value` must be a `RosMsg`.
