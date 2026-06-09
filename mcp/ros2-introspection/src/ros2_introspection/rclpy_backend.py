"""Real backend using rclpy. Imported lazily; only works on the dev PC
(or inside a ROS2 Jazzy container). Validated against a live graph in the
robotnik_dev container (ROS2 Jazzy, rclpy) on 2026-06-10.
"""
from __future__ import annotations

import time

from .backend import MessageSample, NodeInfo, Ros2Backend, TopicInfo


class RclpyBackend(Ros2Backend):
    def __init__(self) -> None:
        import rclpy
        from rclpy.node import Node
        if not rclpy.ok():
            rclpy.init()
        self._rclpy = rclpy
        self._node = Node("ros2_introspection_mcp")

    def list_topics(self) -> list[TopicInfo]:
        return [
            TopicInfo(name=name, types=list(types))
            for name, types in self._node.get_topic_names_and_types()
        ]

    def list_nodes(self) -> list[NodeInfo]:
        return [
            NodeInfo(name=name, namespace=ns)
            for name, ns in self._node.get_node_names_and_namespaces()
        ]

    def get_topic_type(self, topic: str) -> str:
        for name, types in self._node.get_topic_names_and_types():
            if name == topic:
                return types[0]
        raise KeyError(topic)

    def get_message_definition(self, type_name: str) -> str:
        """Return the .msg source text for e.g. 'sensor_msgs/msg/LaserScan'.

        rosidl_runtime_py resolves the interface path through the ament
        index, so it works for any package sourced in the environment.
        """
        from rosidl_runtime_py import get_interface_path

        try:
            path = get_interface_path(type_name)
        except (LookupError, ValueError) as exc:
            raise KeyError(type_name) from exc
        with open(path, encoding="utf-8") as f:
            return f.read()

    def echo_topic(self, topic: str, timeout_s: float = 5.0) -> MessageSample:
        """Subscribe once and return the first message as a plain dict.

        Uses a BEST_EFFORT QoS subscription: compatible with both reliable
        and best-effort publishers (sensor topics are usually best-effort).
        Raises KeyError if the topic does not exist, TimeoutError if no
        message arrives within timeout_s.
        """
        from rclpy.qos import (
            QoSHistoryPolicy,
            QoSProfile,
            QoSReliabilityPolicy,
        )
        from rosidl_runtime_py.convert import message_to_ordereddict
        from rosidl_runtime_py.utilities import get_message

        type_name = self.get_topic_type(topic)  # KeyError si no existe
        msg_cls = get_message(type_name)

        received: list = []

        def _on_msg(msg) -> None:
            if not received:
                received.append(msg)

        qos = QoSProfile(
            depth=1,
            history=QoSHistoryPolicy.KEEP_LAST,
            reliability=QoSReliabilityPolicy.BEST_EFFORT,
        )
        sub = self._node.create_subscription(msg_cls, topic, _on_msg, qos)
        try:
            deadline = time.monotonic() + timeout_s
            while not received and time.monotonic() < deadline:
                self._rclpy.spin_once(self._node, timeout_sec=0.1)
        finally:
            self._node.destroy_subscription(sub)

        if not received:
            raise TimeoutError(
                f"no message on {topic} within {timeout_s:.1f}s"
            )
        data = dict(message_to_ordereddict(received[0]))
        return MessageSample(topic=topic, data=data)

    def list_interfaces(self) -> list[str]:
        seen: list[str] = []
        for _, types in self._node.get_topic_names_and_types():
            for ty in types:
                if ty not in seen:
                    seen.append(ty)
        return seen
