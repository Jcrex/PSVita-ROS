# RosTfBroadcaster

Hereda de: `RefCounted`

A broadcaster for coordinate transforms in the ROS 2 TF2 system.

`RosTfBroadcaster` allows Godot to send coordinate transforms (positions and rotations) to the ROS 2 transformation tree (TF2). It is created through `RosNode.create_tf_broadcaster`.
By sending transforms, you can communicate the spatial relationship between different parts of a robot or environment to other ROS 2 nodes.

## Métodos

### `send_transform(transform: Transform3D, frame_id: String, parent_frame_id: String, is_static: bool = false, timestamp: RosMsg = null) -> void`

Sends a coordinate transformation from `parent_frame_id` to `frame_id`. If `is_static` is `true`, the transform is sent as a static transform which is typically only sent once.
