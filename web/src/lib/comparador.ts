// comparador.ts — carga las fuentes reales de los módulos duales para la
// sección /comparador (split view C ↔ Rust).
//
// La fuente de verdad son los archivos del repo (modules/*): no se copia
// código a la web. Las páginas que usan esto son PRERENDERIZADAS, así que
// la lectura ocurre en build time (en Docker, modules/ ya se copia a la
// imagen de build — ver web/Dockerfile).
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// En build/dev el cwd es web/, así que la raíz del repo es "..".
const REPO_ROOT = resolve('..');

export interface ArchivoFuente {
  /** Ruta relativa a la raíz del repo (se muestra tal cual). */
  ruta: string;
  codigo: string;
  lineas: number;
}

export interface ModuloDual {
  id: string;
  nombre: string;
  resumen: string;
  /** Qué mirar al comparar (guía de estudio, no marketing). */
  clavesEstudio: string[];
  header: ArchivoFuente;
  c: ArchivoFuente;
  rust: ArchivoFuente;
}

function leer(rutaRelativa: string): ArchivoFuente {
  const codigo = readFileSync(resolve(REPO_ROOT, rutaRelativa), 'utf-8');
  return { ruta: rutaRelativa, codigo, lineas: codigo.split('\n').length };
}

interface DefModulo {
  id: string;
  nombre: string;
  resumen: string;
  clavesEstudio: string[];
  header: string;
  c: string;
  rust: string;
}

// Los módulos duales (3 de la Fase 1 + msg-ring). Si aparece un módulo nuevo, añadirlo
// aquí (y ya sale en /comparador; el resto de la página es genérico).
const DEFS: DefModulo[] = [
  {
    id: 'mem-pool',
    nombre: 'mem-pool — asignador de bloques fijos',
    resumen:
      'Pool de memoria sin malloc: free-list intrusiva dentro del buffer del llamador, detección de doble free y de punteros ajenos.',
    clavesEstudio: [
      'La free-list intrusiva: punteros crudos en C vs. aritmética de punteros con `unsafe` acotado en Rust.',
      'La cabecera de 64 bytes: struct + casts en C vs. `#[repr(C)]` y offsets explícitos en Rust.',
      'Cómo ambos devuelven exactamente los mismos códigos de error (contrato del header, verificado por la paridad).',
    ],
    header: 'modules/mem-pool/include/mem_pool.h',
    c: 'modules/mem-pool/impl-c/mem_pool.c',
    rust: 'modules/mem-pool/impl-rust/src/lib.rs',
  },
  {
    id: 'net-udp',
    nombre: 'net-udp — capa UDP mínima',
    resumen:
      'La capa de red más baja: sceNet en la Vita / sockets POSIX en host, tabla estática de 4 sockets, parser IPv4 propio y timeouts por llamada.',
    clavesEstudio: [
      'El doble backend `#ifdef __vita__` (C) vs. `#[cfg(target_os = "vita")]` (Rust) dentro de la misma implementación.',
      'El parser IPv4 escrito a mano dos veces con el mismo comportamiento ante entradas inválidas.',
      'La tabla estática de sockets: array global mutable en C vs. `static mut`/celdas seguras en Rust.',
    ],
    header: 'modules/net-udp/include/net_udp.h',
    c: 'modules/net-udp/impl-c/net_udp.c',
    rust: 'modules/net-udp/impl-rust/src/lib.rs',
  },
  {
    id: 'microros-transport',
    nombre: 'microros-transport — transporte XRCE',
    resumen:
      'Los 4 callbacks del transporte custom de micro-ROS (open/close/write/read) con la convención uxr: timeout ≠ error. El núcleo de la incógnita dura de la Fase 1.',
    clavesEstudio: [
      'Cómo se expone semántica uxr sin incluir headers de micro-ROS (tipos propios en el header compartido).',
      'La convención timeout ≠ error en read: mismos valores de retorno en ambas implementaciones.',
      'Composición de módulos: este módulo llama a net-udp en los dos lenguajes.',
    ],
    header: 'modules/microros-transport/include/microros_transport.h',
    c: 'modules/microros-transport/impl-c/microros_transport.c',
    rust: 'modules/microros-transport/impl-rust/src/lib.rs',
  },
  {
    id: 'msg-ring',
    nombre: 'msg-ring — cola SPSC sin bloqueos',
    resumen:
      'Cola circular de un productor y un consumidor para pasar mensajes ROS2 del hilo de red al de dibujo (o al de Godot) sin mutex ni malloc. Política de cola llena: descartar y contar.',
    clavesEstudio: [
      '`_Atomic uint32_t` + `memory_order_acquire/release` en C vs. `AtomicU32` + `Ordering` en Rust (docs/rust/03).',
      'Contadores u32 que desbordan a propósito: aritmética normal en C vs. `wrapping_add/sub` en Rust.',
      'Una prueba de estrés con 2 hilos reales compartida por ambas implementaciones.',
    ],
    header: 'modules/msg-ring/include/msg_ring.h',
    c: 'modules/msg-ring/impl-c/msg_ring.c',
    rust: 'modules/msg-ring/impl-rust/src/lib.rs',
  },
  {
    id: 'viz-math',
    nombre: 'viz-math — matemática 3D en f32',
    resumen:
      'vec3, cuaterniones y mat4 column-major para TF, cámara y robot del mini-rviz. En Rust sin std: la libm de C se importa con unsafe extern.',
    clavesEstudio: [
      'Structs `#[repr(C)]` y `Copy` pasados por puntero, frente a structs de C.',
      '`unsafe extern "C"` + `safe fn` para usar sinf/cosf desde no_std.',
      'Valores esperados calculados a mano, idénticos para ambas implementaciones.',
    ],
    header: 'modules/viz-math/include/viz_math.h',
    c: 'modules/viz-math/impl-c/viz_math.c',
    rust: 'modules/viz-math/impl-rust/src/lib.rs',
  },
  {
    id: 'msg-cdr',
    nombre: 'msg-cdr — deserializadores CDR de ROS2',
    resumen:
      'TFMessage, JointState, OccupancyGrid y Marker leídos de un buffer CDR sin malloc, con topes fijos, conteo de descartes y fuzz determinista C vs Rust.',
    clavesEstudio: [
      'El cursor con alineación 4/8 (macro TRY en C) frente a `Result` y el operador `?` en Rust.',
      'Slices `&[u8]` con lifetimes frente a punteros crudos.',
      'Un fuzz que detectó una divergencia real de estado parcial entre las dos implementaciones.',
    ],
    header: 'modules/msg-cdr/include/msg_cdr.h',
    c: 'modules/msg-cdr/impl-c/msg_cdr.c',
    rust: 'modules/msg-cdr/impl-rust/src/lib.rs',
  },
  {
    id: 'tf-tree',
    nombre: 'tf-tree — árbol de transformadas',
    resumen:
      'Último valor por frame y resolución de cadenas padre-hijo (como lookupTransform) con detección de ciclos y tabla fija de 32 frames.',
    clavesEstudio: [
      'Un módulo que depende de otros dos: includes en C, dependencias de ruta en Cargo.',
      '`Option<usize>` y `if let` frente a índices con -1 en C.',
      'Composición de matrices hacia la raíz y su inversa rígida.',
    ],
    header: 'modules/tf-tree/include/tf_tree.h',
    c: 'modules/tf-tree/impl-c/tf_tree.c',
    rust: 'modules/tf-tree/impl-rust/src/lib.rs',
  },
];

export function getModulos(): ModuloDual[] {
  return DEFS.map((d) => ({
    id: d.id,
    nombre: d.nombre,
    resumen: d.resumen,
    clavesEstudio: d.clavesEstudio,
    header: leer(d.header),
    c: leer(d.c),
    rust: leer(d.rust),
  }));
}

export function getModulo(id: string): ModuloDual | undefined {
  return getModulos().find((m) => m.id === id);
}
