# RosServerGoalHandle

Hereda de: `RefCounted`

The server-side handle for an accepted action goal.

`RosServerGoalHandle` is handed to the execute callback of a `RosActionServer` for every accepted goal. It carries the goal message and is used to publish feedback and report the outcome.
Every goal must be driven to exactly one terminal state: `succeed`, `abort` or `canceled`. Calling a second terminal method on the same handle is an error.
For long-running goals, spread the work over multiple frames with `await` and poll `is_cancel_requested` so clients can cancel:

```gdscript
func _execute_goal(goal_handle: RosServerGoalHandle):
    var result = goal_handle.create_result()
    for step in range(goal_handle.get_goal().order):
        if goal_handle.is_cancel_requested():
            goal_handle.canceled(result)
            return
        var fb = goal_handle.create_feedback()
        goal_handle.publish_feedback(fb)
        await get_tree().process_frame
    goal_handle.succeed(result)

```

## Métodos

### `abort(result: RosMsg) -> void`

Terminates the goal as failed, sending `result` to the client (the client sees `RosGoalHandle.STATUS_ABORTED`).

### `canceled(result: RosMsg) -> void`

Terminates the goal as canceled, sending `result` to the client (the client sees `RosGoalHandle.STATUS_CANCELED`). Call this in response to `is_cancel_requested` becoming `true`.

### `create_feedback() -> RosMsg`

Creates and returns an empty `RosMsg` of this action's feedback type, ready to be filled and passed to `publish_feedback`.

### `create_result() -> RosMsg`

Creates and returns an empty `RosMsg` of this action's result type, ready to be filled and passed to one of the terminal methods.

### `get_goal() -> RosMsg` *(const)*

Returns the goal message sent by the client.

### `get_goal_id() -> String` *(const)*

Returns the unique identifier of this goal as a hexadecimal string. Useful for logging when handling several concurrent goals.

### `is_active() -> bool` *(const)*

Returns `true` while the goal has not reached a terminal state yet.

### `is_cancel_requested() -> bool` *(const)*

Returns `true` once a client has requested this goal to be canceled. Poll it inside long-running execute callbacks and finish with `canceled`.

### `publish_feedback(feedback: RosMsg) -> void`

Publishes a `feedback` message for this goal. Clients receive it through the `RosGoalHandle.feedback` signal.

### `succeed(result: RosMsg) -> void`

Terminates the goal successfully, sending `result` to the client (the client sees `RosGoalHandle.STATUS_SUCCEEDED`).
