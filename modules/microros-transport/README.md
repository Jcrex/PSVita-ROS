# Módulo dual `microros-transport`

Los **4 callbacks del transporte personalizado de micro-ROS** (`open`,
`close`, `write`, `read`) implementados sobre el módulo `net-udp`. Es el
adaptador entre el cliente XRCE-DDS y el stack de red de la plataforma, y el
núcleo de la **incógnita dura de la Fase 1** (docs/02): ¿levanta la sesión
XRCE con el agente sobre este transporte?

Contrato: `include/microros_transport.h`. Implementaciones equivalentes en
`impl-c/` e `impl-rust/`, verificadas por `tests/parity_test.c`.

## Por qué no incluye headers de micro-ROS

`microxrcedds_client` no existe en la laptop. El módulo expone funciones
propias con la **misma semántica** que `uxrCustomTransport`; el pegamento
trivial hacia `uxr_set_custom_transport_callbacks()` vive en la app
(`vita-app/src/uxr_glue.c`) y se compila solo en el PC, donde la lib real
está disponible. Así el módulo es testeable hoy y conectable mañana.

## Convención de errores (la de uxr)

| Situación | Retorno | `*errcode` |
|---|---|---|
| Éxito | bytes procesados | 0 |
| Timeout en read (uxr reintenta) | 0 | 0 |
| Error real (cerrado, args inválidos, fallo de red) | 0 | 1 |

Distinguir timeout de error es lo más delicado del contrato: si un timeout
se reportara como error, el cliente XRCE abortaría la sesión en cada espera
vacía. El test lo cubre explícitamente (`test_read_timeout_vs_error`).

## API

| Función | Qué hace |
|---|---|
| `microros_transport_open(ip, port)` | Inicializa net-udp si hace falta y abre el socket al agente. Falla si ya está abierto. |
| `microros_transport_close()` | Cierra. `false` si no estaba abierto. |
| `microros_transport_is_open()` | Consulta sin tocar la red. |
| `microros_transport_write(buf, len, &err)` | Envía un datagrama XRCE al agente. |
| `microros_transport_read(buf, cap, timeout_ms, &err)` | Recibe con timeout; 0/err=0 si expira. |

Hay **un** transporte global por app: una sesión XRCE ↔ un agente. `errcode`
puede ser NULL (se ignora).

## Nota Rust: composición de crates

`impl-rust/` introduce la composición de módulos en Rust: el crate depende de
`net_udp_rust` por ruta (`path = "../../net-udp/impl-rust"`) y llama a sus
funciones como Rust normal. En el build "todo Rust" el staticlib resultante
contiene ambos módulos y ningún `.c`. Los crates de módulo son `rlib`; el
`.a` que enlaza C se genera con `cargo rustc --release --crate-type staticlib`
(evita panic_handlers duplicados al componer — explicado en los Cargo.toml).

## Tests de paridad

```bash
tools/run-parity-tests.sh microros-transport
```

Casos: write/read con transporte cerrado, IPs inválidas, doble open, doble
close, reapertura, roundtrip real contra un peer de eco en loopback,
timeout-no-es-error (50 ms y sondeo 0 ms), timeout negativo, buffers NULL,
errcode NULL tolerado.

## Estado

- [x] Paridad C/Rust verificada en host (laptop).
- [ ] Compilación cruzada Vita — en el PC.
- [ ] Sesión XRCE real contra micro-ROS Agent — la incógnita dura, en hardware.
