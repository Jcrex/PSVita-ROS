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

// Los 3 módulos duales de la Fase 1. Si aparece un módulo nuevo, añadirlo
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
