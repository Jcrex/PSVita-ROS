# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The PS Vita ↔ ROS2 project: turn a PS Vita 1000 into a real ROS2 Jazzy node
via micro-ROS (XRCE-DDS) over WiFi/UDP. The repo now contains **everything**:
docs, the dual Rust+C modules, the Vita homebrew app, the MCP server, the
Claude Code skills and the project website. Current state and exact next
steps live in `docs/06-bitacora-estado.md` — **read that first** when
resuming work, and **update it** when closing milestones (also update
`web/src/data/fases.ts`).

### Machine roles

| Role | Machine | IP | Responsibility |
|---|---|---|---|
| Workshop | Laptop (this repo) | 192.168.1.108 | Portable code + host parity tests, docs, web, MCP. Will also run the micro-ROS Agent (it is on the Vita's WiFi network and has ROS2 Jazzy via the `robotnik_dev` docker container). |
| Development | PC CachyOS | 192.168.1.65 | VitaSDK cross-compilation, `.vpk` packaging, hardware deploys |
| Target | PS Vita 1000 | — | ARM Cortex-A9 32-bit, 512 MB RAM, newlib (not Linux) |

**No project toolchains are installed on the laptop.** Rust builds go through
docker (`rust:1-slim`); the web uses pnpm via corepack; ROS2 testing uses the
`robotnik_dev` container. Vita compilation only happens on the PC.

## Core architectural constraint

**Every low-level module has two equivalent implementations** (Rust + C/C++)
behind a shared C header (`modules/*/include/*.h` is the only source of
truth). Both must pass the same parity suite; C/C++ is a permanent fallback.
Key Rust rule learned: module crates are `rlib`; staticlibs are produced
explicitly with `cargo rustc --crate-type staticlib` (one Rust staticlib per
binary — the app uses the umbrella crate `vita-app/rust-modules/`).

## Common commands

```bash
tools/run-parity-tests.sh [module]      # C+Rust parity on host (docker for Rust)
cd mcp/ros2-introspection && .venv/bin/python -m pytest tests/ -q
cd web && pnpm dev                      # site dev server
cd web && docker compose up -d --build  # production site, localhost:4321
```

## Layout

- `modules/{mem-pool,net-udp,microros-transport}/` — dual modules (each has
  its own README with API/design/status). Platform split is *inside* each
  impl: `#ifdef __vita__` / `#[cfg(target_os = "vita")]`; the host branch
  exists so parity tests run on the laptop.
- `vita-app/` — the Fase 1 homebrew (`main.c` + uxr glue + netlog +
  CMake/VitaSDK + `.vpk`). Builds only on the PC. `scripts/` cross-compiles
  microxrcedds_client.
- `mcp/ros2-introspection/` — `FakeBackend` (laptop tests) vs `RclpyBackend`
  (complete; validated against a live Jazzy graph in `robotnik_dev`).
- `docs/rust/` — Rust learning series tied to real repo code. The user is a
  Rust beginner: **every new Rust construct must be explained in comments
  and/or this series**.
- `docs/guias-vita/` — homebrew install guides (YAML frontmatter; the web
  renders them directly from here — do not duplicate content into web/).
- `web/` — Astro 5 SSR + better-sqlite3 + Docker; DB volume at `web/data/`.
  Future home: psvita-ros.jcrex999.com (recipe in `web/README.md`).

## Conventions

- Docs, comments and commit messages in Spanish; commit subjects use
  conventional prefixes (`feat(fase1):`, `docs(rust):`, ...).
- One commit per coherent milestone; never leave parity tests red.
- Code that cannot be verified on the laptop is marked "validar en el PC /
  en hardware" in code and READMEs — keep those markers accurate.

## Sync laptop ↔ PC

Via git (`github.com/Jcrex/PSVita-ROS.git`). `.claude/` stays local.
