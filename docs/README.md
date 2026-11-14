# docs/ — índice de la documentación

**Para retomar: [`06-bitacora-estado.md`](06-bitacora-estado.md)** — el primer bloque es el estado vivo y el siguiente
paso exacto; las sesiones antiguas están en [`bitacora/`](bitacora/README.md). Decisiones: [`adr/`](adr/). Material de
trabajo de la IA: [`ia/`](ia/README.md). Reglas de archivo y de dónde vive cada cosa: [ADR 0014](adr/0014-organizacion-del-repositorio.md).

Los números **no se renumeran**: un doc archivado deja un hueco en la tabla principal y pasa a «Archivados» (abajo);
las menciones abreviadas («doc 10», `docs/19 §3`) se resuelven aquí.

Estados: **Vigente** (se usa hoy) · **En pausa** (pausado por decisión del usuario) · **Histórico** (cerrado, aún
citado como fuente técnica; lleva una línea de estado bajo el título) · **Superado** (decisión sustituida) ·
**Archivado** (movido a `archivo/docs/`, ADR 0014 §2).

## Documentos numerados

| Nº | Título | Estado | Superado por | Fecha |
|---|---|---|---|---|
| 00 | [Visión y objetivos](00-vision-y-objetivos.md) | Vigente (marco) | Producto actual: Godot 4 + `ros2_vita` (ADR 0008) | 2026-06-08 |
| 01 | [Hardware de la Vita y VitaSDK](01-hardware-y-plataforma.md) | Vigente | — | 2026-06-08 |
| 02 | [Arquitectura micro-ROS + UDP (Fase 1)](02-arquitectura-fase1-microros.md) | Vigente | — (incógnita cerrada en hardware, doc 13 §2) | 2026-06-08 |
| 03 | [Estrategia dual Rust + C/C++](03-estrategia-dual-rust-cpp.md) | Vigente | — | 2026-06-08 |
| 04 | [Portabilidad de rviz2](04-investigacion-portabilidad-rviz2.md) | Histórico | Conclusión válida (rviz2 no portable); su Plan B, por ADR 0008 §5 y ADR 0013 | 2026-07-10 |
| 05 | [Setup del entorno en CachyOS](05-setup-entorno-cachyos.md) | Vigente | — | 2026-06-10 |
| 06 | [Bitácora de estado](06-bitacora-estado.md) | Vigente (vivo; tope 300 líneas) | Sesiones antiguas: [`bitacora/`](bitacora/README.md) | 2026-11-13 |
| 07 | [Requisitos: la web como IDE](07-requisitos-web-ide.md) | En pausa (con la web) | Web en pausa (usuario, 2026-11-01); su taller compila la app de la Fase 1 | 2026-07-06 |
| 08 | [Fase de desarrollo de la web](08-fase-desarrollo-web.md) | En pausa (con la web) | Web en pausa (usuario, 2026-11-01) | 2026-07-06 |
| 09 | [Objetivo 2: control de robot](09-objetivo2-control-robot.md) | Histórico | Cerrado en hardware; mapeo reutilizado en `godot/g6-hmi` | 2026-07-07 |
| 10 | — | Archivado | Ver «Archivados» | — |
| 11 | — | Archivado | Ver «Archivados» | — |
| 12 | [Investigación Godot + ROS 2 en la Vita](12-investigacion-godot-ros2-vita.md) | Histórico | Parte Godot 3.5: docs 17–18 y ADR 0008 | 2026-10-27 |
| 13 | [Infraestructura de desarrollo](13-infraestructura-desarrollo-vita.md) | Histórico | Tabla de objetivos: docs 18 y 33 | 2026-10-27 |
| 14 | [Hardware: memoria, hilos, CPU/GPU](14-hardware-vita-memoria-hilos-optimizacion.md) | Vigente | — | 2026-10-27 |
| 15 | [Rust nativo y optimización](15-rust-nativo-y-optimizacion-vita.md) | Vigente | — | 2026-10-27 |
| 16 | — | Archivado | Ver «Archivados» | — |
| 17 | [rclgd: estado del arte](17-rclgd-estado-del-arte-godot-ros2.md) | Vigente | — | 2026-10-27 |
| 18 | [Migración a Godot 4](18-migracion-a-godot4.md) | Vigente | — | 2026-10-27 |
| 19 | — | Archivado | Ver «Archivados» | — |
| 20 | — | Archivado | Ver «Archivados» | — |
| 21 | — | Archivado | Ver «Archivados» | — |
| 22 | [Acceso remoto al PC](22-acceso-remoto-pc.md) | Vigente (sin aplicar) | — | 2026-10-29 |
| 23 | [Guía de pruebas del stack](23-guia-pruebas-stack.md) | Vigente | — | 2026-10-29 |
| 24 | [Portabilidad Ozuba (gdviz…)](24-portabilidad-ozuba.md) | Vigente | — | 2026-11-11 |
| 25 | [URDF en Godot](25-urdf-godot.md) | Vigente | — | 2026-11-11 |
| 26 | [DB-TSDF en la Vita](26-db-tsdf-vita.md) | Vigente (por medir) | — (con ADR 0010, supera a `ia/auditoria/04a`–`04b` e `informes/04a`–`04b`) | 2026-11-12 |
| 27 | [XRCE: límites y relay](27-xrce-limites-y-relay.md) | Vigente | — | 2026-11-11 |
| 28 | [Sensores y visión](28-sensores-y-vision-vita.md) | Vigente | — | 2026-11-11 |
| 29 | [Plantillas de robots y sensores](29-plantillas-robots-sensores.md) | Vigente | — | 2026-11-12 |
| 30 | [Rendimiento XRCE de las plantillas](30-rendimiento-xrce-plantillas.md) | Vigente (registro) | — | 2026-11-12 |
| 31 | [Render sin shaders](31-render-visualizacion-vita.md) | Vigente (por medir) | — | 2026-11-12 |
| 32 | [Acciones y puente en el PC](32-acciones-puente-pc.md) | Vigente | — | 2026-11-12 |
| 33 | [Estación robótica (maestro)](33-investigacion-estacion-robotica.md) | Vigente | — | 2026-11-12 |
| 34 | [Perfil Vita ligero](34-perfil-vita-ligero.md) | Vigente (en curso) | — | 2026-11-13 |
| 35 | [Regla de escenas editables](35-regla-escenas-editables.md) | Vigente (regla) | — | 2026-11-13 |
| 36 | [Visualizar topics en Godot](36-visualizacion-topics-godot.md) | Vigente (implementado en host; el código manda) | Arquitectura, relay, QoS, presupuesto, tareas V1–V15 (§0–§3, §5–§12); estado de gates §9.0 y de la implementación §13 | 2026-11-14 |
| 36a | [Catálogo de displays por tipo](36a-catalogo-displays.md) | Vigente (implementado en host; el código manda) | La §4 del doc 36 («doc 36 §4.x» = 36a); estado por tipo con la ruta real §4.0.1 | 2026-11-14 |
| 37 | [Guía: rclgd y el visor con interfaz gráfica en el PC](37-guia-rclgd-gui-pc.md) | Vigente (guía; verificada sin pantalla) | Contenedor jazzy con pantalla y GPU (`tools/rclgd-gui.sh`), demos de rclgd migradas, proyecto puente del visor, criterio de verde por display, problemas frecuentes y hallazgos (P1: `rclgd.init()` void) | 2026-11-15 |

## Decisiones (`adr/`)

| ADR | Título | Estado real | Superado por / alcance | Fecha |
|---|---|---|---|---|
| [0001](adr/0001-vitasdk-toolchain-base.md) | VitaSDK como toolchain base | Vigente | — | 2026-06-08 |
| [0002](adr/0002-microros-transporte-udp-propio.md) | micro-ROS con transporte UDP propio | Vigente | — | 2026-06-08 |
| [0003](adr/0003-rust-target-armv7-sony-vita.md) | Rust `armv7-sony-vita-newlibeabihf` | Vigente | — | 2026-06-08 |
| [0004](adr/0004-empaquetado-vpk-cmake.md) | `.vpk` con CMake | Aceptado, alcance reducido (2026-10-27) | Apps: export de Godot (ADR 0008); CMake solo `tools/hwprobe` y la app histórica | 2026-06-08 |
| [0005](adr/0005-ui-vita2d-excepcion-dual.md) | UI con vita2d | Superado | ADR 0007 → ADR 0008 | 2026-07-07 |
| [0006](adr/0006-decision-rviz2-vs-mini-rviz.md) | rviz2 descartado → mini-rviz | Aceptado a medias | rviz2 sigue descartado; Plan B (mini-rviz) superado por ADR 0008 §5 enm. y ADR 0013 | 2026-07-10 |
| [0007](adr/0007-convivencia-vita2d-vitagl.md) | Todo vitaGL | Superado | ADR 0008 §5 enm. (2026-11-11), ADR 0011 | 2026-07-10 |
| [0008](adr/0008-godot-via-modulo-estatico.md) | Godot 4 vía módulo estático | Vigente (enmendado 2026-11-11; G7a–G7c verdes) | — | 2026-10-27 |
| [0009](adr/0009-urdf-horneado-en-pc.md) | URDF horneado en el PC | Vigente | — | 2026-11-11 |
| [0010](adr/0010-db-tsdf-escalera-de-bits.md) | DB-TSDF, escalera de bits | Vigente (por medir) | — | 2026-11-12 |
| [0011](adr/0011-presupuesto-render-vita.md) | Presupuesto de render | Vigente (por medir) | — | 2026-11-12 |
| [0012](adr/0012-puente-pc-acciones-y-relay.md) | Puente en el PC | Vigente | — | 2026-11-12 |
| [0013](adr/0013-visualizacion-topics-godot.md) | Visor de topics en Godot | Vigente | — | 2026-11-13 |
| [0014](adr/0014-organizacion-del-repositorio.md) | Organización del repositorio | Aceptada (en ejecución, Fase O) | — | 2026-11-13 |

## Carpetas

| Carpeta | Para qué | Estado |
|---|---|---|
| [`guias-vita/`](guias-vita/README.md) | Instalar el homebrew en la consola | Vigente |
| [`rust/`](rust/) | Rust del repo explicado (00–05) | Vigente (00–02 por actualizar a 8 módulos) |
| [`tutorial/`](tutorial/00-guia-del-tutorial.md) | Lecciones cortas para el usuario (00, 01, 07–10) | Vigente (pausa: modo aprendizaje en pausa desde 2026-11-11) |
| [`bitacora/`](bitacora/README.md) | Sesiones antiguas de la bitácora, un fichero por mes | Registro |
| [`informes/`](informes/00-indice-auditoria.md) | Versiones cortas de la auditoría | 2026-11-01, congelado (`04a`–`04b` superados por doc 26 + ADR 0010) |
| [`ia/`](ia/README.md) | Material de la IA: `tutorial/` (guiones), `medidas/` (logs de hardware), `workshops/`, `auditoria/`, `revision-kimi/`, `organizacion/` | Mixto (ver su README) |

## Archivados

Movidos a `archivo/docs/` el 2026-11-13 (ADR 0014 §2) sin cambiar su contenido. Tabla completa de traslados:
[`../archivo/README.md`](../archivo/README.md).

| Nº | Ruta | Motivo |
|---|---|---|
| 10 | [`archivo/docs/10-plan-objetivos-3-4.md`](../archivo/docs/10-plan-objetivos-3-4.md) | Superado por ADR 0008 §5 (enm. 2026-11-11) y ADR 0013 / doc 36 |
| 11 | [`archivo/docs/11-diseno-mini-rviz.md`](../archivo/docs/11-diseno-mini-rviz.md) | Superado por ADR 0013 (visor propio en Godot) |
| 16 | [`archivo/docs/16-paginas-pendientes-de-leer.md`](../archivo/docs/16-paginas-pendientes-de-leer.md) | Superado: lista de lectura para Godot 3.5 (rclgd ya leído en doc 17) |
| 19 | [`archivo/docs/19-plan-multiagente-migracion-godot4.md`](../archivo/docs/19-plan-multiagente-migracion-godot4.md) | Plan ejecutado (G1–G7 verdes); método vigente en `ia/workshops/README.md` |
| 20 | [`archivo/docs/20-godot35-migracion-historico.md`](../archivo/docs/20-godot35-migracion-historico.md) | (Godot 3.5) Diseño de la migración; superado por ADR 0008 (Godot 4). Archivado con `archivo/godot/godot35/` |
| 21 | [`archivo/docs/21-godot35-plan-implementacion-historico.md`](../archivo/docs/21-godot35-plan-implementacion-historico.md) | (Godot 3.5) Plan de implementación; superado por ADR 0008. Archivado con `archivo/godot/godot35/` |
| — | [`archivo/docs/ia/guion-guia-tutorial-original.md`](../archivo/docs/ia/guion-guia-tutorial-original.md) | Superado por `tutorial/00` + `07` |
| — | [`archivo/docs/ia/prompt-siguiente-sesion.md`](../archivo/docs/ia/prompt-siguiente-sesion.md) | Prompt del 2026-11-13 ya consumido |
