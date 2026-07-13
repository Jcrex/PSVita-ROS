# 12 — Diseño: migración del teleop al entorno Godot

**Fecha:** 2026-07-13 · **Estado:** G1, G2 y G3 HECHOS — migración C completa: el teleop en Godot publica `/cmd_vel` en hardware. Falta G4 (variante Rust).
**Branch de trabajo:** `godot-migration`
**Prerrequisitos cumplidos:** Objetivo 2 cerrado (la app teleop nativa
controla el robot real vía `/cmd_vel`, ver `docs/09-objetivo2-control-robot.md`).

## Motivación

Existe un fork de Godot 3.5-rc5 con soporte nativo de PS Vita
(`~/Proyectos/Godot/godot-vita-3.5-rc5-vita1`, editor x11 precompilado en
`~/Proyectos/Godot/godot_v3.5-rc5-vita.x11.64`). El usuario ya verificó el
flujo completo: un proyecto Godot exportado con el template oficial
(`vita_template_3.5.rc5.tpz`) corre en su Vita física. Godot aporta lo que
más cuesta en el homebrew nativo: UI, input, fuentes, persistencia y ciclo
de iteración rápido (cambiar GDScript no requiere recompilar nada nativo).

**Objetivo de esta branch:** replicar en Godot la app teleop existente —
sesión XRCE contra el agente micro-ROS, publicación de `/cmd_vel` para
controlar el robot real, netlog UDP e IPs editables — **sin reescribir ni
migrar el código C/C++/Rust existente**. Solo se crea código de
implementación (glue y UI); nada de lógica nueva.

## Decisión de arquitectura

**Enfoque elegido: módulo custom del engine vía `custom_modules`.**

Datos que fuerzan la decisión (verificados en el código del fork):

- `platform/vita/detect.py:50` fija `module_gdnative_enabled: False` — en
  la Vita **no hay carga dinámica de librerías**; la única vía para código
  nativo es compilarlo dentro del engine.
- `SConstruct:132` soporta `custom_modules=` (rutas separadas por comas) —
  el módulo puente puede vivir **en este repo** sin tocar el fork.

Enfoques descartados:

- **GDNative:** deshabilitado en la plataforma Vita del fork.
- **Proxy UDP en GDScript** (PacketPeerUDP → proxy en la laptop → ROS2):
  no requiere recompilar el engine, pero la Vita dejaría de ser un nodo
  micro-ROS real y exigiría crear un proxy desde cero. Contradice el
  corazón del proyecto y la regla de "no crear nada nuevo".
- **Vendorizar el módulo dentro del fork:** duplicaría repos a sincronizar;
  `custom_modules` lo hace innecesario.

Consecuencia asumida: el `.tpz` precompilado de 2022 no sirve para la fase
con micro-ROS. Hay que compilar **un export template propio** en el PC
CachyOS (VitaSDK + scons), igual que ya se cross-compila el resto del
código Vita del proyecto.

## Organización del repo

- `vita-app/` y los módulos duales **no se tocan**: siguen siendo la
  referencia funcional y el fallback permanente.
- El fork de Godot queda intacto; el módulo se inyecta al compilar.
- Todo lo nuevo vive bajo `godot/`:

```
godot/                        # proyecto Godot existente
├── modules/microros/         # módulo C++ del engine (puente)
│   ├── SCsub                 # linkea libs existentes del repo
│   ├── config.py
│   ├── register_types.{cpp,h}
│   └── micro_ros_gd.{cpp,h}  # singleton MicroROS
├── scenes/teleop/            # escena teleop dedicada + GDScript
├── scripts/
│   └── build-vita-template.sh  # build del template (solo PC)
├── README.md
└── .gitignore                # excluir .import/
```

## Módulo puente `microros`

Módulo Godot 3.5 estándar que expone a GDScript un singleton **`MicroROS`**
y por debajo **linkea el código ya existente**:

- `modules/{mem-pool,net-udp,microros-transport}` — variante **C** primero.
- `libmicroxrcedds_client` **v2.4.3** + `libmicrocdr` v2.0.1 — los que ya
  cross-compila `vita-app/scripts/build-xrce-client-vita.sh` (el tag
  v2.4.3 es obligatorio: empareja con el agente
  `microros/micro-ros-agent:jazzy`, ver bitácora 2026-07-01).
- `vita-app/src/{uxr_glue,netlog,teleop,config}.c` — reutilizados tal
  cual; `main.c` y `ui.c` no (los reemplazan Godot y la escena).

API GDScript (espejo de lo que hoy hace `main.c`):

```gdscript
MicroROS.setup(agent_ip: String, netlog_ip: String) -> bool
MicroROS.connect_agent() -> bool      # crea la sesión XRCE
MicroROS.is_session_active() -> bool
MicroROS.teleop_step(input: Dictionary, dt: float) -> Dictionary
MicroROS.spin(ms: int)                # bombea la sesión; llamar en _process()
MicroROS.netlog(msg: String)
MicroROS.shutdown()
```

`teleop_step()` recibe el dict de mandos crudo (sticks [-1,1] + botones) y
por dentro llama a `teleop_update()` de `teleop.c` — así el mapeo NO se
reimplementa en GDScript — publica el Twist resultante y devuelve
`{lin_x, lin_y, ang_z, vel_lineal, vel_lateral, published}` para pintarlo.

El módulo es glue de ~200-300 líneas C++, sin lógica propia. Solo compila
para el target Vita (guardas `#ifdef __vita__` / `platform=vita` en
`config.py` — en builds de escritorio el singleton simplemente no existe).

## UI en GDScript (escena teleop dedicada)

- `scenes/teleop/Teleop.tscn` + `teleop.gd`: escena nueva y limpia; las
  escenas existentes (`Primera-scena-silvia/`) quedan como están.
- En pantalla: estado de conexión (se acabó diagnosticar pantallas negras),
  IPs del agente/netlog editables, indicadores en vivo de lo publicado en
  `/cmd_vel`, y consola de log local.
- **Mismo mapeo de controles** que `docs/09-objetivo2-control-robot.md`,
  leído desde el Input de Godot (`platform/vita/joypad_vita.cpp` ya expone
  el pad como joystick estándar).
- Persistencia de IPs con `ConfigFile` en `user://` (mejora gratis frente
  al config actual).
- **Modo simulado en la laptop:** `teleop.gd` detecta el singleton con
  `Engine.has_singleton("MicroROS")`; si no existe (editor x11
  precompilado, sin nuestro módulo), corre con un stub que loguea lo que
  publicaría. Toda la UI se desarrolla y prueba en la laptop sin hardware.

## Flujo de build laptop ↔ PC

**Laptop (esta máquina):** escenas, GDScript, código C++ del módulo
(marcado "validar en el PC"), docs — todo commiteado y pusheado en
`godot-migration`. Aquí no se compila nada nativo (regla del repo).

**PC CachyOS (tras `git pull`):**

1. `godot/scripts/build-vita-template.sh` — comprueba VitaSDK, asegura
   `vita-app/third_party/` (lo compila si falta, reutilizando
   `build-xrce-client-vita.sh`), y compila el fork:
   `scons platform=vita target=release custom_modules=<repo>/godot/modules`.
2. El binario resultante se instala como template custom del proyecto
   (reemplaza al `.tpz` oficial solo para este proyecto).
3. Export normal desde el editor Godot → `.vpk` → FTP a la Vita
   (flujo ya documentado en `docs/guias-vita/`).

El template solo se recompila cuando cambia código C/C++/Rust; los cambios
de GDScript/escenas solo requieren re-exportar el `.vpk` (segundos).

## Prerrequisitos del VitaSDK para compilar el template (G2)

Compilar el engine godot-vita completo (con el módulo `microros`) exige, en
el PC, más que el VitaSDK base. Todo esto quedó resuelto y automatizado al
cerrar G2; se documenta porque un VitaSDK limpio lo necesita:

1. **Entorno cargado:** `source tools/env-devpc.fish` (exporta `VITASDK`,
   `RUSTUP_HOME`, `CARGO_HOME` y mete en el PATH VitaSDK, cargo, cmake, y las
   utilidades `vdpm`/`vita-makepkg`). Sin esto el script muere en
   `VITASDK no exportado`. Falta además `scons` y `zip` del sistema
   (`sudo pacman -S scons zip`).
2. **Driver PowerVR (PVR_PSP2 v3.9):** el fork renderiza con el driver
   propietario de la Vita, no con vitaGL. Aporta `EGL/`, `GLES2/`,
   `gpu_es4/psp2_pvr_hint.h` y las stubs `libIMGEGL/libGLESv2/libgpu_es4_ext`.
   Se instala con el paquete de
   [`vita-packages-extra`](https://github.com/SonicMastr/vita-packages-extra):
   `cd .../vita-packages-extra/pvr_psp2 && vita-makepkg && vdpm pvr_psp2-*-arm.tar.xz`.
   Los `.suprx` runtime del driver ya viajan dentro del template.
3. **Códecs y freetype (vdpm):** el engine enlaza ogg/vorbis/theora/opus,
   jpeg y freetype:
   `vdpm libjpeg-turbo freetype libogg libvorbis libtheora opus`.
4. **Patch `bullet-vita-no-clew`** (`godot/patches/`, lo aplica el build
   script solo): Bullet incluye `clew/clew.c` (loader OpenCL) que usa
   `dlopen`; la newlib de la Vita no tiene carga dinámica. Godot nunca usa
   clew (solo `Bullet3OpenCL/*`, que no se compila), así que se excluye.
   **No afecta a la física:** Bullet corre entero en CPU; la aceleración por
   GPU/OpenCL es imposible en el PowerVR SGX543 de todos modos.
5. **Stub `dlfcn.h`** (`godot/vitasdk-stubs/`, lo copia el build script solo):
   código stock de Godot (`drivers/gles2/rasterizer_storage_gles2.cpp`) hace
   `#include <dlfcn.h>` en cualquier target GLES2, pero las llamadas reales a
   `dlopen`/`dlsym` quedan en bloques `#ifdef ANDROID/IPHONE` — código muerto
   en la Vita. Basta un header-stub de declaraciones (sin enlazar nada).

Los pasos 1-3 tocan el VitaSDK vendorizado (gitignorado); los pasos 4-5 viven
en el repo y el `build-vita-template.sh` los aplica de forma **idempotente**.

**Desinstalación limpia:** `godot/scripts/uninstall-godot.sh` revierte todo lo
anterior (parches con `patch -R`, stubs, paquetes vdpm con `vdpm -u` —que
respeta ficheros compartidos—, template y `godot/build/`), dejando el VitaSDK
en su estado pre-Godot. No toca el toolchain base compartido con `vita-app`.

## Requisitos del `.vpk` de Godot (G3)

Al exportar e instalar el `.vpk` en hardware se pagaron tres lecciones. El
editor de escritorio es el binario **precompilado de 2022** del release de
SonicMastr (`~/Proyectos/Godot/godot_v3.5-rc5-vita.x11.64`), que tiene rarezas:

1. **TITLE_ID (`0xF0030000` si es inválido):** debe ser **9 chars, MAYÚSCULAS,
   alfanumérico, sin símbolos** (p.ej. `PSVITAROS`; `PSVita-ROS` falla por
   guion/minúsculas/10 chars). **Ese editor usa el campo `Title` como
   TITLE_ID e IGNORA el campo `Title Id`** — hay que poner un id válido en
   `Title`. (El código fuente del fork sí los separa; el binario de 2022 es
   anterior a eso.)
2. **Imágenes `sce_sys` (`0x8010113D` si están mal):** deben ser **PNG 8-bit
   colormap**. `icon0.png` = **128×128** (no 64×64). Si el `template.xml`
   de livearea referencia `bg.png` (840×500) y `startup.png` (280×158), esas
   imágenes **deben existir** en el vpk o el instalador falla. El
   `template.xml` viene embebido en el editor, no se puede quitar, así que
   hay que **rellenar los assets de livearea** en el preset. Los placeholders
   están en `godot/vita_{icon128,bg,startup}.png` (generados con imagemagick,
   8-bit; sustituibles por arte real manteniendo tamaño+formato).
3. **El editor ignora el "export path":** escribe siempre `<Title>.vpk` en la
   raíz del proyecto (`create_vpk(sfo->title + ".vpk", …)`), no en la ruta que
   se le indica.

**Bug del port corregido (crash `C2-…` al conectar):** el módulo creaba solo el
stream reliable de **salida**; faltaba el de **entrada** (`uxr_create_input_
reliable_stream`, como en `main.c:201`). Sin él, al responder el agente el
cliente XRCE deref-a un input stream inexistente → crash **solo con el agente
arriba**. Añadido `input_stream_buf` + su creación en `connect_agent()`.

**Nota de build:** `build-vita-template.sh` limpia `bin/vita_template` y demás
artefactos de empaquetado antes de `scons`, porque el paso
`Copy("bin/vita_template", …)` del fork falla en rebuilds con "File exists".

**Variante Rust (segundo hito):** mismo template pero linkeando la
staticlib paraguas `vita-app/rust-modules/` en lugar de las libs C, igual
que hace hoy el `.vpk` Rust (`cargo rustc --crate-type staticlib`, una
staticlib Rust por binario). Los tests de paridad siguen siendo la puerta:
nunca se cierra un hito con paridad roja.

## Manejo de errores

Lecciones ya pagadas que se conservan:

- Comprobar **todos** los valores de retorno (el bug de `netlog_init`
  silencioso de `main.c:100` no se repite).
- Tag XRCE **v2.4.3 fijo** — el desajuste v3.0.0/v2.4.3 con el agente ya
  costó una sesión de diagnóstico entera.
- Reintentos de `connect_agent()` con backoff y estado visible en la UI;
  netlog UDP al puerto 9999 de la laptop como canal de diagnóstico
  secundario.

## Verificación

- **Laptop:** la escena corre en el editor con el stub; los parity tests
  (`tools/run-parity-tests.sh`) siguen verdes — no se tocan los módulos.
- **PC/hardware:** protocolo del Objetivo 2 — agente
  (`microros/micro-ros-agent:jazzy udp4 --port 8888 -v6`) y
  `tools/netlog-listen.sh 9999` en la laptop, `ros2 topic echo /cmd_vel`
  en el contenedor Jazzy, y control del robot real desde la Vita.

## Hitos

1. **G1 — Esqueleto en la branch (laptop):** módulo C++ completo, escena
   teleop con stub funcionando en el editor, build script, docs. Es el
   único hito verificable íntegramente en la laptop.
2. **G2 — Template custom compila (PC):** ✅ **hecho (2026-07-13).** El fork
   compila entero con `custom_modules` en el PC (7,5 min); el `microros` queda
   registrado en el engine (`register_microros_types()`) y el
   `vita_release.zip` (19 MB, con `eboot.bin` + `.suprx` PowerVR) se instala
   como template. Falta validar en hardware que el singleton aparece en
   GDScript (parte de G3). Ver los prerrequisitos del VitaSDK arriba.
3. **G3 — Teleop Godot en hardware:** ✅ **hecho (2026-07-13).** El `.vpk`
   exportado desde el editor instala y corre; la escena teleop responde a
   mandos; la sesión XRCE se establece y **publica `/cmd_vel`** (confirmado
   por el usuario). Cierra la migración (variante C). Se pagaron tres
   lecciones al exportar/instalar (ver "Requisitos del .vpk de Godot" abajo):
   TITLE_ID válido, imágenes `sce_sys` en 8-bit, y un bug del port (faltaba
   el **input reliable stream**, que crasheaba la sesión con el agente arriba).
4. **G4 — Variante Rust del template.**

## Fuera de alcance de esta branch

- Migrar/reescribir C/C++/Rust a GDScript o C#.
- Funcionalidad nueva no presente en la app nativa actual.
- Los Objetivos 3/4 (mini-rviz): siguen su propio plan (`docs/10`,
  `docs/11`); si en el futuro conviene rehacer mini-rviz sobre Godot, será
  una decisión aparte (probable ADR) — esta branch no la prejuzga.
