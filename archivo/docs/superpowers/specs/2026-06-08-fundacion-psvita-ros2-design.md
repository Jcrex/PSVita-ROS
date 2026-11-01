# Fundación del proyecto PS Vita ↔ ROS2 — Diseño (Fase 0)

- **Fecha:** 2026-06-08
- **Estado:** Aprobado (pendiente de revisión final del usuario)
- **Alcance de este documento:** Aproximación 3 ("Fundación equilibrada"). Diseña la *capa meta* (documentación, skills, MCP y tooling de sincronización) que se produce en la laptop-taller y se instala en el PC de desarrollo para arrancar la **Fase 1**.

---

## 1. Contexto

### Máquinas
| Rol | Equipo | IP | Función |
|---|---|---|---|
| **Taller de preparación** | Laptop (sesión actual) | 192.168.1.108 | Solo produce ideas, planes, docs, skills, MCP y scripts. **Cero instalaciones.** No se desarrolla a futuro aquí. |
| **PC de desarrollo** | CachyOS + KDE Plasma, Ryzen 5800X, RTX 5060 Ti 16 GB | 192.168.1.65 | Desarrollo fijo y continuo. Toda instalación y ejecución ocurre aquí. Ya tiene ROS2 Jazzy + Gazebo resueltos vía Docker. Tiene Claude Code. |
| **Objetivo** | PS Vita 1000 ("fat") | — | ARM Cortex-A9 32-bit (ARMv7), 512 MB RAM, 128 MB VRAM. Homebrew vía VitaSDK. |

- Transferencia laptop → PC: por SMB (ya instalado). Se entrega un script de sincronización; la transferencia la dispara el usuario.
- ROS2 objetivo: **Jazzy**.
- ROS2/Gazebo en CachyOS: **ya resuelto vía Docker** — fuera del alcance, no se toca.

### Restricciones transversales (aplican a todas las fases)
1. **Doble implementación Rust + C/C++** en todo lo que toque hardware, memoria o sistema embebido, con C/C++ como respaldo permanente y equivalente.
2. Proyecto **secuencial por objetivos**, de largo plazo, con vocación de **publicarse**.
3. En la laptop **no se instala nada**; todo se ejecuta/instala en el PC.

### Objetivos del proyecto (del usuario, fijados)
1. Recibir y enviar topics de ROS2.
2. Controlar un robot desde la Vita (joysticks, botones, pantallas táctiles delantera y trasera).
3. Compilar una app de ROS2 (rviz2) en la consola y que sea funcional.
4. Recibir topics y visualizar robots, mapas y otros topics en rviz2 como en un PC.
5. Aprovechar el hardware de la Vita (cámara → imagen por ROS2, giroscopio, panel táctil trasero, etc.) para una app nativa de control/gestión.
6. Desarrollar un conjunto de herramientas para estandarizar el desarrollo ROS2 → PS Vita y publicarlo.

> **Esta Fase 0 prepara la fundación y arranca la Fase 1 (objetivo 1).** Los objetivos 3-6 quedan documentados como incógnitas abiertas, no se diseñan en detalle todavía.

---

## 2. Aterrizaje técnico (decisiones de realidad)

- **ROS2 Jazzy completo en la Vita: inviable.** Asume Linux/glibc, DDS pesado y memoria abundante. La Vita no tiene SO Linux completo.
- **Camino realista de Fase 1:** **micro-ROS** (cliente Micro XRCE-DDS) en la Vita ↔ por WiFi/UDP ↔ **micro-ROS Agent** (Docker en el PC) ↔ grafo **ROS2 Jazzy**. La Vita se vuelve un nodo ROS2 real.
- **rviz2 / Gazebo nativos en la Vita: incógnita de investigación abierta** (objetivos 3 y 4), no un descarte. Se analiza el árbol de dependencias (Qt, `rviz_rendering`/OGRE, `rclcpp`, DDS) contra VitaSDK para encontrar el muro real. Gazebo y demás herramientas pesadas siguen corriendo en el PC.

---

## 3. Estructura del repo (la laptop-taller)

```
ps-vita-ros2/
├── README.md                     # qué es esto + cómo sincronizar al PC
├── docs/
│   ├── 00-vision-y-objetivos.md
│   ├── 01-hardware-y-plataforma.md
│   ├── 02-arquitectura-fase1-microros.md
│   ├── 03-estrategia-dual-rust-cpp.md
│   ├── 04-investigacion-portabilidad-rviz2.md
│   ├── 05-setup-entorno-cachyos.md
│   ├── adr/
│   │   ├── 0001-vitasdk-toolchain-base.md
│   │   ├── 0002-microros-transporte-udp-propio.md
│   │   ├── 0003-rust-target-armv7-sony-vita.md
│   │   └── 0004-empaquetado-vpk-cmake.md
│   └── superpowers/specs/
│       └── 2026-06-08-fundacion-psvita-ros2-design.md   # este documento
├── skills/
│   ├── vita-dual-module/
│   ├── vita-build-package/
│   └── vita-deploy-logs/
├── mcp/
│   └── ros2-introspection/
├── tools/
│   └── sync-to-devpc.sh
└── .gitignore
```

**Regla de frontera:** aquí se escriben docs, skills, el código del MCP y scripts (la capa meta). **No** se escribe el código C/C++/Rust que correrá en la Vita — ese nace en el PC. El MCP se escribe aquí pero solo se prueba en el PC (necesita ROS2 Jazzy vivo).

---

## 4. Decisiones de toolchain (se documentan aquí, se instalan en el PC)

| Pieza | Decisión | Nota |
|---|---|---|
| **Toolchain C/C++** | **VitaSDK** (`arm-vita-eabi-gcc`, newlib) | Gráficos: `vita2d`/`vitaGL`. Red: APIs `sceNet` (UDP). |
| **Build C/C++** | **CMake** + `vita.toolchain.cmake` | Empaquetado: `vita-elf-create` → `vita-make-fself` → `vita-mksfoex` → `vita-pack-vpk` (`.vpk`). |
| **Rust** | target **`armv7-sony-vita-newlibeabihf`** (tier 3, nightly, `-Z build-std`) vía **`cargo-vita`** | Enlaza contra newlib de VitaSDK. Requiere `VITASDK` exportado. |
| **micro-ROS (cliente Vita)** | `microxrcedds_client` como **lib estática armv7** con **transporte personalizado** | Implementa 4 callbacks (open/close/write/read) sobre UDP de la Vita. **Incógnita dura a validar primero.** |
| **micro-ROS Agent** | `micro-ROS-Agent` en **Docker en el PC**, transporte **UDP4** | Puentea a ROS2 Jazzy. |
| **Visualizador propio (fase posterior)** | `vitaGL` (OpenGL ES) | Reservado para el "mini-rviz" nativo; no se decide ahora. |

**Orden de validación impuesto:** primero levantar el cliente micro-ROS en la Vita con transporte UDP propio contra el agente. De esa incógnita cuelga toda la Fase 1.

---

## 5. Estrategia dual Rust + C/C++

Frontera = **contrato C-ABI**:

- Cada módulo de bajo nivel se define primero como **interfaz C** (`.h`): funciones, structs, códigos de error. El header es *la verdad* del módulo.
- Dos implementaciones cumplen el header:
  - `impl-c/` → C/C++ sobre VitaSDK.
  - `impl-rust/` → Rust `#[no_mangle] extern "C"`, compilado a `staticlib` para el target Vita.
- La app y micro-ROS solo conocen el **header C**. Se elige implementación en **build time** con `-DVITA_IMPL=c|rust`.
- **Tests de paridad:** una misma batería corre contra ambas implementaciones y compara comportamiento. Divergencia = fallo. Garantiza que el respaldo C/C++ sea siempre equivalente.

Estructura por módulo (en el PC):
```
modules/net-udp/
├── include/net_udp.h        # contrato C-ABI (la verdad)
├── impl-c/net_udp.c
├── impl-rust/src/lib.rs      # extern "C", staticlib
├── tests/parity_test.c       # corre contra ambas
└── CMakeLists.txt            # -DVITA_IMPL selecciona
```

Módulos duales candidatos en Fase 1: `net-udp` (sockets `sceNet`), `microros-transport` (los 4 callbacks), `mem-pool` (memoria acotada). La lógica de alto nivel/UI puede no ser dual al principio; la regla aplica a lo que toca hardware/memoria/sistema.

---

## 6. Skills y MCP

### Skills de Claude Code (escritas aquí, instaladas/usadas en el PC)
| Skill | Qué hace | Por qué skill |
|---|---|---|
| **`vita-dual-module`** | Scaffold de módulo dual (header C-ABI + `impl-c` + `impl-rust` + test de paridad + CMake). | Workflow de scaffolding + convenciones. |
| **`vita-build-package`** | Compila C/C++ (CMake+VitaSDK) o Rust (`cargo-vita`), selecciona `VITA_IMPL`, produce `.vpk`. | Encapsula la cadena de empaquetado. |
| **`vita-deploy-logs`** | Sube `.vpk` a la Vita por **FTP (VitaShell)**, instala/lanza, captura logs por red (UDP, estilo PrincessLog). | Bucle deploy-test repetitivo y propenso a error. |

### MCP construido ahora: `ros2-introspection`
- Corre en el PC (donde vive ROS2 Jazzy). Da a Claude Code visibilidad **en vivo** del grafo ROS2 para generar código suscriptor/publicador de la Vita con tipos correctos.
- Lenguaje: **Python sobre `rclpy`**.
- Herramientas: `list_topics`, `list_nodes`, `get_topic_type`, `get_message_definition`, `echo_topic` (una muestra), `list_interfaces`.
- Se escribe aquí, se documenta su instalación, se **prueba en el PC**.

### MCPs solo especificados (no construidos hasta validar hardware)
- `vita-deploy` (deploy como servicio MCP).
- `microros-agent` (control del agente).
- Quedan descritos en docs para no automatizar sobre supuestos.

---

## 7. Sincronización al PC

- `tools/sync-to-devpc.sh`: `rsync` sobre el recurso SMB montado (o `rsync` por SSH si el usuario lo prefiere) hacia `192.168.1.65`. La transferencia la dispara el usuario.
- El PC es siempre la **fuente de verdad** del desarrollo; la laptop solo emite la fundación una vez.

---

## 8. Fuera de alcance (de esta Fase 0)
- Código C/C++/Rust que corre en la Vita (nace en el PC).
- Diseño detallado de objetivos 3-6 (rviz2 nativo, cámara/giroscopio/táctil, toolkit publicable).
- Cualquier instalación en la laptop.
- ROS2/Gazebo en CachyOS (ya resuelto).

## 9. Criterio de éxito de la Fase 0
Al sincronizar al PC, el usuario tiene: (a) docs y ADRs que fijan toolchain y arquitectura; (b) la investigación de portabilidad de rviz2 con su árbol de decisión; (c) 3 skills instalables; (d) el MCP `ros2-introspection` listo para probar; (e) un script de sync; (f) una guía paso a paso de qué instalar en el PC para arrancar la Fase 1.
