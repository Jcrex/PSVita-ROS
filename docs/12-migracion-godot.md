# 12 — Diseño: migración del teleop al entorno Godot

**Fecha:** 2026-07-13 · **Estado:** diseño aprobado, implementación pendiente
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
MicroROS.setup(agent_ip: String, netlog_ip: String)
MicroROS.connect_agent() -> bool      # crea la sesión XRCE
MicroROS.is_session_active() -> bool
MicroROS.publish_cmd_vel(linear: float, angular: float)
MicroROS.spin()                       # bombea la sesión; llamar en _process()
MicroROS.netlog(msg: String)
```

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
2. **G2 — Template custom compila (PC):** el fork compila con
   `custom_modules`, el singleton aparece en GDScript en la Vita.
3. **G3 — Teleop Godot en hardware:** sesión XRCE activa, `/cmd_vel`
   controla el robot real. Cierra la migración (variante C).
4. **G4 — Variante Rust del template.**

## Fuera de alcance de esta branch

- Migrar/reescribir C/C++/Rust a GDScript o C#.
- Funcionalidad nueva no presente en la app nativa actual.
- Los Objetivos 3/4 (mini-rviz): siguen su propio plan (`docs/10`,
  `docs/11`); si en el futuro conviene rehacer mini-rviz sobre Godot, será
  una decisión aparte (probable ADR) — esta branch no la prejuzga.
