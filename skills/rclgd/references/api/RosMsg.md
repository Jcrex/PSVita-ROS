# RosMsg

Hereda de: `RefCounted`

A dynamic wrapper for ROS 2 messages.

`RosMsg` provides a flexible way to handle ROS 2 messages within Godot. It uses **BabelFish** to dynamically translate ROS 2 message buffers into Godot-friendly `Variant` data and vice versa.
Fields can be accessed dynamically using `get_member` and `set_member`, or via Godot's property system if the message has been initialized.
To improve the development experience, `RosMsg` includes a utility to generate GDScript "wrapper" classes that provide IDE autocomplete for specific message types.

## Métodos

### `from_type(ros_type_name: String) -> RosMsg` *(static)*

Factory method that creates and returns a new `RosMsg` instance for the given `ros_type_name` (e.g., `"std_msgs/msg/String"`).

### `gen_editor_support(p_type: String, p_dest_folder: String) -> void` *(static)*

Generates GDScript wrapper classes for the specified `p_type` and all its nested dependencies in the `p_dest_folder`. These generated scripts inherit from `RosMsg` and provide typed properties for every message field, enabling IDE autocomplete and better type safety in Godot.

### `get_member(p_name: StringName) -> Variant` *(const)*

Returns the value of the message field specified by `p_name`. If the field is a nested message, it returns another `RosMsg` instance.

### `get_ros_interface_name() -> String` *(const)*

Returns the original ROS 2 interface name (e.g., `"std_msgs/msg/String"`).

### `get_type_name() -> String` *(const)*

Returns the Godot-formatted name of the message type (e.g., `"RosStdMsgsString"`). This name matches the class name of generated editor support scripts.

### `init(ros_type_name: String) -> void`

Initializes the `RosMsg` instance to represent a message of the specified `ros_type_name`. This clears any previous data and allocates a new ROS 2 message buffer.

### `set_member(p_name: StringName, p_value: Variant) -> void`

Sets the value of the message field specified by `p_name` to `p_value`. The value is automatically converted to the appropriate ROS 2 type. If the field is a nested message, `p_value` must be a `RosMsg`.
