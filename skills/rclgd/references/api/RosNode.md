# RosNode

Hereda de: `RefCounted`

A ROS 2 Node that manages publishers, subscribers, and other communication interfaces.

The `RosNode` is the primary interface for interacting with the ROS 2 network. It provides factory methods to create publishers, subscribers, clients, and services, and allows management of node-level parameters and timers. Its ROS 2 logger is available through `get_logger`, so messages reach the console and `/rosout` like any other ROS node's.
A node must be initialized using `init` before it can be used to create other communication components.

## Métodos

### `count_publishers(topic: String) -> int`

Returns the number of publishers currently active on a specific `topic` in the ROS 2 graph.

### `count_subscribers(topic: String) -> int`

Returns the number of subscribers currently active on a specific `topic` in the ROS 2 graph.

### `create_action_client(action_name: String, action_type: Variant, qos: RosQoS = null) -> RosActionClient`

Creates and returns a `RosActionClient` for the specified `action_name` and `action_type` (e.g. `"example_interfaces/action/Fibonacci"`). Use `qos` to configure the Quality of Service for the action client.

### `create_action_server(action_name: String, action_type: Variant, execute_callback: Callable, goal_callback: Callable = Callable(), qos: RosQoS = null) -> RosActionServer`

Creates and returns a `RosActionServer` for the specified `action_name` and `action_type`. Accepted goals are handed to `execute_callback` on the main thread as a `RosServerGoalHandle`, which must be driven to a terminal state. Goals are accepted by default; pass `goal_callback` to decide yourself: it receives the goal `RosMsg` and returns `true` to accept. `goal_callback` runs on a ROS executor thread, not the main thread, so it must not touch nodes or the scene tree. Cancel requests are always accepted. Use `qos` to configure the Quality of Service for the action server. See `RosActionServer` for a full example.

### `create_client(srv_name: String, srv_type: Variant, qos: RosQoS = null) -> RosClient`

Creates and returns a `RosClient` for the specified service name and type. Use `qos` to configure the Quality of Service for the client.

### `create_publisher(topic: String, type: Variant, qos: RosQoS = null) -> RosPublisher`

Creates and returns a `RosPublisher` to send messages to a specific `topic`. Use `qos` to configure the Quality of Service for the publisher.

### `create_service(srv_name: String, srv_type: Variant, callback: Callable, qos: RosQoS = null) -> RosService`

Creates and returns a `RosService` server for the specified service name and type. The `callback` is triggered whenever a request is received. Use `qos` to configure the Quality of Service for the service server.

### `create_subscription(topic: String, type: Variant, callback: Callable, qos: RosQoS = null) -> RosSubscriber`

Creates and returns a `RosSubscriber` to receive messages from a specific `topic`. The `callback` is triggered for every new message received, always on the Godot main thread. Use `qos` to configure the Quality of Service for the subscription.

### `create_tf_broadcaster() -> RosTfBroadcaster`

Creates and returns a `RosTfBroadcaster` for publishing coordinate transforms into the TF2 system.

### `create_tf_listener(cache_time_sec: float = 10.0) -> RosTfListener`

Creates and returns a `RosTfListener` for looking up coordinate transforms in the TF2 system.
`cache_time_sec` is how far back the buffer keeps transforms, which bounds how old a `RosTfListener.lookup_transform` stamp may be. Raise it when replaying a bag or when data arrives well behind TF.

### `create_timer(seconds: float, callback: Callable) -> RosTimer`

Creates and returns a `RosTimer` that triggers the `callback` at the specified `seconds` interval, synced with the ROS 2 executor's clock.

### `declare_parameter(name: String, default_value: Variant) -> void`

Declares a parameter on the node with a `default_value`. Parameters must be declared before they can be retrieved or modified by external tools.

### `get_logger() -> RosLogger` *(const)*

Returns the node's `RosLogger`, named after the node. Messages logged through it go to the console and `/rosout`. The same instance is returned on every call, so `once`, `skip_first` and `throttle_duration_sec` filter state is kept. Equivalent to rclpy's `Node.get_logger()`.

```gdscript
var logger := ros_node.get_logger()
logger.info("Simulation started")

```

### `get_name() -> String` *(const)*

Returns the name of the node as registered in the ROS 2 graph.

### `get_namespace() -> String` *(const)*

Returns the namespace of the node.

### `get_parameter(name: String) -> Variant`

Returns the current value of the parameter with the specified `name`.

### `get_topic_names_and_types() -> Dictionary`

Returns a `Dictionary` containing all currently active topic names as keys and their associated message types as values.

### `init(node_name: String, namespace: String = "") -> void`

Initializes the node with a `node_name` and an optional `namespace`. This must be called before using any other functions of the node.

### `now() -> RosMsg`

Returns the current ROS 2 system time as a `RosMsg` of type `builtin_interfaces/msg/Time`.

### `resolve_frame(frame_id: String) -> String`

Prepends the node's namespace to a `frame_id` if it is not already absolute, helping resolve local frame names in multi-agent simulations.

### `set_parameter(name: String, value: Variant) -> void`

Sets the value of a previously declared parameter on the node.

## Señales

### `parameter_changed(name: String, value: Variant) -> void`

Emitted whenever a node parameter is updated by an external tool or by `set_parameter` locally.
