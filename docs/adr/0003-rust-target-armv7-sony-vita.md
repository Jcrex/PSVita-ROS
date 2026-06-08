# ADR 0003: Rust target `armv7-sony-vita-newlibeabihf`

- **Estado:** Aceptado
- **Fecha:** 2026-06-08

## Contexto

Uno de los objetivos transversales del proyecto es explorar los límites de Rust en sistemas embebidos propietarios, ejecutando el lenguaje en una plataforma (PS Vita) para la que no existe soporte oficial de primera clase. Esto no es solo un capricho técnico: la restricción de implementación dual Rust + C/C++ obliga a que todo módulo que toque hardware, memoria o sistema embebido tenga dos implementaciones equivalentes bajo un contrato C-ABI compartido. Sin soporte funcional de Rust en la Vita, esa restricción transversal quedaría incumplida.

El ecosistema Rust contempla plataformas de soporte reducido mediante los llamados **targets de nivel 3 (tier 3)**: targets para los que existe una definición de compilación pero que no reciben pruebas automatizadas ni garantías de que el compilador principal los soporte indefinidamente. El uso de tier 3 exige siempre compilador nightly y la flag `-Z build-std`, que reconstruye la biblioteca estándar (o `core`/`alloc`) desde fuentes para el target indicado.

El target específico de la PS Vita es `armv7-sony-vita-newlibeabihf`. Este target codifica exactamente las características de la plataforma: ARMv7 con FPU de hardware, ABI de punto flotante hard, y newlib como biblioteca de sistema (en lugar de glibc). Enlaza contra la newlib del sysroot de VitaSDK, por lo que es coherente con la decisión de toolchain del ADR 0001.

La herramienta `cargo-vita` es el envoltorio de Cargo que integra este target en el flujo de trabajo habitual: invoca `cargo build` con las flags correctas de nightly, llama a las herramientas de post-procesado de VitaSDK para convertir el ELF en un artefacto compatible con la Vita, y puede integrarse con CMake como paso de build externo.

## Decisión

Se adopta soporte Rust en la Vita usando el target de nivel 3 **`armv7-sony-vita-newlibeabihf`** con las siguientes condiciones:

- Se usa siempre **compilador nightly de Rust** y la flag `-Z build-std` para reconstruir `core`, `alloc` y las partes de `std` que sean portables al target.
- La herramienta de integración es **`cargo-vita`**, que encapsula la invocación correcta de nightly y el post-procesado del artefacto.
- Las implementaciones Rust de módulos duales usan `#[no_mangle] extern "C"` para exportar funciones con ABI C, y se compilan como `crate-type = ["staticlib"]`. Esto garantiza que el linker de CMake puede enlazar la biblioteca Rust como si fuera una librería estática C convencional.
- La variable de entorno `VITASDK` debe estar exportada para que `cargo-vita` localice el sysroot de newlib de VitaSDK al compilar.
- **C/C++ es el respaldo permanente**: si un módulo no compila correctamente con el target Rust (por limitaciones del tier 3, bugs de nightly, o dependencias incompatibles con newlib), la implementación C equivalente se activa mediante `-DVITA_IMPL=c` sin necesidad de cambios en el código del módulo ni en la lógica de micro-ROS.

## Consecuencias

**Positivas:**

- Se cumple la restricción transversal de implementación dual: cada módulo de bajo nivel tiene una implementación Rust y una C/C++, intercambiables en build time.
- Rust aporta garantías de seguridad de memoria en tiempo de compilación (sin uso after-free, sin data races en código safe) en un dominio —embebido con gestión manual de memoria— donde esos errores son especialmente costosos de depurar.
- El modelo de tipos de Rust facilita expresar invariantes del protocolo XRCE-DDS (estados de sesión, rangos de IDs, ciclo de vida de streams) de forma que el compilador los verifique.
- La comunidad que mantiene el target `armv7-sony-vita-newlibeabihf` y `cargo-vita` es la misma que mantiene VitaSDK, por lo que ambas herramientas evolucionan coordinadas.

**Negativas / restricciones:**

- El target es **tier 3**: no hay garantías de estabilidad a largo plazo. Un cambio en nightly puede romper la compilación del target hasta que el maintainer lo repare. Se asume esta inestabilidad como coste conocido y se mitiga con el respaldo C/C++.
- Se requiere **Rust nightly**. El canal nightly introduce compiladores con cambios no estabilizados que pueden alterar el comportamiento del código o de las optimizaciones. Para código de producción embebido esto implica fijar la versión de nightly en `rust-toolchain.toml` y actualizarla de forma controlada.
- Las crates de ecosistema que dependen de `std` completo o de características específicas de Linux/glibc (threading de OS, networking estándar, `std::fs`) no están disponibles directamente. El desarrollo Rust en este target requiere usar `no_std` o crates cuidadosamente seleccionadas compatibles con `core`/`alloc`.
- El overhead de build aumenta: reconstruir `core`/`alloc`/`std` con `-Z build-std` añade tiempo de compilación, especialmente en limpiezas completas. Se mitiga con cachés de compilación (`sccache`) en el PC de desarrollo.

## Alternativas consideradas

**Solo C/C++ (sin Rust):** La opción más conservadora. Eliminaría la dependencia de nightly, el target experimental y toda la complejidad de la integración `cargo-vita`. Sin embargo, descarta uno de los objetivos explícitos del proyecto: explorar los límites de Rust en embebido propietario. La restricción de implementación dual quedaría incumplida. Se descarta.

**Rust stable con target genérico `thumbv7em-none-eabihf`:** Este target sí está en tier 2 (con garantías de compilación) y es stable. Sin embargo, no enlaza contra la newlib de VitaSDK sino contra una ABI bare-metal sin biblioteca de sistema, lo que hace imposible llamar a las APIs `sceNet` y demás syscalls de la Vita desde Rust. No es aplicable al objetivo del proyecto.

**WebAssembly (WASM) como capa intermedia:** Algunas plataformas usan runtimes WASM embebidos para ejecutar código portable. La Vita no tiene un runtime WASM disponible que sea práctico, y añadirlo sumaría una capa de indirección con overhead de JIT o interpretación incompatible con los requisitos de rendimiento en tiempo real de los callbacks de micro-ROS. Se descarta.
