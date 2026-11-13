# Borrador de `docs/README.md` (O1c, 2026-11-13)

> Borrador para el juez Fable / el usuario. Al aprobarlo se copia **desde la línea `# docs/`** a `docs/README.md`.
> Estados y evidencias: `docs/ia/organizacion/O1c-clasificacion-docs.md`. Los números **no se renumeran**; si un doc
> se archiva, la fila queda con la ruta `archivo/docs/…`.

---

# docs/ — índice de la documentación

**Empieza por [`06-bitacora-estado.md`](06-bitacora-estado.md)**: el primer bloque es el estado vivo y el siguiente
paso exacto. Decisiones: [`adr/`](adr/). Material de trabajo de la IA: [`ia/`](ia/README.md).

Estados: **Vigente** (se usa hoy) · **Vigente (pausa)** (pausado por decisión del usuario) · **Histórico** (cerrado,
útil como registro) · **Superado por X** (decisión sustituida; se conserva o se archiva en `archivo/docs/`).

## Documentos numerados

| Nº | Título | Estado | Superado por | Fecha |
|---|---|---|---|---|
| 00 | [Visión y objetivos](00-vision-y-objetivos.md) | Vigente | — | 2026-06-08 |
| 01 | [Hardware de la Vita y VitaSDK](01-hardware-y-plataforma.md) | Vigente | — | 2026-06-08 |
| 02 | [Arquitectura micro-ROS + UDP (Fase 1)](02-arquitectura-fase1-microros.md) | Vigente | — | 2026-06-08 |
| 03 | [Estrategia dual Rust + C/C++](03-estrategia-dual-rust-cpp.md) | Vigente | — | 2026-06-08 |
| 04 | [Portabilidad de rviz2](04-investigacion-portabilidad-rviz2.md) | Histórico | Conclusión válida (rviz2 no portable); su Plan B, por ADR 0008 §5 y ADR 0013 | 2026-07-10 |
| 05 | [Setup del entorno en CachyOS](05-setup-entorno-cachyos.md) | Vigente | — | 2026-06-10 |
| 06 | [Bitácora de estado](06-bitacora-estado.md) | Vigente (vivo) | — | 2026-11-13 |
| 07 | [Requisitos: la web como IDE](07-requisitos-web-ide.md) | Superado | Web en pausa (2026-11-01); su taller compila `vita-app` → ADR 0008 | 2026-07-06 |
| 08 | [Fase de desarrollo de la web](08-fase-desarrollo-web.md) | Superado (pausa) | Web en pausa (2026-11-01) | 2026-07-06 |
| 09 | [Objetivo 2: control de robot](09-objetivo2-control-robot.md) | Histórico | Cerrado en hardware; mapeo reutilizado en `godot/g6-hmi` | 2026-07-07 |
| 10 | [Plan Objetivos 3–4 (rviz2/mini-rviz)](10-plan-objetivos-3-4.md) | Superado | ADR 0008 §5 enm. (2026-11-11) y ADR 0013 / doc 36 | 2026-07-07 |
| 11 | [Diseño del mini-rviz y VBM](11-diseno-mini-rviz.md) | Superado | ADR 0013 / doc 36 (visor propio en Godot) | 2026-07-10 |
| 12 | [Investigación Godot + ROS 2 en la Vita](12-investigacion-godot-ros2-vita.md) | Histórico | Parte Godot 3.5: docs 17–18 y ADR 0008 | 2026-10-27 |
| 13 | [Infraestructura de desarrollo](13-infraestructura-desarrollo-vita.md) | Histórico | Tabla de objetivos: docs 18 y 33 | 2026-10-27 |
| 14 | [Hardware: memoria, hilos, CPU/GPU](14-hardware-vita-memoria-hilos-optimizacion.md) | Vigente | — | 2026-10-27 |
| 15 | [Rust nativo y optimización](15-rust-nativo-y-optimizacion-vita.md) | Vigente | — | 2026-10-27 |
| 16 | [Páginas pendientes de leer](16-paginas-pendientes-de-leer.md) | Superado | ADR 0008 (lista orientada a Godot 3.5; rclgd ya leído en 17) | 2026-10-27 |
| 17 | [rclgd: estado del arte](17-rclgd-estado-del-arte-godot-ros2.md) | Vigente | — | 2026-10-27 |
| 18 | [Migración a Godot 4](18-migracion-a-godot4.md) | Vigente | — | 2026-10-27 |
| 19 | [Plan multiagente de la migración](19-plan-multiagente-migracion-godot4.md) | Histórico | Ejecutado (G1–G7); método vigente en `ia/workshops/README.md` | 2026-10-27 |
| 20 | [(Godot 3.5) Diseño de la migración](20-godot35-migracion-historico.md) | Superado | ADR 0008 (Godot 4) | 2026-07-13 |
| 21 | [(Godot 3.5) Plan de implementación](21-godot35-plan-implementacion-historico.md) | Superado | ADR 0008 (Godot 4) | 2026-07-13 |
| 22 | [Acceso remoto al PC](22-acceso-remoto-pc.md) | Vigente (sin aplicar) | — | 2026-10-29 |
| 23 | [Guía de pruebas del stack](23-guia-pruebas-stack.md) | Vigente | — | 2026-10-29 |
| 24 | [Portabilidad Ozuba (gdviz…)](24-portabilidad-ozuba.md) | Vigente | — | 2026-11-11 |
| 25 | [URDF en Godot](25-urdf-godot.md) | Vigente | — | 2026-11-11 |
| 26 | [DB-TSDF en la Vita](26-db-tsdf-vita.md) | Vigente (por medir) | — (sustituye a `ia/auditoria/04a`–`04b`) | 2026-11-12 |
| 27 | [XRCE: límites y relay](27-xrce-limites-y-relay.md) | Vigente | — | 2026-11-11 |
| 28 | [Sensores y visión](28-sensores-y-vision-vita.md) | Vigente | — | 2026-11-11 |
| 29 | [Plantillas de robots y sensores](29-plantillas-robots-sensores.md) | Vigente | — | 2026-11-12 |
| 30 | [Rendimiento XRCE de las plantillas](30-rendimiento-xrce-plantillas.md) | Vigente (registro) | — | 2026-11-12 |
| 31 | [Render sin shaders](31-render-visualizacion-vita.md) | Vigente (por medir) | — | 2026-11-12 |
| 32 | [Acciones y puente en el PC](32-acciones-puente-pc.md) | Vigente | — | 2026-11-12 |
| 33 | [Estación robótica (maestro)](33-investigacion-estacion-robotica.md) | Vigente | — | 2026-11-12 |
| 34 | [Perfil Vita ligero](34-perfil-vita-ligero.md) | Vigente (en curso) | — | 2026-11-13 |
| 35 | [Regla de escenas editables](35-regla-escenas-editables.md) | Vigente (regla) | — | 2026-11-13 |
| 36 | [Visualizar topics en Godot](36-visualizacion-topics-godot.md) | Vigente (sin código) | — | 2026-11-13 |

## Decisiones (`adr/`)

| ADR | Título | Estado | Superado por | Fecha |
|---|---|---|---|---|
| [0001](adr/0001-vitasdk-toolchain-base.md) | VitaSDK como toolchain base | Vigente | — | 2026-06-08 |
| [0002](adr/0002-microros-transporte-udp-propio.md) | micro-ROS con transporte UDP propio | Vigente | — | 2026-06-08 |
| [0003](adr/0003-rust-target-armv7-sony-vita.md) | Rust `armv7-sony-vita-newlibeabihf` | Vigente | — | 2026-06-08 |
| [0004](adr/0004-empaquetado-vpk-cmake.md) | `.vpk` con CMake | Parcial | Apps: export de Godot (ADR 0008); CMake solo `vita-app`/`hwprobe` | 2026-06-08 |
| [0005](adr/0005-ui-vita2d-excepcion-dual.md) | UI con vita2d | Superado | ADR 0007 → ADR 0008 | 2026-07-07 |
| [0006](adr/0006-decision-rviz2-vs-mini-rviz.md) | rviz2 descartado → mini-rviz | Parcial | rviz2 sigue descartado; mini-rviz: ADR 0008 §5 enm. y ADR 0013 | 2026-07-10 |
| [0007](adr/0007-convivencia-vita2d-vitagl.md) | Todo vitaGL | Superado | ADR 0008 §5 enm. (2026-11-11), ADR 0011 | 2026-07-10 |
| [0008](adr/0008-godot-via-modulo-estatico.md) | Godot 4 vía módulo estático | Vigente (enmendado 2026-11-11) | — | 2026-10-27 |
| [0009](adr/0009-urdf-horneado-en-pc.md) | URDF horneado en el PC | Vigente | — | 2026-11-11 |
| [0010](adr/0010-db-tsdf-escalera-de-bits.md) | DB-TSDF, escalera de bits | Vigente (por medir) | — | 2026-11-12 |
| [0011](adr/0011-presupuesto-render-vita.md) | Presupuesto de render | Vigente (por medir) | — | 2026-11-12 |
| [0012](adr/0012-puente-pc-acciones-y-relay.md) | Puente en el PC | Vigente | — | 2026-11-12 |
| [0013](adr/0013-visualizacion-topics-godot.md) | Visor de topics en Godot | Vigente | — | 2026-11-13 |

## Carpetas

| Carpeta | Para qué | Estado |
|---|---|---|
| [`guias-vita/`](guias-vita/README.md) | Instalar el homebrew en la consola | Vigente |
| [`rust/`](rust/) | Rust del repo explicado (00–05) | Vigente (00–02 por actualizar a 8 módulos) |
| [`tutorial/`](tutorial/00-guia-del-tutorial.md) | Lecciones cortas para el usuario (00, 01, 07–10) | Vigente (pausa: modo aprendizaje en pausa desde 2026-11-11) |
| [`informes/`](informes/00-indice-auditoria.md) | Versiones cortas de la auditoría | Histórico (congelado 2026-11-01; `04a`–`04b` superados por 26) |
| [`ia/`](ia/README.md) | Material para Claude: auditoría, workshops, revisiones, guiones, planes | Mixto (ver su README) |

`archivo/docs/` guarda lo archivado con su ruta original (ver [`../archivo/README.md`](../archivo/README.md)).
