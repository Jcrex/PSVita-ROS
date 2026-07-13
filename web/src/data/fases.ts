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
      { texto: 'Comparador C++/Rust (split view de los 3 módulos duales, /comparador)', estado: 'hecho' },
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
    id: 'fase-godot',
    nombre: 'Migración a Godot — teleop sobre el engine',
    resumen:
      'Replicar la app teleop dentro del fork godot-vita 3.5 mediante un módulo custom del engine (custom_modules) que reutiliza el código C/Rust existente, sin reescribir nada. Diseño en docs/12, plan en docs/13.',
    hitos: [
      { texto: 'G1 — Esqueleto: módulo microros (puente C++→singleton GDScript), escena teleop con stub en el editor, build script y docs', estado: 'hecho' },
      { texto: 'G2 — Template custom compila en el PC: engine godot-vita + microros → vita_release.zip instalado. Prerreq. del VitaSDK resueltos: PVR_PSP2 v3.9, códecs vdpm, patch bullet-vita-no-clew y stub dlfcn.h (docs/12 §Prerrequisitos); uninstall-godot.sh', estado: 'hecho' },
      { texto: 'G3 — Teleop Godot en hardware: el .vpk instala, el singleton MicroROS corre y la sesión XRCE publica /cmd_vel (confirmado en hardware). Lecciones del .vpk: TITLE_ID 9 chars, imágenes sce_sys 8-bit, y el bug del input reliable stream corregido', estado: 'hecho' },
      { texto: 'G4 — Variante Rust del template (staticlib paraguas en lugar de las libs C)', estado: 'pendiente' },
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
      { texto: 'Etapa D — Módulos duales de visualización: deserializadores CDR + árbol TF + math 3D', estado: 'pendiente' },
      { texto: 'Etapa E — mini-rviz MVP: modelo del robot animado por /tf y /joint_states + marcadores + mapa', estado: 'pendiente' },
      { texto: 'Etapa F — Verificación en hardware con robot simulado en tiempo real y cierre', estado: 'pendiente' },
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
