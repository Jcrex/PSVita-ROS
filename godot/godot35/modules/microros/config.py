# config.py — el módulo solo existe en builds de Vita (docs/12): en la
# plataforma vita no hay GDNative y el código nativo va dentro del engine.
def can_build(env, platform):
    return platform == "vita"


def configure(env):
    pass
