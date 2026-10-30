# 19 — Plan multiagente para la migración a Godot 4 + ROS2 en la Vita

> **Para qué sirve:** este documento es la **hoja de ruta ejecutable** para que varios agentes de
> Claude (subagentes o sesiones en paralelo) completen la migración a Godot 4 (`godot4-vita`) con
> ROS2 nativo vía micro-ROS, incluidos los forks y ports necesarios. Contiene: el **mapa jerárquico**
> de todo lo que hay que migrar o actualizar (§3), las **ramas de ataque** estudiadas (§2), el
> **reparto por agentes** (15 agentes A —A0–A13 y A7b— + 6 de la escuadra K de rclgd/skills) con propiedad de ficheros (§4–§5), las **oleadas** y dependencias (§6), el
> **protocolo** de coordinación (§7) y los **briefs** listos para copiar como prompt (§9).
>
> Base: `docs/18` (estudio de migración), ADR 0008 (Aceptado), `godot/ros2_vita/API_PARITY.md`.
> Fecha: 2026-10-27. Marcas: **[V]** verificado en código/ejecución, **[I]** inferido, **[?]** por comprobar.

---

## 1. Decisiones de partida (no se reabren sin el usuario)

| # | Decisión | Fuente |
|---|---|---|
| D1 | Godot **4** con el port `godot4-vita` (4.8-dev7); 2D/HMI primero (render GXM nativo) | ADR 0008 §5 |
| D2 | **Red: opción A** — `net-udp` inicializa `sceNet` y XRCE usa sus sockets; el motor no se toca para la red | Usuario, 2026-10-27; docs/18 §4.3 |
| D3 | Solo **Linux** (portátil) y **CachyOS** (PC). Sin Windows ⇒ addon `psvita` + editor 4.8-dev7 Linux | Usuario |
| D4 | Desarrollo con el **Godot 4.7.1 que descarga rclgd** (`ros2 rclgd editor`); un 2.º editor 4.8-dev7 solo exporta | Usuario + `rclgd/CMakeLists.txt` [V] |
| D5 | **Fork de godot4-vita solo si hace falta**, con parches mínimos proponibles a upstream; prioridad: compatibilidad con el entorno estándar | Usuario |
| D6 | El **SDK/módulos Rust no dependen de Godot**: Godot es un consumidor más (junto a `vita-app` y una futura app `cargo-vita`) | docs/18 §3 |
| D7 | API GDScript objetivo = la de **rclgd** (mismo script en PC y Vita) | ADR 0008 §4 |
| D8 | Reglas del repo: paridad C/Rust nunca en rojo; docs en español; marcas «validar en el PC / en hardware» | CLAUDE.md |

---

## 2. Ramas de ataque estudiadas (qué se elige y qué se vigila)

### 2.1 Ramas de los repositorios upstream **[V]** (`git ls-remote`, 2026-10-27)

| Repo | Rama/etiqueta | Qué es | Uso en el plan |
|---|---|---|---|
| `WolffsRoom/godot4-vita` | `main` @ `d1a5f29` | estado actual del port | **Base fijada** (el parche del loader aplica) |
| | `release/v0.1` @ `80ecc08` | mismo **código** que `main`; solo cambia `README.md` (`git diff --stat`) | equivalente; sin valor extra |
| | etiqueta `v0.1` @ `cd85955` | versión anterior (24 ficheros distintos, sobre todo docs/ejemplos) | alternativa conservadora; el parche **también aplica** (`git apply --check`) |
| `Ozuba/rclgd` | `rolling` @ `4d0a8b3` (HEAD por defecto, v3.0.0) | estudiado en docs/17 | referencia de API |
| | **`jazzy`** @ `aeb82b3` | rama de nuestra distro; difiere de `rolling` en `README.md`, `ros_type_utils.hpp` y el `.gdextension` de la plantilla; `GODOT_VERSION "4.7.1"` igual | **la que instala el usuario en el PC** |
| | `kilted`, `lyrical` | otras distros | ignorar |
| | ~~`feature/native-msg-classes`~~ @ `92ef998` (2026-10-26) | clases tipadas nativas desde `package.xml`; **elimina** las clases sombra y `RosMsg.gen_editor_support`. **Fusionada en `rolling` (`bfbda5c`) y `jazzy` (`fb12a65`) el 2026-10-28**; la rama ya no existe [V 2026-10-29] | **adoptar** (§2.3, rama R-N) |
| | `main` (2026-10-21), `colcon` (2026-01) | históricas | ignorar |
| `Ozuba/roomba_ws` | `main` @ `8332acb` | taller ROSCon | fuente de la HMI piloto |

### 2.2 Ramas técnicas (estrategias) y elección

| Rama | Descripción | Estado / elección |
|---|---|---|
| **R-M** Módulo en árbol | `godot/ros2_vita` compilado dentro del motor (`custom_modules=`) | **Base elegida**; escrita, sin compilar (G1) |
| **R-G** GDExtension estática | Escribir `ros2_vita` contra **godot-cpp** y en la Vita cargarlo **enlazado estáticamente** con `GDExtensionManager::load_extension_from_function()` (existe en el core de godot4-vita, `core/extension/gdextension_manager.h:72` **[V]**; `dlopen` es un stub nulo, `loader/dl_stubs.c` **[V]**). En el PC el mismo código sería una GDExtension dinámica cargable en el **editor 4.7.1 de rclgd** ⇒ **pruebas sin compilar el motor**. | **Spike** (agente A7b). Riesgos: godot-cpp en un `.so` `-nostdlib` (imports de libstdc++) **[?]**; choque de nombres con rclgd si se cargan juntos (no se cargan juntos: proyecto de pruebas aparte) |
| **R-N** Clases tipadas nativas | Igual que la rama `feature/native-msg-classes` de rclgd: registrar `RosGeometryMsgsTwist`… como clases reales derivadas de `RosMsg`, desde el **esquema `.rsch`** (no hace falta ament ni babel_fish). En R-M se haría con `ClassDB::register_extension_class(ObjectGDExtension*)` (existe en `core/object/class_db.h:304` **[V]**); en R-G con `classdb_register_extension_class6`, como rclgd. | **Adoptar** — rclgd ya la fusionó (2026-10-28). No se implementan clases sombra (T3.2.3 descartada); hasta T3.2.4, scripts portables con tipos por texto (`API_PARITY.md`) |
| **R-RENDER** | GXM 2D (validado en juegos) / GXM 3D experimental / VitaGL-GLES3 (atascado) | **GXM 2D**; 3D solo pruebas |
| **R-NET** | A (elegida) / B (init en el motor) | **A**; B queda como posible PR a upstream si algún día se quiere ENet de Godot |
| **R-LANG** | Código del `.so`: solo C / C + Rust PIC `core` | **C primero** (ya validado en Fase 1); Rust PIC cuando pase `verify_runtime.py` (R2) |
| **R-XRCE-API** | Entidades por XML (`uxr_buffer_create_*_xml`, como `vita-app`) / binario (`*_bin`) **[?]** / referencias | **XML primero** (probado en hardware en Fase 1); binario como optimización medida |
| **R-THREAD** | Sesión XRCE en hilo propio con colas (rx: `Mutex`+`List`; tx: `msg-ring` SPSC) / perfil `UCLIENT_PROFILE_MULTITHREAD` | **Hilo propio + colas** |
| **R-EXPORT** | editor 4.8-dev7 Linux oficial (instantánea *dev*) **[?]** / compilarlo desde la etiqueta `4.8-dev7` / parchear el control de versión del addon | 1.ª opción si existe; si no, compilar; el parche del addon solo como último recurso (formato de recursos) |

### 2.3 Impacto de las clases nativas de rclgd (antes `feature/native-msg-classes`, **fusionadas el 2026-10-28**) en nuestro diseño **[V]** (CHANGELOG *Forthcoming*)
> Actualización 2026-10-29: skill `rclgd` y `API_PARITY.md` revisadas contra `jazzy@fb12a65`. rclgd lee
> `depend`/`exec_depend`/`build_depend` de `res://package.xml` y resuelve en el índice ament; la Vita lo hará
> desde el `.rsch`. rclgd usa `thread_local` al construir: el módulo en árbol debe evitarlo (TLS a medias).
- Toda interfaz de las dependencias de `res://package.xml` se registra al arrancar como clase nativa
  (`Ros` + PascalCase) con propiedades tipadas, `new()` y ayuda del editor. **Breaking:** desaparecen
  `addons/rclgd/gen`, el plugin y `RosMsg.gen_editor_support`; un script pasado como tipo ya no se
  resuelve por `ROS_TYPE_NAME`; los juegos exportados necesitan `package.xml` en el filtro de no-recursos.
- **Para la Vita encaja mejor que las clases sombra**: el `.rsch` ya contiene los campos y tipos; la
  Vita registraría las mismas clases desde él. Requisito nuevo: el esquema debe cargarse **antes** de que
  GDScript analice los scripts (inicialización del módulo, nivel `SCENE`, con `res://` ya montado **[I]**).
- Acción: tareas **T3.2.4** y **T5.3.2** (§3); vigilancia en **A1**.

---

## 3. Mapa jerárquico de todo lo que hay que migrar / actualizar

Formato: `ID  Elemento — dueño · máquina · puerta · estado`. Máquinas: **L** laptop, **P** PC CachyOS,
**V** Vita. Estados: ✅ hecho · 🟡 escrito sin compilar · ⏳ pendiente · 🔭 vigilar.

```
0. GOBIERNO Y DECISIONES
├─ T0.1  ADR 0008 aceptado (Godot 4, red A, fork mínimo) ................ A0 · L · —  · ✅
├─ T0.2  Plan multiagente (este doc) + mapa ............................. A0 · L · —  · ✅
├─ T0.3  Tablero de estado (§8) y bitácora/fases.ts al cerrar hitos ..... A0 · L · —  · continuo
└─ T0.4  Decisiones pendientes del usuario (§10) ........................ A0 · — · —  · ⏳

1. MOTOR / RUNTIME godot4-vita (upstream + fork mínimo)
├─ 1.1 Fijación y fork
│  ├─ T1.1.1 Fijar base `d1a5f29` (alternativa `v0.1`) en build-godot-template.sh .. A2 · L · G0 · ✅
│  ├─ T1.1.2 Crear fork `Jcrex/godot4-vita` SOLO si un parche no cabe como serie ... A2 · P · —  · ⏳ (M19)
│  ├─ T1.1.3 Rama del fork `psvita-ros/base` = upstream + serie `godot/loader-patches` A2 · P · G3 · ⏳
│  └─ T1.1.4 Procedimiento de rebase sobre upstream (script + check) ............ A2 · P · G3 · ⏳ (M17)
├─ 1.2 Loader (eboot) y tabla de imports
│  ├─ T1.2.1 Parche 0001: bcmp, sincosf, 11 sce* de red, sysmodule ................ A2 · L · G0 · ✅
│  ├─ T1.2.2 Repetir clausura de imports con `arm-vita-eabi-nm` sobre objetos reales A4 · P · G2 · ✅
│  ├─ T1.2.3 Parches 000N para lo que falte (pthread, time, rand…) ................ A2 · P · G2 · ⏳
│  └─ T1.2.4 Proponer los parches a upstream (PR) ................................ A2 · P · —  · ⏳
├─ 1.3 Compilación de la plantilla
│  ├─ T1.3.1 G1 host: Godot 4.8 linuxbsd + custom_modules=godot → godot/test ...... A2 · P · G1 · ✅
│  ├─ T1.3.2 G3 Vita: build-godot-template.sh → verify_runtime.py PASS ............ A2 · P · G3 · ✅
│  └─ T1.3.3 Medir tamaño/tiempo de arranque de libgodot.so con ros2_vita ......... A11 · V · G4 · ⏳
├─ 1.4 Entrada y sensores en el motor
│  ├─ T1.4.1 IMU ya expuesta (Input accel/gyro/gravity) → verificar valores/ejes .. A9 · V · G7 · ⏳
│  ├─ T1.4.2 Panel táctil trasero (parche display_server_vita.cpp) ................ A9 · P · G7 · ⏳
│  └─ T1.4.3 Cámara: actualización de textura sin recrearla (texture_2d_update) .. A9 · P · G7 · ⏳
└─ 1.5 Red en el motor (opción B) .............................................. — · — · —  · ✗ descartada (D2)

2. CAPA ROS DUAL (módulos C+Rust, independientes de Godot)
├─ 2.1 net-udp dentro de libgodot.so (opción A)
│  ├─ T2.1.1 Idempotencia de net_udp_init frente a una red ya iniciada (EEXIST) .. A5 · L · G0 · ⏳
│  ├─ T2.1.2 Pool de sceNetInit (1 MiB) y su sitio (.bss del .so) frente a 365 MiB A5 · P · G3 · ⏳
│  ├─ T2.1.3 Estado WiFi (sceNetCtlInetGetState) antes de abrir; error claro ...... A5 · L/V · G5 · ⏳
│  ├─ T2.1.4 net_udp_shutdown al salir del juego / suspensión de la consola ...... A5 · V · G5 · ⏳
│  └─ T2.1.5 Añadir sceNetCtlInetGetState (y lo que use) al parche del loader ..... A5+A2 · L · G0 · ⏳
├─ 2.2 microros-transport y cliente XRCE
│  ├─ T2.2.1 Compilar microxrcedds_client + microcdr PIC para el .so .............. A4 · P · G2 · ✅
│  ├─ T2.2.2 Compilar el cliente XRCE para HOST (docker) → pruebas contra el agente A6 · L · H1 · ⏳
│  └─ T2.2.3 Ajustes XRCE (MTU, historia, heartbeat) — plan E1 de docs/13 ......... A6 · V · G5 · ⏳
├─ 2.3 Núcleo de sesión XRCE en C, sin tipos de Godot (nuevo: `ros2_vita/xrce_core.c`)
│  ├─ T2.3.1 API C: start/stop/advertise/subscribe/publish/poll + callback rx ...... A6 · L · H1 · ⏳
│  ├─ T2.3.2 Hilo de sesión + cola tx (msg-ring SPSC) + cola rx ................... A6 · L · H1 · ⏳
│  ├─ T2.3.3 Entidades XML por topic; nombres DDS rt/… y pkg::msg::dds_::T_ ....... A6 · L · H1 · ⏳
│  ├─ T2.3.4 Mapeo RosQoS → stream reliable/best-effort, depth, durability ........ A6 · L · H1 · ⏳
│  ├─ T2.3.5 Reconexión (uxr_ping_agent_session) y sincronía de reloj (now()) ..... A6 · L · H1 · ⏳
│  └─ T2.3.6 ¿Versión dual Rust? (decidir tras medir; no bloquea) .................. A13 · — · —  · ⏳
├─ 2.4 msg-schema y tipos
│  ├─ T2.4.1 Generador desde package.xml (cerrar dependencias como rclgd) .......... A7 · L · G0 · ⏳
│  ├─ T2.4.2 Cruzar fixtures con rclpy real (robotnik_dev) ........................ A7 · L · G0 · ⏳
│  └─ T2.4.3 Coste por mensaje en ARM (Imu, LaserScan, Image) ..................... A11 · V · G5 · ⏳
├─ 2.5 tf-tree / viz-math / msg-ring / mem-pool: compilar PIC y medir ............ A4 · P · G2 · ✅
└─ 2.6 Coexistencia con vita-app (ELF estático): ningún cambio rompe Fase 1-4 ..... A11 · L · G0 · continuo

3. MÓDULO GODOT ros2_vita (API = rclgd)
├─ 3.1 Infraestructura del módulo
│  ├─ T3.1.1 config.py/SCsub/register_types (Godot 4) ............................ A8 · L · G1 · ✅
│  ├─ T3.1.2 SCsub: compilar xrce_core.c, uxr/microcdr PIC como File nodes ........ A4 · P · G1 · ⏳
│  └─ T3.1.3 (rama R-G) spike godot-cpp + load_extension_from_function ............ A7b · L/P · G1' · ⏳
├─ 3.2 RosMsg
│  ├─ T3.2.1 RosMsg dinámico sobre msg-schema (_get/_set, Packed*) ................ A7 · L · G1 · ✅
│  ├─ T3.2.2 Carga del esquema: res://ros/schema.rsch al iniciar el módulo ........ A7 · L · G1 · ✅
│  ├─ T3.2.3 ~~Clases sombra GDScript~~ — descartada: rclgd ya no las usa (2026-10-28) A7 · — · —  · ✗
│  └─ T3.2.4 Clases tipadas NATIVAS desde el esquema (rama R-N; rclgd ya las tiene) A7 · L · G1 · ⏳
├─ 3.3 Runtime
│  ├─ T3.3.1 Singleton rclgd, init(args), ok, shutdown, ros_ready ................. A8 · L · G1 · ✅
│  ├─ T3.3.2 RosNode: pub/sub/timer, ~ y relativos, parámetros locales ............ A8 · L · G1 · ✅
│  ├─ T3.3.3 LoopbackTransport (pruebas) ......................................... A8 · L · G1 · ✅
│  ├─ T3.3.4 XrceTransport = envoltura Godot de xrce_core.c ....................... A6 · L/P · G5 · ⏳
│  ├─ T3.3.5 now() sincronizado con el agente ..................................... A6 · V · G5 · ⏳
│  └─ T3.3.6 Señales de error de red/estado (ros_ready, ros_lost) ................. A8 · L · G1 · ⏳
├─ 3.4 Paridad de API pendiente
│  ├─ T3.4.1 TF: create_tf_broadcaster / create_tf_listener sobre tf-tree ......... A8 · L · G1 · ⏳ (M11)
│  ├─ T3.4.2 RosLogger + /rosout ................................................. A8 · L · G5 · ⏳ (M13)
│  ├─ T3.4.3 Servicios (XRCE requester/replier) + await req.completed ............ A8 · P/V · G5 · ⏳ (M12)
│  ├─ T3.4.4 Acciones (sobre servicios + topics; muy posterior) .................. A8 · — · —  · ⏳
│  └─ T3.4.5 Mantener API_PARITY.md al día con cada versión de rclgd ............. A1 · L · —  · continuo
└─ 3.5 Pruebas del módulo
   ├─ T3.5.1 godot/test: runner GDScript (24 fixtures, loopback, timers, ejes) .... A11 · P · G1 · ✅
   ├─ T3.5.2 Pruebas del XrceTransport en host contra el agente (docker) .......... A11 · L/P · H1 · ⏳
   └─ T3.5.3 Mismo script de prueba en el editor de rclgd (PC) y en la Vita ....... A11 · P/V · G5 · ⏳

4. TOOLCHAIN Y BUILD
├─ T4.1 tools/vita-doctor.sh (Godot 4) ......................................... A4 · L · G0 · ✅
├─ T4.2 tools/check-vita-imports.py ............................................ A4 · L · G0 · ✅
├─ T4.3 tools/build-rust-pic.sh (nightly, -Zbuild-std=core, PIC) ................ A4 · P · G2 · ✅
├─ T4.4 tools/build-godot-template.sh (base fijada + parches + verify) .......... A2 · P · G3 · ✅
├─ T4.5 Script de build PIC del cliente XRCE (variante de vita-app/scripts) ..... A4 · P · G2 · ✅
├─ T4.6 Imagen docker de host para H1 (cliente XRCE + agente) .................. A11 · L · H1 · ⏳
└─ T4.7 CI ligera (GitHub Actions): paridad + host tests + web build ........... A11 · L · —  · ⏳ (opcional)

5. FLUJO DE TRABAJO Y EXPORTACIÓN
├─ 5.1 Editores
│  ├─ T5.1.1 rclgd (rama jazzy) en el PC; `ros2 rclgd editor` (4.7.1) ............ A3 · P · —  · ⏳
│  ├─ T5.1.2 Editor 4.8-dev7 Linux (descarga dev o compilar etiqueta 4.8-dev7) .... A3 · P · G3 · ⏳ (M18)
│  └─ T5.1.3 Prueba de sesgo 4.7.1 ↔ 4.8-dev7 (escenas, recursos importados) ...... A3 · P · G4 · ⏳ (M15)
├─ 5.2 Exportación
│  ├─ T5.2.1 Addon psvita + plantilla propia vita_release.zip (Custom Template) .. A3 · P · G4 · ⏳
│  ├─ T5.2.2 Script de exportación headless sobre una copia del proyecto ......... A3 · P · G4 · ⏳
│  ├─ T5.2.3 Filtros: *.rsch y package.xml como no-recursos ...................... A3 · P · G4 · ⏳ (M8)
│  └─ T5.2.4 Ajustes de proyecto Vita (960×544, worker_pool=2, Compatibility) .... A3 · P · G4 · ⏳
├─ 5.3 Proyecto "doble" (PC rclgd ↔ Vita ros2_vita)
│  ├─ T5.3.1 Plantilla de proyecto con package.xml + autoload ROS + ajustes ros/* A10 · L · G1 · ⏳
│  ├─ T5.3.2 Paso de export: package.xml → schema.rsch (+ clases nativas, R-N) ... A7 · L · G4 · ⏳
│  └─ T5.3.3 Parámetros sin línea de órdenes (ros/agent_ip, ros/parameters/*) .... A8 · L · G1 · ⏳
└─ 5.4 Despliegue: VitaShell/FTP + ux0:data/<juego>, netlog ...................... A3 · P/V · G4 · ⏳

6. APLICACIONES Y SENSORES
├─ T6.1 HMI piloto (de roomba_hmi): teleop /cmd_vel + /odom + estado ............ A10 · P/V · G6 · ⏳ (M9)
├─ T6.2 Publicar IMU (sensor_msgs/Imu) desde Input ............................... A9 · V · G7 · ⏳
├─ T6.3 Panel trasero → topic propio / Joy ...................................... A9 · V · G7 · ⏳
├─ T6.4 Cámara → CompressedImage (decisión de diseño, coste) ..................... A9 · V · G7 · ⏳
├─ T6.5 Mini-rviz en Godot (TF + marcadores) — reutiliza tf-tree/viz-math ........ A10 · V · G6+ · ⏳
└─ T6.6 Port de patrones de rclgd-sensors (RosSensor, PublishQueue) a GDScript ... A10 · L · G1 · ⏳

7. RENDIMIENTO Y HARDWARE
├─ T7.1 hwprobe (docs/14 §9) dentro y fuera de Godot ............................ A11 · V · —  · ⏳
├─ T7.2 Latencia extremo a extremo PC→Vita→Godot ................................ A11 · V · G5 · ⏳
├─ T7.3 FPS de la HMI a 333/444 MHz y uso de RAM (365 MiB) ...................... A11 · V · G6 · ⏳ (M16)
└─ T7.4 Coste de texturas por fotograma (cámara/mapa) ........................... A9 · V · G7 · ⏳

8. RUST (SDK propio, independiente de Godot)
├─ T8.1 Umbrella crate PIC para libgodot.so (core-only, sin TLS, sin panics std) A13 · P · G2 · ✅
├─ T8.2 verify_runtime.py con Rust dentro (relocaciones 2/21/22/23) ............ A13 · P · G3 · ✅ (docs/18 §4.5)
├─ T8.3 App cargo-vita independiente reutilizando los módulos ................... A13 · P · —  · ⏳
└─ T8.4 Serie docs/rust: PIC, build-std, cdylib vs staticlib (explicado) ........ A12 · L · —  · ⏳

9. DOCUMENTACIÓN Y WEB
├─ T9.1 docs/18 y docs/19 al día; API_PARITY.md ................................. A12 · L · —  · continuo
├─ T9.2 Guía de usuario: "crear un juego Godot+ROS2 para la Vita" (docs/guias-vita) A12 · L · G6 · ⏳
├─ T9.3 Web: fases.ts, comparador, sección de la migración ....................... A12 · L · —  · continuo
└─ T9.4 docs/16: páginas pendientes de leer (editor 4.8-dev7, issues del port) ... A1 · P · —  · ⏳

10. UPSTREAM Y VIGILANCIA
├─ T10.1 rclgd: cambios de API, nueva versión publicada, nueva versión de Godot .. A1 · L · — · 🔭 (native-msg-classes fusionada 2026-10-28)
├─ T10.2 godot4-vita: commits nuevos, salida a 4.8 estable, ruta GL ............. A1 · L · — · 🔭
├─ T10.3 micro-XRCE-DDS / micro-ROS agent Jazzy ................................. A1 · L · — · 🔭
└─ T10.4 PRs nuestros a upstream (loader, panel trasero, textura) ............... A2 · P · — · ⏳

11. SKILLS DE IA (conocimiento reutilizable por una IA limpia) — escuadra K
├─ 11.1 Skill `rclgd` (skills/rclgd/)
│  ├─ T11.1.1 SKILL.md: reglas, esqueleto, mapa de API, cómo documentarse ........ K5 · L · E1 · ✅
│  ├─ T11.1.2 references/api/* generadas de doc_classes (17 clases) ............. K1 · L · E1 · ✅
│  ├─ T11.1.3 conceptos / tooling / mensajes-y-tipos / versiones / errores ....... K2,K3 · L · E1 · ✅
│  ├─ T11.1.4 scripts: rclgd-docs.sh (probado), xml_to_md.py (probado), dump_api.gd K1 · L/P · E1 · 🟡 (dump_api sin ejecutar)
│  ├─ T11.1.5 Repasar TODOS los tests de rclgd y extraer recetas por método ........ K3 · L · E1 · ⏳
│  └─ T11.1.6 Clases nativas: skill actualizada a `jazzy@fb12a65` (2026-10-29) ..... K1 · P · E1 · ✅
├─ 11.2 Skill `godot4-ros-scripting` (skills/godot4-ros-scripting/)
│  ├─ T11.2.1 SKILL.md + godot4-esencial + patrones-roomba ......................... K4 · L · E1 · ✅
│  ├─ T11.2.2 templates/*.gd (robot, sensor, HMI, runner) ......................... K4 · L · E2 · 🟡 (sin ejecutar)
│  ├─ T11.2.3 Ejecutar las plantillas en el editor 4.7.1 de rclgd (headless) ........ K6 · P · E2 · ⏳
│  └─ T11.2.4 Recetas de sensores restantes (lidar, cámara, GPS) desde rclgd-sensors K4 · L · E1 · ⏳
├─ 11.3 Skill `ros2-vita-godot` (skills/ros2-vita-godot/)
│  ├─ T11.3.1 SKILL.md: diferencias, límites, flujo, reglas ....................... K5 · L · E1 · ✅
│  └─ T11.3.2 Mantenerla al día con cada puerta G*/H1 ............................. A12 · L · — · continuo
├─ 11.4 Verificación con IA limpia
│  ├─ T11.4.1 Batería skills/rclgd/evals/preguntas.md (18 casos) .................. K6 · L · E1 · ✅ (escrita)
│  ├─ T11.4.2 Pasarla con un subagente sin contexto y corregir huecos ............... K6 · L · E1 · ⏳
│  └─ T11.4.3 Re-pasarla tras cada versión de rclgd ................................. K6 · L · E1 · continuo
└─ 11.5 Distribución
   ├─ T11.5.1 Publicar en la web (sección «Skills de IA») ........................... A12 · L · — · ✅
   └─ T11.5.2 Instalar en el PC: copiar a ~/.claude/skills/ (docs/05) ............... A0 · P · — · ⏳
```

Puertas de skills: **E1** = la IA limpia responde bien la batería citando la skill; **E2** = las
plantillas `.gd` corren sin errores en el editor 4.7.1 de rclgd.

Puerta nueva **H1** (laptop/PC, sin Vita): el núcleo `xrce_core.c` compilado para host se conecta al
`micro-ros-agent:jazzy` en docker y un `ros2 topic echo` en `robotnik_dev` ve sus mensajes (y al revés).
**G1'**: variante de G1 para la rama R-G (GDExtension cargada en el editor 4.7.1 de rclgd).

---

## 4. Agentes (roster)

| Agente | Rol | Máquina | Posee (escribe) | Lee |
|---|---|---|---|---|
| **A0** Orquestador | Reparte tareas, integra ramas, mantiene tablero, bitácora y fases | L | `docs/06`, `docs/19` §8, `web/src/data/fases.ts` | todo |
| **A1** Vigía upstream / investigador | Ramas y cambios de rclgd, godot4-vita, XRCE; docs/16; API_PARITY | L (+P navegador) | `docs/16`, `godot/ros2_vita/API_PARITY.md`, `docs/17` | clones upstream |
| **A2** Motor y fork | Fijación, parches del loader/motor, fork mínimo, G1/G3 | P | `godot/loader-patches/`, `tools/build-godot-template.sh`, fork | docs/18 §2–§4 |
| **A3** Editor y exportación | rclgd jazzy, editor 4.8-dev7, addon, export headless, despliegue | P | `tools/export-vita.sh` (nuevo), `godot/export/` (nuevo) | docs/18 §2.5, §7 |
| **A4** Toolchain cruzada | Builds PIC C/Rust/XRCE, clausura de imports, SCsub de libs | P | `tools/check-vita-imports.py`, `tools/build-rust-pic.sh`, `tools/build-xrce-pic.sh` (nuevo), `godot/ros2_vita/SCsub` | docs/18 §3–§4 |
| **A5** Red opción A | `net-udp` en contexto `.so`: idempotencia, pool, estado WiFi, ciclo de vida | L→P→V | `modules/net-udp/**` | docs/18 §4.3 |
| **A6** Transporte XRCE | `xrce_core.c`, `XrceTransport`, QoS, reconexión, reloj, ajustes E1 | L→V | `godot/ros2_vita/xrce_core.{c,h}`, `XrceTransport` en `ros_runtime.*` | vita-app/src/main.c, docs/13 E1 |
| **A7** Mensajes y tipos | `RosMsg`, esquemas, generador desde package.xml, clases nativas (R-N) | L | `godot/ros2_vita/ros_msg.*`, `modules/msg-schema/**`, `tools/gen_msg_schema.py` | rclgd `src/rclgd/ros_type_registry.*` |
| **A7b** Spike R-G | Prototipo godot-cpp + carga estática; informe go/no-go | L/P | `godot/spike-gdextension/` (nuevo, desechable) | core/extension |
| **A8** Paridad de API | Runtime, RosNode, TF, logger, servicios, parámetros, señales | L | `godot/ros2_vita/ros_runtime.*` (salvo XrceTransport), `register_types.*` | API_PARITY |
| **A9** Sensores y entrada | IMU, panel trasero, cámara, texturas | P/V | parches 1.4 (vía A2), `godot/examples/sensors/` | docs/14 |
| **A10** Apps y ejemplos | HMI piloto, plantilla de proyecto doble, patrones rclgd-sensors | P | `godot/examples/**`, `godot/project-template/` | roomba_ws |
| **A11** QA y medidas | godot/test, H1, CI, paridad, rendimiento en Vita | L/P/V | `godot/test/**`, `tools/run-*`, `.github/workflows/` | todo |
| **A12** Documentación y web | docs, guías, serie Rust, web | L | `docs/**` (salvo dueños anteriores), `web/**` (salvo fases.ts) | todo |
| **A13** Rust | Umbrella PIC, verify_runtime con Rust, cargo-vita, ¿xrce_core dual? | P | `vita-app/rust-modules/`, `modules/*/impl-rust/` (coordinado con A5/A7) | docs/15 |

### Escuadra K — especialistas en rclgd y autores de skills
| Agente | Rol | Máquina | Posee (escribe) | Lee |
|---|---|---|---|---|
| **K1** Referencia de API | Clases, firmas, señales, constantes; regenera `references/api`; vigila ramas de rclgd | L | `skills/rclgd/references/api/`, `skills/rclgd/scripts/`, `references/versiones.md` | `rclgd/doc_classes/*.xml`, CHANGELOG |
| **K2** Conceptos | Hilos, ciclo de vida, tiempo, QoS, TF, parámetros, tipos | L | `skills/rclgd/references/{conceptos,mensajes-y-tipos}.md` | `docs/concepts/*`, `docs/tutorials/custom_messages.rst`, `ros_msg.cpp` |
| **K3** Tooling y ejemplos | apt/fuente/docker, CLI, colcon, tests headless; recetas extraídas de los tests | L | `skills/rclgd/references/{tooling,errores-comunes}.md`, `references/recetas.md` (nuevo) | `docs/getting_started/*`, `rclgd/test/`, `rclgd_cli/` |
| **K4** Godot (nodos, escenas, scripts) | Patrones de roomba_ws, esencial de Godot 4, plantillas | L | `skills/godot4-ros-scripting/**` | `roomba_ws`, `turtlesim_rclgd`, doc del motor (`--doctool`) |
| **K5** Autor/editor de skills | Coherencia, frontmatter válido, progresión (SKILL.md breve → referencias), puente con la Vita | L | `skills/*/SKILL.md`, `skills/ros2-vita-godot/**` | todo lo anterior + docs/18, API_PARITY |
| **K6** Verificador «IA limpia» | Pasa la batería con un subagente sin contexto; ejecuta plantillas (E2) | L/P | `skills/rclgd/evals/` | solo las skills (a propósito) |

**Regla de propiedad:** un fichero tiene **un** dueño; los demás proponen cambios por su rama y el
dueño los integra. Conflictos previstos: `ros_runtime.*` (A6 solo toca la clase `XrceTransport`);
`modules/*/impl-rust` (A13 coordina con el dueño del módulo); el parche del loader (A2 integra lo que
A5/A4 pidan).

---

## 5. Dependencias entre tareas (resumen)

```
T1.2.1 ─┬─► T1.2.2 ─► T1.2.3 ─► T1.3.2 (G3) ─► G4 ─► G5 ─► G6/G7
        │                ▲                       ▲      ▲
T4.5 ───┴─► T2.2.1 ──────┘                       │      │
T3.1.1 ─► T1.3.1 (G1) ─► T3.5.1 ─────────────────┘      │
T2.2.2 ─► T2.3.* (H1) ─► T3.3.4 ────────────────────────┘
T5.1.2 ─► T5.2.1 ─► T5.2.2 ─► G4
T2.4.1 ─► T5.3.2 ─► T3.2.4 (R-N)        T3.1.3 (R-G) ─► decisión go/no-go ─► (si go) migrar 3.*
```

---

## 6. Oleadas (qué puede correr en paralelo)

| Oleada | Dónde | Agentes en paralelo | Sale cuando |
|---|---|---|---|
| **O0 — ya, sin PC ni Vita** | laptop | A1 (vigilancia + API_PARITY con R-N), A5 (idempotencia/estado WiFi en host), A6 (`xrce_core.c` + H1 en docker), A7 (generador desde package.xml, fixtures con rclpy), A8 (TF, logger local, señales), A11 (imagen H1, CI), A12 | H1 verde; paridad verde |
| **O1 — PC** | CachyOS | A2 (G1, G3), A3 (rclgd jazzy, editor 4.8-dev7, export), A4 (PIC, imports), A7b (spike R-G), A13 (Rust PIC) | G1, G2, G3 verdes (G3: 2026-10-30); go/no-go R-G |
| **O2 — PC + Vita** | Vita | A3 (despliegue), A6 (XRCE real), A5 (WiFi real), A11 (medidas) | G4, G5 |
| **O3 — apps** | PC + Vita | A9, A10, A11 | G6, G7 |
| **O4 — consolidación** | todas | A2 (PRs upstream, rebase), A1, A12 (guía final) | fork mínimo o cero; docs cerradas |

En el portátil caben **7 agentes** en paralelo en O0 porque sus ficheros no se solapan (§4).
La **escuadra K** corre en O0 en paralelo con ellos (solo toca `skills/`): K1–K4 en paralelo, después
K5 (coherencia) y al final K6 (verificación E1); K6 repite E2 en O1 con el PC.

---

## 7. Protocolo de coordinación

1. **Ramas git:** la rama de integración es la designada por la sesión (hoy `ccr-44e2db2a-mr6xqr`;
   después la que indique el usuario). Cada agente trabaja en `mig/<agente>-<tarea>` (p. ej.
   `mig/a6-xrce-core`) o en un *worktree* aislado; A0 integra con *merge* (sin reescribir historia).
2. **Antes de empezar:** leer `CLAUDE.md`, `docs/06` (último bloque), `docs/18`, este documento (§1, su
   fila en §4 y su brief en §9).
3. **Al terminar cada tarea:** `tools/run-parity-tests.sh` verde; pruebas propias verdes; marcas
   «validar en el PC / en hardware» exactas; commit en español (`feat(godot4): …`, `fix(net-udp): …`);
   informe corto a A0: qué se hizo, qué se verificó (con salida), qué queda, qué ficheros tocó.
4. **Nada de hardware simulado:** lo que exige PC o Vita se entrega como **checklist ejecutable** para
   el usuario (comandos exactos + qué resultado esperar) y la tarea queda ⏳ con la puerta indicada.
5. **No reabrir decisiones (§1)**; las dudas nuevas van a A0, que las acumula en §10 para el usuario.
6. **Upstream:** nunca empujar a repos ajenos; los PRs a upstream los prepara A2 y los aprueba el usuario.
7. **Rust:** todo constructo nuevo se explica en comentarios y/o `docs/rust/` (usuario principiante).
8. **Definiciones de agentes:** `.claude/` es local (no se versiona). Para usar los briefs como
   subagentes de Claude Code, copiar cada brief de §9 a `.claude/agents/<nombre>.md` con cabecera:
   ```
   ---
   name: a6-xrce
   description: Transporte XRCE de ros2_vita (xrce_core.c, XrceTransport). Usar para tareas T2.3.*, T3.3.4-5.
   ---
   <texto del brief>
   ```

---

## 8. Tablero de estado (lo mantiene A0)

| Puerta | Estado | Fecha | Evidencia |
|---|---|---|---|
| G0 | **verde** | 2026-10-27 | paridad 8 módulos; parche aplica en `d1a5f29` y `v0.1` |
| H1 | pendiente | — | — |
| E1 | batería escrita; pendiente de pasar con IA limpia | 2026-10-27 | `skills/rclgd/evals/preguntas.md` |
| E2 | pendiente (PC) | — | plantillas sin ejecutar |
| G1 | **verde** | 2026-10-29 | PC: godot4-vita `d1a5f29` `linuxbsd` + `ros2_vita` compila; `run_host_tests.sh` 294 comprobaciones / 0 fallos |
| G1' | pendiente | — | spike R-G sin empezar |
| G2 | **verde** | 2026-10-29 | PC: XRCE+microcdr, 8 módulos C y umbrella Rust en PIC; `check-vita-imports` (arm-vita-eabi-nm) 0 ausentes con el parche (11 sin él); 0 TLS |
| G3–G7 | pendiente | — | — |

Hechos de partida para O0: Fase 1 **cerró en hardware** (2026-07-01: `/vita_hello` visible y
`/pc_hello` recibido) con `net-udp` + `microros-transport` + XRCE en un ELF estático ⇒ la opción A usa
un camino **ya probado en la Vita**; lo nuevo es ejecutarlo dentro de `libgodot.so`.

---

## 9. Briefs por agente (copiar como prompt)

Todos empiezan igual: *«Proyecto PSVita-ROS. Lee CLAUDE.md, el último bloque de docs/06, docs/18 y
docs/19 (§1, tu fila de §4, tu brief). Respeta la propiedad de ficheros. Paridad nunca en rojo. Lo que
no puedas verificar, márcalo y entrégalo como checklist. Termina con un informe a A0.»*

**A1 — Vigía upstream.** Compara `Ozuba/rclgd` (`jazzy`, `rolling`; nativas ya fusionadas) y
`WolffsRoom/godot4-vita` (`main`, `release/v0.1`, etiquetas) con los commits fijados en docs/18/19.
Resume cambios de API, versión de Godot y build. Actualiza `API_PARITY.md` (añade la columna de clases
nativas R-N) y docs/16. Salida: tabla de cambios + acciones propuestas por agente.

**A2 — Motor y fork.** En el PC: (1) `tools/vita-doctor.sh`; (2) G1: compilar Godot 4.8 `linuxbsd`
con `custom_modules=<repo>/godot` y pasar `godot/test/run_host_tests.sh`; (3) G3:
`tools/build-godot-template.sh` hasta `verify_runtime.py` PASS. Mantén la serie `godot/loader-patches/`;
crea el fork solo si un parche no cabe como serie (D5). Documenta el procedimiento de rebase.

**A3 — Editor y exportación.** Instala rclgd (rama `jazzy`) y comprueba `ros2 rclgd editor` (4.7.1).
Consigue o compila el editor **4.8-dev7 Linux**; instala el addon `psvita` con la plantilla propia;
escribe `tools/export-vita.sh` (export headless sobre una copia del proyecto, filtros `*.rsch` y
`package.xml`). Ejecuta M15 (sesgo 4.7.1↔4.8-dev7) y documenta qué se rompe.

**A4 — Toolchain cruzada.** Compila microxrcedds_client/microcdr y los módulos C como **PIC**;
`tools/build-rust-pic.sh`; ejecuta `tools/check-vita-imports.py --nm arm-vita-eabi-nm` sobre los objetos
reales y pide a A2 los imports que falten. Ajusta `godot/ros2_vita/SCsub` para enlazar libs como
`env.File`. Salida: lista de imports final y tamaños.

**A5 — Red opción A.** En `modules/net-udp` (C y Rust, misma API): `net_udp_init` idempotente también
si la red la inició otro (tratar «ya inicializada» como éxito, constante real a validar en hardware);
consulta del estado WiFi con error claro; `net_udp_shutdown` seguro al salir. Paridad en host. Lista
para A2 los `sce*` nuevos para la tabla del loader.

**A6 — Transporte XRCE.** Extrae de `vita-app/src/main.c` un núcleo C sin tipos de Godot
(`godot/ros2_vita/xrce_core.{c,h}`): hilo de sesión, cola tx (`msg-ring`) y rx, entidades XML por
topic (`rt/<topic>`, `<pkg>::msg::dds_::<T>_`), QoS, reconexión, sincronía de reloj. Compílalo para
host en docker y supera **H1** contra `micro-ros-agent:jazzy` (`--net=host --ipc=host`) con
`ros2 topic echo/pub` en `robotnik_dev`. Después, `XrceTransport` como envoltura fina.

**A7 — Mensajes y tipos.** Generador `package.xml → schema.rsch` (cierre de dependencias);
fixtures cruzados con rclpy real; clases **nativas** desde el esquema como las de rclgd (rama R-N,
`ClassDB::register_extension_class`, sin `thread_local`; referencia `rclgd/src/rclgd/ros_type_registry.*`),
cargadas antes de analizar scripts. Sin clases sombra (rclgd las eliminó). Mantén `msg-schema` con paridad.

**A7b — Spike R-G.** Prototipo mínimo con godot-cpp (rama de 4.7): una clase `RosMsg` que se cargue
(a) como GDExtension dinámica en el editor 4.7.1 de rclgd y (b) enlazada estáticamente en un Godot
4.8 de host vía `load_extension_from_function`. Mide imports nuevos (libstdc++) frente al loader de la
Vita. Entrega go/no-go razonado; el código es desechable.

**A8 — Paridad de API.** Completa `RosNode` según API_PARITY: TF (broadcaster/listener sobre
`tf-tree`), `RosLogger` local (+ `/rosout` cuando haya XRCE), señales de estado, parámetros desde
ajustes del proyecto; servicios cuando A6 tenga XRCE. Añade pruebas al runner GDScript.

**A9 — Sensores.** IMU desde `Input` → `sensor_msgs/Imu` con ejes REP-103; parche del panel trasero
en `display_server_vita.cpp` (vía A2); propuesta de cámara con coste medido (evitar recrear la textura).

**A10 — Apps.** Plantilla de proyecto doble (package.xml, autoload `ROS`, ajustes `ros/*`); HMI
piloto desde `roomba_hmi` (teleop + odometría + estado) que corra **sin cambios** en el editor de
rclgd y en la Vita; port de `RosSensor`/`PublishQueue` a GDScript puro.

**A11 — QA.** Imagen docker para H1; runner de `godot/test`; CI opcional (paridad, H1, web);
checklists de medidas en Vita (latencia, FPS, RAM, coste por mensaje) y `hwprobe`.

**A12 — Docs y web.** Mantén docs/18–19, guía «crear un juego Godot+ROS2 para la Vita» en
`docs/guias-vita/`, serie Rust (PIC, build-std), web y comparador. Todo doc nuevo debe aparecer en la web.

**A13 — Rust.** Umbrella crate PIC `core`-only para `libgodot.so`; superar `verify_runtime.py` con
Rust dentro; app `cargo-vita` independiente reutilizando los módulos; valorar versión dual de `xrce_core`.

---

### Briefs de la escuadra K (rclgd → skills)
Prefijo común extra: *«Primero `skills/rclgd/scripts/rclgd-docs.sh sync jazzy` (o la rama indicada) y
`version`; trabaja solo sobre fuentes oficiales (docs/*.rst, doc_classes, tests, plantilla) y cita de
dónde sale cada afirmación. Si readthedocs no es accesible, el clon tiene el mismo contenido.»*

**K1 — Referencia de API.** Regenera `references/api` con `rclgd-docs.sh api`; compara con la versión
anterior (`git diff`); documenta cambios en `versiones.md`. Si hay Godot+rclgd, ejecuta `dump_api.gd` y
anota diferencias entre XML y ClassDB real. Vigila la próxima versión publicada (apt) de rclgd.

**K2 — Conceptos.** Lee `docs/concepts/*` y los tutoriales; verifica cada regla contra el código
(`rclgd/src/rclgd/*.cpp`) cuando la doc sea ambigua (p. ej. copia de arrays, alias de submensajes).
Mantén `conceptos.md` y `mensajes-y-tipos.md` cortos y con ejemplos mínimos.

**K3 — Tooling y recetas.** Recorre `rclgd/test/project/tests/*.gd` y escribe `references/recetas.md`:
una receta por operación (pub/sub, QoS, timer, servicio cliente/servidor, acción cliente/servidor, TF,
parámetros, logging) con el fragmento real del test y su fichero:línea. Añade síntomas nuevos a
`errores-comunes.md`. Documenta la instalación en CachyOS vía el contenedor `robotnik_dev`.

**K4 — Godot.** Completa `godot4-ros-scripting`: recetas de cada sensor de `rclgd-sensors` (lidar,
cámara, GPS, fisheye; compositores y lecturas de GPU), patrón de gizmos/`@tool`, y la HMI. Revisa las
plantillas contra la API real.

**K5 — Autor de skills.** Frontmatter YAML válido (descripción entre comillas), `SKILL.md` < ~150 líneas
con enlaces a referencias, nada duplicado entre skills, puente correcto con `ros2-vita-godot` y
API_PARITY. Publicación en la web (sección «Skills de IA»).

**K6 — Verificador.** Lanza un subagente **sin contexto del repo** con acceso solo a `skills/`; pásale
`skills/rclgd/evals/preguntas.md` sin las respuestas; puntúa; abre tareas para cada fallo. En el PC,
ejecuta las plantillas en un proyecto de `ros2 rclgd create` (E2).

## 10. Decisiones pendientes del usuario (las acumula A0)
1. Rama de integración y nombre de las ramas `mig/*` (propuesta en §7).
2. ¿Se crea ya el fork `Jcrex/godot4-vita` vacío (para PRs) o solo cuando haga falta (D5)?
3. Tras el spike R-G: ¿se migra el módulo a godot-cpp si resulta viable?
4. Cámara: ¿publicar `CompressedImage` desde la Vita o solo mostrar imagen remota?
