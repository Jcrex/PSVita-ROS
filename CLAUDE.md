# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The PS Vita ↔ ROS2 project: turn a PS Vita 1000 into a real ROS2 Jazzy node
via micro-ROS (XRCE-DDS) over WiFi/UDP. The repo now contains **everything**:
docs, the dual Rust+C modules, the Vita homebrew app, the MCP server, the
Claude Code skills and the project website. Current state and exact next
steps live in `docs/06-bitacora-estado.md` — **read that first** when
resuming work, and **update it** when closing milestones. (`web/src/data/fases.ts`
too, but the web is **paused** since 2026-11-01 — see `web/` below.) The latest full-repo
audit is `docs/ia/auditoria/README.md` (2026-11-01): pending cleanup lots, bugs and
optimizations.

### Machine roles

| Role | Machine | IP | Responsibility |
|---|---|---|---|
| Workshop | Laptop | 192.168.1.108 | Portable code + host parity tests, docs, web, MCP. ROS 2 tests via the `robotnik_dev` container (historical: it ran the agent in Fase 1). |
| Development | PC CachyOS | 192.168.1.65 | VitaSDK cross-compilation, `.vpk` packaging, hardware deploys, **and the micro-ROS Agent** (station `docker/vita-ros.sh up`, UDP 8888) |
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

- `modules/{mem-pool,net-udp,microros-transport,msg-ring,viz-math,msg-cdr,tf-tree,msg-schema}/` — dual modules (each has
  its own README with API/design/status). Platform split is *inside* each
  impl: `#ifdef __vita__` / `#[cfg(target_os = "vita")]`; the host branch
  exists so parity tests run on the laptop.
- `vita-app/` — the Fase 1 homebrew (`main.c` + uxr glue + netlog +
  CMake/VitaSDK + `.vpk`). Builds only on the PC. `scripts/` cross-compiles
  microxrcedds_client.
- `godot/` — módulo Godot **4** `ros2_vita` en árbol (godot4-vita; ADR 0008,
  `docs/18`), compilado y probado en host (G1) y compilado para la Vita con `verify_runtime.py` PASS (G3) y
  **corriendo en hardware** con transporte XRCE: ida y vuelta con ROS 2 Jazzy y HMI de teleop con `/odom`
  (G4+G5+G6, 2026-10-30; G7 IMU calibrada en hardware y visor 3D en PC `godot/g7b-imu3d`, 2026-11-01; siguiente G7c = modelo 3D en la propia Vita, guion `docs/ia/guion-g7c-3d-en-la-vita.md`; luego panel trasero y cámara); `godot/loader-patches/` parchea el loader; `godot/vitasdk-stubs/dlfcn.h` va al SDK;
  `godot/test/` pruebas GDScript; `godot/g4-smoke/` + `tools/export-vita-vpk.sh` = proyecto mínimo y exportación a `.vpk` (G4, editor 4.8-dev7); el SDK Rust no depende de Godot; `tools/vita-doctor.sh` diagnostica el entorno;
  `tools/build-godot-template.sh` es la receta (solo PC; necesita VitaGL del port en `toolchains/vitagl-src` y
  `tools/build-pcre2-vita.sh`, docs/18 §4.5);
  `tools/check-vita-imports.py` / `build-rust-pic.sh` / `build-c-pic.sh` verifican/construyen los enlaces (G2); `tools/hwprobe/`
  es una sonda de hardware (sin compilar; docs/14 §9).
  `godot/godot35/` = app teleop en Godot 3.5 (HISTÓRICO, validada en hardware; docs/20–21);
  `godot/rclgd/` = clon local de rclgd (jazzy, trae Godot 4.7.1), no versionado.
- `docker/` — estación ROS 2 Jazzy propia (`vita-ros.sh`): agente micro-ROS, monitor de la Vita,
  puente Zenoh, turtlesim/TurtleBot3; `tools/vita-stack.sh` la usa por defecto.
- `mcp/ros2-introspection/` — `FakeBackend` (laptop tests) vs `RclpyBackend`
  (complete; validated against a live Jazzy graph in `robotnik_dev`).
- `skills/` — AI skills (versioned; install with `tools/install-skills.sh`, steps in `skills/INSTALAR.md`): `vita-*` (Vita workflow), `rclgd` (rclgd
  API + `scripts/rclgd-docs.sh` to fetch the official docs), `godot4-ros-scripting`,
  `ros2-vita-godot`. Published on the web ("Skills de IA"). Regenerate `rclgd/references/api` when
  rclgd changes (`references/versiones.md`).
- `docs/rust/` — Rust learning series tied to real repo code. The user is a
  Rust beginner: **every new Rust construct must be explained in comments
  and/or this series**.
- `archivo/` — archived (obsolete or superseded) material, keeping its original path inside
  (`archivo/docs/superpowers/` …). See `archivo/README.md`; pending lots in `docs/ia/auditoria/README.md`.
- `docs/informes/` — short reports for the user (≤ 500 words), e.g. the 2026-11-01 audit;
  their long versions are in `docs/ia/auditoria/`.
- `docs/guias-vita/` — homebrew install guides (YAML frontmatter; the web
  renders them directly from here — do not duplicate content into web/).
- `web/` — Astro 5 SSR + better-sqlite3 + Docker; DB volume at `web/data/`.
  Future home: psvita-ros.jcrex999.com (recipe in `web/README.md`).
  **PAUSED (user decision, 2026-11-01):** the user is planning a restructure and may
  discontinue the web now that Godot is the main product. Do not add collections or
  sections (e.g. for `docs/informes/` or `archivo/`) until they decide.
  Previous rule, suspended meanwhile: **all documentation must be published on the web in its section** (user
  rule). This is automated via glob collections in `src/content.config.ts`:
  any new .md under `docs/`, `docs/adr/`, `docs/rust/`, `docs/guias-vita/`
  or a module/app/MCP README shows up after a rebuild. If you create a NEW
  docs folder or category, add a collection + section for it (and a COPY
  line in `web/Dockerfile` if it's a new top-level path).

## Working method: learning mode (since 2026-10-31, user decision)

The user wants to continue the project on their own, audit code and explain it in detail —
not just validate what Claude writes. Full method and curriculum:
`docs/tutorial/07-ruta-completa-de-aprendizaje.md`. In every milestone:

- **Explain before coding**: plan in plain Spanish (what, why, alternatives); the user decides.
- **Leave the user a real coding task** (a "reto" in the lesson) instead of writing everything.
- **Give commands, don't run them** (docker, `ros2`, build, export, deploy): explain each part;
  run them yourself only if the user asks.
- **Guided audit before commit**: walk the `git diff` with the P10 checklist and ask the user what
  each part does.
- **Every milestone leaves a lesson** in `docs/tutorial/` (like `08-godot-imu-primer-sensor.md`),
  with "comprueba que lo has entendido" questions and a progress table.
- Cite `file:line` or official docs for every claim; mark guesses as hypotheses.
- **Two documentations.** For the user: chat explanations, `docs/tutorial/` and `docs/informes/` docs are
  **≤ 500 words each** (check with `wc -w`): direct, tables and commands, no padding. For Claude:
  `docs/ia/` (detailed teaching scripts and `docs/ia/auditoria/`, not on the web) + the technical docs `docs/00–23`.
  Rules: `docs/ia/README.md`.
- **Shells:** the user runs **fish** on the PC CachyOS (this machine) and **zsh** elsewhere. Commands
  given to the user for the PC must be fish-valid (`set VAR valor`, not `VAR=valor` alone; no
  `export`, `$(...)` → `(...)`); for the laptop, zsh. Scripts with a shebang (`tools/*.sh`) are fine.

## Conventions

- Docs, comments and commit messages in Spanish; commit subjects use
  conventional prefixes (`feat(fase1):`, `docs(rust):`, ...).
- One commit per coherent milestone; never leave parity tests red.
- Code that cannot be verified on the laptop is marked "validar en el PC /
  en hardware" in code and READMEs — keep those markers accurate.

## Sync laptop ↔ PC

Via git (`github.com/Jcrex/PSVita-ROS.git`). `.claude/` stays local.
