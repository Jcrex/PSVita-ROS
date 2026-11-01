---
title: "Informe 02b — Optimizar ros2_vita y las apps en la Vita"
description: "Dónde gasta memoria y CPU la capa ROS de Godot 4 en la Vita, qué mejorar primero y qué fallos hay."
fecha: 2026-11-01
---

# Informe 02b — Optimizar ros2_vita y las apps

**Resumen:** lo caro no es la red, sino **crear y tirar objetos** `RosMsg`: cada `/odom` crea ~43 y usa 11.
Todo va en el hilo principal, una vez por frame. Sin medir. Detalle: `docs/ia/auditoria/02b-optimizacion-ros2vita-apps.md`.

## Mejoras, por orden

| # | Qué | Impacto | Riesgo |
|---|---|---|---|
| 1 | Pintar `reliable_full` en el HUD de G6 | prueba el punto 2 | nulo |
| 2 | ¿El stream fiable se queda sin confirmar? | explicaría el «stream lleno» de G6 | — |
| 3 | Decodificar sin crear árboles por defecto (`ros_msg.cpp`) | alto | bajo |
| 4 | Guardar en caché los nombres de campo (`StringName`) | alto | bajo |
| 5 | Copiar arrays `float64` directamente, sin pasar a `Array` | medio | bajo |
| 6 | MTU 512 → 1400: `/odom` (720 B) cabe en un datagrama | medio | medio |
| 7 | Reutilizar el mensaje en GDScript y refrescar el HUD a 10 Hz | medio | nulo |
| 8 | Conectar con 3 reintentos (no 10) y salir sin esperar | menos congelaciones | bajo |
| 9 | Quitar 2 MiB de pools de red que no se usan | RAM | bajo |
| 10 | Detectar que el agente se cayó y reconectar | robustez | medio |

**Punto 2 (hipótesis):** el cliente XRCE solo envía HEARTBEAT («¿te llegó?») si pasan ≥ 100 ms entre dos
llamadas; nosotros llamamos cada 16–33 ms. Si el agente solo confirma tras un HEARTBEAT, `/cmd_vel` acaba
yendo siempre por *best effort*.

## Fallos encontrados

| Fallo | Gravedad |
|---|---|
| Si el agente se reinicia, la app sigue diciendo «conectado» | media |
| Sin agente: hasta 10 s congelada al conectar y 10 al salir | media |
| Dos mensajes *best effort* en el mismo frame: el segundo se pierde | baja |
| `rclgd.shutdown()` dentro de un timer puede colgar la app | baja |
| Un timer dispara como mucho una vez por frame: `hz:=50` a 30 fps da 30 Hz | aviso |

## Cómo medir

En el host, `ros2 topic hz /odom`; en la Vita, pintar `rclgd.get_transport_info()` y los µs de 1000
`deserialize` (`Time.get_ticks_usec()`).

## Reto

En `godot/g6-hmi/main.gd`, crea el `Twist` en `_ready()`, reutilízalo en `_publicar_cmd()` y pinta
`reliable_full`.

## Comprueba que lo has entendido

1. ¿Por qué no hace falta un `RosMsg` nuevo en cada `publish`? (pista: `ros_runtime.cpp:313`)
2. ¿Qué pasa con un mensaje de 720 B si la MTU es 512, y qué cambia con 1400?
3. ¿Por qué un timer de 50 Hz no llega a 50 Hz si el juego va a 30 fps?
