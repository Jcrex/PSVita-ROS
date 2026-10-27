# RosTimer

Hereda de: `RefCounted`

A timer that triggers a callback at a fixed rate, synchronized with the ROS 2 executor.

`RosTimer` provides a way to execute Godot code on a regular schedule, managed by the ROS 2 executor. It is created through `RosNode.create_timer`.
Unlike Godot's built-in timers, `RosTimer` is tied to the ROS 2 clock and processing loop, making it more suitable for tasks requiring synchronization with ROS 2 events or simulation time.

## Métodos

### `cancel() -> void`

Stops the timer from triggering its callback.

### `get_remaining_time() -> float` *(const)*

Returns the amount of time (in seconds) remaining until the next timer trigger.

### `is_canceled() -> bool` *(const)*

Returns `true` if the timer has been canceled.

### `is_ready() -> bool` *(const)*

Returns `true` if the timer is ready to trigger its callback.

### `reset() -> void`

Resets the timer's internal clock. If the timer was previously canceled, it will start running again.
