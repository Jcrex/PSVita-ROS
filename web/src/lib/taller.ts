// taller.ts — el "taller" de la web: ejecutar herramientas locales del PC
// de desarrollo (compilar el .vpk, depurar los módulos duales, deploy FTP)
// desde endpoints, con la salida en streaming.
//
// SOLO tiene sentido (y solo se activa) cuando la web corre en el propio
// PC de desarrollo: TALLER_ENABLED=1 en el entorno del servidor. En
// cualquier otro despliegue (docker público, laptop sin toolchain) los
// endpoints devuelven 403 y la página lo explica. Es la "Opción 1" de
// docs/07 §5: invocación local del toolchain; la capa remota (SSH/runner)
// se añadirá después sin cambiar este núcleo.
import { spawn } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';
import { resolve } from 'node:path';

export function tallerActivo(): boolean {
  return process.env.TALLER_ENABLED === '1';
}

// Raíz del repo: en dev/prod local el cwd del server es web/.
export const REPO_ROOT = resolve(process.env.TALLER_REPO_ROOT ?? '..');

// ---------- jobs con salida en streaming ----------

export type JobEstado = 'corriendo' | 'ok' | 'error';

export interface Job {
  id: number;
  tipo: string; // 'build' | 'debug' | 'deploy'
  titulo: string;
  estado: JobEstado;
  exitCode: number | null;
  inicio: string;
  lineas: string[];
}

type Suscriptor = (linea: string | null) => void; // null = job terminado

const MAX_LINEAS = 4000;
const MAX_JOBS_GUARDADOS = 10;

class Taller {
  private jobs = new Map<number, Job>();
  private subs = new Map<number, Set<Suscriptor>>();
  private contador = 0;
  /** Un solo proceso pesado a la vez (cmake y gdb no se pisan). */
  corriendo: Job | null = null;

  getJob(id: number): Job | undefined {
    return this.jobs.get(id);
  }

  /**
   * Lanza `bash -c script`. El script SOLO debe construirse con valores
   * validados por allowlist/regex; los datos libres van por `env`.
   */
  lanzar(
    tipo: string,
    titulo: string,
    script: string,
    env: Record<string, string> = {},
    alTerminar?: (job: Job) => void,
  ): Job {
    if (this.corriendo) {
      throw new Error(`Ya hay un job en marcha: "${this.corriendo.titulo}" (#${this.corriendo.id})`);
    }
    const job: Job = {
      id: ++this.contador,
      tipo,
      titulo,
      estado: 'corriendo',
      exitCode: null,
      inicio: new Date().toISOString(),
      lineas: [],
    };
    this.jobs.set(job.id, job);
    this.subs.set(job.id, new Set());
    this.corriendo = job;

    // Recorte del historial en memoria (el persistente vive en SQLite).
    for (const id of [...this.jobs.keys()].slice(0, -MAX_JOBS_GUARDADOS)) {
      if (this.jobs.get(id)?.estado !== 'corriendo') {
        this.jobs.delete(id);
        this.subs.delete(id);
      }
    }

    const proc = spawn('bash', ['-c', script], {
      cwd: REPO_ROOT,
      env: { ...process.env, ...env },
      stdio: ['ignore', 'pipe', 'pipe'],
    });

    let resto = { out: '', err: '' };
    const trocear = (cual: 'out' | 'err', chunk: Buffer) => {
      resto[cual] += chunk.toString('utf8');
      const partes = resto[cual].split('\n');
      resto[cual] = partes.pop() ?? '';
      for (const p of partes) this.emitir(job, cual === 'err' ? `! ${p}` : p);
    };
    proc.stdout.on('data', (c) => trocear('out', c));
    proc.stderr.on('data', (c) => trocear('err', c));
    proc.on('close', (code) => {
      if (resto.out) this.emitir(job, resto.out);
      if (resto.err) this.emitir(job, `! ${resto.err}`);
      job.exitCode = code;
      job.estado = code === 0 ? 'ok' : 'error';
      this.corriendo = null;
      alTerminar?.(job);
      for (const fn of this.subs.get(job.id) ?? []) fn(null);
    });
    proc.on('error', (e) => {
      this.emitir(job, `! no se pudo lanzar bash: ${e.message}`);
      job.estado = 'error';
      this.corriendo = null;
      for (const fn of this.subs.get(job.id) ?? []) fn(null);
    });
    return job;
  }

  private emitir(job: Job, linea: string) {
    job.lineas.push(linea);
    if (job.lineas.length > MAX_LINEAS) job.lineas.shift();
    for (const fn of this.subs.get(job.id) ?? []) {
      try {
        fn(linea);
      } catch {
        /* suscriptor roto */
      }
    }
  }

  suscribir(id: number, fn: Suscriptor): () => void {
    this.subs.get(id)?.add(fn);
    return () => this.subs.get(id)?.delete(fn);
  }
}

const g = globalThis as typeof globalThis & { __psvitaTaller?: Taller };
export const taller: Taller = (g.__psvitaTaller ??= new Taller());

// ---------- helpers de dominio ----------

export const VARIANTES = ['c', 'rust'] as const;
export type Variante = (typeof VARIANTES)[number];

export const MODULOS = ['mem-pool', 'net-udp', 'microros-transport'] as const;

export const IP_RE = /^(\d{1,3}\.){3}\d{1,3}$/;

export function rutaVpk(variante: Variante): string {
  return resolve(REPO_ROOT, `vita-app/build-${variante}/vita-ros2-hello.vpk`);
}

export interface VpkInfo {
  variante: Variante;
  existe: boolean;
  bytes: number | null;
  modificado: string | null;
}

export function infoVpks(): VpkInfo[] {
  return VARIANTES.map((v) => {
    const ruta = rutaVpk(v);
    if (!existsSync(ruta)) return { variante: v, existe: false, bytes: null, modificado: null };
    const st = statSync(ruta);
    return { variante: v, existe: true, bytes: st.size, modificado: st.mtime.toISOString() };
  });
}
