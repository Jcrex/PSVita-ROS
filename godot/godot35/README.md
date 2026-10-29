# godot/godot35/ — la app teleop en Godot 3.5 (HISTÓRICO, validada en hardware)

> **Histórico (fusionado desde la rama `godot-migration` el 2026-10-29).** El proyecto se mudó a
> **Godot 4** (`godot4-vita`; ADR 0008, `docs/18`, módulo `../ros2_vita/`). Esta carpeta se conserva
> porque **funciona en la Vita** (G1–G3 de la rama 3.5: teleop publicando `/cmd_vel`) y es la
> referencia probada para la HMI piloto de Godot 4 (`docs/19` T6.1) y para las lecciones del `.vpk`.
> Antes vivía en la raíz de `godot/`; los scripts ya usan las rutas nuevas.

Subproyecto de la antigua rama `godot-migration` (diseño en
`docs/20-godot35-migracion-historico.md`, plan en `docs/21-godot35-plan-implementacion-historico.md`):
replica la app teleop nativa de `vita-app/` como proyecto Godot 3.5,
reutilizando **sin reescribir** los módulos duales C/Rust, el cliente
XRCE v2.4.3 y el glue de `vita-app/src/`.

## Piezas

| Ruta | Qué es |
|---|---|
| `project.godot` | Proyecto Godot 3.5 (GLES2, 940×544, preset de export "PlayStation Vita") |
| `modules/microros/` | Módulo C++ del engine: expone el singleton `MicroROS` a GDScript. Se compila **dentro** del fork godot-vita vía `custom_modules=<repo>/godot/godot35/modules` (en la Vita no hay GDNative) |
| `scenes/teleop/` | La escena teleop: UI de conexión, IPs editables persistentes, indicadores de `/cmd_vel`. Con stub para correr en el editor de la laptop sin hardware |
| `scripts/build-vita-template.sh` | (Solo PC) compila el export template custom con el módulo dentro y lo instala en `~/.local/share/godot/templates/3.5.rc5/`. Instala stubs y aplica patches (idempotente) antes de `scons` |
| `scripts/uninstall-godot.sh` | (Solo PC) revierte limpiamente todo lo que instaló el build (parches, stubs, paquetes vdpm, template, artefactos) dejando el VitaSDK como antes de Godot |
| `patches/` | Parches al fork godot-vita aplicados en el build (p.ej. excluir `clew.c` de Bullet: usa `dlopen`, ausente en la Vita). Cada `.patch` explica su porqué |
| `vitasdk-stubs/` | Cabeceras que el VitaSDK no trae pero código stock de Godot incluye (p.ej. `dlfcn.h`, con llamadas muertas en la Vita). El build las copia al SDK |

## Flujo de trabajo

- **Laptop:** editor Godot x11 (`~/Proyectos/Godot/godot_v3.5-rc5-vita.x11.64`)
  para escenas y GDScript. La escena corre en modo SIMULADO (stub).
- **PC (VitaSDK):** `source tools/env-devpc.fish`, luego
  `godot/godot35/scripts/build-vita-template.sh` una vez por cambio nativo; después,
  exportar el `.vpk` desde el editor y subirlo por FTP (guías en
  `docs/guias-vita/`). El template solo se recompila si cambia código
  C/C++/Rust. **Prerrequisitos del VitaSDK** (PVR_PSP2, códecs vdpm, patch
  clew, stub dlfcn) documentados en `docs/20-godot35-migracion-historico.md`
  §"Prerrequisitos del VitaSDK".
- **Desinstalar Godot 3.5** (cuando ya no se use): `godot/godot35/scripts/uninstall-godot.sh`.

## Estado

G1–G3 hechos (hardware). G4 (variante Rust del template 3.5) **no se hará**: la variante Rust
continúa en Godot 4 (`docs/19` T8.x). Bitácora: `docs/06-bitacora-estado.md`.
