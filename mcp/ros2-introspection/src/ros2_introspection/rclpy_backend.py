"""Real backend using rclpy. Imported lazily; only works on the dev PC."""
from __future__ import annotations

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
        # Resolve via ament index / rosidl; concrete impl validated on the PC.
        raise NotImplementedError("validar en el PC con rosidl/ament_index")

    def echo_topic(self, topic: str, timeout_s: float = 5.0) -> MessageSample:
        # Subscribe once, spin until a message or timeout; validated on the PC.
        raise NotImplementedError("validar en el PC")

    def list_interfaces(self) -> list[str]:
        seen: list[str] = []
        for _, types in self._node.get_topic_names_and_types():
            for ty in types:
                if ty not in seen:
                    seen.append(ty)
        return seen
