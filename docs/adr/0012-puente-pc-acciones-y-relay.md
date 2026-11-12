# ADR 0012: Puente en el PC (`vita_relay` + módulos de mando y acciones) en vez de acciones nativas en la Vita

- **Estado:** Aceptado el 2026-11-12.
  - El relay de datos ya está implementado y probado en el PC: `docker/scripts/vita_relay.py`, pruebas de las
    funciones puras y minimapa del G1.
  - Los módulos de mando y acciones están por implementar.
  - Diseño de W2 (Opus) y W9 (Fable, cortado por límites de uso; integrado en el doc 32).
- **Fecha:** 2026-11-12

## Contexto

- **Límites de XRCE en la Vita (doc 27):** best effort ≤ 488 B por mensaje; fiable ≈ 7,5 KiB en recepción, y al
  enviar bloquea el hilo principal.
- **Grafo ROS sin traducir:** casi ningún mensaje de RViz, Nav2 o MoveIt cabe tal cual.
- **Huecos de `ros2_vita`:** no tiene servicios ni acciones. El cliente XRCE v2.4.3 sí trae requester/replier (W9).
- **Seguridad:** la teleop necesita hombre muerto aunque se caiga el WiFi, y eso no se puede garantizar desde la
  propia Vita.

## Decisión

1. **Datos (PC → Vita):** el nodo **`vita_relay`** en el PC republica el último valor a ritmo fijo, en best effort,
   en formatos compactos de ≤ 488 B. Formatos actuales: scan, pose2d, juntas, mapa por teselas de 32×32 a 2 bit y
   path con Douglas-Peucker.
   - Cada salida comprueba su tamaño (`_pub`) y el nodo publica su ancho de banda en `/vita/relay_bw`.
   - Patrón validado: `/g1/estado`.
2. **Mando y acciones, en tres niveles:**
   - **Nivel 0:** solo topics cuando el ecosistema ya los ofrece (`/goal_pose`, status y feedback, `~/status` de
     Servo, `/fmu/out/*`).
   - **Nivel 1 (la decisión):** puente con el protocolo **VAB/1**. Órdenes idempotentes con acuse y estado
     replicado, todo con tipos estándar. Módulos `mando`, `accion_nav`, `accion_brazo`, `accion_dron` y `srv`
     (lista blanca). Corre en una **segunda instancia** del proceso (`vita-ros.sh puente`, servicio docker con
     reinicio automático), porque el GIL y los módulos pesados del relay bloquearían el temporizador del hombre
     muerto.
   - **Nivel 2 (aplazado):** servicios y acciones nativos en `ros2_vita`.
3. **La puerta de mando vive en el lado robot:** hombre muerto, caducidad, rampas y rearme por flanco. Si se corta el
   WiFi, el robot para solo.
4. El mismo GDScript cliente corre en el PC (rclgd) y en la Vita (ros2_vita): el protocolo son topics con tipos
   estándar.

## Alternativas descartadas

- **Acciones nativas sobre servicios XRCE:** viables, pero cuestan ~2 semanas y no resuelven el tamaño de los
  resultados (MoveGroup), el sello de tiempo de Servo ni el hombre muerto. El puente haría falta igual. Quedan como
  nivel 2.
- **Zenoh-Pico / Pico-ROS:** port de 1–3 semanas para sustituir un transporte ya validado en hardware, y sin
  acciones.
- **rosbridge:** `websocket` y `mbedtls` están desactivados en el port (docs/18).
- **Subir MTU e historial de XRCE:** es ortogonal; se deja como experimento barato (doc 27).
- **Hombre muerto solo en la Vita o con QoS deadline/liveliness:** inválido por el comportamiento del agente (W9).

## Consecuencias

- Todo robot nuevo necesita su entrada en el relay o el puente: el contrato de formatos está en los docs 27 y 32.
- La estación docker gana dos procesos (`relay`, `puente`) que hay que vigilar. `vita_relay` mide su propio ancho de
  banda.
