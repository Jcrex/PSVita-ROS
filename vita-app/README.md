# vita-app — "Vita ROS2 Teleop" (Fase 1 + Objetivo 2)

La app homebrew del proyecto: la Vita se une al grafo ROS2 Jazzy como
nodo, **publica `/vita_hello`** (Fase 1, visible con `ros2 topic echo`),
**recibe `/pc_hello`** (Fase 1) y, desde el Objetivo 2, es un **mando de
teleoperación**: publica `geometry_msgs/Twist` en **`/cmd_vel`** a ~20 Hz
desde los sticks y botones (mapeo completo en
`docs/09-objetivo2-control-robot.md`; resumen en pantalla, en la propia UI).

```
main.c ──> uxr_glue ──> microros-transport ──> net-udp ──> WiFi/UDP
                                                              │
        laptop/PC: micro-ROS Agent (Docker, udp4:8888) <──────┘
                        │
                  grafo ROS2 Jazzy (ros2 topic echo /vita_hello)
```

## Archivos

| Archivo | Qué hace |
|---|---|
| `src/main.c` | Ciclo de vida completo: red → transporte → **sesión XRCE (incógnita dura)** → entidades DDS por XML → bucle: `/vita_hello` 1 Hz + `/cmd_vel` ~20 Hz + recepción. Sale con START. |
| `src/teleop.{h,c}` | **Objetivo 2:** mapeo mandos → Twist, lógica PURA sin headers de la Vita (zona muerta, flancos △/✕, rampa lateral, clamps). Se testea en host. |
| `tests/teleop_test.c` | Batería del mapeo (39 checks) — corre con `scripts/check-teleop.sh` en laptop o PC, sin VitaSDK. |
| `src/uxr_glue.{h,c}` | Adapta los 4 callbacks del módulo dual a `uxrCustomTransport`. Único archivo que incluye headers de micro-ROS. |
| `src/netlog.{h,c}` | Log por UDP a la laptop usando nuestro `net-udp` (en la Vita no hay consola). Escuchar con `nc -u -l -p 9999`. |
| `ui/layout.json` | **La UI de la app, declarativa** (paneles, textos, valores en vivo). Editable a mano o desde la web (`/taller/ui`). |
| `src/ui_types.h` | Tipos del layout (`ui_widget`, `ui_state`), sin dependencias de la Vita: compilan en host. |
| `src/ui_layout.h` | GENERADO desde `ui/layout.json` por `scripts/gen-ui-header.mjs` — no editar a mano. |
| `src/ui.{h,c}` | Intérprete del layout con **vita2d** (GPU + fuente PGF). Solo Vita, solo C — ADR 0005. |
| `scripts/gen-ui-header.mjs` | Codegen `layout.json` → `ui_layout.h` (node, sin dependencias). |
| `scripts/check-ui-layout.sh` | Verificación EN HOST: regenera el header y comprueba que compila (gcc `-fsyntax-only`). |
| `rust-modules/` | Crate paraguas: un solo `libvita_modules_rust.a` con los 3 módulos duales (evita staticlibs Rust duplicadas). |
| `scripts/build-xrce-client-vita.sh` | Cross-compila `microxrcedds_client`+`microcdr` para armv7 Vita (perfil custom transport, sin POSIX). |
| `CMakeLists.txt` | Build con VitaSDK, selección `-DVITA_IMPL=c\|rust`, empaquetado `.vpk`. |

## Compilar (EN EL PC, no en la laptop)

```bash
export VITASDK=/usr/local/vitasdk
cd vita-app
./scripts/build-xrce-client-vita.sh        # una vez: micro-XRCE para Vita

cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake \
      -DVITA_IMPL=c -B build && cmake --build build
# -> build/vita-ros2-hello.vpk  (instalar con VitaShell; skill vita-deploy-logs)
```

Para el binario con los módulos en Rust: `-DVITA_IMPL=rust` (requiere
`rustup toolchain install nightly` + componente `rust-src`; ADR 0003).
Se generan dos `.vpk` distintos para comparar ambas implementaciones en
hardware real.

### Configurar IPs sin tocar código

```bash
cmake ... -DAGENT_IP=192.168.1.108 -DAGENT_PORT=8888 \
      -DNETLOG_IP=192.168.1.108 -DNETLOG_PORT=9999 -B build
```

### UI declarativa (vita2d + layout.json)

Desde 2026-07-07 la app dibuja una UI en pantalla (antes: negra a propósito).
La pantalla NO se programa: se describe en `ui/layout.json` y `ui.c` la
interpreta con vita2d (ADR 0005 — excepción consciente a la regla dual: es
código de app, sin rama host ni paridad Rust).

```bash
# tras editar ui/layout.json (o desde la web en /taller/ui):
node scripts/gen-ui-header.mjs      # regenera src/ui_layout.h
scripts/check-ui-layout.sh          # lo mismo + check de compilación en host
# después, recompilar el .vpk como siempre
```

Widgets v1: `panel` (rect + borde), `label` (texto fijo) y `valor` (dato en
vivo: `estado_conexion`, `contador_publicados`, `ultimo_pc_hello`,
`agente` y, desde el Objetivo 2, `vel_lineal`, `vel_lateral`, `cmd_vel`,
`contador_cmd`). Límites en el codegen (≤32 widgets, pantalla 960×544,
texto ASCII ≤63). El enlace usa libvita2d del VitaSDK (si falta:
`vdpm libvita2d` — el paquete NO se llama `vita2d`; con el nombre malo
vdpm reporta éxito aunque el tar falle). El dibujado real solo se valida
en hardware.

**Topología de red de la Fase 1:** el PC está por ethernet y la Vita solo
tiene WiFi, así que **el agente corre en la laptop** (192.168.1.108), que sí
está en la red WiFi y tiene ROS2 Jazzy:

```bash
# en la laptop:
docker run -it --rm --net=host --ipc=host microros/micro-ros-agent:jazzy udp4 --port 8888 -v6
# en otra terminal (logs de la Vita):
tools/netlog-listen.sh 9999
```

**`--ipc=host` es obligatorio** si el grafo ROS2 (`ros2 topic echo`/`pub`) corre
en otro contenedor: sin namespace IPC compartido, Fast-DDS descubre los
topics por UDP multicast (comparte `--net=host`) pero no puede entregar
datos reales por memoria compartida entre contenedores — el topic aparece
"emparejado" en `ros2 topic info` y aun así no llega nada. Bloqueó el
criterio 2 de la Fase 1 hasta diagnosticarlo el 2026-07-01 (ver
`docs/06-bitacora-estado.md`).

## Validación de la Fase 1 (en hardware)

1. Lanzar agente y `nc` en la laptop; abrir la app en la Vita.
2. El netlog debe mostrar `SESION XRCE ESTABLECIDA` → incógnita dura resuelta.
3. `ros2 topic echo /vita_hello` muestra los mensajes → criterio 1 ✔
4. `ros2 topic pub /pc_hello std_msgs/msg/String "data: 'ping'" -r 1` y el
   netlog muestra `criterio 2 de la Fase 1 CUMPLIDO` → criterio 2 ✔

## Estado

- [x] Código completo y revisado (laptop).
- [x] Crate paraguas Rust compila y exporta los símbolos C-ABI (verificado en host x86_64).
- [x] Cross-compilación de microxrcedds_client (PC).
- [x] Build del .vpk en sus dos variantes (PC).
- [x] Sesión XRCE real + criterios 1 y 2 (hardware Vita) — **Fase 1 cerrada**, ver `docs/06`.
- [x] UI declarativa: codegen + check en host verdes; editor web `/taller/ui` operativo (laptop).
- [x] UI declarativa: build con vita2d enlazado en el PC (libvita2d vía
      `vdpm libvita2d` — ojo, el paquete NO se llama `vita2d`). Dibujado
      real pendiente de hardware.
- [x] Objetivo 2: teleop `/cmd_vel` implementado (39 checks host verdes,
      `.vpk` C y Rust compilados en el PC).
- [ ] Objetivo 2 en hardware: `ros2 topic echo /cmd_vel` + turtlesim
      obedeciendo a la Vita (ver docs/09, "Cómo probarlo").

Detalle pendiente de hardware: el alto de la fuente PGF por defecto (la
preview web asume ~20 px a escala 1, igual que `ui.c`).
