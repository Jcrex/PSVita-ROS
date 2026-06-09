# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

This is the **laptop workshop** for the PS Vita ↔ ROS2 project. It produces the meta-layer: documentation, Claude Code skills, and the `ros2-introspection` MCP server. It does **not** contain the C/C++/Rust code that runs on the Vita — that lives on the dev PC.

### Machine roles

| Role | Machine | IP | Responsibility |
|---|---|---|---|
| Workshop | Laptop (this repo) | 192.168.1.108 | Produces docs, skills, MCP |
| Development | PC CachyOS | 192.168.1.65 | All builds, installs, execution |
| Target | PS Vita 1000 | — | ARM Cortex-A9 32-bit, 512 MB RAM |

**Nothing from this project is installed or built on the laptop.** All compilation and execution happens on the PC CachyOS.

## MCP server — `mcp/ros2-introspection`

Python package (`ros2-introspection-mcp`) exposing ROS2 graph introspection tools to Claude Code via stdio transport. Runs on the dev PC where `rclpy` is available (ROS2 Jazzy).

### Architecture

- `backend.py` — `Ros2Backend` Protocol + `FakeBackend` (in-memory, used in tests)
- `rclpy_backend.py` — real implementation using `rclpy` (only works on the dev PC)
- `server.py` — `build_server(backend)` factory + `main()` entry point; tests inject `FakeBackend`

The `FakeBackend`/`RclpyBackend` split is intentional: all tests on the laptop use `FakeBackend`; the real `RclpyBackend` is validated on the PC with a live ROS2 graph.

Tools exposed: `list_topics`, `list_nodes`, `get_topic_type`, `get_message_definition` ⚠️, `echo_topic` ⚠️, `list_interfaces`. The ⚠️ tools raise `NotImplementedError` in `RclpyBackend` until completed on the PC.

### Running tests

```bash
cd mcp/ros2-introspection
pip install -e ".[dev]"   # installs pytest; rclpy comes from the ROS2 env, not pip
pytest
```

### Installing on the dev PC

```bash
source /opt/ros/jazzy/setup.bash
cd mcp/ros2-introspection
pip install -e .
python -m ros2_introspection.server   # runs the MCP server
```

## Skills (`skills/`)

Three Claude Code skills for use on the dev PC:

- **`vita-dual-module`** — scaffold a new low-level Vita module with dual Rust + C/C++ structure behind a shared C-ABI header. Always use this for any module touching hardware, memory, or system.
- **`vita-build-package`** — build and package a `.vpk` via CMake+VitaSDK (C/C++) or `cargo-vita` (Rust).
- **`vita-deploy-logs`** — deploy a `.vpk` to a real PS Vita via FTP and capture runtime logs over UDP.

## Core architectural constraint

**Every low-level module must have two equivalent implementations** (Rust + C/C++) behind a shared C header. The C header is the only source of truth. Both implementations must pass the same parity test suite. C/C++ is a permanent equivalent fallback, not a placeholder.

## Sync to dev PC

```bash
git push   # from laptop
git pull   # on the PC (github.com/Jcrex/PSVita-ROS.git)
```

The `.claude/` directory is excluded from sync (local Claude config/memory).
