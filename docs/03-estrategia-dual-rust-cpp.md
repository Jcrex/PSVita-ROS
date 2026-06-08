# Estrategia dual Rust + C/C++ con contrato C-ABI

**Fecha de creación:** 2026-06-08
**Estado:** Fundación aprobada

---

## El principio: el header C es la verdad

La regla central de la estrategia dual es simple y no tiene excepciones: **el header C (`.h`) es la verdad de cada módulo.** El header define la interfaz pública completa: las funciones que el módulo expone, los structs que maneja, los códigos de error que devuelve, y las constantes que el usuario necesita.

Nada de lo que no está en el header es parte del contrato. La implementación C/C++ puede usar clases, templates o cualquier construcción de C++; la implementación Rust puede usar traits, iteradores y unsafe blocks; lo que importa es que ambas cumplen el contrato del header y solo el header.

Esta disciplina tiene una consecuencia muy concreta: toda la app homebrew de la Vita y el cliente micro-ROS interactúan únicamente a través del header C. No importa si detrás hay C, C++ o Rust. El linker ve el mismo símbolo con el mismo tipo de retorno y los mismos parámetros en todos los casos.

---

## Dos implementaciones bajo un mismo contrato

Cada módulo dual tiene exactamente dos implementaciones, ambas obligadas a ser funcionales y equivalentes en todo momento:

### `impl-c/`: C/C++ sobre VitaSDK

La implementación C/C++ usa el toolchain VitaSDK directamente: puede llamar a `sceNet`, usar tipos de VitaSDK, y aprovechar cualquier característica de la plataforma. Es la implementación primaria en cuanto a garantía de funcionamiento: si Rust falla en algún aspecto del entorno de la Vita, C/C++ es el fallback que no puede fallar.

**C/C++ no es el segundo idioma: es el respaldo permanente.** No hay ningún escenario en el que C/C++ quede obsoleto o se permita que quede desactualizado respecto a Rust. Si la implementación Rust evoluciona, la C/C++ debe evolucionar con ella.

### `impl-rust/`: Rust con `#[no_mangle] extern "C"`, compilado a `staticlib`

La implementación Rust declara todas sus funciones públicas con `#[no_mangle]` y `extern "C"` para que el linker las vea con los mismos nombres que el header C declara. Se compila como `staticlib` (en `Cargo.toml`: `crate-type = ["staticlib"]`), lo que produce un archivo `.a` que CMake enlaza igual que cualquier otra biblioteca estática.

El target de compilación es `armv7-sony-vita-newlibeabihf`, el target de Rust para la PS Vita (Tier 3, requiere nightly y `-Z build-std`). Dado que la Vita usa newlib y no la librería estándar de Rust para sistemas con OS, la implementación Rust puede necesitar `#![no_std]` en algunas partes o configurar cuidadosamente qué partes de `std` son accesibles vía el runtime de newlib. Estos detalles se documentan en el ADR correspondiente y en los propios módulos.

---

## Selección en build time

La elección de implementación ocurre en tiempo de compilación mediante la variable CMake **`-DVITA_IMPL=c`** o **`-DVITA_IMPL=rust`**. El `CMakeLists.txt` de cada módulo interpreta esta variable y enlaza la biblioteca estática correcta.

```cmake
# Fragmento ilustrativo de CMakeLists.txt de un módulo dual
if(VITA_IMPL STREQUAL "rust")
    # Compilar impl-rust/ con cargo-vita y enlazar el .a resultante
    add_custom_command(...)
    target_link_libraries(${MODULE_NAME} PRIVATE vita_impl_rust)
else()
    # Por defecto: C/C++
    target_sources(${MODULE_NAME} PRIVATE impl-c/net_udp.c)
endif()
```

No hay selección en tiempo de ejecución. El binario final de la Vita lleva una sola implementación enlazada estáticamente. Si se quiere comparar el comportamiento de ambas implementaciones en la plataforma real, se generan dos `.vpk` distintos con sendas invocaciones de CMake, uno con `-DVITA_IMPL=c` y otro con `-DVITA_IMPL=rust`.

---

## Tests de paridad

Los tests de paridad son el mecanismo que garantiza que C/C++ y Rust son siempre equivalentes y que el respaldo funciona. La regla es:

- Cada módulo dual tiene un conjunto de tests en `tests/parity_test.c` (u otro nombre equivalente).
- La **misma batería de tests** se compila y ejecuta **dos veces**: una contra la implementación C/C++ y otra contra la implementación Rust.
- Si el resultado de una prueba difiere entre implementaciones, eso es un **fallo** que debe corregirse antes de continuar.
- Una divergencia no resuelta significa que el respaldo C/C++ ya no es equivalente, lo que viola la restricción transversal más importante del proyecto.

Los tests de paridad no son tests unitarios normales. No solo verifican que el código es correcto; verifican que ambas implementaciones son intercambiables. Incluyen casos de borde: buffers nulos, tamaños cero, errores de red simulados, timeout en recepción.

La skill `vita-dual-module` genera el scaffold de los tests de paridad junto con el resto del módulo, para que ningún módulo dual quede sin ellos desde el primer momento.

---

## Estructura por módulo

Cada módulo dual sigue esta estructura de directorios y archivos, sin excepción:

```
modules/net-udp/
├── include/net_udp.h        # contrato C-ABI (la verdad)
├── impl-c/net_udp.c
├── impl-rust/src/lib.rs      # extern "C", staticlib
├── tests/parity_test.c       # corre contra ambas
└── CMakeLists.txt            # -DVITA_IMPL selecciona
```

El directorio `include/` contiene el header y solo el header. Nada de implementación en los headers. `impl-c/` y `impl-rust/` son independientes entre sí: cada una compila sola sin incluir nada de la otra. `tests/` no incluye ninguna implementación directamente; se enlaza contra la lib que CMake selecciona según `VITA_IMPL`.

Esta estructura es también lo que genera la skill `vita-dual-module` de forma automática. Si se necesita añadir un módulo dual nuevo, la skill es el punto de entrada correcto para asegurar que se cumple el scaffold completo.

---

## Módulos duales candidatos en la Fase 1

Los tres módulos duales que deben existir antes de que la Fase 1 pueda completarse son:

**`net-udp`**: Encapsula la inicialización del stack de red de la Vita (`sceNetPoolCreate`, `sceNetInit`, `sceNetCtlInit`), la creación y configuración de sockets UDP sobre `sceNet`, y las operaciones de envío y recepción. Es la capa de red más baja del proyecto. Sin este módulo no hay comunicación con el agente.

**`microros-transport`**: Implementa los 4 callbacks del transporte personalizado de micro-ROS (`open`, `close`, `write`, `read`) usando `net-udp` como capa inferior. Este módulo es el adaptador entre el cliente XRCE-DDS y el stack de red de la plataforma. Es el núcleo de la incógnita dura de la Fase 1.

**`mem-pool`**: Proporciona un asignador de memoria con pools de tamaño fijo que micro-ROS usa para sus asignaciones internas. Evita la fragmentación del heap y los fallos tardíos de `malloc` en sesiones largas. Es especialmente importante si la app va a correr indefinidamente (como haría un nodo de control de robot).

### Qué no necesita ser dual al inicio

La lógica de alto nivel y la interfaz de usuario no son módulos duales al inicio del proyecto. La lógica que lee los controles (sticks, botones, táctil), renderiza en pantalla con `vita2d`/`vitaGL`, o gestiona el ciclo de vida de la app puede estar escrita enteramente en C/C++ sin una implementación Rust paralela. La regla dual aplica a lo que toca hardware de bajo nivel, memoria de sistema y el sistema embebido en sí, no a toda la base de código.

Esta aclaración es importante para no sobredimensionar el esfuerzo inicial. En la Fase 1, la estrategia dual se aplica con precisión quirúrgica a los tres módulos que importan: red, transporte y memoria.
