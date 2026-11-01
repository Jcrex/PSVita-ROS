---
name: vita-build-package
description: "Use when building a Vita homebrew and producing an installable .vpk — Godot 4 flow (tools/build-godot-template.sh + tools/export-vita-vpk.sh, editor 4.8-dev7) and the historical Fase 1 CMake+VitaSDK flow (-DVITA_IMPL=c|rust)."
---

## Cuándo usar esta skill

Cada vez que haya que compilar para la Vita y obtener un `.vpk` instalable. Hay dos flujos:

| Flujo | Estado | Qué produce |
|---|---|---|
| **Godot 4** (`ros2_vita` dentro del motor) | **Vivo** (G1–G6 verdes, G4–G6 en hardware) | `build/<proyecto>.vpk` |
| **Fase 1** (`vita-app/`, C + CMake) | Histórico (Objetivos 1–2) | `vita-app/build-*/vita-ros2-hello.vpk` |

Para desplegar y leer logs, después: skill `vita-deploy-logs`. Para Godot 4 en detalle: skill
`ros2-vita-godot` y `docs/18-migracion-a-godot4.md`.

---

## Precondición (los dos flujos)

1. **Solo en el PC de desarrollo** (CachyOS, `192.168.1.65`). En la laptop no hay toolchains.
2. Cargar el entorno del repo (todo vive en `toolchains/`, gitignorado):
   - fish (shell del usuario en el PC): `source tools/env-devpc.fish`
   - bash/zsh: `source tools/env-devpc.sh`
   Define `VITASDK=<repo>/toolchains/vitasdk`, `RUSTUP_HOME`, `CARGO_HOME` y el `PATH`.
3. Diagnóstico rápido del entorno: `tools/vita-doctor.sh`.

---

## Flujo Godot 4 (vivo)

### 1. Plantilla de exportación (una vez, o al cambiar `ros2_vita`/módulos)

```bash
tools/build-godot-template.sh --dry-run                       # ver los pasos sin ejecutar
VITAGL_ROOT=<repo>/toolchains/vitagl-src tools/build-godot-template.sh [salida]
```

- `VITAGL_ROOT` (obligatoria): VitaGL parcheado del port, con `libvitaGL.a` (docs/18 §4.5).
- Opcionales: `GODOT_VITA_REF` (por defecto `d1a5f29`), `GODOT_WORK` (por defecto
  `toolchains/godot4-vita`), `RUST_PIC_LIB` (staticlib Rust PIC de `tools/build-rust-pic.sh`;
  sin ella se compilan los `.c` de los módulos).
- Pasos: clona godot4-vita, aplica `godot/loader-patches/`, instala el stub `dlfcn.h` en el SDK,
  compila con SCons (`custom_modules=godot/ros2_vita`, ≈1–2 h), pasa `verify_runtime.py` y genera
  `<salida>/vita_release.zip` (por defecto `toolchains/godot4-vita/out/`).
- Requiere SCons (`python3 -m SCons`) y las libs XRCE PIC (`vita-app/scripts/build-xrce-client-vita.sh`
  con `XRCE_PIC=1`; sin ellas el módulo compila pero el transporte XRCE da `ERR_UNAVAILABLE`).

### 2. Exportar el proyecto a `.vpk`

```bash
tools/export-vita-vpk.sh <dir_proyecto> [salida.vpk]
# p. ej. tools/export-vita-vpk.sh godot/g6-hmi        -> build/g6-hmi.vpk
```

- Necesita el **editor de host 4.8-dev7** (`GODOT4_DEV7`, por defecto
  `toolchains/godot4-vita/engine/bin/godot.linuxbsd.editor.x86_64`); el exportador rechaza otra
  versión (el 4.7.1 de rclgd no vale para exportar).
- Otras variables: `VITA_TEMPLATE` (por defecto `toolchains/godot4-vita/out/vita_release.zip`),
  `PSVITA_ADDON`.
- El proyecto debe tener `project.godot` y `export_presets.cfg` con el preset `"PS Vita"`.
- Trabaja sobre una **copia** temporal (el 4.8-dev7 reescribe escenas). Log junto al `.vpk`:
  `build/<nombre>-export.log`. Al terminar imprime tamaño, sha256 y el contenido del `.vpk`.

---

## Flujo Fase 1 — CMake + VitaSDK (histórico)

App `vita-app/` (Objetivos 1–2). Se conserva como referencia; no es el flujo actual.

```bash
cd vita-app
./scripts/build-xrce-client-vita.sh                    # una vez: cliente micro-XRCE para la Vita
cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake \
      -DVITA_IMPL=c -B build-c
cmake --build build-c                                  # -> build-c/vita-ros2-hello.vpk
```

- `-DVITA_IMPL=c` (por defecto) o `rust`. En `rust`, CMake compila el crate paraguas
  `vita-app/rust-modules` con `cargo +nightly rustc --release --crate-type staticlib`
  (`-Zbuild-std`; el target `armv7-sony-vita-newlibeabihf` es tier 3 y no se instala con
  `rustup target add`).
- Otras opciones de caché: `AGENT_IP`, `NETLOG_IP`, `NETLOG_PORT` (por defecto la laptop
  `192.168.1.108:9999`).
- El empaquetado (`vita-elf-create → vita-make-fself → vita-mksfoex → vita-pack-vpk`) lo hacen las
  macros de `vita.cmake` (`vita_create_vpk`, ADR 0004); no hace falta invocarlo a mano.

### `cargo-vita`: no usado

El repo **no** usa `cargo vita build vpk`. Una app Rust completa con `cargo-vita` (modo B de
`docs/15` §2) es la tarea **T8.3, pendiente** (`docs/19`). Los módulos Rust se enlazan siempre como
staticlib explícita (regla de CLAUDE.md).

---

## Verificación del artefacto

```bash
ls -lh build/<proyecto>.vpk              # Godot 4
ls -lh vita-app/build-c/vita-ros2-hello.vpk  # Fase 1
```

Tamaño 0 o ausente = falló el empaquetado (ver el log de exportación o de CMake). Que el `.vpk`
exista no prueba que funcione: la verificación real es instalarlo y ejecutarlo (skill
`vita-deploy-logs`).

---

## Errores frecuentes

| Síntoma | Causa probable | Acción |
|---|---|---|
| `VITASDK no definido` / `arm-vita-eabi-gcc: not found` | Entorno sin cargar | `source tools/env-devpc.fish` (o `.sh`) |
| `export-vita-vpk.sh`: `hace falta 4.8.dev7` | Editor equivocado | Apuntar `GODOT4_DEV7` al editor 4.8-dev7 |
| `export-vita-vpk.sh`: `ERROR: falta …` | Falta plantilla, addon o preset | Ejecutar antes `build-godot-template.sh`; revisar `export_presets.cfg` |
| `verify_runtime.py`: `Imports missing` | Símbolo no resuelto por el loader | docs/18 §4.2; `tools/check-vita-imports.py` |
| `ros2_vita: SIN transporte XRCE` en el log de SCons | Faltan libs `xrce-vita-pic` | `XRCE_PIC=1 vita-app/scripts/build-xrce-client-vita.sh` |
| Fase 1, Rust: `can't find crate for 'std'` | Falta `-Zbuild-std` | Usar el `CMakeLists.txt` del repo, no `cargo build` a mano |
| `CMake Error: could not load cache` | `build*/` corrupto | Borrar el directorio de build y reconfigurar |
