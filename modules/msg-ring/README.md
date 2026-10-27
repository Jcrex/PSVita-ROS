# Módulo dual `msg-ring`

Cola circular **SPSC sin bloqueos** (un productor, un consumidor) de mensajes
de tamaño variable acotado. Sirve para pasar mensajes ROS2 del **hilo de red**
(el que ejecuta `uxr_run_session_*`) al **hilo de dibujo** o al hilo principal
de Godot, sin mutex ni malloc. Nació del ADR 0008 (módulo `ros2_vita` de
Godot) y también lo usará la app C para desacoplar red y mini-rviz.

`include/msg_ring.h` es la única verdad; `impl-c/` (C11 `<stdatomic.h>`) e
`impl-rust/` (`core::sync::atomic`) la cumplen y pasan la misma batería.

## API (resumen del header)

| Función | Qué hace |
|---|---|
| `msg_ring_required_size(slot_size, n)` | 64 B de cabecera + `n` × redondeo8(4 + `slot_size`). 0 si inválido (`n` no potencia de 2, desborde...). |
| `msg_ring_create(backing, len, slot_size, n)` | Inicializa en el buffer del llamador (alineado a 8). NULL si inválido. |
| `msg_ring_push(r, data, len)` | **Solo el productor.** `OK`, `ERR_FULL` (descarta y cuenta), `ERR_TOO_BIG`. |
| `msg_ring_pop(r, out, cap, &len)` | **Solo el consumidor.** `OK`, `ERR_EMPTY`, `ERR_BUF_SMALL` (no consume). |
| `msg_ring_count / dropped / capacity / slot_size` | Consultas. |

## Decisiones

- **Política de cola llena:** se descarta el mensaje *nuevo* y se incrementa
  `dropped`. En visualización/teleop es preferible perder un dato a bloquear
  el hilo de red. El netlog debe informar `dropped` periódicamente.
- **Un mensaje = una ranura:** sin fragmentación; el tamaño máximo se fija
  al crear (p. ej. 256 B para `Twist`/`JointState` pequeño; los mapas grandes
  NO pasan por aquí, ver `docs/11`).
- **Orden de memoria:** `release` al publicar, `acquire` al leer. Imprescindible
  en la Cortex-A9 (reordena escrituras); x86 lo perdona, así que el test de
  host **no demuestra** corrección en ARM — ver "Estado".

## Tests

```bash
tools/run-parity-tests.sh msg-ring
```

Casos: tamaños y desbordes, create inválido, FIFO, cola llena + `dropped`,
tamaños límite y errores, 100 000 vueltas (wrap de máscara), y **estrés con
2 hilos reales** (2 000 000 mensajes, cola de 8 ranuras, orden y contenido
verificados).

## Estado

- [x] Paridad C/Rust en host (x86_64): verde, incluido el estrés de 2 hilos.
- [x] ThreadSanitizer (`gcc -fsanitize=thread`) sobre la impl C: sin avisos (2026-10-27).
- [ ] **Validar en el PC:** cross-compilar a la Vita (`-DVITA_IMPL=c|rust`).
- [ ] **Validar en hardware:** correr el estrés en la Cortex-A9 (hilos de
      `sceKernelCreateThread`) — única prueba real del orden de memoria ARM.
- [ ] Integrar en `vita-app` (hilo de red → render) y en el módulo Godot.
