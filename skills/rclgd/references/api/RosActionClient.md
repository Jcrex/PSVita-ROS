# RosActionClient

Hereda de: `RefCounted`

A ROS 2 Action Client for sending goals to an action server.

`RosActionClient` allows Godot to send goals to ROS 2 action servers. It is created through `RosNode.create_action_client`.
Actions are designed for long-running tasks: unlike services they provide continuous feedback while the goal executes, and they can be canceled mid-flight.
Use `create_goal` to build a goal message, then `send_goal` to dispatch it. The returned `RosGoalHandle` acts as a handle for the in-flight goal: connect to its signals or `await` them to track acceptance, feedback and the final result.

```gdscript
var client = ros_node.create_action_client("fibonacci", "example_interfaces/action/Fibonacci")
if client.wait_for_server(2.0):
    var goal = client.create_goal()
    goal.order = 10
    var handle = client.send_goal(goal)
    handle.feedback.connect(func(msg): print("Partial: ", msg.sequence))
    await handle.completed
    if handle.get_status() == RosGoalHandle.STATUS_SUCCEEDED:
        print("Result: ", handle.get_result().sequence)

```

## Métodos

### `create_goal() -> RosMsg`

Creates and returns an empty `RosMsg` of the correct type for this client's action goals (e.g. the `Goal` part of the action definition).

### `is_server_ready() -> bool` *(const)*

Returns `true` if an action server for this action is currently available. Unlike `wait_for_server` this never blocks.

### `send_goal(goal: RosMsg) -> RosGoalHandle`

Sends a `goal` to the action server asynchronously. Returns a `RosGoalHandle` that tracks the goal's lifecycle: acceptance/rejection, feedback and the final result.

### `wait_for_server(timeout_sec: float) -> bool`

Blocks until the action server is available or `timeout_sec` is reached. Returns `true` if the server is available.

### `wait_for_server_async(timeout_sec: float) -> void`

Asynchronously waits for the action server to become available up to `timeout_sec` seconds. Emits the `server_available` signal when the server state changes or the timeout is reached.

## Señales

### `server_available(available: bool) -> void`

Emitted when the action server becomes available or when an asynchronous wait times out.
