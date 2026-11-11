# config.py — módulo estático de Godot 4 (godot4-vita 4.8-dev7).
# Compilado y probado en host (G1, 2026-10-29); para la Vita: compilado con verify_runtime.py PASS (G3, 2026-10-30) y validado en hardware (G4–G6, 2026-10-30). Ver godot/README.md.


def can_build(env, platform):
    # "vita": la plataforma del port (platform/vita de godot4-vita).
    # "linuxbsd": solo para las pruebas de host (transporte loopback, sin Vita).
    return platform in ("vita", "linuxbsd")


def configure(env):
    pass
