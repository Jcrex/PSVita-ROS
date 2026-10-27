# 18 — Migración a Godot 4 (godot4-vita 4.8-dev7): inventario, brechas y plan

**Fecha:** 2026-10-27 · **Decisión del usuario:** priorizar Godot 4 para aprovechar el
estudio de `rclgd`/`roomba_ws` (docs/17). Este documento es la investigación extensiva
de **qué hay que migrar, qué no, y qué falta para que funcione**.
Marcas: **[V]** leído en el código fuente citado · **[T]** comprobado con una herramienta
en la laptop (se indica cuál) · **[I]** inferencia · **[?]** por comprobar en el PC o la Vita.

Fuentes estudiadas (clones de solo lectura, sin ejecutar nada de ellos): `WolffsRoom/godot4-vita`
commit `d1a5f29` (2026-10-27, 547 MB), `Ozuba/rclgd` `4d0a8b3`, `Ozuba/roomba_ws` `8332acb`,
`eProsima/Micro-XRCE-DDS-Client` v2.4.3 y `Micro-CDR` v2.0.1 (compilados en host para analizar símbolos).

---

## 0. Resumen ejecutivo

1. **El código del Rust SDK de la Vita NO depende de Godot** y no hay que migrarlo: los módulos
   (`mem-pool`, `net-udp`, `microros-transport`, `msg-ring`, `viz-math`, `msg-cdr`, `tf-tree`,
   `msg-schema`) son crates `no_std` con ABI C y paridad C/Rust. Godot es **un consumidor más**
   (junto a `vita-app` y, a futuro, una app Rust con `cargo-vita`). Lo que cambia es **cómo se
   enlazan** (§3): dentro de un `libgodot.so` PIC sin libc, no en un ELF estático.
2. **Lo que sí se migra** es la capa Godot (`godot/`), la receta de compilación, la tubería de
   exportación y varios documentos. Ya está hecho en esta sesión: reescritura del módulo para
   Godot 4 (§6), parche del loader (§4.2), scripts de build y de comprobación de imports (§4.4).
3. **El runtime `godot4-vita` es real pero joven** (§1): 2D con render GXM nativo validado en juegos;
   canvas 2D "subconjunto"; 3D experimental; sin GDExtension; sin red inicializada. No es un
   "drop-in" de Godot 4.8.
4. **Hallazgos que condicionan el diseño** (cada uno con evidencia abajo):
   - `libgodot.so` se enlaza con `-nostdlib` y el **loader resuelve todos los imports** con una
     tabla manual; el empaquetador rechaza el runtime si falta uno (§2.2).
   - **No hay red**: ni `sceNet*` en la tabla ni inicialización de `libnet` en el motor (§4.3).
   - Las bibliotecas externas deben ser **PIC** y la plataforma **descarta las libs dadas como
     texto** al enlazar el `.so` (§3.2).
   - Solo el editor **exactamente 4.8-dev7** exporta a Vita; `rclgd` es 4.7.1 (§7).
   - `websocket` y `mbedtls` están desactivados: la vía B (rosbridge) **ya no existe** en 4.x (§2.4).
5. **Lo que se puede verificar sin Vita** está dividido en puertas G0–G7 (§8). Hoy: G0 verde.
   La compilación del motor con SCons **no se ejecutó** aquí (el entorno bloqueó correr los scripts
   de build de un repositorio de terceros); queda como puerta G1 en el PC.

---

## 1. Estado real de godot4-vita

El README principal ("Games running on this engine") y `platform/vita/README.md`/`ROADMAP.md`
parecen contradecirse; **no lo hacen**: hablan de dos renderers distintos **[V]**.

| Ruta de render | Qué es | Estado según el propio repo |
|---|---|---|
| **GXM nativo 2D** (`rasterizer_gxm_vita.cpp` + `gxm_canvas_vita.inc`) | Traduce comandos de `CanvasItem` a dibujos GXM vía libvita2d; **sin shaders GLES** | **Es el que se distribuye.** Validado en hardware en Dodge the Creeps, Ambidextro, Deltarune Lightners Live Plus, Tenebrarium |
| GXM 3D (`rasterizer_scene_gxm_vita.inc`, `libgodot_gxm3d.so`) | Mallas con skinning en CPU, iluminación por vértice | **Experimental**: OVERBURDEN ~30 FPS; Buckshot Roulette no arranca el juego; sin sombras/niebla/post-proceso/shaders propios |
| VitaGL/GLES3 ("Compatibility" adaptado) | Traducción ES3→Cg | **Parado/histórico**: el ROADMAP (2026-10-10) deja el canvas completo "sin aprobar", pantalla negra sin resolver |

Hechos adicionales **[V]**:
- Versión fijada **4.8-dev7** (`version.py` = 4.8.0 dev). Licencia MIT. Mantenedor único (README en portugués/inglés).
- `UPDATES_2026_10.md` lista limitaciones propias: canvas parcial, "no es un export template
  para cualquier juego 4.8", sin CI en hardware, fondos/partículas sustituidos "para esta demo".
- Cada afirmación de hardware se acompaña de "verificado en host, no en la Vita" cuando procede:
  el repositorio es **honesto sobre su alcance**, y nosotros debemos serlo igual.

**Consecuencia para nosotros:** una app de control/HMI **2D con Control nodes** es el mejor
encaje; el mini-rviz 3D con vitaGL seguirá en `vita-app/` (ADR 0007) y **no** se mueve a Godot.

---

## 2. Cómo funciona por dentro lo que nos afecta

### 2.1 Arquitectura de ejecución **[V]**
```
eboot.bin (loader, C)  ── so_util: mapea y reubica ──►  libgodot.so (PIC, ARM hard-float)
   default_dynlib.c (tabla manual de imports)              Godot 4.8-dev7 + OS_Vita + GXM
   tls_stubs.c, dl_stubs.c, gxm_bridge.c                   AudioDriverVita, JoypadVita, touch
```
- El motor se compila `-fPIC` y se enlaza `-shared -nostdlib -Wl,--unresolved-symbols=ignore-all`
  (`platform/vita/SCsub`); **todo símbolo externo** (libc de newlib, SDK de Sony, helpers de GCC)
  se resuelve **en el loader**, por `strcmp` lineal sobre `default_dynlib[]` (681 entradas hoy) **[T]**.
- `tools/verify_runtime.py` (lo ejecuta el empaquetador) exige: ELF32 ARM `ET_DYN` hard-float,
  2 segmentos `PT_LOAD` (RX en vaddr 0 y RW), `.hash/.dynsym/.rel.dyn/.rel.plt/.init_array`,
  `main` exportado y **solo relocaciones 2, 21, 22, 23** (`R_ARM_ABS32`, `GLOB_DAT`, `JUMP_SLOT`,
  `RELATIVE`); rechaza `DT_NEEDED` y cualquier import ausente en la tabla.
- `tls_stubs.c` define a mano las funciones `_ZTH…` de `thread_local` que el `.so` dejó sin
  resolver: **el TLS está a medias** ⇒ ni `thread_local` de C++ ni de Rust en nuestro código **[V]**.

### 2.2 Memoria y datos **[V]**
- Paquete con `ATTRIBUTE2=12` (≈365 MiB de usuario). Heap de newlib: el **loader** declara
  `_newlib_heap_size_user = 256 MiB` (`loader/main.c:36`); el motor declara 96 MiB
  (`godot_vita.cpp:65`) — el ROADMAP ya marca la doble definición como pendiente (P1).
  Esto **cierra E-H5** de `docs/14`: la Vita-Godot ya usa memoria ampliada.
- Datos: `app0:game_data_folder.cfg` → `ux0:data/<carpeta>/game_data`; con `game.pck` se monta con
  `--main-pack` (150 ms por recurso suelto ⇒ **usar pack**). Scripts exportados **como texto**.
- Texturas: RGBA4444 por defecto (RGBA8888 opcional) con presupuesto de 64 MiB; **`texture_2d_update`
  vuelve a crear la textura entera** (`rasterizer_gxm_vita.cpp:81`) ⇒ una cámara que actualice
  un `ImageTexture` por fotograma libera y reserva en cada frame **[V]** (impacto **[?]**).
- Hilos: `WorkerThreadPool` limitado a 2 (arreglo de un crash real decodificado); decodificadores
  de la animación de arranque en los núcleos 1 y 2; el 4.º núcleo solo con CapUnlocker **[V]**.

### 2.3 Entrada y sensores que Godot ya expone **[V]**
- Mando completo como `joypad 0` (D-pad, sticks, botones, hombros, START/SELECT) y **panel táctil frontal**.
- **Acelerómetro, giroscopio y gravedad ya llegan a `Input.get_accelerometer/gyroscope/gravity`**
  (`display_server_vita.cpp:262-270`, `sceMotionGetState`) ⇒ el **IMU del Objetivo 5 desde Godot es
  casi gratis** (publicar con `RosPublisher`); unidades **[?]**.
- **No** hay: panel táctil **trasero**, cámaras, vibración/LED, red.

### 2.4 Módulos del motor activados/desactivados **[V]** (`detect.py`)
Desactivados: `mono`, `openxr`, `webrtc`, **`websocket`**, `jolt_physics`, `csg`, `upnp`, **`mbedtls`**.
Activados: `multiplayer`, `enet` (builtin), `gdscript`, `regex`... ⇒ la **vía B** de `docs/12` (rosbridge por
`ws://`) **muere en 4.x**; TLS no existe. Los sockets POSIX de Godot (`drivers/unix`) existen, pero **sin red
inicializada** (§4.3).

### 2.5 Exportación **[V]**
- Plataforma "PS Vita" para el editor **Windows propio** (`Godot4Vita.exe`, módulo `vita_editor`) **o** como
  *addon clásico* (`editor/addons/psvita`) en el editor **oficial 4.8-dev7** (no hace falta Windows si se
  consigue ese editor en Linux **[?]**). `platform.gd:103` exige `Engine.get_version_info()` = 4.8-dev7
  ("matching resource format"); la plantilla (`vita_release.zip`) lleva hashes SHA-256.
- Se admite **plantilla personalizada** ("Custom Template") ⇒ ahí entra la que construimos con `ros2_vita`.
- Exporta con el exportador de recursos de Godot: escenas remapeadas, texturas/fuentes/audio desde
  `.godot/imported`; **la Vita nunca importa**. Exportación siempre Release.

---

## 3. El SDK de Rust no depende de Godot — y qué cambia al enlazarlo

### 3.1 Tres consumidores de los mismos módulos

| | `vita-app` (C, ya en hardware) | `libgodot.so` (módulo `ros2_vita`) | App Rust (cargo-vita, futuro) |
|---|---|---|---|
| Enlace | ELF estático → `vita-elf-create` → VELF/SELF | objetos dentro de un `.so` **PIC** | ELF estático |
| libc/SDK | `-lc`, `-lSce*_stub` del SDK | **ninguna**: imports por la tabla del loader | `-lc`, stubs |
| Relocación Rust | `static` (por defecto del target) | **`pic` obligatoria** (§2.1) | `static` |
| Rust `std` | `-Zbuild-std=std,panic_abort` | **`core` solamente** (sin TLS ni pthread) | `std` posible |
| Verificación | `vita-elf-create` | `verify_runtime.py` | — |
| Script | CMake de `vita-app` | `tools/build-rust-pic.sh` + SCsub | `cargo vita` |

La interfaz (headers C) es la misma; **ningún crate cambia de código**. Cambian flags de compilación.

### 3.2 Reglas nuevas para cualquier código que entre en `libgodot.so`
1. **PIC**: C con `-fPIC` (SCons ya lo pone); Rust con `-C relocation-model=pic` **[?]** (la bandera existe;
   que el resultado pase `verify_runtime.py` solo se sabe en el PC).
2. **Cierre de imports**: todo símbolo no definido debe estar en `default_dynlib.c` (§4).
3. **Sin TLS**: nada de `thread_local`/`#[thread_local]`; nuestros módulos son `no_std` ⇒ cumplen **[T: 0 referencias
   a TLS en `libmods_c.a`, el staticlib Rust, `libmicroxrcedds_client.a` ni `libmicrocdr.a`, `nm -A` en host]**.
4. **Los `.a` deben entrar como *Node* de SCons**: `platform/vita/SCsub` filtra
   `LIBS` y **descarta las cadenas** (las trata como libs del SDK). `SCsub` de `ros2_vita` usa
   `env.File(ruta)` o compila los `.c` directamente. (Confirmado en la línea 29 de `platform/vita/SCsub` **[V]**.)
5. **Sin excepciones/RTTI nuevos**: nuestro C es C puro; el módulo C++ sigue las reglas del motor.
6. `-fpermissive` y `-fno-optimize-sibling-calls` de CCFLAGS también se aplican a los `.c` del módulo
   (avisos inocuos con GCC en modo C **[?]**).

---

## 4. Cierre de imports (el problema nº 1 del enlace)

### 4.1 Método **[T]**
`tools/check-vita-imports.py` compara `nm -u` de cualquier `.a/.o` con la tabla del loader. Aquí se ejecutó con
`nm` del **host** sobre binarios de host (aproxima; la verdad es `arm-vita-eabi-nm` en el PC):

| Artefacto | Imports ausentes de la tabla |
|---|---|
| `libmicroxrcedds_client.a` v2.4.3 (perfil custom, PIC) | **0** |
| `libmicrocdr.a` v2.0.1 | **0** |
| Módulos C (host) | `sincosf`* · `__errno_location`† |
| Staticlib Rust umbrella (host) | `bcmp` · `__errno_location`† |

\* GCC fusiona `sinf`+`cosf` del mismo argumento en `sincosf` (`viz_math.c`, `quat_from_axis_angle`).
† glibc-específico del backend host de `net-udp`; **no existe** en la rama Vita.

Además, la rama **Vita** de `net-udp` (C y Rust) pide 11 funciones del SDK que **ni están en la tabla**:
`sceSysmoduleLoadModule`, `sceNetInit/Term`, `sceNetCtlInit/Term`, `sceNetSocket/SocketClose/Connect/Send/Recv/Setsockopt`.
La tabla trae `socket/sendto/recvfrom` (newlib) pero **ninguna `sceNet*`** (solo 21 funciones `sce*`: audio, ctrl, io, motion,
power, touch).

### 4.2 Parche del loader (hecho, comprobado)
`godot/loader-patches/0001-ros2-vita-imports.patch` añade `bcmp`, `sincosf`, los 11 `sce*` de red y `sceSysmoduleUnloadModule`
a `default_dynlib.c`. **`git apply --check` pasa sobre el commit `d1a5f29`** **[T]**. El loader ya enlaza `SceNet_stub`,
`SceNetCtl_stub` y `SceSysmodule_stub` (`loader/CMakeLists.txt`), así que las direcciones existen.
Si `sincosf` o `bcmp` no estuvieran en la newlib del SDK, alternativas: compilar `viz_math.c` con
`-fno-builtin-sincos` y evitar `==` sobre slices en Rust (usar un bucle) **[?]**.

### 4.3 Red: dos caminos (decisión pendiente, prueba en Vita)
Godot (`drivers/unix`) usa sockets POSIX de newlib, que en VitaSDK delegan en `sceNet`, pero **requieren
`sceSysmoduleLoadModule(SCE_SYSMODULE_NET)` + `sceNetInit(pool)` + `sceNetCtlInit()` previos**, y el motor no lo hace.
- **A. Backend sceNet en `net-udp` (lo que usa hoy la app C):** necesita las 11 entradas del parche y que alguien
  haga la inicialización (el propio `net_udp_init`). Cero cambios en el motor. **Elegido para el hito M5.**
- **B. Inicializar la red en el motor** (`os_vita.cpp`/`godot_vita.cpp`: una función `VitaNet::init()`) y que
  `net-udp` use POSIX en ese runtime. Beneficio añadido: funcionan `ENet`, `UDPServer`, `StreamPeerTCP` de Godot.
  Requiere un parche al motor (propio, pequeño) y mantenerlo al rebasar.
- Ambos exigen decidir el pool de `sceNetInit` (1 MiB hoy en `net-udp`) frente al presupuesto de 365 MiB.

### 4.4 Herramientas entregadas
`tools/check-vita-imports.py` (esta comprobación, con `--nm arm-vita-eabi-nm` en el PC),
`tools/build-rust-pic.sh`, `tools/build-godot-template.sh` (aplica el parche, compila, ejecuta `verify_runtime.py`).

---

## 5. Brechas funcionales frente a `rclgd` (qué falta construir)

| Capacidad | Estado en `ros2_vita` | Nota |
|---|---|---|
| `RosMsg` dinámico (propiedades anidadas, arrays, strings) | **Escrito** (`ros_msg.cpp`), sobre `msg-schema` | sin compilar; pruebas GDScript listas (§8, G1) |
| Pub/Sub/Timer/QoS/Parámetros/`now()` | **Escrito** con transporte `loopback` | `xrce` es un *stub* (M7) |
| Clases sombra GDScript (`Ros*` con `ROS_TYPE_NAME`) | Generables **en el PC con rclgd**; nuestro `RosMsg` acepta la clase como tipo | adjuntar el script al recibir ⇒ opcional (M8) |
| Esquema `.rsch` en el `.pck` | Generador listo (`tools/gen_msg_schema.py`) | hay que **incluir `*.rsch` en el filtro de exportación** (no es recurso) (M8) |
| TF (`tf-tree`) | Módulo listo; **binding pendiente** | sin historial ni *timeouts* (M11) |
| Servicios / Acciones | **no** | XRCE-DDS-RPC **[?]** / más adelante (M12) |
| `/rosout`, `RosLogger` | **no** (consola) | M13 |
| `get_topic_names_and_types`, contadores | **no aplica** | XRCE no expone el grafo |

---

## 6. Qué cambió en el código de `godot/` (3.5 → 4.8)

| Concepto | Godot 3.5 (descartado) | Godot 4.8 in-tree (nuevo) |
|---|---|---|
| Registro | `register_X_types()` | `initialize_X_module(ModuleInitializationLevel)` + `GDREGISTER_CLASS` |
| Objetos de ROS | `Node` + señal | `RefCounted`/`Object` (como rclgd) + `Callable` |
| Bytes | `PoolByteArray` | `PackedByteArray` (`ptrw()`, `write[i]`) |
| Singleton | `Engine::add_singleton(..)` (3.x) | `Engine::get_singleton()->add_singleton(Engine::Singleton("rclgd", obj))` |
| Callbacks | `connect(obj, "metodo")` | `Callable`, lambdas, `await` |
| Hilo principal | `call_deferred` en `Node` | cola protegida con `Mutex` + `SceneTree::process_frame` |
| Registro de proyecto | `config.py` `can_build(env, platform)` | igual; `platform in ("vita","linuxbsd")` |
| Compilación de C | `SCsub` con `env_modules` | igual + `.c` y `File` para `.a` (§3.2) |

Archivos: `config.py`, `SCsub`, `register_types.*`, `ros_msg.*`, `ros_runtime.*` (todos **sin compilar**),
`API_PARITY.md`, `test/` (runner GDScript + `run_host_tests.sh`), `loader-patches/`.
`godot_compat.h` y la rama 3.5 **se eliminaron** (siguen en el historial de git).

---

## 7. Flujo de trabajo y versiones

```
PC (CachyOS)                          Vita
 Godot 4.7.1 + rclgd (apt/colcon)  ─┐   .pck + loader + libgodot.so(+ros2_vita)
   desarrollo contra ROS2 real      ├─► Godot 4.8-dev7 + addon psvita  ──► VPK + ux0:data/<juego>
 mismos .gd/.tscn                  ─┘   (plantilla propia vita_release.zip)
```
- **Sesgo de versión:** rclgd 4.7.1 / runtime 4.8-dev7. Los proyectos se abren en 4.8 y se "convierten"; los
  scripts GDScript usados (lambdas, `await`, tipos) existen en ambos. Riesgo: formato de escena entre 4.7 y
  4.8-dev **[?]** → prueba M15. rclgd (GDExtension `compatibility_minimum=4.7`) podría cargarse en el
  editor 4.8-dev7 del PC **[?]**.
- **Un único `package.xml`/proyecto** puede servir a los dos mundos: en el PC lo construye `colcon`; para la
  Vita se exporta con el addon.
- **Autoload `ROS`** (de rclgd) funciona igual: en la Vita no hay línea de órdenes ⇒ los parámetros salen de
  `ros/parameters/*` y de `ros/agent_ip` (ajustes de proyecto).
- Esquema de tipos: el proyecto declara sus paquetes en `package.xml` (como rclgd); `tools/gen_msg_schema.py`
  produce `res://ros/schema.rsch` (hoy a mano; M8 lo automatiza como paso de exportación).

---

## 8. Puertas de verificación (qué se puede probar dónde)

| Puerta | Dónde | Qué demuestra | Estado |
|---|---|---|---|
| **G0** | laptop | 8 módulos con paridad; `msg-schema` con `type_idx`; parche del loader aplica en `d1a5f29`; `check-vita-imports` funciona; scripts de build con `--dry-run` | **VERDE (2026-10-27)** |
| **G1** | PC (host) | El módulo **compila** contra Godot 4.8 (`platform=linuxbsd custom_modules=…`) y pasa `godot/test` (RosMsg ↔ CDR bit a bit, pub/sub loopback, timers, ejes) | pendiente (intento aquí **bloqueado** por política del entorno) |
| **G2** | PC (cruzada) | C y Rust PIC compilados para ARM; `check-vita-imports` (con `arm-vita-eabi-nm`) sin faltantes tras el parche | pendiente |
| **G3** | PC | `build-godot-template.sh` completa; `verify_runtime.py` PASS; `vita_release.zip` | pendiente |
| **G4** | Vita | Un `.pck` con script que usa `rclgd.init(loopback)` y `RosMsg` arranca; `rclgd.ok()` | pendiente |
| **G5** | Vita + agente | Transporte XRCE: `std_msgs/String` llega a `ros2 topic echo` | pendiente |
| **G6** | Vita + robot | HMI piloto: teleop `/cmd_vel` + `/odom` en pantalla | pendiente |
| **G7** | Vita | IMU (`Input.get_*`) y panel trasero publicados; cámara (decisión de diseño) | pendiente |

---

## 9. Registro de riesgos

| # | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| R1 | Port 4.x joven (un mantenedor, 2D parcial, pantalla negra histórica en la ruta GL) | Alta | Alto | Usar solo la ruta GXM 2D; fijar commit; contribuir arreglos; mantener `vita-app` como app principal |
| R2 | Rust PIC/`core` no pasa `verify_runtime.py` (relocaciones o imports) | Media | Alto | Alternativa: solo C en el módulo (ya es el valor por defecto de `SCsub`) |
| R3 | Faltan más imports de los detectados (`nm` de host aproxima) | Media | Medio | Repetir `check-vita-imports` con `arm-vita-eabi-nm`; ampliar el parche |
| R4 | Mantener parches propios (loader/motor) al rebasar sobre upstream | Media | Medio | Parches pequeños y aislados en `godot/loader-patches/`; proponer a upstream |
| R5 | Sesgo 4.7.1 (rclgd) ↔ 4.8-dev7 (runtime) | Media | Medio | M15; si falla, construir rclgd contra 4.8 o desarrollar en el editor 4.8 |
| R6 | Rendimiento: GDScript a 333–444 MHz, textura recreada por fotograma, CDR de mensajes grandes | Alta | Medio | Medir con `hwprobe`/FPS; imágenes JPEG pequeñas; preferir arrays empaquetados |
| R7 | Sin red hasta M5 (sceNet) | Cierta | Alto | Parche del loader + init de red (opciones A/B) |
| R8 | El editor 4.8-dev7 oficial no se descarga fácilmente / solo Windows | Media | Medio | Preguntar al usuario (Windows disponible) |
| R9 | `class_name` global y `ProjectSettings.get_global_class_list()` en export | Media | Bajo | No dependemos de ello: `RosMsg` acepta tipo por texto |

---

## 10. Backlog de migración

| ID | Tarea | Dónde | Depende de | Estado |
|---|---|---|---|---|
| M1 | Decisión Godot 4 + ADR 0008 aceptado | doc | — | **hecho** |
| M2 | Reescribir módulo a Godot 4 (RosMsg, runtime, pruebas) | laptop | — | **hecho (sin compilar)** |
| M3 | Parche del loader (imports) | laptop | — | **hecho (aplica en d1a5f29)** |
| M4 | Herramientas: `check-vita-imports`, `build-rust-pic`, `build-godot-template` | laptop | — | **hecho** |
| M5 | G1: compilar el módulo en host y pasar `godot/test` | PC | M2 | pendiente |
| M6 | G2: cross-compilar C y Rust PIC; cerrar imports con `arm-vita-eabi-nm` | PC | M3,M4 | pendiente |
| M7 | Red en la Vita (opción A/B) + `XrceTransport` (hilo de sesión, entidades por topic) | PC+Vita | M6 | pendiente |
| M8 | Exportación: `*.rsch` en el filtro, generación de esquemas desde `package.xml`, clases sombra | PC | M5 | pendiente |
| M9 | HMI piloto en Godot (teleop + estado + dock) tomando `roomba_hmi` | PC+Vita | M7,M8 | pendiente |
| M10 | Sensores propios: IMU (ya expuesto), panel táctil trasero (parche `display_server_vita.cpp`), cámara | PC+Vita | M7 | pendiente |
| M11 | Binding de `tf-tree` (`create_tf_broadcaster/listener`) | laptop+PC | M5 | pendiente |
| M12 | Servicios/acciones (XRCE-RPC) y parámetros remotos | PC+Vita | M7 | pendiente |
| M13 | `/rosout` y `RosLogger` | PC | M7 | pendiente |
| M14 | Docs/web/bitácora; páginas a leer (docs/16) | laptop | — | **hecho** |
| M15 | Prueba de sesgo 4.7.1↔4.8-dev7 (escena, extensión rclgd) | PC | — | pendiente |
| M16 | Medidas: coste por mensaje, textura por fotograma, FPS de la HMI | Vita | M9 | pendiente |
| M17 | Vigilar upstream (`godot4-vita` y `rclgd`) y rebasar | continuo | — | continuo |

---

## 11. Preguntas abiertas para el usuario
1. ¿Hay **Windows** (PC o VM) para el editor `Godot4Vita.exe`, o se prefiere el **addon** con el editor 4.8-dev7 oficial en Linux?
2. ¿Red por **opción A** (backend sceNet, sin tocar el motor) o **B** (init de red en el motor + Godot ENet)? Recomiendo A primero.
3. ¿Aceptas mantener un **fork/parche** de godot4-vita para (a) el parche del loader, (b) el panel trasero? Alternativa: parches en este repo (`godot/loader-patches/`), que es lo que se hace ahora.

---

## 12. Fuentes
- godot4-vita: [README](https://github.com/WolffsRoom/godot4-vita), `platform/vita/{README,BUILDING,ROADMAP,UPDATES_2026_10}.md`,
  `detect.py`, `SCsub`, `loader/{main.c,default_dynlib.c,CMakeLists.txt,tls_stubs.c}`, `tools/{verify_runtime.py,build_release_template.sh}`,
  `editor/addons/psvita/platform.gd`.
- rclgd y roomba_ws: ver `docs/17`.
- Micro-XRCE-DDS-Client v2.4.3 y Micro-CDR v2.0.1: compilados en host (perfil de `vita-app/scripts/build-xrce-client-vita.sh`) para analizar símbolos.
- Godot (in-tree): `core/object/class_db.h` (`GDREGISTER_*`), `core/config/engine.h` (`add_singleton`), `modules/jsonrpc` (módulo de referencia), `methods.py` (`add_source_files`).
