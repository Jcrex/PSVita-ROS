# godot/ — la app de la Vita en Godot

Subproyecto de la branch `godot-migration` (diseño en
`docs/12-migracion-godot.md`, plan en `docs/13-plan-implementacion-godot.md`):
replica la app teleop nativa de `vita-app/` como proyecto Godot 3.5,
reutilizando **sin reescribir** los módulos duales C/Rust, el cliente
XRCE v2.4.3 y el glue de `vita-app/src/`.

## Piezas

| Ruta | Qué es |
|---|---|
| `project.godot` | Proyecto Godot 3.5 (GLES2, 940×544, preset de export "PlayStation Vita") |
| `modules/microros/` | Módulo C++ del engine: expone el singleton `MicroROS` a GDScript. Se compila **dentro** del fork godot-vita vía `custom_modules=` (en la Vita no hay GDNative) |
| `scenes/teleop/` | La escena teleop: UI de conexión, IPs editables persistentes, indicadores de `/cmd_vel`. Con stub para correr en el editor de la laptop sin hardware |
| `scripts/build-vita-template.sh` | (Solo PC) compila el export template custom con el módulo dentro y lo instala en `~/.local/share/godot/templates/3.5.rc5/`. Instala stubs y aplica patches (idempotente) antes de `scons` |
| `scripts/uninstall-godot.sh` | (Solo PC) revierte limpiamente todo lo que instaló el build (parches, stubs, paquetes vdpm, template, artefactos) dejando el VitaSDK como antes de Godot |
| `patches/` | Parches al fork godot-vita aplicados en el build (p.ej. excluir `clew.c` de Bullet: usa `dlopen`, ausente en la Vita). Cada `.patch` explica su porqué |
| `vitasdk-stubs/` | Cabeceras que el VitaSDK no trae pero código stock de Godot incluye (p.ej. `dlfcn.h`, con llamadas muertas en la Vita). El build las copia al SDK |

## Flujo de trabajo

- **Laptop:** editor Godot x11 (`~/Proyectos/Godot/godot_v3.5-rc5-vita.x11.64`)
  para escenas y GDScript. La escena corre en modo SIMULADO (stub).
- **PC (VitaSDK):** `source tools/env-devpc.fish`, luego
  `scripts/build-vita-template.sh` una vez por cambio nativo; después,
  exportar el `.vpk` desde el editor y subirlo por FTP (guías en
  `docs/guias-vita/`). El template solo se recompila si cambia código
  C/C++/Rust. **Prerrequisitos del VitaSDK** (PVR_PSP2, códecs vdpm, patch
  clew, stub dlfcn) documentados en `docs/12-migracion-godot.md`
  §"Prerrequisitos del VitaSDK".
- **Desinstalar Godot** (cuando ya no se use): `scripts/uninstall-godot.sh`.

## Estado

Ver la bitácora (`docs/06-bitacora-estado.md`) y los hitos G1-G4 de
`docs/12-migracion-godot.md`.
