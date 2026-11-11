# rclgd

Hereda de: `Object`

Main entry point for the ROS 2 GDExtension.

The [rclgd] singleton is the core of the ROS 2 bridge for Godot. It manages the global ROS 2 context, the executor thread, and the lifecycle of ROS 2 nodes.
Before using any other ROS 2 components, `init` must be called to initialize the environment. In projects created with `ros2 rclgd create`, the `ROS` autoload does this at startup, passing the command-line arguments and the `ros/parameters/*` project settings.
**Executor modes:** By default the ROS 2 executor spins in a separate thread. Subscription, timer and action execute callbacks are deferred to the Godot main thread, so regular GDScript stays safe; service callbacks and action goal callbacks run on the executor thread. Launch with `--ros-args -p use_separate_thread:=false` to spin synchronously on the physics tick instead.
**Simulation time:** Launch with `--ros-args -p publish_sim_time:=true` to make Godot the time source: the physics tick drives and publishes `/clock`, scaled by `Engine.time_scale`. The standard `use_sim_time:=true` instead makes node clocks (and timers) *follow* `/clock` — use it alone in a visualizer running next to an external simulator, or together with `publish_sim_time` when the Godot app is itself the simulator.
**Error handling:** RCLGD errors break into the script debugger by default. Set the `rclgd/debug/break_on_error` project setting to `false` to only log them instead.

## Métodos

### `get_logger(name: String) -> RosLogger` *(const)*

Returns a `RosLogger` with the given `name` that is not tied to any node, like rclpy's `rclpy.logging.get_logger()`. Use it in autoloads, tools or code without a `RosNode`. Messages go to the console only; use `RosNode.get_logger` (or a child of it) to also publish on `/rosout`.
A new instance is returned on every call, so keep a reference if you use the `once`, `skip_first` or `throttle_duration_sec` filters.

### `get_logger_effective_level(name: String) -> RosLogger.LoggingSeverity` *(const)*

Returns the effective severity threshold of the logger called `name`, inherited from its ancestors when not set explicitly. Equivalent to `rclpy.logging.get_logger_effective_level()`.

### `get_logging_severity_from_string(log_severity: String) -> RosLogger.LoggingSeverity` *(const)*

Converts a severity name such as `"debug"` or `"WARN"` (case-insensitive) to a `RosLogger.LoggingSeverity` value. Reports an error and returns `RosLogger.UNSET` for unknown names. Equivalent to `rclpy.logging.get_logging_severity_from_string()`.

### `godot_to_ros_quat(q: Quaternion) -> Quaternion` *(const)*

Converts a rotation from the Godot axis convention to the ROS axis convention. This is the exact mapping used internally by `RosTfBroadcaster`, so rotations you build by hand (e.g. for an `Odometry` message) stay consistent with TF.

### `godot_to_ros_vector(v: Vector3) -> Vector3` *(const)*

Converts a vector from the Godot axis convention (-Z forward, +Y up) to the ROS axis convention (+X forward, +Z up). This is the exact mapping used internally by `RosTfBroadcaster`.

### `init(args: PackedStringArray = PackedStringArray()) -> void`

Initializes the ROS 2 context and starts the executor. This method must be called once at the start of the application, usually in a main script's `_ready()` function.
Arguments provided in `args` are passed to the ROS 2 initialization system (e.g., for remapping or parameter overrides).

### `ok() -> bool` *(const)*

Returns `true` if the ROS 2 context is currently active and the executor is running.

### `ros_to_godot_quat(q: Quaternion) -> Quaternion` *(const)*

Converts a rotation from the ROS axis convention to the Godot axis convention. Inverse of `godot_to_ros_quat` and the exact mapping used internally by `RosTfListener`.

### `ros_to_godot_vector(v: Vector3) -> Vector3` *(const)*

Converts a vector from the ROS axis convention (+X forward, +Z up) to the Godot axis convention (-Z forward, +Y up). Inverse of `godot_to_ros_vector` and the exact mapping used internally by `RosTfListener`.

### `set_logger_level(name: String, level: RosLogger.LoggingSeverity) -> void`

Sets the minimum severity emitted by the logger called `name`, which can be a node's logger or a child logger such as `"my_node.lidar"`. Equivalent to `rclpy.logging.set_logger_level()`.

### `shutdown() -> void`

Shuts down the ROS 2 context and stops the executor thread. This should be called when the application is closing to ensure a clean exit.

## Señales

### `ros_ready() -> void`

Emitted when the ROS 2 context has been successfully initialized and is ready to create nodes and communication interfaces.
