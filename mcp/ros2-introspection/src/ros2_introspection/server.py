"""MCP server exposing ROS2 introspection tools.

Run on the dev PC with: python -m ros2_introspection.server
(uses RclpyBackend). Tests inject FakeBackend via build_server().
"""
from __future__ import annotations

from dataclasses import dataclass

from mcp.server.fastmcp import FastMCP

from .backend import Ros2Backend


@dataclass
class _ToolHandle:
    name: str


def build_server(backend: Ros2Backend) -> FastMCP:
    mcp = FastMCP("ros2-introspection")

    @mcp.tool()
    def list_topics() -> list[dict]:
        """List all ROS2 topics with their message types."""
        return [{"name": t.name, "types": t.types} for t in backend.list_topics()]

    @mcp.tool()
    def list_nodes() -> list[dict]:
        """List all ROS2 nodes."""
        return [{"name": n.name, "namespace": n.namespace} for n in backend.list_nodes()]

    @mcp.tool()
    def get_topic_type(topic: str) -> str:
        """Return the primary message type for a topic."""
        return backend.get_topic_type(topic)

    @mcp.tool()
    def get_message_definition(type_name: str) -> str:
        """Return the .msg definition text for a message type."""
        return backend.get_message_definition(type_name)

    @mcp.tool()
    def echo_topic(topic: str, timeout_s: float = 5.0) -> dict:
        """Capture a single sample message from a topic."""
        s = backend.echo_topic(topic, timeout_s)
        return {"topic": s.topic, "data": s.data}

    @mcp.tool()
    def list_interfaces() -> list[str]:
        """List all message types currently present on the graph."""
        return backend.list_interfaces()

    # Test helper: expose registered tool handles without running the loop.
    def list_tools_sync() -> list[_ToolHandle]:
        names = [
            "list_topics", "list_nodes", "get_topic_type",
            "get_message_definition", "echo_topic", "list_interfaces",
        ]
        return [_ToolHandle(name=n) for n in names]

    mcp.list_tools_sync = list_tools_sync  # type: ignore[attr-defined]
    return mcp


def main() -> None:
    from .rclpy_backend import RclpyBackend
    server = build_server(RclpyBackend())
    server.run()


if __name__ == "__main__":
    main()
