# Hardware de la Vita 1000 y plataforma VitaSDK

**Fecha de creación:** 2026-06-08
**Estado:** Fundación aprobada

---

## PS Vita 1000 ("fat"): el hardware objetivo

La unidad objetivo es una PS Vita modelo 1000, la primera revisión del hardware de Sony, conocida popularmente como "fat" para distinguirla de la Vita 2000 más delgada. Sus capacidades de cómputo, red y entrada la hacen una candidata técnicamente interesante para un nodo ROS2 embebido.

### Procesador y memoria

El procesador es un **ARM Cortex-A9 de 4 núcleos a 32 bits (arquitectura ARMv7)**, corriendo habitualmente a 444 MHz en homebrew. No dispone de unidad de punto flotante de doble precisión por hardware, lo que tiene implicaciones en código de coma flotante intensivo. La memoria del sistema es de **512 MB RAM**, compartida entre el SO de la Vita y las aplicaciones. La memoria de vídeo es de **128 MB VRAM**, gestionada por las APIs gráficas de bajo nivel.

Este perfil de memoria —cientos de megabytes, no gigabytes— define inmediatamente el espacio de posibilidades: aplicaciones de escritorio modernas como ROS2 completo o stacks DDS de propósito general están descartadas, pero micro-ROS, diseñado exactamente para sistemas con recursos acotados, encaja bien dentro de este presupuesto si los buffers se dimensionan con cuidado.

### Conectividad de red

La Vita 1000 incorpora **WiFi 802.11 b/g/n** (banda de 2.4 GHz, sin soporte 5 GHz). Esta es la única interfaz de red disponible para la comunicación con el agente micro-ROS en el PC. La latencia y el ancho de banda de WiFi en entornos domésticos son suficientes para los volúmenes de mensajes ROS2 típicos en robótica de servicio, pero el diseño del transporte debe asumir que la conexión puede ser no confiable y manejar reconexiones con el agente.

### Dispositivos de entrada y sensores

La riqueza de dispositivos de entrada y sensores de la Vita 1000 es uno de los atractivos principales del proyecto:

- **Dos sticks analógicos** con rango completo: izquierdo y derecho.
- **Cruceta digital** de cuatro direcciones.
- **Botones frontales**: triángulo, círculo, cruz, cuadrado; más L, R, Start, Select.
- **Pantalla táctil frontal capacitiva (OLED)** de 5 pulgadas y resolución 960×544. La pantalla OLED de la Vita 1000 tiene calidad superior a la LCD de la Vita 2000, lo cual es relevante para visualización.
- **Panel táctil trasero capacitivo**: una superficie táctil sin pantalla en la parte posterior de la consola. Es un dispositivo de entrada único que pocas plataformas tienen y que ofrece posibilidades de interfaz de usuario no convencionales.
- **Giroscopio y acelerómetro de tres ejes**: permiten publicar datos de orientación e inercia como topics ROS2 del tipo `sensor_msgs/Imu`.
- **Cámara frontal** (640×480 a 120 fps o 1280×720 a 60 fps en modos limitados) y **cámara trasera** (mismas capacidades): fuentes de imagen publicables como `sensor_msgs/Image`.
- **Micrófono integrado**: fuente de audio.

La combinación de todos estos dispositivos convierte a la Vita en un controlador de robot con más riqueza de entrada que un gamepad convencional, y en un dispositivo de captura de sensores con potencial para contribuir al grafo de percepción del robot.

---

## VitaSDK: la plataforma de desarrollo

### Qué es VitaSDK

**VitaSDK** es el toolchain de código abierto para desarrollar homebrew en PS Vita. Su compilador es `arm-vita-eabi-gcc`, un GCC cruzado (cross-compiler) que produce binarios ARMv7 para el entorno de ejecución de la Vita. La biblioteca C estándar usada es **newlib**, no glibc; esta distinción es fundamental y tiene consecuencias en cada módulo del proyecto.

La Vita no ejecuta un kernel Linux completo. El entorno de ejecución del homebrew es una capa sobre el sistema operativo propietario de Sony (basado en un núcleo personalizado) que se accede a través de funciones de sistema cuyos nombres tienen el prefijo `sce` (por ejemplo, `sceKernelCreateThread`, `sceNetSocket`, `sceCtrlReadBufferPositive`). VitaSDK proporciona headers y stubs para llamar a estas funciones desde código C/C++.

### newlib versus glibc: la diferencia que lo cambia todo

La ausencia de glibc es la restricción técnica más importante de la plataforma. Prácticamente toda la cadena de software de escritorio de Linux —y en particular ROS2— asume glibc: `pthreads` compatible con POSIX completo, `epoll`/`select` completos, `dlopen`, y decenas de extensiones específicas de glibc que las bibliotecas usan sin pensar. Newlib implementa un subconjunto de la biblioteca C estándar diseñado para sistemas embebidos. Es funcional, pero no es equivalente.

Esto significa que cualquier biblioteca externa que se quiera usar en la Vita debe bien compilarse directamente con VitaSDK y newlib (aceptando las limitaciones), bien tener sus dependencias de glibc reemplazadas por alternativas compatibles con newlib, o bien ser descartada. Es el filtro principal en el análisis de portabilidad de rviz2 y otras dependencias (ver `docs/04-investigacion-portabilidad-rviz2.md`).

### Gráficos

El ecosistema VitaSDK dispone de dos capas de gráficos:

- **`vita2d`**: biblioteca 2D acelerada por GPU para renderizar sprites, texto y formas geométricas simples. Adecuada para interfaces de usuario básicas.
- **`vitaGL`**: implementación de OpenGL ES sobre el hardware gráfico de la Vita. Es la opción para cualquier renderizado 3D o para portar código que use OpenGL. Relevante como base del visualizador propio ("mini-rviz") si rviz2 nativo no es portable.

### Red: `sceNet` y `sceNetCtl`

El acceso a la red desde homebrew se hace a través de las APIs propietarias de Sony para networking:

- **`sceNet`**: gestiona el stack de red y proporciona sockets con una interfaz BSD-like (similar a `socket()`, `bind()`, `sendto()`, `recvfrom()`). Soporta UDP y TCP.
- **`sceNetCtl`**: controla la interfaz WiFi: conectarse a una red, consultar la IP asignada, gestionar el estado de la conexión.

El hecho de que la API de sockets sea BSD-like facilita la implementación del transporte UDP para micro-ROS, pero no es idéntica a los sockets POSIX: las funciones tienen nombres distintos (`sceNetSocket` en lugar de `socket`), gestionan internamente su propia memoria de red, y la inicialización del stack de red requiere pasos específicos de la plataforma. El módulo `net-udp` del proyecto encapsula exactamente estas diferencias.

---

## Presupuesto de memoria y sus implicaciones

Con 512 MB de RAM compartidos entre el sistema y la aplicación, el espacio real disponible para la app homebrew es considerable pero finito: típicamente cientos de megabytes, no un espacio ilimitado. Esto impone disciplina en la gestión de memoria.

micro-ROS está diseñado para sistemas embebidos con restricciones mucho más severas (microcontroladores con kilobytes de RAM), por lo que sus requerimientos de memoria son modestos. Sin embargo, los buffers para mensajes, las entidades XRCE-DDS (publishers, subscribers, sesiones) y el pool de memoria de micro-ROS deben dimensionarse explícitamente. No se puede depender de que `malloc` sea siempre exitoso o eficiente.

Por este motivo el diseño incluye el módulo **`mem-pool`** en la estrategia dual: un asignador de memoria con pools fijos y acotados que micro-ROS usa en lugar del asignador de propósito general. Al ser un módulo dual (Rust + C/C++ bajo un contrato C-ABI), puede implementarse y verificarse con rigor desde el inicio y cambiarse de implementación si una resulta más eficiente en la plataforma real.

Esta restricción de memoria también justifica la elección de micro-ROS sobre cualquier intento de portar el stack DDS completo: no es una limitación del proyecto, es una elección consciente y correcta dado el hardware.

---

## Por qué ROS2 completo no entra en la Vita

La conclusión es clara: ROS2 completo no es viable en la Vita 1000. Los motivos son acumulativos:

1. ROS2 Jazzy asume un sistema operativo Linux con glibc. La Vita no tiene kernel Linux y su toolchain usa newlib.
2. El stack DDS (Fast DDS, Cyclone DDS) asume recursos de memoria y CPU propios de un ordenador de escritorio.
3. `rclcpp` y sus dependencias (Boost, bibliotecas de C++ moderno) se compilan asumiendo un entorno Linux completo.
4. Las herramientas de ROS2 (Python, colcon, ament) no existen en la plataforma.

El camino realista es **micro-ROS**: un cliente XRCE-DDS mínimo que se compila como biblioteca estática para sistemas embebidos y se comunica con un agente que vive en una máquina completa. Este es exactamente el diseño de la Fase 1, descrito en detalle en `docs/02-arquitectura-fase1-microros.md`.
