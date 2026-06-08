# ADR 0002: micro-ROS con transporte UDP propio

- **Estado:** Aceptado
- **Fecha:** 2026-06-08

## Contexto

La PS Vita 1000 necesita convertirse en un nodo ROS2 real capaz de publicar y suscribir tópicos del grafo. ROS2 Jazzy completo es inviable en la Vita: la pila de comunicaciones DDS asume un sistema Linux con glibc, memoria abundante y un sistema de ficheros POSIX completo, ninguno de los cuales está disponible bajo VitaSDK/newlib. La alternativa diseñada para microcontroladores y dispositivos embebidos con restricciones similares es **micro-ROS**, que implementa el protocolo XRCE-DDS sobre un agente externo (ejecutándose en el PC) que actúa como puente hacia el grafo ROS2 completo.

El componente cliente de micro-ROS es `microxrcedds_client` (también conocido como Micro XRCE-DDS Client). Esta librería está diseñada para ser portable a plataformas no-Linux mediante una capa de transporte abstracta: el integrador solo necesita implementar cuatro callbacks (`open`, `close`, `write`, `read`) que adaptan la comunicación al mecanismo de red disponible en la plataforma destino. La librería no impone ningún stack de red concreto.

La PS Vita dispone de conectividad WiFi 802.11b/g y expone las APIs de red bajo `sceNet`, que proporciona sockets BSD-like sobre UDP e IP. No existe otra ruta de comunicación práctica entre la Vita y el PC de desarrollo en la configuración de trabajo del proyecto.

## Decisión

Se usa `microxrcedds_client` compilado como **librería estática ARMv7** para VitaSDK, con un **transporte personalizado** sobre UDP implementado mediante los cuatro callbacks del API de integración de la librería:

- `uxr_custom_transport_open`: inicializa el socket UDP usando `sceNetSocket` y asocia dirección y puerto del agente.
- `uxr_custom_transport_close`: cierra el socket y libera recursos `sceNet`.
- `uxr_custom_transport_write`: envía un datagrama UDP con `sceNetSendto`.
- `uxr_custom_transport_read`: recibe un datagrama con `sceNetRecvfrom`, con timeout controlado.

El agente micro-ROS corre como contenedor Docker en el PC de desarrollo (IP 192.168.1.65) escuchando en UDP4. La Vita (conectada por WiFi a la misma red) actúa como cliente XRCE y se registra contra ese agente al arrancar la aplicación.

Esta decisión constituye la **incógnita técnica dura de la Fase 1**: la viabilidad completa del proyecto depende de que esta integración funcione correctamente. Por ello se valida primero, antes de construir cualquier otra capa de la aplicación.

## Consecuencias

**Positivas:**

- Se reutiliza íntegramente la pila estándar de micro-ROS (`microxrcedds_client`) sin necesidad de modificar su código fuente. Los cuatro callbacks de transporte son exactamente el punto de extensión oficial y documentado de la librería.
- El agente micro-ROS estándar (imagen Docker `microros/micro-ros-agent`) no requiere modificaciones. La interoperabilidad con el grafo ROS2 Jazzy es inmediata una vez que la sesión XRCE se establece.
- UDP es un protocolo ligero y sin estado de conexión, apropiado para las restricciones de memoria y el modelo de ejecución de la Vita.
- Los módulos `net-udp` y `microros-transport` son candidatos directos a la estrategia de implementación dual Rust/C++, con contrato C-ABI. Una vez validada la implementación C, puede reemplazarse por la implementación Rust sin alterar la lógica de micro-ROS.

**Negativas / restricciones:**

- La implementación de los cuatro callbacks sobre `sceNet` es trabajo no trivial y no existe precedente documentado públicamente. Requiere entender las diferencias entre la API `sceNet` y BSD sockets estándar (manejo de timeouts, códigos de error, inicialización del stack de red de la Vita).
- UDP no garantiza entrega ni orden. Para los tópicos de control (joystick, botones) esto es aceptable; para escenarios futuros que requieran fiabilidad, `microxrcedds_client` admite transporte fiable sobre UDP (XRCE Reliable), pero su implementación añade complejidad al buffer de reenvío en la Vita.
- `microxrcedds_client` debe compilarse desde fuentes con el toolchain VitaSDK/newlib, lo que puede requerir parches de portabilidad si la librería usa APIs POSIX no disponibles en newlib. Este riesgo se evalúa durante la validación de la Fase 1.
- Depuración en red: un fallo silencioso (pérdida de paquetes, problema de inicialización del stack WiFi de la Vita) puede ser difícil de diagnosticar. Se planifica desde el inicio instrumentar los callbacks con logs por UDP hacia una herramienta tipo PrincessLog.

## Alternativas consideradas

**Transporte serie (UART):** micro-ROS soporta transporte serie nativamente. Sin embargo, la PS Vita 1000 no expone un puerto serie accesible de forma práctica en el hardware consumer: los pines del conector propietario de la Vita incluyen líneas UART, pero acceder a ellas requiere hardware adicional (modificación del conector, adaptador custom) y no sería reproducible en una configuración estándar. La conectividad WiFi integrada es la interfaz de red natural de la consola y no requiere hardware adicional. Se descarta el transporte serie.

**Transporte TCP:** `microxrcedds_client` también soporta TCP. TCP garantiza entrega y orden, pero añade overhead de conexión y gestión de estado que es innecesario para los tópicos de bajo nivel de la Fase 1. Más importante: la API `sceNet` implementa TCP, pero el comportamiento de blocking/non-blocking y los códigos de error difieren de BSD estándar de forma más acusada que en UDP, lo que añade complejidad a la implementación de los callbacks. UDP es suficiente para el caso de uso y más simple de integrar. Se descarta TCP en favor de UDP para la Fase 1.

**Puerto de rmw_microxrcedds directamente:** Existe la capa RMW (`rmw_microxrcedds`) que conecta `rclc` con el cliente XRCE. Portar `rclc` y toda la cadena sumaría mucha más superficie de dependencias POSIX a adaptar para VitaSDK/newlib. La estrategia elegida —usar `microxrcedds_client` directamente con su API C, sin `rclc`— minimiza la superficie de portabilidad para la Fase 1.
