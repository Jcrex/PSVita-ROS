---
title: "DB-TSDF en la PS Vita: ¿se puede?"
description: "Viabilidad de llevar el mapeo LiDAR DB-TSDF (UPO) a la Vita: presupuesto, arquitecturas y etapas."
fecha: 2026-11-01
---

# DB-TSDF en la PS Vita: ¿se puede?

DB-TSDF hace un mapa 3D de vóxeles con un LiDAR y solo usa CPU. Cada punto actualiza un cubo
de K³ vóxeles con un AND de máscaras (`tsdf3d_16.hpp:230-246`). No lanza rayos, así que el coste es
**puntos × K³**. Licencia MIT. Detalle: `docs/ia/auditoria/04b-dbtsdf-viabilidad-vita.md`.

## Cifras (hipótesis, sin medir)

| Recurso | Paper/repo | Vita |
|---|---|---|
| CPU | i7 de 16 hilos: 155 ms por scan de 65 k puntos | unas 150× más lenta |
| Memoria | ~2,4 GB | ~64 MB para el mapa |
| Red | VLP-16 en crudo: 480 KB por scan | `ros2_vita` acepta ≤ 16 KB por mensaje (MTU 512) |

En la Vita: 3 000 puntos reducidos con K=5 cuestan 10–50 ms. Un LaserScan del TurtleBot3, unos 3 ms.

## Arquitecturas

| | La Vita… | CPU | Red | Veredicto |
|---|---|---|---|---|
| **A** | mapea todo | ✗ (segundos) | ✗ | descartada |
| **B** | solo dibuja el mapa del PC | ~0 | poca | primer escalón |
| **C** | integra una nube reducida en un volumen local | 10–50 ms | 0,5–3 Mbps | **objetivo** |

**Recomendación:** empezar por B y luego pasar a C, primero en **2D con el LaserScan** del TurtleBot3.
El PC reduce la nube, la pasa a `odom` y la manda en trozos de ≤ 490 B (*best effort*).
La vista será cenital 2D, porque el 3D de Godot en la Vita es experimental (docs/18:51).

## Etapas

| Puerta | Dónde | Prueba |
|---|---|---|
| T0 | docker | Original como **oráculo** (1 hilo) |
| T1 | host | Medir el original con K=5/7/21: el paper dice 21 y el repo usa 5–7 |
| T2 | laptop | `modules/tsdf-local` dual C+Rust, con paridad y comparado con el oráculo |
| **T3** | **Vita** | **Microbenchmark: ms por scan con 1–3 hilos a 333/444 MHz.** Decide si seguir con C |
| T4–T5 | PC + Vita | Nodo troceador; contar trozos perdidos |
| T6 | Vita | Arquitectura B |
| T7–T8 | Vita | C en 2D, después en 2,5D/3D con un hilo propio de mapeo |

## Aprender antes

Hay que entender PointCloud2 frente a LaserScan, qué es un TSDF, las máscaras de bits y `popcount`,
el búfer circular de `grid_16.hpp`, los ciclos y las cachés, la fragmentación XRCE y las carreras entre hilos.

## Comprueba que lo has entendido

1. ¿Por qué el coste depende de los puntos y de K, pero no de la resolución?
2. ¿Por qué se mandan trozos *best effort* y no un mensaje fiable grande?
3. A 0,10 m, ¿cuántos bytes ocupa una celda de 1 m³? (Cada vóxel ocupa 4 B.)
