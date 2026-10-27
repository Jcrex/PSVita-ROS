# 16 — Páginas que no se pudieron abrir (para leer en el PC)

**Fecha:** 2026-10-27 · Desde el entorno de la laptop/nube solo resuelven
**GitHub** (`github.com`, `raw.githubusercontent.com`) y el buscador; el resto
da `getaddrinfo ENOTFOUND`. Esta lista es lo que conviene abrir **desde el PC**
(con navegador normal) y, de cada una, **qué dato extraer** y **qué marcador
[?] cierra**. Al leerla, anotar el resultado en el documento indicado.

Leyenda de prioridad: **A** bloquea una decisión/implementación · **B** mejora
la precisión · **C** contexto.

> † = ruta **inferida** (no aparecía en ningún resultado ni enlace leído); si da
> 404, buscar el título en el sitio. Las demás URLs salieron de resultados reales.

## Godot (docs/12, ADR 0008)

| Pri | URL | Qué extraer | Cierra |
|---|---|---|---|
| A | https://forum.godotengine.org/t/create-export-template-for-ps-vita/122770 | pasos reales de la plantilla Vita 3.5, versión exacta, errores, límites de RAM | P2/P5, docs/12 §2 |
| A | https://docs.godotengine.org/en/3.5/development/cpp/custom_modules_in_cpp.html | señales (`ADD_SIGNAL`), hilos y `call_deferred`, **enlazar librerías estáticas externas** (SCsub `LIBS`/`LIBPATH`) | P10 |
| A | https://docs.godotengine.org/en/3.5/tutorials/performance/threads/index.html † | qué es seguro llamar desde un hilo que no es el principal | P10 (`RosNode`) |
| B | https://docs.godotengine.org/pt-br/4.x/engine_details/engine_api/custom_platform_ports.html | requisitos de un port de plataforma (solo para entender los ports existentes) | docs/12 §3 |
| B | https://docs.godotengine.org/en/stable/engine_details/architecture/index.html † | arquitectura interna del motor 4.x (servidores, renderer, módulos) | capa 4.x |
| B | https://wololo.net/2022/07/15/release-godot-game-engine-3-5-ported-to-ps-vita/ | anuncio del port 3.5: funciones, límites declarados | docs/12 §2 |
| A | https://rclgd.readthedocs.io/en/latest/concepts/architecture.html y `/classes/class_rclgd.html` | **nombres exactos de la API GDScript** (clases, métodos, señales, tipos de mensajes) | P1, ADR 0008 §API |
| B | https://rclgd.readthedocs.io/en/stable/tutorials/make_rclgd_pkg.html y `/tutorials/turtlesim_rclgd.html` | ejemplo completo para copiar la forma de uso | P1 |
| B | https://index.ros.org/p/rclgd/ | estado/versiones/mantenedores (el índice dice "UNMAINTAINED") | docs/12 §5 |
| C | https://github.com/godotengine/godot-docs (rama 3.5) → `development/cpp/` | alternativa en GitHub a los docs bloqueados (sí se puede abrir desde la nube con la ruta correcta; la probada dio 404) | P10 |

GitHub accesible pero **no leído por falta de ruta**: `SonicMastr/godot-vita`
(README solo mostró el de Godot; mirar la carpeta `platform/vita/`, los issues
abiertos y los workflows de Actions para ver la receta real de compilación);
`WolffsRoom/godot4-vita` → `BUILDING.md`, `GXM_BACKEND.md`, `INTEGRATED_WINDOWS.md`,
`platform/vita/vitagl/README.md` (los nombra el README pero no se abrieron).

## micro-ROS / XRCE (docs/12 §4, docs/13 §3)

| Pri | URL | Qué extraer | Cierra |
|---|---|---|---|
| A | https://micro.ros.org/docs/tutorials/advanced/microxrcedds_rmw_configuration/ | todos los parámetros de memoria/streams (aunque usamos el cliente XRCE directo, no el rmw) | E1 |
| A | https://micro-xrce-dds.docs.eprosima.com/ † (Read the Docs, manual del cliente) | **nombres reales** de creación por referencia/XML/binario, límites de MTU y streams | docs/13 §3 |
| B | https://micro.ros.org/docs/concepts/middleware/memo_prof | tablas de consumo de memoria | referencia |
| B | https://micro.ros.org/download/ROSCon2020-FrancescaFinocchiaro.pdf | cifras de perfilado (400 B/publisher, 8.7 kB/subscriber) | referencia |
| B | https://discourse.openrobotics.org/t/micro-ros-memory-profiling-is-out/16928 | metodología de perfilado | E1 |
| C | https://arxiv.org/abs/2309.07496 | estudio DDS/Zenoh en WiFi | ADR futuro zenoh |
| C | https://zenoh.io/blog/2022-06-09-zenoh-pico-above-and-beyond/ | cifras de zenoh-pico (autopublicadas) | ADR futuro |

## Hardware de la Vita (docs/14)

| Pri | URL | Qué extraer | Cierra |
|---|---|---|---|
| A | https://docs.vitasdk.org/group__SceThreadmgr.html † (y `kernel_2threadmgr_2thread_8h.html`) | constantes de prioridad y de máscara de afinidad, tamaño de stack por defecto, qué núcleos usa el usuario | E-H2 |
| A | https://docs.vitasdk.org/group__SceSysmemUser.html | semántica de `SceKernelAllocMemBlockOpt`, alineaciones mínimas por tipo | E-H3 |
| A | https://wiki.henkaku.xyz/vita/Hardware † (y rama `Memory`, `Kernel`, `SceKernelThreadMgr`) | mapa de memoria, núcleos disponibles, cachés | E-H2/E-H6 |
| B | https://playstationdev.wiki/psvitadevwiki/ † (portada y páginas de CPU/GPU/Memory) | detalle de hardware y de la GPU | docs/14 §2, §5 |
| B | https://docs.vitasdk.org/group__SceMotionUser.html y `group__SceCameraUser.html` | descripción oficial de motion/cámara | docs/13 §5 |
| B | https://developer.arm.com/documentation/ddi0388 † (Cortex-A9 TRM) | caché L1, NEON, orden de memoria, eventos de rendimiento | docs/14 §2 [A] |
| B | https://consolemods.org/wiki/Vita:PSVshell y https://www.tweaktown.com/news/47804/sony-underclocked-ps-vitas-cpu-frequency-444mhz/index.html | relojes 333/444/500, condiciones (WiFi) | E-H1 |
| C | https://docs.unity3d.com/kr/560/ScriptReference/PlayerSettings.PSVita-memoryExpansionMode.html | modos de expansión de memoria (+29/+77 MB) | docs/14 §3.1 |
| C | https://en.wikipedia.org/wiki/PlayStation_Vita | cifras generales | contexto |

GitHub para ampliar (sí accesible, solo faltó tiempo): `vitasdk/vita-headers`
(`psp2/kernel/cpu.h`, `psp2/kernel/modulemgr.h`), `vitasdk/vdpm`/`autobuilds`
(dónde viven `pvr_psp2` y `vita-rss-libdl`), `Rinnegatamante/vitaGL`
(`samples/*/Makefile` con las banderas de enlace), `Vita3K/Vita3K`
(`vita3k/kernel/src`, `vita3k/mem`: cómo modela hilos y memoria),
`xerpi/ds4vita` (issue sobre SceMotionDev no documentado).

## Rust en la Vita (docs/15)

| Pri | URL | Qué extraer | Cierra |
|---|---|---|---|
| B | https://doc.rust-lang.org/nightly/rustc/platform-support/armv7-sony-vita-newlibeabihf.html | (ya leído su `.md` en GitHub) comprobar si cambió | — |
| B | https://vita-rust.github.io/ † (libro "work in progress") | guía oficial del ecosistema | docs/15 |
| B | https://github.com/vita-rust/vitasdk-sys † y `.../examples` | cómo se generan los bindings, ejemplos con hilos y memblocks | docs/15 §6 |

## Buscador: resultados NO verificados con la fuente

Dato citado por el buscador sin abrir la página: lista de resolución de
`vitaShaRK`/`libshacccg` (vitaGL README, parcial), "Godot port no soporta nada
superior a 3.5" (foro), `-DUNIX_SOCKET_UNAVAILABLE` (sí verificado en
Swisha33), "tres de los cuatro núcleos para juegos" (GameFAQs, **no fiable**),
"CPU a 333 MHz por defecto / 444 con WiFi apagado" (TweakTown).

## Cómo usar esta lista

En el PC: abrir cada URL de prioridad A, copiar lo pedido a
`docs/12`/`13`/`14`/`15` quitando el marcador **[?]**, y marcar la fila aquí
con la fecha. Si una URL ya no existe, buscar el equivalente y anotarlo.
