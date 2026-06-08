# ADR 0001: VitaSDK como toolchain base

- **Estado:** Aceptado
- **Fecha:** 2026-06-08

## Contexto

Desarrollar software homebrew para la PS Vita exige un toolchain de compilación cruzada que produzca binarios ARMv7 (Cortex-A9, 32 bits) compatibles con el sistema de ejecución de homebrew de la consola. La Vita no corre un kernel Linux estándar ni expone las ABI habituales de sistemas de escritorio, por lo que no es posible reutilizar toolchains genéricos de Linux embebido sin adaptación significativa.

El proyecto tiene dos requisitos entrelazados: (1) compilar código C/C++ que use las APIs nativas de la Vita (red, gráficos, entrada, sistema de archivos) y (2) enlazar librerías de terceros —en particular `microxrcedds_client` para micro-ROS— que se deben compilar desde fuentes para el mismo target. Ambos requisitos obligan a elegir desde el inicio un toolchain bien definido alrededor del cual construir todo el sistema de build.

El ecosistema de homebrew de la Vita dispone de una única solución de toolchain de código abierto madura: VitaSDK. Este SDK mantiene una cadena `arm-vita-eabi-gcc` basada en GCC, con bibliotecas de sistema basadas en **newlib** (en lugar de glibc), cabeceras y stubs que cubren las syscalls y APIs del firmware de la consola (SceNet, SceDisplay, SceCtrl, etc.), y una colección de herramientas auxiliares para el empaquetado del artefacto instalable (`.vpk`).

## Decisión

Se adopta **VitaSDK** como toolchain C/C++ único y canónico del proyecto. Concretamente:

- El compilador es `arm-vita-eabi-gcc` (parte de la distribución de VitaSDK).
- La biblioteca de sistema es **newlib**, tal como la proporciona VitaSDK; no se intenta sustituir por musl ni por una implementación parcial de glibc.
- Las cabeceras de sistema son las de VitaSDK, que exponen las APIs del firmware (`SceNet`, `SceKernel`, `SceDisplay`, etc.).
- La variable de entorno `VITASDK` debe apuntar al directorio de instalación del SDK; todas las herramientas de build (CMake, cargo-vita) leen esta variable para localizar el sysroot.
- CMake usa el fichero `vita.toolchain.cmake` incluido en VitaSDK para configurar el cross-compile de forma declarativa.

## Consecuencias

**Positivas:**

- VitaSDK es el estándar de facto del ecosistema homebrew de la Vita, con una comunidad activa, repositorio de paquetes (`vitasdk/packages`) y ejemplos numerosos. Adoptar la herramienta estándar minimiza la fricción para portar dependencias y resolver problemas.
- Las APIs del firmware (`sceNet`, `sceDisplay`, etc.) están directamente accesibles a través de las cabeceras incluidas en el SDK sin necesidad de ingeniería inversa adicional.
- El target Rust de nivel 3 `armv7-sony-vita-newlibeabihf` enlaza contra la newlib de VitaSDK, por lo que Rust y C/C++ comparten la misma biblioteca de sistema sin conflictos de ABI.

**Negativas / restricciones:**

- Se trabaja con **newlib**, no con glibc. Esto significa que librerías que asumen POSIX completo o extensiones de glibc (p. ej., ciertas partes de Boost, algunas implementaciones de `std::thread`) no compilan directamente y requieren adaptación o sustitución.
- `microxrcedds_client` y otras dependencias de micro-ROS deben compilarse desde sus fuentes con este toolchain; no existe un paquete binario precompilado para `arm-vita-eabi`. Este proceso requiere parches de configuración y es parte de la incógnita técnica dura de la Fase 1.
- Cualquier actualización del firmware de la Vita o del propio VitaSDK puede introducir cambios en las APIs o en el sysroot que obliguen a recompilar todo el árbol de dependencias.

## Alternativas consideradas

**SDK oficial de Sony:** Sony distribuyó un SDK oficial para desarrolladores licenciados de PS Vita. Está cerrado, no es accesible legalmente para proyectos homebrew, y su uso implicaría restricciones de distribución que son incompatibles con el objetivo de publicar el proyecto. Se descarta completamente.

**Toolchain ARM genérico (`arm-none-eabi` o `arm-linux-gnueabihf`):** Sería técnicamente posible construir binarios ARMv7 con un toolchain genérico, pero requeriría replicar a mano el sysroot de la Vita, todas las cabeceras de las APIs del firmware y la lógica de enlazado específica del formato ELF de la consola. VitaSDK ya resuelve exactamente ese problema; reinventarlo no aporta valor y aumentaría el riesgo de incompatibilidades.

**DevkitARM (devkitPro):** Orientado principalmente a Nintendo DS/3DS y consolas similares; no tiene soporte para las APIs específicas de la Vita ni para el formato `.vpk`. No es aplicable.
