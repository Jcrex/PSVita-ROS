// fases.ts — estado del proyecto que muestra la página /progreso.
// ACTUALIZAR AL CERRAR HITOS (fuente: docs/06-bitacora-estado.md del repo).
export type EstadoHito = 'hecho' | 'en-curso' | 'bloqueado-pc' | 'bloqueado-hw' | 'pendiente';

export interface Hito {
  texto: string;
  estado: EstadoHito;
}

export interface Fase {
  id: string;
  nombre: string;
  resumen: string;
  hitos: Hito[];
}

export const fases: Fase[] = [
  {
    id: 'fase-0',
    nombre: 'Fase 0 — Fundación',
    resumen:
      'La capa meta: documentación de arquitectura, ADRs, skills de Claude Code, MCP de introspección ROS2 y tooling.',
    hitos: [
      { texto: 'Docs 00-05 y 4 ADRs', estado: 'hecho' },
      { texto: '3 skills (dual-module, build-package, deploy-logs)', estado: 'hecho' },
      { texto: 'MCP ros2-introspection con FakeBackend + tests', estado: 'hecho' },
      { texto: 'RclpyBackend completo validado contra ROS2 Jazzy vivo (docker)', estado: 'hecho' },
    ],
  },
  {
    id: 'fase-1',
    nombre: 'Fase 1 — Objetivo 1: topics ROS2',
    resumen:
      'La Vita entra al grafo ROS2 vía micro-ROS (XRCE-DDS) sobre WiFi/UDP. Tres módulos duales Rust+C y la app homebrew.',
    hitos: [
      { texto: 'Módulo dual mem-pool (paridad C/Rust en host)', estado: 'hecho' },
      { texto: 'Módulo dual net-udp (sceNet + POSIX, paridad en host)', estado: 'hecho' },
      { texto: 'Módulo dual microros-transport (4 callbacks XRCE, paridad)', estado: 'hecho' },
      { texto: 'App "Vita ROS2 Hello" (código completo + crate paraguas Rust)', estado: 'hecho' },
      { texto: 'Entorno del PC: VitaSDK, Rust nightly + cargo-vita, cmake, agente micro-ROS', estado: 'hecho' },
      { texto: 'Cross-compilar microxrcedds_client (libs ARM para la Vita)', estado: 'hecho' },
      { texto: 'Empaquetar el .vpk (variantes C y Rust, ambas construidas)', estado: 'hecho' },
      { texto: 'Primer .vpk instalado en la Vita real (USB, VitaShell)', estado: 'hecho' },
      { texto: 'Incógnita dura: sesión XRCE sobre sceNet (RESUELTA — confirmada en hardware, reproducible en 4 lanzamientos)', estado: 'hecho' },
      { texto: 'Criterios: /vita_hello visible + /pc_hello recibido (confirmados en vivo y simultáneos)', estado: 'hecho' },
    ],
  },
  {
    id: 'fase-web',
    nombre: 'Fase de desarrollo — Panel de control web',
    resumen:
      'Prioridad activa desde 2026-07-06 (docs/08). Primer hito ALCANZADO el mismo día: los seis frentes no bloqueados están operativos en la web real (comparador, tutorial, dashboard con datos reales, visor 3D, debug en host y base del compilador). Corre en paralelo a los objetivos numerados.',
    hitos: [
      { texto: 'Comparador C++/Rust (split view de los módulos duales, /comparador)', estado: 'hecho' },
      { texto: 'Tutorial del SDK de VitaSDK (guía "de cero a .vpk" en /guias)', estado: 'hecho' },
      { texto: 'Dashboard ROS2 editable (netlog UDP en vivo por SSE + salud XRCE + topics, layout en SQLite)', estado: 'hecho' },
      { texto: 'Visor 3D/URDF/SDF standalone (three.js + modelo de prueba VitaBot, /visor3d)', estado: 'hecho' },
      { texto: 'Debug de módulos duales en host (gdb batch sobre los parity tests, /taller/debug)', estado: 'hecho' },
      { texto: 'Base del compilador web (toolchain local: .vpk real compilado y descargable, /taller/compilador)', estado: 'hecho' },
      { texto: 'Editor visual de la UI de la app (layout declarativo + codegen + aplicar/compilar, /taller/ui — ADR 0005)', estado: 'hecho' },
      { texto: 'Build con vita2d en el PC (libvita2d instalada vía vdpm; ambas variantes enlazan)', estado: 'hecho' },
      { texto: 'UI de la app dibujada en la Vita real (hardware)', estado: 'bloqueado-hw' },
      { texto: 'Capa remota del compilador (cuando la web no corra en el PC) y debug en la Vita real', estado: 'pendiente' },
    ],
  },
  {
    id: 'fase-2',
    nombre: 'Objetivo 2 — Control de robot',
    resumen:
      'La Vita como mando de teleoperación ROS2: sticks y botones publicando geometry_msgs/Twist en /cmd_vel a ~20 Hz (diseño y mapeo en docs/09).',
    hitos: [
      { texto: 'Diseño detallado: mapeo mandos→Twist, REP 103, arquitectura (docs/09)', estado: 'hecho' },
      { texto: 'teleop.c puro (sin headers Vita) + batería en host (39 checks, check-teleop.sh)', estado: 'hecho' },
      { texto: 'App publica /cmd_vel (Twist CDR) a ~20 Hz + UI teleop (velocidades y Twist en vivo)', estado: 'hecho' },
      { texto: '.vpk C y Rust del teleop compilados en el PC', estado: 'hecho' },
      { texto: 'Verificación en vivo: ros2 topic echo /cmd_vel siguiendo los mandos', estado: 'hecho' },
      { texto: 'Un robot (turtlesim como mínimo) obedeciendo a la Vita', estado: 'hecho' },
    ],
  },
  {
    id: 'fase-godot35',
    nombre: 'Migración a Godot 3.5 — teleop sobre el engine (histórico)',
    resumen:
      'Replicar la app teleop dentro del fork godot-vita 3.5 mediante un módulo custom del engine (custom_modules) que reutiliza el código C/Rust existente, sin reescribir nada. Validada en hardware; desde 2026-10-29 es histórico (godot/godot35/, docs/20 y docs/21): el proyecto se muda a Godot 4.',
    hitos: [
      { texto: 'G1 — Esqueleto: módulo microros (puente C++→singleton GDScript), escena teleop con stub en el editor, build script y docs', estado: 'hecho' },
      { texto: 'G2 — Template custom compila en el PC: engine godot-vita + microros → vita_release.zip instalado. Prerreq. del VitaSDK resueltos: PVR_PSP2 v3.9, códecs vdpm, patch bullet-vita-no-clew y stub dlfcn.h (docs/20 §Prerrequisitos); uninstall-godot.sh', estado: 'hecho' },
      { texto: 'G3 — Teleop Godot en hardware: el .vpk instala, el singleton MicroROS corre y la sesión XRCE publica /cmd_vel (confirmado en hardware). Lecciones del .vpk: TITLE_ID 9 chars, imágenes sce_sys 8-bit, y el bug del input reliable stream corregido', estado: 'hecho' },
      { texto: 'Fusionado en la línea Godot 4 (2026-10-29): proyecto 3.5 movido a godot/godot35/. El G4 de 3.5 (variante Rust) no se hará: la variante Rust sigue en Godot 4 (docs/19 T8.x)', estado: 'hecho' },
    ],
  },
  {
    id: 'fase-3-4',
    nombre: 'Objetivos 3 y 4 — rviz2 / mini-rviz en la Vita',
    resumen:
      'Compilar rviz2 (o construir el mini-rviz con vitaGL) y visualizar robots, TF, mapas y marcadores en la consola en tiempo real. Plan completo de desarrollo en docs/10.',
    hitos: [
      { texto: 'Etapa A — Auditoría del árbol rviz2 (rclcpp/Qt/OGRE vs newlib) + ADR de decisión (docs/04)', estado: 'hecho' },
      { texto: 'Etapa B — vitaGL en la app: escena 3D + modo VIZ + IP configurable desde la consola (ADR 0007: todo vitaGL); validado en hardware', estado: 'hecho' },
      { texto: 'Sistema de UI no fijo: layout adaptativo + tipografía mejorada (acordado 2026-07-10, parte de la Etapa C)', estado: 'pendiente' },
      { texto: 'Etapa C — UI declarativa v2: imágenes y formas + editor web ampliado', estado: 'pendiente' },
      { texto: 'Etapa D — Módulos duales de visualización: deserializadores CDR + árbol TF + math 3D (módulos hechos y verdes en host; falta integrarlos en main.c / D4)', estado: 'en-curso' },
      { texto: 'Etapa E — mini-rviz MVP: modelo del robot animado por /tf y /joint_states + marcadores + mapa', estado: 'pendiente' },
      { texto: 'Etapa F — Verificación en hardware con robot simulado en tiempo real y cierre', estado: 'pendiente' },
    ],
  },
  {
    id: 'fase-godot',
    nombre: 'Infraestructura de desarrollo — Godot, Rust nativo y optimización',
    resumen:
      'Investigación web de Godot en la Vita y de la pila micro-ROS (docs/12, docs/13, ADR 0008) más la infraestructura que no necesita hardware. Lo que requiere el PC o la Vita está listado como pendiente.',
    hitos: [
      { texto: 'Investigación Godot+ROS2 en la Vita con fuentes y marcas de confianza (docs/12)', estado: 'hecho' },
      { texto: 'ADR 0008: Godot vía módulo C++ estático sobre la capa ROS dual (propuesto)', estado: 'hecho' },
      { texto: 'Módulo dual msg-ring (cola SPSC red→render/Godot): paridad C/Rust + estrés 2 hilos + TSan en host', estado: 'hecho' },
      { texto: 'tools/vita-doctor.sh (diagnóstico de entorno) y serie Rust 03 (atómicos)', estado: 'hecho' },
      { texto: 'Esqueleto godot/ros2_vita + tools/build-godot-template.sh (sin compilar)', estado: 'hecho' },
      { texto: 'Estudio de hardware (memoria, hilos, CPU/GPU) con fuentes y plan de experimentos (docs/14) + sonda tools/hwprobe', estado: 'hecho' },
      { texto: 'Rust nativo: guía de uso y optimización del target Vita (docs/15)', estado: 'hecho' },
      { texto: 'Etapa D1-D3: módulos duales viz-math, msg-cdr (fixtures Jazzy + fuzz) y tf-tree con paridad C/Rust', estado: 'hecho' },
      { texto: 'Lista de páginas no accesibles para leer en el PC (docs/16)', estado: 'hecho' },
      { texto: 'Estudio del código de rclgd y roomba_ws (ROSCon): arquitectura, API, patrones de sensores/HMI y matriz de reutilización (docs/17)', estado: 'hecho' },
      { texto: 'Tabla de paridad de API rclgd ↔ Vita (godot/ros2_vita/API_PARITY.md) y revisión del ADR 0008 (recomienda Godot 4)', estado: 'hecho' },
      { texto: 'Módulo dual msg-schema: codec CDR genérico guiado por esquema (sustituto de ros_babel_fish) con 24 tipos reales y fuzz C=Rust', estado: 'hecho' },
      { texto: 'Decisión del usuario: Godot 4 (godot4-vita) como primera meta; ADR 0008 aceptado', estado: 'hecho' },
      { texto: 'Investigación de migración a Godot 4 (docs/18): internals del loader, clausura de imports, reglas de enlace Rust PIC, riesgos y backlog', estado: 'hecho' },
      { texto: 'Módulo ros2_vita reescrito para Godot 4 en árbol (RosMsg, RosNode, pub/sub/timer, singleton rclgd, transporte loopback) + pruebas GDScript', estado: 'hecho' },
      { texto: 'Parche del loader (11 sce* de red, sincosf, bcmp) + tools/check-vita-imports.py y build-rust-pic.sh', estado: 'hecho' },
      { texto: 'Red: opción A elegida (net-udp inicializa sceNet dentro de libgodot.so)', estado: 'hecho' },
      { texto: 'Plan multiagente de la migración (docs/19): mapa jerárquico, ramas de ataque, 15 agentes + escuadra K, oleadas O0-O4', estado: 'hecho' },
      { texto: 'Oleada O0 (laptop): núcleo xrce_core.c + puerta H1 contra el agente, generador package.xml→schema, TF/logger, net-udp idempotente', estado: 'pendiente' },
      { texto: 'Spike R-G: GDExtension godot-cpp enlazada estáticamente (load_extension_from_function) — go/no-go', estado: 'bloqueado-pc' },
      { texto: 'Fusión de la rama godot-migration (Godot 3.5, hardware OK) como histórico en godot/godot35/; rclgd (jazzy, Godot 4.7.1) clonado en godot/rclgd/', estado: 'hecho' },
      { texto: 'Escuadra K (6 agentes rclgd) en el plan + skills rclgd, godot4-ros-scripting y ros2-vita-godot (docs oficiales, API generada, plantillas, batería para IA limpia)', estado: 'hecho' },
      { texto: 'Skill rclgd actualizada a jazzy@fb12a65: clases tipadas nativas (sin clases sombra), API regenerada; API_PARITY y regla de scripts portables para la Vita (T3.2.4 pendiente)', estado: 'hecho' },
      { texto: 'Verificar las skills: batería E1 con IA limpia y plantillas E2 en el editor de rclgd', estado: 'pendiente' },
      { texto: 'Editor 4.8-dev7 para Linux compilado (mismo árbol que G1, GODOT_VERSION_STATUS=dev7) y VPK de prueba exportado desde CachyOS con tools/export-vita-vpk.sh (godot/g4-smoke, 22 MB; en host da G4 OK)', estado: 'hecho' },
      { texto: 'G4: Godot 4 con ros2_vita corre en la Vita — g4-smoke.vpk muestra fondo verde y «G4 OK» (rclgd.init en loopback + pub/sub de Twist en hardware)', estado: 'hecho' },
      { texto: 'Fork de godot4-vita solo si hace falta (parches mínimos, proponibles a upstream; compatible con el entorno estándar)', estado: 'pendiente' },
      { texto: 'G1: módulo ros2_vita compilado dentro de godot4-vita (Godot 4.8, linuxbsd) y pruebas de host verdes (294 comprobaciones, 0 fallos)', estado: 'hecho' },
      { texto: 'G2: cliente XRCE, 8 módulos C y staticlib Rust compilados en PIC para la Vita; 0 imports fuera de la tabla del loader parcheada, 0 TLS', estado: 'hecho' },
      { texto: 'G3: plantilla de la Vita con el módulo: verify_runtime.py PASS (681 imports) y vita_release.zip (23,5 MB); variante Rust también PASS. VitaGL del port, pcre2-32 propio y stub dlfcn.h; bug de RUSTFLAGS en build-rust-pic.sh corregido', estado: 'hecho' },
      { texto: 'G5: transporte XRCE en ros2_vita — Godot 4 en la Vita publica /vita_hello y /cmd_vel (10 Hz) en ROS 2 Jazzy (confirmado en hardware). La red se inicia en el cargador: dentro de Godot sceNetInit daba UID_RL_OVERFLOW', estado: 'hecho' },
      { texto: 'Estación docker/ propia: agente micro-ROS, monitor de la Vita, puente Zenoh, turtlesim y TurtleBot3/Gazebo', estado: 'hecho' },
      { texto: 'Cruzar fixtures de msg-cdr con ROS2 real (robotnik_dev) y cross-compilar los módulos nuevos', estado: 'bloqueado-pc' },
      { texto: 'Experimentos de latencia XRCE (MTU, heartbeat, streams) y estrés ARM de msg-ring', estado: 'bloqueado-hw' },
      { texto: '"Hola mundo" Godot en la Vita: RAM, FPS, ATTRIBUTE2=12 (P5/P6)', estado: 'bloqueado-hw' },
    ],
  },
  {
    id: 'fase-5-6',
    nombre: 'Objetivos 5-6 — sensores nativos y toolkit',
    resumen:
      'Cámara/giroscopio/táctil trasero como sensores ROS2, y publicar el toolkit completo para la comunidad.',
    hitos: [{ texto: 'Sin diseñar (regla secuencial: esperan al cierre de 3-4)', estado: 'pendiente' }],
  },
];

export const estadoLabels: Record<EstadoHito, { label: string; cls: string }> = {
  hecho: { label: 'Hecho', cls: 'done' },
  'en-curso': { label: 'En curso', cls: 'wip' },
  'bloqueado-pc': { label: 'Siguiente: en el PC', cls: 'pc' },
  'bloqueado-hw': { label: 'Requiere la Vita', cls: 'hw' },
  pendiente: { label: 'Pendiente', cls: 'todo' },
};
