# config.py — ¡ESQUELETO SIN VERIFICAR! (validar en el PC con godot-vita 3.5)
# Godot llama a estas funciones al descubrir el módulo (API de Godot 3.x).


def can_build(env, platform):
    # Solo tiene sentido en la Vita: depende de sceNet y de las staticlibs
    # cross-compiladas del repo.
    return platform == "vita"


def configure(env):
    pass
