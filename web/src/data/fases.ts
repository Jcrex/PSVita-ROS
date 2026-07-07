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
      { texto: 'UI de la app dibujada en la Vita real (build con vita2d en el PC + hardware)', estado: 'bloqueado-pc' },
      { texto: 'Capa remota del compilador (cuando la web no corra en el PC) y debug en la Vita real', estado: 'pendiente' },
    ],
  },
  {
    id: 'fase-2',
    nombre: 'Objetivo 2 — Control de robot',
    resumen:
      'Sticks, botones y táctiles publicando geometry_msgs/Twist. La Fase 1 ya está validada, así que el diseño detallado puede arrancar.',
    hitos: [{ texto: 'Diseño detallado', estado: 'pendiente' }],
  },
  {
    id: 'fase-3-6',
    nombre: 'Objetivos 3-6 — rviz2, sensores, toolkit',
    resumen:
      'Portar rviz2 (o mini-rviz con vitaGL), cámara/giroscopio como sensores ROS2, y publicar el toolkit completo.',
    hitos: [
      { texto: 'Investigación de portabilidad rviz2 (método fijado en docs/04)', estado: 'pendiente' },
    ],
  },
];

export const estadoLabels: Record<EstadoHito, { label: string; cls: string }> = {
  hecho: { label: 'Hecho', cls: 'done' },
  'en-curso': { label: 'En curso', cls: 'wip' },
  'bloqueado-pc': { label: 'Siguiente: en el PC', cls: 'pc' },
  'bloqueado-hw': { label: 'Requiere la Vita', cls: 'hw' },
  pendiente: { label: 'Pendiente', cls: 'todo' },
};
