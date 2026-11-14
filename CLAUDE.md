# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The PS Vita ↔ ROS2 project: turn a PS Vita 1000 into a real ROS2 Jazzy node
via micro-ROS (XRCE-DDS) over WiFi/UDP. The repo now contains **everything**:
docs, the dual Rust+C modules, the Godot 4 module and apps, the MCP server, the
Claude Code skills and the (paused) project website. Current state and exact next
steps live in `docs/06-bitacora-estado.md` — **read that first** when
resuming work, and **update it** when closing milestones; older sessions are in `docs/bitacora/`
(one file per month). Docs index: `docs/README.md`. Where things live and how they are archived:
`docs/adr/0014-organizacion-del-repositorio.md`. The latest full-repo
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
binary — the umbrella crate is `modules/paraguas-rust/`).

## Common commands

```bash
tools/run-parity-tests.sh [module]      # C+Rust parity on host (docker for Rust)
GH=toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64     # (PC)
godot/test/run_host_tests.sh "$GH"      # ros2_vita host tests (test/project/runner.gd)
"$GH" --headless --path godot/g1-sensores --script res://comun/pruebas/runner.gd   # plantillas tests
python3 tools/check-doc-links.py        # broken doc links / cited paths (--baseline f to diff)
cd mcp/ros2-introspection && .venv/bin/python -m pytest tests/ -q
cd web && pnpm dev                      # site dev server
cd web && docker compose up -d --build  # production site, localhost:4321
```

## Layout

- `modules/{mem-pool,net-udp,microros-transport,msg-ring,viz-math,msg-cdr,tf-tree,msg-schema}/` — dual modules (each has
  its own README with API/design/status). Platform split is *inside* each
  impl: `#ifdef __vita__` / `#[cfg(target_os = "vita")]`; the host branch
  exists so parity tests run on the laptop.
- `godot/` — Godot **4** (godot4-vita 4.8-dev7; ADR 0008, `docs/18`). Flat layout, grouped in `godot/README.md`
  (which also lists the 7 versioned symlinks: never rewrite them in bulk):

  | Group | Folders |
  |---|---|
  | Engine | `ros2_vita/` (in-tree static module, rclgd API), `loader-patches/` (loader imports), `vitasdk-stubs/` (`dlfcn.h` for the SDK), `test/` (host tests) |
  | Shared library | `plantillas/` (seen as `res://comun` in the projects; historical name); world `plantillas/mundo/mundo.tscn` |
  | Live apps | `g1-unitree/`, `g1-sensores/`, `rbkairos-plus/`, `dron-mapeo/` (+ `visor-ros/` in Fase V) |
  | Closed gates (regression + lessons) | `g4-smoke/`, `g5-xrce/`, `g6-hmi/`, `g7-imu/` (G7a IMU, G7c 3D on the Vita: no SubViewport), `g7b-imu3d/` |
  | External, not versioned | `rclgd/` (local rclgd clone, jazzy, Godot 4.7.1) |

  Tools (PC only): `tools/build-godot-template.sh` (recipe; needs `toolchains/vitagl-src`, `tools/build-pcre2-vita.sh`
  and the XRCE client in `toolchains/xrce/` from `tools/build-xrce-client-vita.sh`), `tools/export-vita-vpk.sh`,
  `tools/deploy-vpk-ftp.sh`, `tools/vita-doctor.sh`, `tools/check-vita-imports.py` / `build-rust-pic.sh` /
  `build-c-pic.sh` (G2), `tools/urdf2godot/`; `tools/hwprobe/` is a hardware probe (not compiled; docs/14 §9).
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
- `docs/` — index `docs/README.md` (numbers never renumbered); `docs/bitacora/` (old sessions); `docs/adr/`
  (0001–0014); `docs/ia/{tutorial,medidas,workshops,auditoria,organizacion}/` (AI working material).
- `archivo/` — archived (obsolete or superseded) material, keeping its original path inside: the Fase 1 homebrew
  `archivo/vita-app/` (rebuild steps in `archivo/README.md`), Godot 3.5 `archivo/godot/godot35/`, superseded docs
  `archivo/docs/` (10, 11, 16, 19, 20, 21, …). See `archivo/README.md`; pending lots in `docs/ia/auditoria/README.md`.
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

## Working method: autonomous research + implementation (since 2026-11-11, user decision)

**Learning mode is PAUSED** (it was active 2026-10-31 → 2026-11-11; method kept in
`docs/tutorial/07-ruta-completa-de-aprendizaje.md` for when it resumes). The user's learning is slower than
the research, so: **keep researching and implementing autonomously**, run the commands yourself (docker,
`ros2`, builds, exports), and only stop for irreversible decisions or contradictions with an accepted ADR.
When the user explicitly asks to learn something, generate the guide/lesson then.

- **Reports: long only.** Write the full technical docs (`docs/24+`, `docs/ia/`, ADRs). Do NOT write the
  short ≤ 500-word versions in `docs/informes/` unless the user asks for one.
- Research stage 2026-11 ("estación robótica", LT1–LT8): multi-agent workshops, board and logs in
  `docs/ia/workshops/` (method in its README).
- Cite `file:line` or official docs for every claim; mark guesses as hypotheses ([V]/[I]/[?]).
- Hardware tests still need the user (the Vita is in their hands): give exact commands and the green criterion.
- **Shells:** the user runs **fish** on the PC CachyOS (this machine) and **zsh** elsewhere. Commands
  given to the user for the PC must be fish-valid (`set VAR valor`, not `VAR=valor` alone; no
  `export`, `$(...)` → `(...)`); for the laptop, zsh. Scripts with a shebang (`tools/*.sh`) are fine.

## Conventions

- Archiving and moving files: rules of ADR 0014 (`docs/adr/0014-organizacion-del-repositorio.md`).
- Docs, comments and commit messages in Spanish; commit subjects use
  conventional prefixes (`feat(fase1):`, `docs(rust):`, ...).
- One commit per coherent milestone; never leave parity tests red.
- Code that cannot be verified on the laptop is marked "validar en el PC /
  en hardware" in code and READMEs — keep those markers accurate.
- **Godot scenes rule (user decision, 2026-11-13; `docs/35-regla-escenas-editables.md`):** what is seen and where
  (world, props, collisions, light, environment, robot spawn) lives in an editable `.tscn`, never built from JSON
  in code. Code only adapts the scene to the platform (PC/Vita mesh choice, merging, culling) and creates runtime
  things (robot physics, sensors, camera, HUD). Never save meshes the Vita must not load: store the path and show
  an editor-only preview (child without `owner`). JSON is only for non-placement config (ROS, sensors, control).
  The template world `godot/plantillas/mundo/mundo.tscn` is shared by all template projects. Generated scenes
  (e.g. `g1-unitree/casa/casa.tscn` from `docker/g1/casa.json`) are edited at their source.

## Sync laptop ↔ PC

Via git (`github.com/Jcrex/PSVita-ROS.git`). `.claude/` stays local.
