---
name: vita-build-package
description: Use when building a Vita homebrew and producing an installable .vpk — drives CMake+VitaSDK (C/C++) or cargo-vita (Rust), selects the implementation, and runs the packaging chain.
---

## Cuándo usar esta skill

Invocar esta skill cada vez que se necesite compilar código de la Vita y obtener un `.vpk` instalable. Cubre tanto la ruta C/C++ con CMake+VitaSDK como la ruta Rust con `cargo-vita`. Incluye la verificación mínima del artefacto resultante.

---

## Precondición

Antes de ejecutar cualquier comando de build, verificar que:

1. **`VITASDK` está exportado** en el entorno del PC de desarrollo:
   ```bash
   echo $VITASDK
   # Debe mostrar la ruta al SDK, p. ej. /usr/local/vitasdk
   ```
   Si no está exportado, añadirlo al entorno:
   ```bash
   export VITASDK=/usr/local/vitasdk
   export PATH=$VITASDK/bin:$PATH
   ```
   Esta variable es necesaria tanto para la ruta CMake como para la ruta Rust (`cargo-vita` la usa internamente).

2. **El PC de desarrollo** (CachyOS, IP `192.168.1.65`) es donde se ejecutan todos los comandos. No ejecutar builds en la laptop-taller.

3. El directorio de trabajo es la raíz del módulo o del proyecto Vita (donde está el `CMakeLists.txt` o el `Cargo.toml` según la ruta elegida).

---

## Ruta C/C++ — CMake + VitaSDK

### Configurar el build

```bash
cmake \
  -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake \
  -DVITA_IMPL=<c|rust> \
  -B build
```

- `-DVITA_IMPL=c`: usa la implementación C/C++ (`impl-c/<nombre>.c`).
- `-DVITA_IMPL=rust`: usa el staticlib Rust generado por `cargo-vita`. Requiere que el staticlib ya esté compilado o que el `CMakeLists.txt` lo invoque como step de build.
- Si no se especifica `DVITA_IMPL`, el `CMakeLists.txt` del proyecto usa `c` como valor por defecto.

### Compilar

```bash
cmake --build build
```

### Cadena de empaquetado

El `CMakeLists.txt` del módulo encapsula toda la cadena de empaquetado en el target `<app>.vpk`. Los pasos que ejecuta internamente son:

```
vita-elf-create    → convierte el ELF genérico a ELF de Vita
vita-make-fself    → genera el self firmado (eboot.bin)
vita-mksfoex       → genera el SFO (metadatos de la app: título, ID, versión)
vita-pack-vpk      → empaqueta eboot.bin + SFO + assets en el .vpk final
```

No es necesario invocar estos comandos manualmente; son targets de CMake. Si se necesita inspeccionar un paso concreto, se puede invocar el target intermedio con `cmake --build build --target <target>`.

### Salida esperada

```
build/<app>.vpk
```

---

## Ruta Rust — cargo-vita

### Compilar y empaquetar en un solo comando

```bash
cargo vita build vpk --release
```

Esto:
1. Compila el crate para el target `armv7-sony-vita-newlibeabihf` (tier 3, nightly, `-Z build-std`).
2. Ejecuta internamente la misma cadena `vita-elf-create → vita-make-fself → vita-mksfoex → vita-pack-vpk`.
3. Produce el `.vpk` en `target/armv7-sony-vita-newlibeabihf/release/<nombre>.vpk` (o la ruta que configure el `Cargo.toml`).

Si el target no está instalado:
```bash
rustup target add armv7-sony-vita-newlibeabihf
```

Si se requiere compilar sin empaquetar (solo el binario ELF):
```bash
cargo vita build elf --release
```

### Salida esperada

```
target/armv7-sony-vita-newlibeabihf/release/<nombre>.vpk
```

---

## Verificación del artefacto

Una vez finalizado el build por cualquiera de las dos rutas, verificar que el `.vpk` existe y tiene tamaño mayor que cero:

```bash
# Ruta CMake
ls -lh build/<app>.vpk

# Ruta Rust
ls -lh target/armv7-sony-vita-newlibeabihf/release/<nombre>.vpk
```

Un `.vpk` con tamaño 0 indica que la cadena de empaquetado falló silenciosamente; revisar los logs de CMake o de `cargo-vita`.

**Importante:** la verificación real del `.vpk` es instalarlo y ejecutarlo en la consola. Que el archivo exista y tenga tamaño no garantiza que la app funcione. Para el ciclo completo de deploy y prueba en hardware, usar la skill `vita-deploy-logs`.

---

## Errores frecuentes

| Síntoma | Causa probable | Acción |
|---|---|---|
| `arm-vita-eabi-gcc: not found` | `VITASDK` no exportado o `PATH` incompleto | Exportar `VITASDK` y añadir `$VITASDK/bin` al `PATH` |
| `error: could not find toolchain for target` | Target Rust no instalado | `rustup target add armv7-sony-vita-newlibeabihf` |
| `.vpk` vacío o ausente | Fallo en `vita-pack-vpk` | Revisar que `vita-mksfoex` tiene un `param.sfo` válido y que el `eboot.bin` existe |
| `CMake Error: could not load cache` | Directorio `build/` corrupto | `rm -rf build/` y reconfigurar |
| Rust: `can't find crate for 'std'` | Falta `-Z build-std` | Verificar `.cargo/config.toml` con `build-std = ["std", "panic_abort"]` |
