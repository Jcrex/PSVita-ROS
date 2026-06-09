# Módulo dual `net-udp`

La **capa de red más baja** del proyecto: inicialización del stack de red y
sockets UDP "conectados" a un destino fijo (el micro-ROS Agent del PC).
`microros-transport` consume este módulo; nada por encima toca sockets.

Contrato: `include/net_udp.h` (la verdad). Implementaciones equivalentes en
`impl-c/` (C) e `impl-rust/` (Rust no_std con FFI manual), verificadas por
`tests/parity_test.c`.

## Doble plataforma dentro de cada implementación

| Plataforma | C (`#ifdef __vita__`) | Rust (`#[cfg(target_os = "vita")]`) | Estado |
|---|---|---|---|
| PS Vita | `sceNet`/`sceNetCtl` + pool estático de 1 MiB | FFI manual a los stubs `sceNet*` de VitaSDK | escrito, **compilar en el PC y validar en hardware** |
| Host (Linux) | sockets POSIX | FFI manual a la libc (sin crate `libc`) | paridad verificada en laptop |

La rama host existe para poder ejecutar los tests de paridad sin la consola;
la rama Vita es la real. Las constantes de error sceNet (`SCE_NET_ERROR_EAGAIN`,
`EBUSY`...) están anotadas en el código y deben confirmarse contra los headers
de VitaSDK al compilar en el PC.

## API (resumen)

| Función | Qué hace |
|---|---|
| `net_udp_init()` | Inicializa el stack (Vita: sysmodule → `sceNetInit` → `sceNetCtlInit`). Idempotente. |
| `net_udp_shutdown()` | Cierra sockets vivos y libera el stack. |
| `net_udp_open(ip, port)` | Socket UDP conectado a `ip:port`. NULL si: sin init, ip mal formada, port 0, tabla llena (máx. 4) o fallo del SO. |
| `net_udp_close(sock)` | Cierra y libera la entrada. NULL es no-op. |
| `net_udp_send(sock, buf, len)` | Envía un datagrama; devuelve bytes o error negativo. |
| `net_udp_recv(sock, buf, cap, timeout_ms)` | Recibe con timeout (`0` = sondeo, `<0` = inválido); `NET_UDP_ERR_TIMEOUT` si expira. |

## Decisiones de diseño

- **Sin malloc**: tabla estática de `NET_UDP_MAX_SOCKETS = 4` sockets.
  El agotamiento de la tabla es un caso testeado.
- **Parser IPv4 propio** idéntico en ambas implementaciones: el rechazo de
  cadenas mal formadas no depende de la libc de cada plataforma.
- **Socket UDP "conectado"** (`connect()` sobre UDP): fija el destino por
  defecto y hace que el kernel filtre datagramas de otros orígenes. No hay
  handshake; es solo estado local.
- **Timeout por llamada** vía `SO_RCVTIMEO` (en la Vita se expresa en
  microsegundos; en POSIX, `struct timeval`).
- **Mono-hilo**: el estado global asume un solo hilo llamante (documentado
  explícitamente en la impl Rust con `UnsafeCell + unsafe impl Sync`).

## Tests de paridad

```bash
tools/run-parity-tests.sh net-udp
```

El test levanta un peer UDP POSIX en 127.0.0.1 (puerto efímero) que hace de
mini-agente de eco, sin hilos. Casos: init/shutdown/idempotencia, open antes
de init, 10 variantes de IP inválida, agotamiento y reciclaje de la tabla,
roundtrip de datos real, timeouts (50 ms medido, sondeo 0 ms, negativo),
argumentos inválidos de send/recv y uso tras close.

## Estado

- [x] Paridad C/Rust verificada en host (laptop).
- [ ] Compilación cruzada Vita (VitaSDK / cargo nightly) — en el PC.
- [ ] Validación de constantes sceNet y comportamiento real — en hardware.
