# config.py — módulo estático de Godot 4 (godot4-vita 4.8-dev7).
# ¡SIN COMPILAR! Ver godot/README.md (puerta G1: compilar en el host del PC).


def can_build(env, platform):
    # "vita": la plataforma del port (platform/vita de godot4-vita).
    # "linuxbsd": solo para las pruebas de host (transporte loopback, sin Vita).
    return platform in ("vita", "linuxbsd")


def configure(env):
    pass
