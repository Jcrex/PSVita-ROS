---
title: "DB-TSDF: análisis del código"
description: "Qué hace DB-TSDF, de qué depende y cuánta memoria y CPU pide."
fecha: 2026-11-01
---

# DB-TSDF: análisis del código

Repo `robotics-upo/DB-TSDF` (commit `663c5a8`), paper arXiv:2509.20081.

## Qué es un TSDF (en 3 líneas)

1. El mundo se divide en cubitos (vóxeles) de, p. ej., 5 cm.
2. Cada vóxel guarda su distancia a la superficie más cercana, recortada a un máximo.
3. La superficie es donde esa distancia vale cero; de ahí se saca una malla 3D.

## Qué aporta «DB» (Directional Bitmask)

- La distancia es **el número de bits a 1** de una máscara de 16 bits (`grid_16.hpp:29`).
- Integrar un punto LiDAR = hacer `AND` con un kernel precalculado de K×K×K vóxeles (`tsdf3d_16.hpp:236-238`).
  La AND solo baja la distancia: un «mínimo» barato.
- Hay un kernel por **dirección** del rayo (60×60) que marca como ocupada la «sombra» tras el impacto.
- Coste por scan: puntos × K³, **no depende de la resolución**.

Entradas: `PointCloud2` + pose por TF. **No localiza**.
Salidas: `/cloud` y servicios que guardan ficheros (PCD, malla…).

## Vóxel y memoria

| Dato | Valor |
|---|---|
| Vóxel | 4 B (`d` 2 B, signo 1 B, hits 1 B; `grid_16.hpp:27-33`) |
| Celda | 1 m³ = 8 000 vóxeles a 5 cm = 32 KB |
| Preset college | 75 000 celdas ≈ **2,4 GB** |
| Preset mai | 50 000 celdas ≈ **1,6 GB** |
| Vita a 10 cm, 200 MB (hipótesis) | ~50 000 celdas |

Al llenarse, recicla la celda más vieja (`grid_16.hpp:197-205`).

## CPU

- Paper (versión 32 bits): ~150 ms/scan en un i7-13620H con 16 hilos.
- Versión 16 bits del repo: 20–40 ms/scan (`docs/index.html:277-287`).
- Sin SIMD explícito; casi todo es `float`.
- Vita (hipótesis): 5–10 k puntos y K=5 → ~10–40 ms. El cuello de botella será el **WiFi**.

## Dependencias

| Dependencia | Uso | ¿Bloquea en Vita? | Alternativa |
|---|---|---|---|
| ROS 2 Humble `rclcpp` | nodo | Sí | micro-ROS/XRCE (ya en el repo) |
| `tf2_ros` | pose | Sí | topic de pose + `modules/tf-tree` |
| PCL | tipo de punto, ficheros | Sí | `struct {x,y,z}` + `msg-cdr` |
| VTK | malla | Sí | hacerla en el PC |
| OpenMP | 16 hilos | Probable | 3 hilos de la Vita |
| Eigen | vectores | No | sirve tal cual |
| Boost, message_filters | nada | No | quitar |
| Flags `-mavx` | x86 | Sí | flags NEON |

## Licencia

**MIT**: se puede portar conservando el aviso de copyright.

## Comprueba que lo has entendido

1. ¿Por qué hacer `AND` con una máscara equivale a quedarse con la distancia mínima?
2. Si bajas la resolución de 5 cm a 10 cm, ¿cuánto ocupa cada celda de 1 m³ y por qué?
3. ¿Qué debe mandar el robot a la Vita además de la nube, y por qué?
