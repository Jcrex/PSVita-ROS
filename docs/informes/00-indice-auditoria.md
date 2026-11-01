---
title: Índice de la auditoría (2026-11-01)
description: Resumen de los 7 informes de la flota y las decisiones pendientes.
fecha: 2026-11-01
---

# Auditoría del proyecto — índice

Siete agentes revisaron el repo **sin tocar nada**. Cada informe corto está aquí; el largo, en
`docs/ia/auditoria/`.

| Informe | Idea principal |
|---|---|
| 01a Limpieza tools/infra | Ningún script muerto. 3 ficheros basura. `vita-app/` archivable tras sacar 3 piezas que Godot 4 usa |
| 01b Limpieza módulos/godot/docs | Archivar `docs/superpowers/`. Muchas docs con estados viejos. **`.godot/` de G7a sin ignorar** |
| 02a Optimización módulos | 3 bugs (uno confirmado con ASan). `vita-app` compila sin optimizar (-O0) |
| 02b Optimización ros2_vita | Demasiados objetos por mensaje. Sin reconexión si cae el agente |
| 03 Mapa de Rust | Rust en 9 crates, paridad 16/16. En la Vita, Rust solo se probó con `vita-app` |
| 04a DB-TSDF código | Máscara de bits + `AND`. Licencia MIT. Bloquean PCL, OpenMP y ROS 2 completo |
| 04b DB-TSDF en la Vita | Primero la Vita dibuja el mapa del PC; luego mapea en local con nube reducida |

## Qué decides tú

| Lote | Acción | Riesgo |
|---|---|---|
| 0 | Ignorar `godot/g7-imu/.godot/` antes del commit de G7a | ninguno |
| 1 | Borrar 5 ficheros basura | ninguno |
| 2 | Archivar `docs/superpowers/` en `archivo/` | bajo (3 enlaces de la web) |
| 2b | Archivar `vita-app/` y `godot35/` | medio (unas 20 rutas que cambiar) |
| 3 | Poner al día docs, skills y marcadores | ninguno |
| 4 | Arreglar 7 bugs | buenos **retos** para ti |
| 5 | Optimizaciones (-O0, MTU, caché) | medir antes y después |

## Dato corregido

La Vita va a **333 MHz con el WiFi encendido** (`docs/14:22`). A 444 MHz solo con el WiFi apagado.

## Comprueba que lo has entendido

1. ¿Por qué no se puede archivar `vita-app/` entero sin más?
2. ¿Qué pasaría si haces el commit de G7a sin ignorar `.godot/`?
3. ¿Por qué el primer paso con DB-TSDF es que el PC mapee y la Vita solo dibuje?
