# RosGoalHandle

Hereda de: `RefCounted`

A handle that tracks the lifecycle of a goal sent through a `RosActionClient`.

`RosGoalHandle` is returned by `RosActionClient.send_goal` and behaves like a promise: you can poll it with `is_completed` and `get_result`, or connect to (and `await`) its signals.
All signals are emitted on the Godot main thread, so it is always safe to touch the scene tree from their handlers.
The typical lifecycle is: `accepted` (or `rejected`) → zero or more `feedback` emissions → `completed` with the final result and status.
**Note:** If the goal is rejected by the server, `completed` is still emitted (with a `null` result and `STATUS_UNKNOWN`) so that `await handle.completed` never hangs.

## Métodos

### `cancel() -> void`

Asks the server to cancel this goal. Cancellation is cooperative: the server decides when (and whether) to stop. The outcome still arrives through `completed`, with `STATUS_CANCELED` if the cancellation was honored.

### `get_result() -> RosMsg` *(const)*

Returns the result message once the goal has completed, or `null` before completion (and for rejected goals).

### `get_status() -> int` *(const)*

Returns the terminal status of the goal as one of the `Status` constants. Before completion this is `STATUS_UNKNOWN`.

### `is_accepted() -> bool` *(const)*

Returns `true` once the server has accepted the goal.

### `is_completed() -> bool` *(const)*

Returns `true` once the goal has reached a terminal state and the result is available through `get_result`.

## Señales

### `accepted() -> void`

Emitted when the server accepts the goal and starts executing it.

### `completed(result: RosMsg, status: int) -> void`

Emitted when the goal reaches a terminal state. `result` holds the action result message (`null` if the goal was rejected) and `status` is one of the `Status` constants.

### `feedback(msg: RosMsg) -> void`

Emitted every time the server publishes feedback for this goal.

### `rejected() -> void`

Emitted when the server rejects the goal. `completed` follows immediately with a `null` result.

## Constantes

- `STATUS_UNKNOWN = 0` (enum `Status`) — The goal has no terminal status yet (still executing), or it was rejected by the server.
- `STATUS_SUCCEEDED = 4` (enum `Status`) — The goal finished successfully. Matches `action_msgs/GoalStatus.STATUS_SUCCEEDED`.
- `STATUS_CANCELED = 5` (enum `Status`) — The goal was canceled after a cancel request. Matches `action_msgs/GoalStatus.STATUS_CANCELED`.
- `STATUS_ABORTED = 6` (enum `Status`) — The server aborted the goal. Matches `action_msgs/GoalStatus.STATUS_ABORTED`.
