# 12 — Investigación: Godot + ROS2 en la PS Vita

> **DECISIÓN 2026-10-27:** el usuario priorizó **Godot 4** (`godot4-vita`); todo lo que esta página dice
> de Godot 3.5 (`godot-vita`, plantillas 3.5, vía B de rosbridge) queda **descartado**: ver
> `docs/18-migracion-a-godot4.md` y el ADR 0008 (Aceptado).
>
> **ACTUALIZACIÓN 2026-10-27 (ROSCon):** se estudió el código fuente completo de
> `rclgd` y `roomba_ws` → **`docs/17-rclgd-estado-del-arte-godot-ros2.md`**.
> Correcciones a esta página: `rclgd` está **mantenido** (v3.0.0, 4 distros con
> CI, última actividad 2026-10-22), exige **Godot 4.7** y su API usa `Callable`/
> `await` (no ejecutable en Godot 3.5); P1 (nombres de la API) queda **cerrado**
> → `godot/ros2_vita/API_PARITY.md`. El límite de 5 argumentos de `bind_method`
> citado en §3 es de Godot 3, no de 4.

**Fecha:** 2026-10-27 · **Estado:** investigación (web) completada; todo lo que
requiere hardware o el PC queda en la lista de pendientes (§8).
**Método:** búsqueda web + lectura de READMEs/issues en GitHub. Cada
afirmación lleva su fuente y una marca de confianza:
**[V]** verificado en la fuente · **[I]** inferencia propia a partir de lo
verificado · **[?]** no pude confirmarlo (hosts bloqueados o sin documentar).

> Regla anti-alucinación (heredada de `docs/10` §10): nada de esta página
> se da por cierto en hardware hasta que se pruebe en la Vita. Lo que no
> pude leer queda como **[?]** y entra en la lista de pendientes.

---

## 1. Resumen ejecutivo (1 minuto)

1. **Godot en la Vita existe, pero hay DOS ports no oficiales y
   mutuamente incompatibles**, con filosofías distintas (§2).
2. **Ninguno soporta GDExtension** (port 4.x: declarado; port 3.x: no
   existe en 3.x) y Rust no soporta enlace dinámico en la Vita **[V]**.
   Consecuencia: la integración de ROS2 en Godot **debe ser un módulo
   C++ estático compilado dentro del motor** (plantilla de exportación
   propia), no una extensión cargable. Esto es el núcleo del ADR 0008.
3. Nuestra arquitectura ya encaja: los módulos duales exponen un
   **header C** (`modules/*/include/*.h`) y se enlazan como staticlib.
   Un módulo estático de Godot es solo otro consumidor de esos headers.
4. El transporte de micro-ROS usa `sceNet` directamente (módulo
   `net-udp`), **no** los sockets de Godot. Por tanto el bloqueo
   `-DUNIX_SOCKET_UNAVAILABLE` de la plantilla oficial 3.5 **[V]** no
   afecta a ROS2 (sí a `PacketPeerUDP` de GDScript).
5. **Conflicto de GPU a resolver** (§6): Godot-Vita y nuestra app
   (ADR 0007: vitaGL dueño del GPU) no pueden convivir en un proceso.
   Decisión propuesta: apps separadas, capa ROS compartida.
6. Para el desarrollo de escritorio existe **rclgd** (Godot 4 + rclcpp)
   **[V]** — sirve como banco de pruebas de la API GDScript, aunque su
   estado es "UNMAINTAINED" en el índice ROS **[V]**.

---

## 2. Estado del arte de Godot en la Vita

| | **godot-vita** (SonicMastr) | **godot4-vita** (WolffsRoom) |
|---|---|---|
| Base | Godot **3.5** (rama `3.x`; basado en Stary2001/EIREXE) **[V]** | Godot **4.8-dev7** fijado **[V]** |
| Gráficos | **PVR_PSP2** (driver GLES2) **[V]**; solo **GLES2** **[V]** | **GXM nativo** para 2D (sin shaders GLES); 3D GXM experimental; vitaGL parcheado como dependencia de build **[V]** |
| Shaders | Compilación en runtime cada arranque (sin caché; GLES2) **[V]** (foro) | CanvasItem/spatial shaders **no** se renderizan **[V]** |
| GDExtension | No aplica (3.x usa GDNative; sin evidencia de soporte) **[?]** | **No soportado** **[V]** |
| C# | No documentado **[?]** | No **[V]** |
| Red | Plantilla oficial 3.5-rc5-vita1 compilada con `-DUNIX_SOCKET_UNAVAILABLE` → sin sockets **[V]** | No documentado **[?]** |
| Exportación | Plantillas `3.5-rc5-vita1` en releases; juegos hechos con 3.x ≤ 3.5-rc5 **[V]** | Editor Windows propio con plataforma "PS Vita" y empaquetado VPK en GDScript **[V]** |
| Memoria | No documentado **[?]** | `ATTRIBUTE2=12` (~365 MiB de usuario), heap newlib grande, CDRAM para GPU, 64 MiB de texturas **[V]** |
| Rendimiento citado | — | OVERBURDEN (3D) ~30 FPS; 2D validado en 4 juegos **[V]** |
| Madurez | 334★, 21 issues abiertos, sin releases en la página **[V]** | Proyecto reciente, solo Windows como editor, UI en portugués **[V]** |

Fuentes:
[godot-vita](https://github.com/SonicMastr/godot-vita) ·
[godot4-vita](https://github.com/WolffsRoom/godot4-vita) ·
[issue #37](https://github.com/SonicMastr/godot-vita/issues/37) (error
0xF0030000 al cambiar el título; arreglado en builds 3.6.beta; las
plantillas deben actualizarse junto con el editor) ·
[plantilla 3.5 con red de Swisha33](https://github.com/Swisha33/Vita-Template-with-network-)
· [foro de Godot](https://forum.godotengine.org/t/create-export-template-for-ps-vita/122770)
(no accesible desde esta sesión; solo conozco el resumen del buscador:
"no soporta nada superior a 3.5", "activar *Fallback to GLES2* o crashea
al arrancar") · [Wololo: Godot 3.5 en Vita](https://wololo.net/2022/07/15/release-godot-game-engine-3-5-ported-to-ps-vita/)
(no accesible).

### Datos útiles ya verificados del ecosistema

- **Compilar la plantilla 3.5:** `scons p=vita target=release tools=no`
  tras instalar VitaSDK con vdpm más `vita-rss-libdl` y `pvr_psp2` (de
  *vita-packages-extra*); ~1–2 h en GitHub Actions **[V]**
  ([Swisha33](https://github.com/Swisha33/Vita-Template-with-network-)).
- **Empaquetado 3.5:** `godot --export-pack "VitaPack" build/game.pck`
  con textura ETC, luego `tools/make_vpk.py`; los PNG de LiveArea deben
  ser **8 bits indexados** **[V]**.
- **Red en 3.5 con sockets habilitados:** funcionan HTTP plano, TCP/UDP
  (`StreamPeerTCP`, `PacketPeerUDP`, `UDPServer`) y `ws://`; **no hay
  HTTPS/TLS ni `wss://`** **[V]** (aún en verificación en hardware por
  su autor).
- **Port 4.x:** carga `game.pck` con `--main-pack`; ~150 ms por búsqueda
  de recurso suelto, así que se debe usar pack **[V]**. El loader
  (`eboot.bin`) mapea y reubica una `libgodot.so` PIC **[V]**.
- **Libs de la Vita para GPU:** vitaGL exige `libshacccg.suprx`
  extraído y descifrado en la consola **[V]**; flags de compilación
  útiles: `NO_DEBUG=1`, `HAVE_SHADER_CACHE=1`, `HAVE_TEXTURE_CACHE=1`,
  `HAVE_PROFILING=1`, `HAVE_DEBUGGER=1` **[V]**
  ([vitaGL README](https://github.com/Rinnegatamante/vitaGL)).

---

## 3. Cómo se escribe una integración nativa en Godot

Godot ofrece tres mecanismos para código nativo:

| Mecanismo | Carga | ¿Sirve en la Vita? |
|---|---|---|
| **Módulo C++** (`modules/<nombre>/`) | Estático, compilado en el motor con SCons | **SÍ** — único camino viable |
| GDNative (3.x) / GDExtension (4.x) | Biblioteca dinámica (`.so`) | **NO** — Rust no soporta enlace dinámico en la Vita **[V]**; port 4.x lo declara no soportado **[V]** |
| GDScript puro + sockets | Script | Solo si la plantilla trae sockets (§5, vía B) |

**Estructura de un módulo (Godot 3.x)** **[V]**
([docs 3.5](https://github.com/godotengine/godot-docs/blob/3.5/development/cpp/custom_modules_in_cpp.rst)):

```
modules/ros2_vita/
├── config.py            # can_build(env, platform) y configure(env)
├── SCsub                # env.add_source_files(env.modules_sources, "*.cpp")
├── register_types.h/cpp # register_ros2_vita_types() / unregister_...()
└── ros_node.h/cpp       # class RosNode : public Node { GDCLASS(RosNode, Node) ... }
```

- Métodos expuestos con `ClassDB::bind_method(D_METHOD("nombre","arg"), &Clase::metodo)`;
  el límite por defecto es 5 parámetros (13 con `method_bind_ext.gen.inc`) **[V]**.
- Se compila con `scons custom_modules=../mi_carpeta` (o dentro de
  `modules/`) **[V]**. Ojo: **Godot 4 cambia la API de registro**
  (`initialize_<mod>_module(ModuleInitializationLevel)`) **[I]**, de modo
  que el módulo necesita una capa fina por versión.
- Señales, hilos y enlazado de librerías externas estáticas **no** los
  pude leer en la documentación (**[?]**): quedan como pendientes del PC.
  Lo conocido por práctica común de Godot 3: `ADD_SIGNAL(MethodInfo(...))`
  en `_bind_methods` y `call_deferred()`/cola propia para pasar datos de
  hilos de red al hilo principal **[I]**.
- Las **plataformas personalizadas** de Godot no requieren tocar el
  código existente (carpeta `platform/<x>` + `detect.py`), pero para
  consolas la documentación advierte que es un proceso largo
  ([docs](https://docs.godotengine.org/pt-br/4.x/engine_details/engine_api/custom_platform_ports.html)).
  **No** haremos un port de Godot: reutilizamos uno existente.

**Conclusión §3:** nuestros headers C + staticlibs (Rust o C) se enlazan
al motor desde el `SCsub` del módulo (`env.Append(LIBS=[...], LIBPATH=[...])`
**[I]**), reutilizando exactamente lo ya validado en hardware.

---

## 4. Funcionamiento interno de nuestra pila ROS2 en la Vita (mapa)

```
 Godot/GDScript o app C ──► API alto nivel (futuro: ros-facade)
                                   │
              micro-XRCE-DDS Client v2.4.3 (+ Micro-CDR v2.0.1)   ← cross-compilado
                                   │  callbacks open/close/write/read
                  modules/microros-transport  (dual C/Rust)
                                   │
                        modules/net-udp  (dual C/Rust)  ──► sceNet (UDP)
                                   │            ▲
                        modules/mem-pool (dual) │  (asignaciones acotadas)
                                   ▼            │
        WiFi ──► micro-ROS Agent (laptop, docker --net=host --ipc=host)
                                   ▼
                         grafo ROS2 Jazzy (Fast-DDS)
```

Parámetros de compilación del cliente XRCE que podemos ajustar para
optimizar (extraídos del `CMakeLists.txt` del cliente, defaults reales
**[V]**; los marcados ★ se usan hoy en `build-xrce-client-vita.sh`):

| Variable | Default | Nota para la Vita |
|---|---|---|
| `UCLIENT_PROFILE_UDP/TCP/SERIAL/DISCOVERY` | ON | ★ apagados: usamos transporte custom |
| `UCLIENT_PROFILE_CUSTOM_TRANSPORT` | ON | ★ activo |
| `UCLIENT_CUSTOM_TRANSPORT_MTU` | 512 | **Subirlo a ~1400** reduce fragmentación en WiFi (MTU Ethernet 1500) **[I]** |
| `UCLIENT_MAX_OUTPUT_RELIABLE_STREAMS` / `INPUT_*` | 1 / 1 | Más streams permiten separar teleop de visualización **[I]** |
| `UCLIENT_MAX_OUTPUT_BEST_EFFORT_STREAMS` | 1 | idem |
| `UCLIENT_MIN_HEARTBEAT_TIME_INTERVAL` | 100 ms | Bajar mejora latencia de los reliable, sube tráfico |
| `UCLIENT_MAX_SESSION_CONNECTION_ATTEMPTS` | 10 | — |
| `UCLIENT_PROFILE_MULTITHREAD` | OFF | ★ apagado. **Necesario** si la sesión se atiende desde un hilo distinto al que crea entidades (caso Godot) **[I]** |
| `UCLIENT_PROFILE_SHARED_MEMORY` | OFF | Solo para varios clientes en el mismo proceso; no aplica |
| `UCLIENT_PROFILE_STREAM_FRAMING` | ON | Solo serial; innecesario en UDP **[I]** |
| `UCLIENT_TWEAK_XRCE_WRITE_LIMIT` | ON | permite writes > 64 kB |

Fuente: [Micro-XRCE-DDS-Client/CMakeLists.txt](https://raw.githubusercontent.com/eProsima/Micro-XRCE-DDS-Client/master/CMakeLists.txt).
En `main.c` hoy: `STREAM_BUFFER_SIZE 4096`, `STREAM_HISTORY 4`.

Referencias de memoria de micro-ROS (otro hardware, orden de magnitud,
**no** extrapolar a la Vita): ~400 B por publisher y ~8.7 kB por
subscriber con UDP, creación XML, history 4, MTU 512
([ROSCon 2020, Finocchiaro](https://micro.ros.org/download/ROSCon2020-FrancescaFinocchiaro.pdf)
— referencia vía buscador; el host estaba bloqueado). La **creación por
referencia** reduce memoria frente a XML **[V buscador]**. La Vita tiene
512 MB de RAM, así que la memoria *no* es el cuello de botella: lo son
la latencia WiFi y el hilo único de `uxr_run_session_time`.

**Alternativas de middleware** (investigadas, no adoptadas):
- *zenoh-pico / rmw_zenoh*: mejor en WiFi/4G que DDS en un estudio de
  escritorio ([arXiv 2309.07496](https://arxiv.org/abs/2309.07496v2)),
  pero el puerto a MCU está menos maduro que micro-ROS y no hay
  benchmark XRCE vs zenoh-pico **[V buscador]**. Se deja como **ADR
  futuro**, no como trabajo actual.

---

## 5. Tres vías para tener ROS2 en Godot (de menor a mayor esfuerzo)

| Vía | Qué es | Pros | Contras | Estado |
|---|---|---|---|---|
| **A. PC de desarrollo con rclgd** | Godot 4 de escritorio + `rclgd` (GDExtension sobre rclcpp, Jazzy) para prototipar escenas y scripts contra ROS2 real | Cero código nuestro; itera sin Vita | No corre en la Vita; estado UNMAINTAINED **[V]** | Disponible; **probar en el PC** |
| **B. rosbridge por `ws://`** | GDScript (`WebSocketClient`) ↔ `rosbridge_server` en la laptop ↔ ROS2 | Sin código nativo; solo requiere plantilla 3.5 **con red** | JSON pesado, depende de un servidor; sin TLS | Prototipado rápido; **pendiente** |
| **C. Módulo estático `ros2_vita`** (recomendada) | Módulo C++ que envuelve XRCE + nuestros módulos duales, expone `RosNode` a GDScript | Rendimiento real, sin PC intermedio salvo el agente, reutiliza lo validado | Hay que compilar una plantilla de Godot propia (1–2 h por build) | **Diseño en ADR 0008; implementación pendiente** |

**Idea clave:** diseñar la API GDScript de la vía C **compatible con la
de rclgd** (publicar/suscribir/tipos por nombre) para que *el mismo
script* corra en el PC (vía A) y en la Vita (vía C). Los nombres exactos
de la API de rclgd **[?]** (docs bloqueados): primera tarea del PC.
Lo que sí sé de su arquitectura **[V buscador]**: usa `ros_babel_fish`
para mensajes sin recompilar, el *executor* gira en un hilo aparte y los
callbacks se difieren al hilo principal de Godot — el mismo patrón que
proponemos (cola SPSC entre hilo de red y hilo principal).

Fuente: [rclgd](https://rclgd.readthedocs.io/) · [índice ROS](https://index.ros.org/p/rclgd/).

---

## 6. Conflicto de GPU y decisión de procesos

- ADR 0007: **vitaGL es el único dueño del GPU** y no se puede cerrar
  (sin `sceGxmTerminate`, `eglTerminate` es no-op) **[V, repo]**.
- godot-vita 3.5 usa PVR_PSP2 (otro camino a GXM); godot4-vita usa GXM
  directo **[V]**. **Ninguno de los dos puede coexistir con vitaGL en el
  mismo proceso** **[I]** (dos inicializadores del mismo GPU).
- Además, Godot-4 Vita no renderiza shaders propios y su 3D es
  experimental **[V]** → un "mini-rviz dentro de Godot" estaría muy
  limitado frente a nuestro mini-rviz vitaGL ya validado.

**Decisión propuesta (ADR 0008):** **dos aplicaciones/VPK independientes
que comparten la capa ROS** (módulos duales + XRCE):

| App | Motor | Para qué |
|---|---|---|
| `vita-ros2` (actual) | C + vitaGL | Teleop (Obj. 2), mini-rviz (Obj. 3/4), sensores (Obj. 5) |
| `vita-ros2-godot` (nueva) | Godot + módulo `ros2_vita` | Paneles/HUD/juegos de control hechos en el editor de Godot |

La única restricción es que **no se ejecuten a la vez** (RAM/GPU/puerto
de netlog).

---

## 7. Rust nativo en la Vita (estado verificado)

Fuente: [Rust platform support: armv7-sony-vita-newlibeabihf](https://raw.githubusercontent.com/rust-lang/rust/master/src/doc/rustc/src/platform-support/armv7-sony-vita-newlibeabihf.md).

- Target **Tier 3**; mantenedores nikarh, pheki y zetanumbers **[V]**.
- Sin binarios precompilados: `-Z build-std=std,panic_abort` con
  nightly **[V]** (el repo ya lo hace; ADR 0003).
- `std` **parcial** (`std::process` devuelve error); `#![no_std]` es
  viable con `core` + opcional `alloc` **[V]**.
- Sin enlace dinámico; ELF Thumb enlazado con `arm-vita-eabi-gcc` **[V]**.
- No hay filtrado de tests (la Vita no recibe argumentos) y la suite de
  `library/std` no está soportada **[V]**.
- `cargo-vita` (`cargo +nightly install cargo-vita`) ofrece `build vpk`,
  `upload` (FTP), `run`, `logs` (TCP, PrincessLog), `coredump`,
  `reboot` y configuración en `[package.metadata.vita]`; por defecto
  usa `vita_mksfoex_flags = ["-d","ATTRIBUTE2=12"]` **[V]**
  ([cargo-vita](https://github.com/vita-rust/cargo-vita)).
- **godot-rust (gdext) queda descartado** en la Vita: necesita
  GDExtension/enlace dinámico **[I]**. Rust entra en Godot **solo vía
  staticlib con ABI C** (el crate paraguas actual), igual que hoy.

**Hallazgo accionable:** nuestro `vita-app/CMakeLists.txt` no pasa
`ATTRIBUTE2=12` a `mksfoex` (grep del 2026-10-27), mientras que
cargo-vita y godot4-vita lo usan para ampliar la memoria de usuario
(~365 MiB) **[V]**. La app actual no lo necesita; **una app Godot sí**
→ pendiente de validar en hardware antes de la app Godot.

---

## 8. Pendientes (todo lo que NO se pudo hacer sin Vita/PC)

| # | Pendiente | Dónde | Bloquea |
|---|---|---|---|
| P1 | ~~Leer la API real de rclgd~~ **CERRADO 2026-10-27** (docs/17, API_PARITY.md) | — | — |
| P2 | Compilar `godot-vita` 3.5 desde fuente (`scons p=vita target=release tools=no`) con sockets habilitados y confirmar versión exacta/commit a fijar | PC | vía B y C |
| P3 | Probar `godot4-vita` (editor Windows) — ¿hay Windows? Si no, evaluar build Linux de la plantilla | PC | vía C 4.x |
| P4 | Módulo `ros2_vita` mínimo: `RosNode.publish_string()` hacia `/vita_hello` | PC + Vita | vía C |
| P5 | Medir RAM libre y FPS de un "hola mundo" Godot en Vita | Vita | decisión 3.5 vs 4.x |
| P6 | Validar `ATTRIBUTE2=12` en nuestra app y su efecto en RAM | Vita | app Godot |
| P7 | Decidir `UCLIENT_CUSTOM_TRANSPORT_MTU` (1400) y streams con medición de latencia | Vita + laptop | optimización |
| P8 | `libshacccg.suprx` instalado (ShaRKF00D) si Godot/vitaGL lo pide | Vita | gráficos |
| P9 | Confirmar sockets/`ws://` de la plantilla 3.5-con-red en hardware (vía B) | Vita | vía B |
| P10 | Leer docs de módulos Godot sobre señales/hilos/enlazado estático (host bloqueado desde esta sesión) | PC | módulo C++ |
| P11 | ¿Vita3K sirve para CI de VPK? (red/sceNet sin documentar) | PC | tests |

---

## 9. Fuentes

- [SonicMastr/godot-vita](https://github.com/SonicMastr/godot-vita) · [issue #37](https://github.com/SonicMastr/godot-vita/issues/37)
- [WolffsRoom/godot4-vita](https://github.com/WolffsRoom/godot4-vita)
- [Swisha33/Vita-Template-with-network-](https://github.com/Swisha33/Vita-Template-with-network-)
- [Bunkai9448/GodotVitaSystemTest](https://github.com/Bunkai9448/GodotVitaSystemTest)
- [Rinnegatamante/vitaGL](https://github.com/Rinnegatamante/vitaGL)
- [vitasdk/vdpm](https://github.com/vitasdk/vdpm) (no documenta dónde viven `pvr_psp2`/vitaGL)
- [vita-rust/cargo-vita](https://github.com/vita-rust/cargo-vita)
- [Rust: armv7-sony-vita-newlibeabihf](https://raw.githubusercontent.com/rust-lang/rust/master/src/doc/rustc/src/platform-support/armv7-sony-vita-newlibeabihf.md)
- [eProsima Micro-XRCE-DDS-Client](https://github.com/eProsima/Micro-XRCE-DDS-Client) · [CMakeLists](https://raw.githubusercontent.com/eProsima/Micro-XRCE-DDS-Client/master/CMakeLists.txt)
- [micro-ROS-Agent](https://github.com/micro-ROS/micro-ROS-Agent) (transportes UDP/TCP/serial)
- [Godot: módulos C++ (3.5)](https://github.com/godotengine/godot-docs/blob/3.5/development/cpp/custom_modules_in_cpp.rst)
- [Godot: plataformas personalizadas](https://docs.godotengine.org/pt-br/4.x/engine_details/engine_api/custom_platform_ports.html)
- [rclgd](https://rclgd.readthedocs.io/) · [índice ROS](https://index.ros.org/p/rclgd/)
- [Zenoh: zenoh-pico](https://zenoh.io/blog/2022-06-09-zenoh-pico-above-and-beyond/) · [arXiv 2309.07496](https://arxiv.org/abs/2309.07496v2)
