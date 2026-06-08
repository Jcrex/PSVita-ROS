# ADR 0004: Empaquetado `.vpk` con CMake

- **Estado:** Aceptado
- **Fecha:** 2026-06-08

## Contexto

La PS Vita ejecuta homebrew en formato `.vpk` (Vita Package): un archivo ZIP renombrado que contiene el ejecutable firmado (`eboot.bin`), los metadatos del título (`param.sfo`) y los recursos de la aplicación (iconos, imágenes de inicio, assets). Producir un `.vpk` instalable desde el código fuente requiere una cadena de pasos obligatoria proporcionada por VitaSDK:

1. `vita-elf-create`: transforma el ELF de salida de GCC/Clang en un ELF en formato Vita con las relocaciones específicas de la plataforma.
2. `vita-make-fself`: empaqueta el ELF Vita en un `eboot.bin` firmado (FSELF, fake self-signed).
3. `vita-mksfoex`: genera el fichero `param.sfo` con los metadatos del título (nombre, ID, versión).
4. `vita-pack-vpk`: ensambla el `.vpk` final a partir del `eboot.bin`, el `param.sfo` y los recursos.

Además, el proyecto requiere seleccionar en tiempo de build cuál de las dos implementaciones de cada módulo dual se usa: la C/C++ (`-DVITA_IMPL=c`) o la Rust (`-DVITA_IMPL=rust`). Esta selección afecta tanto a la compilación de los módulos como al paso de enlazado del ejecutable final.

Se necesita un sistema de build que: (a) gestione la compilación cruzada hacia ARMv7 con VitaSDK, (b) encapsule la cadena de empaquetado sin que el desarrollador tenga que invocarla manualmente, (c) soporte la selección de implementación dual, y (d) integre los artefactos generados por `cargo-vita` (bibliotecas estáticas Rust) como dependencias del ejecutable C.

## Decisión

Se usa **CMake** como sistema de build único del proyecto, configurado mediante el fichero `vita.toolchain.cmake` incluido en VitaSDK. La cadena de empaquetado completa se encapsula en el `CMakeLists.txt` principal usando las macros de CMake proporcionadas por VitaSDK:

- `vita_create_self(TARGET STRIPPED)`: envuelve los pasos `vita-elf-create` y `vita-make-fself`.
- `vita_create_vpk(TARGET TITLEID EBOOT SFO ...)`: ensambla el `.vpk` invocando `vita-mksfoex` y `vita-pack-vpk` con los metadatos y recursos declarados en CMake.

La selección de implementación dual se controla con la variable de CMake `-DVITA_IMPL=c|rust`:

- `VITA_IMPL=c` enlaza el módulo desde `impl-c/` (compilado con `arm-vita-eabi-gcc`).
- `VITA_IMPL=rust` invoca `cargo-vita build` como paso de build externo de CMake (`ExternalProject` o `add_custom_command`) y enlaza la `staticlib` resultante.

El `CMakeLists.txt` de cada módulo dual encapsula esa lógica mediante una función helper que abstrae la selección al resto del árbol de build. El ejecutable principal y la capa de micro-ROS solo declaran dependencias sobre el nombre lógico del módulo, sin saber qué implementación se eligió.

## Consecuencias

**Positivas:**

- El build es **reproducible y declarativo**: un `cmake -DVITA_IMPL=c ..` seguido de `make` produce el `.vpk` completo desde cero sin pasos manuales intermedios. Esto es fundamental para integración continua y para que cualquier colaborador pueda construir el proyecto sin conocer los detalles de las herramientas VitaSDK.
- CMake + `vita.toolchain.cmake` es la combinación estándar documentada en VitaSDK y usada por la mayoría de proyectos homebrew serios. Existe abundante documentación y ejemplos.
- La integración de `cargo-vita` como `add_custom_command` de CMake permite que el paso de compilación Rust sea un ciudadano de primera clase en el grafo de dependencias: solo se recompila cuando cambian los fuentes Rust.
- La selección `-DVITA_IMPL=c|rust` hace trivial la comparación de artefactos entre implementaciones y facilita los tests de paridad automatizados.

**Negativas / restricciones:**

- El `CMakeLists.txt` principal acumula complejidad al tener que gestionar: cross-compile, la cadena de empaquetado Vita, la selección dual, y la invocación de `cargo-vita`. Requiere documentación interna explícita para que sea mantenible.
- CMake no conoce natively el sistema de módulos de Cargo. La integración entre ambos (`ExternalProject` o `add_custom_command`) rompe algunas garantías de reconstrucción incremental de CMake: cambios en dependencias transitivas de Cargo (crates del `Cargo.lock`) no siempre invalidan el target CMake automáticamente. Se mitiga fijando las versiones en `Cargo.lock` y documentando cuándo limpiar el directorio de build.
- El paso `vita_create_vpk` requiere que los recursos (icono, imagen de inicio) existan en el directorio de fuentes. El proyecto debe mantener assets de marcador de posición funcionales para que el build no falle en ausencia de recursos definitivos.

## Alternativas consideradas

**Makefiles escritos a mano:** La cadena de empaquetado VitaSDK puede invocarse directamente desde un Makefile. Muchos proyectos homebrew pequeños toman este camino. Sin embargo, para un proyecto con múltiples módulos, implementación dual, y necesidad de selección de implementación en build time, un Makefile manual escalaría mal: las reglas de dependencia entre targets se vuelven frágiles, la integración de `cargo-vita` requeriría lógica condicional ad hoc, y la reproducibilidad del build depende de que el desarrollador mantenga las dependencias actualizadas a mano. CMake proporciona todo esto de forma declarativa. Se descarta Makefile manual.

**Meson:** Meson tiene soporte de cross-compile mediante ficheros de configuración explícitos y es una alternativa moderna a CMake. Sin embargo, el ecosistema homebrew de la Vita y VitaSDK usan CMake como herramienta estándar: `vita.toolchain.cmake` y las macros `vita_create_self`/`vita_create_vpk` son artefactos CMake sin equivalente oficial en Meson. Portar esas macros a Meson supondría trabajo de mantenimiento adicional sin beneficio tangible. Se descarta Meson.

**SCons / Bazel:** Ambos sistemas de build son válidos en entornos de mayor escala, pero ninguno tiene integración documentada con VitaSDK y ambos requerirían reimplementar desde cero la lógica de cross-compile y empaquetado. El coste de adopción supera con creces el beneficio para un proyecto de este tamaño. Se descartan.
