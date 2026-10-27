# RosTfListener

Hereda de: `RefCounted`

A listener for coordinate transforms in the ROS 2 TF2 system.

`RosTfListener` allows Godot to query the current spatial relationships between different coordinate frames in the ROS 2 TF2 tree. It is created through `RosNode.create_tf_listener`.
By listening for transforms, you can determine the position and rotation of robot parts, sensors, or other objects relative to each other or a global frame.
Omit the `time` argument to get the newest transform available. Pass the time the data was captured instead — a message's `header.stamp` goes straight through — and the reading stays pinned to where the robot actually was when it was taken, rather than snapping to the newest transform:
[codeblock lang=gdscript]
var here = tf.lookup_transform("map", "base_link")                       # now
var then = tf.lookup_transform("map", msg.header.frame_id, msg.header.stamp)
if then == null:
push_warning(tf.get_last_error())
[/codeblock]
Every `time` argument accepts `null` (latest available transform), a `float` of seconds since the epoch, or a `RosMsg` holding a `builtin_interfaces/msg/Time`.
The method names and argument order mirror `tf2_ros.Buffer`, so code and habits carry over from rclpy. The one deliberate difference is that `time` is optional here — TF2 requires it, and expects a zero time to mean "latest".

## Métodos

### `all_frames_as_yaml() -> String` *(const)*

Returns the TF2 debug dump of every known frame, with the same content as `ros2 run tf2_tools view_frames`: each frame's parent, broadcasting authority, publish rate and buffer extent.

### `can_transform(target_frame: String, source_frame: String, time: Variant = null, timeout_sec: float = 0.0) -> bool` *(const)*

Returns `true` if a transformation between `source_frame` and `target_frame` is available at `time`, or right now when `time` is omitted. On failure the reason is available through `get_last_error`.
Asks the same question as `lookup_transform` without doing the work, and takes the same `timeout_sec`.

### `can_transform_full(target_frame: String, target_time: Variant, source_frame: String, source_time: Variant, fixed_frame: String, timeout_sec: float = 0.0) -> bool` *(const)*

Whether `lookup_transform_full` would succeed for the same arguments. On failure the reason is available through `get_last_error`.

### `clear() -> void`

Drops every stored transform, for instance after `/clock` jumps backwards. Frame names stay registered, so `get_frame_names` keeps reporting them; create a fresh listener to forget the frames as well.

### `frame_exists(frame: String) -> bool` *(const)*

Returns `true` if `frame` is known to the buffer.

### `get_cache_time() -> float` *(const)*

Returns how far back, in seconds, the buffer keeps transforms. Set through `RosNode.create_tf_listener`.

### `get_frame_latest_time(frame: String) -> float` *(const)*

Returns the stamp of the newest transform stored for `frame`, in seconds. Returns `0.0` for an unknown frame, and also for a frame that is only published statically, since static transforms are stored at time zero.

### `get_frame_names() -> PackedStringArray` *(const)*

Returns every frame name the buffer has heard of, in no particular order. Useful for building a frame picker.

### `get_frame_parent(frame: String) -> String` *(const)*

Returns the frame `frame` is attached to, or an empty string when it is a tree root or is unknown. Walking this repeatedly reconstructs the frame tree.

### `get_last_error() -> String` *(const)*

Returns the TF2 message explaining why the most recent lookup failed, or an empty string once one succeeds. This is the text to show a user when a frame is missing or a stamp falls outside the buffer.

### `lookup_transform(target_frame: String, source_frame: String, time: Variant = null, timeout_sec: float = 0.0) -> Variant`

Attempts to find the coordinate transformation from `source_frame` to `target_frame`. Returns a `Transform3D` (already converted to the Godot axis convention) representing the position and orientation of the source frame relative to the target frame.
With `time` omitted the newest available transform is used. Given a time, the transform is resolved at that moment instead, interpolating between the surrounding samples — pass a message's `header.stamp` to place its data where the robot was when the data was produced.
Returns `null` if the transform is not available — the frames are not connected, or the stamp falls outside the buffer — so a failed lookup can be distinguished from a genuine identity transform; `get_last_error` then explains why. If `timeout_sec` is greater than zero, the lookup blocks for up to that long waiting for the transform to become available. This works because rclgd spins the executor on its own thread by default; under `-p use_separate_thread:=false` nothing would be left to fill the buffer while the caller waits, so the timeout is not applied.

### `lookup_transform_full(target_frame: String, target_time: Variant, source_frame: String, source_time: Variant, fixed_frame: String, timeout_sec: float = 0.0) -> Variant`

The advanced ("time travel") lookup: where `source_frame` was at `source_time`, expressed in `target_frame` as it is at `target_time`, bridged through `fixed_frame` — a frame assumed not to move over that interval, typically `map` or `odom`.
This stays a separate method rather than more optional arguments on `lookup_transform`, matching tf2's own split: relating two different instants is a different question from placing one, and most combinations of the two argument sets are meaningless.
Returns `null` on failure; see `get_last_error`.
