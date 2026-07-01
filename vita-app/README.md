# vita-app — "Vita ROS2 Hello" (Fase 1)

La app homebrew que valida la Fase 1: la Vita se une al grafo ROS2 Jazzy
como nodo, **publica `/vita_hello`** (visible con `ros2 topic echo` en el
PC/laptop) y **recibe `/pc_hello`** publicado desde fuera.

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
| `src/main.c` | Ciclo de vida completo: red → transporte → **sesión XRCE (incógnita dura)** → entidades DDS por XML → bucle pub 1 Hz + recepción. Sale con START. |
| `src/uxr_glue.{h,c}` | Adapta los 4 callbacks del módulo dual a `uxrCustomTransport`. Único archivo que incluye headers de micro-ROS. |
| `src/netlog.{h,c}` | Log por UDP a la laptop usando nuestro `net-udp` (en la Vita no hay consola). Escuchar con `nc -u -l -p 9999`. |
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
- [ ] Cross-compilación de microxrcedds_client (PC).
- [ ] Build del .vpk en sus dos variantes (PC).
- [ ] Sesión XRCE real + criterios 1 y 2 (hardware Vita).

Detalles que pueden necesitar ajuste al compilar en el PC (anotados en el
código): firmas exactas de `uxrCustomTransport` según la versión del
cliente, nombres DDS (`rt/`, `std_msgs::msg::dds_::String_`) según la
versión del agente, y stubs sce* adicionales en el enlace.
