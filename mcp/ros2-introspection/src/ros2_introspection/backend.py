"""Backend abstraction for ROS2 introspection.

RclpyBackend (real) runs only on the dev PC where rclpy exists.
FakeBackend (in-memory) lets the tools be tested on the laptop without ROS2.
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Protocol


@dataclass(frozen=True)
class TopicInfo:
    name: str
    types: list[str]


@dataclass(frozen=True)
class NodeInfo:
    name: str
    namespace: str


@dataclass(frozen=True)
class MessageSample:
    topic: str
    data: dict


class Ros2Backend(Protocol):
    def list_topics(self) -> list[TopicInfo]: ...
    def list_nodes(self) -> list[NodeInfo]: ...
    def get_topic_type(self, topic: str) -> str: ...
    def get_message_definition(self, type_name: str) -> str: ...
    def echo_topic(self, topic: str, timeout_s: float = 5.0) -> MessageSample: ...
    def list_interfaces(self) -> list[str]: ...


@dataclass
class FakeBackend:
    topics: list[TopicInfo] = field(default_factory=list)
    nodes: list[NodeInfo] = field(default_factory=list)
    definitions: dict[str, str] = field(default_factory=dict)
    samples: dict[str, MessageSample] = field(default_factory=dict)

    def list_topics(self) -> list[TopicInfo]:
        return list(self.topics)

    def list_nodes(self) -> list[NodeInfo]:
        return list(self.nodes)

    def get_topic_type(self, topic: str) -> str:
        for t in self.topics:
            if t.name == topic:
                return t.types[0]
        raise KeyError(topic)

    def get_message_definition(self, type_name: str) -> str:
        return self.definitions[type_name]

    def echo_topic(self, topic: str, timeout_s: float = 5.0) -> MessageSample:
        return self.samples[topic]

    def list_interfaces(self) -> list[str]:
        seen: list[str] = []
        for t in self.topics:
            for ty in t.types:
                if ty not in seen:
                    seen.append(ty)
        return seen
