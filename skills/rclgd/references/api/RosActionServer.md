# RosActionServer

Hereda de: `RefCounted`

A ROS 2 Action Server that executes long-running goals from clients.

`RosActionServer` lets Godot act as a server for ROS 2 actions. It is created through `RosNode.create_action_server`, passing an execute callback.
Incoming goals are accepted by default and handed to the execute callback on the Godot main thread as a `RosServerGoalHandle`. To reject goals, pass a goal callback to `RosNode.create_action_server`: it receives the goal `RosMsg` and returns `true` to accept it. Cancel requests are always accepted; the execute callback observes them by polling `RosServerGoalHandle.is_cancel_requested` and decides how to finish the goal.
**Threading:** ROS needs the accept/reject answer immediately, so the goal callback runs synchronously on a ROS executor thread, not the main thread, and possibly on several threads at once. Only inspect the goal message there; do not touch nodes or the scene tree. For checks that need game state, accept the goal and abort it at the start of the execute callback instead. The client then sees the goal accepted and then aborted:

```gdscript
func _execute_goal(goal_handle: RosServerGoalHandle):
    if not car.is_inside_tree():
        goal_handle.abort(goal_handle.create_result())
        return
    # ... run the goal

```

The execute callback must drive every goal to exactly one terminal state: `RosServerGoalHandle.succeed`, `RosServerGoalHandle.abort` or `RosServerGoalHandle.canceled`. Because the callback runs on the main thread, long-running goals should spread their work over frames with `await` rather than blocking.

```gdscript
var server = ros_node.create_action_server("fibonacci", "example_interfaces/action/Fibonacci",
    func(goal_handle):
        var sequence = [0, 1]
        for i in range(2, goal_handle.get_goal().order):
            sequence.append(sequence[i - 1] + sequence[i - 2])
            var fb = goal_handle.create_feedback()
            fb.sequence = sequence
            goal_handle.publish_feedback(fb)
            await get_tree().process_frame
        var result = goal_handle.create_result()
        result.sequence = sequence
        goal_handle.succeed(result)
)

```

Keep a reference to the returned server object: like every rclgd interface it unregisters from the ROS graph when it is freed.
