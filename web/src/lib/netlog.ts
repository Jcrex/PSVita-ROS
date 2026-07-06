// netlog.ts — receptor UDP de los logs de la Vita, DENTRO del backend web.
//
// La app de la Vita (vita-app/src/netlog.c) manda sus logs por UDP al
// puerto 9999 del host configurado como NETLOG_IP. Hasta ahora se leían
// con tools/netlog-listen.sh; este módulo hace lo mismo desde el servidor
// Astro para alimentar el widget de logs del dashboard (datos REALES, no
// mockeados) por SSE.
//
// Ojo: solo puede haber UN receptor por puerto — si netlog-listen.sh está
// corriendo, este socket no podrá abrir (EADDRINUSE) y el dashboard lo
// mostrará como "listener inactivo" en vez de romperse.
//
// Config por env: NETLOG_PORT (defecto 9999), NETLOG_DISABLED=1 para no
// abrir el socket (p. ej. en un despliegue público sin Vita cerca).
import { createSocket, type Socket } from 'node:dgram';

export interface LogEntry {
  n: number;
  ts: string; // ISO
  ip: string;
  texto: string;
}

export interface XrceHitos {
  /** Última vez que el netlog vio "SESION XRCE ESTABLECIDA". */
  sesionEstablecida: string | null;
  /** Última vez que se vio "/pc_hello recibido" (criterio 2 en vivo). */
  pcHelloRecibido: string | null;
}

export interface NetlogEstado {
  activo: boolean;
  puerto: number;
  error: string | null;
  vitaIp: string | null;
  ultimoPaquete: string | null;
  totalPaquetes: number;
  xrce: XrceHitos;
}

type Suscriptor = (e: LogEntry) => void;

const MAX_BUFFER = 500;

class Netlog {
  private socket: Socket | null = null;
  private buffer: LogEntry[] = [];
  private subs = new Set<Suscriptor>();
  private contador = 0;

  estado: NetlogEstado = {
    activo: false,
    puerto: Number(process.env.NETLOG_PORT ?? 9999),
    error: null,
    vitaIp: null,
    ultimoPaquete: null,
    totalPaquetes: 0,
    xrce: { sesionEstablecida: null, pcHelloRecibido: null },
  };

  constructor() {
    if (process.env.NETLOG_DISABLED === '1') {
      this.estado.error = 'Desactivado por NETLOG_DISABLED=1';
      return;
    }
    this.abrir();
  }

  private abrir() {
    const s = createSocket('udp4');
    s.on('error', (err: NodeJS.ErrnoException) => {
      this.estado.activo = false;
      this.estado.error =
        err.code === 'EADDRINUSE'
          ? `Puerto ${this.estado.puerto} ocupado (¿netlog-listen.sh corriendo?). Cierra el otro receptor y reinicia la web.`
          : String(err.message ?? err);
      s.close();
      this.socket = null;
    });
    s.on('listening', () => {
      this.estado.activo = true;
      this.estado.error = null;
    });
    s.on('message', (msg, rinfo) => this.recibir(msg, rinfo.address));
    s.bind(this.estado.puerto);
    this.socket = s;
  }

  private recibir(msg: Buffer, ip: string) {
    const ahora = new Date().toISOString();
    this.estado.vitaIp = ip;
    this.estado.ultimoPaquete = ahora;
    this.estado.totalPaquetes++;

    // Un datagrama puede traer varias líneas; el arranque de la app puede
    // traer ruido binario (visto en hardware) — se filtra a imprimibles.
    for (const cruda of msg.toString('utf8').split('\n')) {
      const texto = cruda.replace(/[^\x20-\x7e¡-￿]/g, '').trim();
      if (!texto) continue;
      if (texto.includes('SESION XRCE ESTABLECIDA')) this.estado.xrce.sesionEstablecida = ahora;
      if (texto.includes('/pc_hello recibido')) this.estado.xrce.pcHelloRecibido = ahora;

      const entry: LogEntry = { n: ++this.contador, ts: ahora, ip, texto };
      this.buffer.push(entry);
      if (this.buffer.length > MAX_BUFFER) this.buffer.shift();
      for (const fn of this.subs) {
        try {
          fn(entry);
        } catch {
          /* un suscriptor roto no tumba al resto */
        }
      }
    }
  }

  backlog(): LogEntry[] {
    return [...this.buffer];
  }

  suscribir(fn: Suscriptor): () => void {
    this.subs.add(fn);
    return () => this.subs.delete(fn);
  }
}

// Singleton real aunque Vite/Astro reevalúe el módulo en dev (HMR).
const g = globalThis as typeof globalThis & { __psvitaNetlog?: Netlog };
export const netlog: Netlog = (g.__psvitaNetlog ??= new Netlog());
