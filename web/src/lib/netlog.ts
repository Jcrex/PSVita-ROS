// netlog.ts — logs de la Vita para el dashboard, DENTRO del backend web.
//
// La app de la Vita (vita-app/src/netlog.c) manda sus logs por UDP al
// puerto 9999 del host configurado como NETLOG_IP. Este módulo los sirve
// al widget de logs del dashboard (datos REALES, no mockeados) por SSE.
//
// Solo puede haber UN receptor por puerto, y en el despliegue docker ese
// receptor es el ingestor del monitor (scripts/netlog-ingester.mjs), que
// arranca en el mismo contenedor y escribe en SQLite. Antes ambos peleaban
// por el 9999 y el que perdía (normalmente este) dejaba el dashboard sin
// logs con "puerto ocupado... reinicia la web". Ahora hay dos fuentes:
//
//  - 'udp':    este módulo abre el socket 9999 él mismo (modo dev en la
//              laptop, sin ingestor).
//  - 'sqlite': sigue las líneas que el ingestor escribe en la SQLite
//              compartida (sondeo cada 1 s). Se usa cuando NETLOG_MODE=
//              sqlite (fijado en docker-compose.yml) o, como degradación
//              automática, cuando el bind da EADDRINUSE — en ese caso
//              reintenta el puerto cada 15 s, así ya no hace falta
//              reiniciar la web al cerrar netlog-listen.sh.
//
// Config por env: NETLOG_PORT (defecto 9999), NETLOG_MODE=sqlite para no
// intentar el socket, NETLOG_DISABLED=1 para apagarlo del todo (p. ej. en
// un despliegue público sin Vita cerca).
import { createSocket, type Socket } from 'node:dgram';
// El filtro de ruido binario es el MISMO que usa el ingestor del monitor
// (una sola fuente de verdad, con tests en scripts/netlog-parser.test.mjs).
// Imprescindible: al 9999 también llegan paquetes binarios de otros
// dispositivos de la red (p. ej. el sondeo broadcast de la app TP-Link
// Kasa, que usa ese mismo puerto) y sin filtro salían como "Ѵ���…".
import { cleanLine } from '../../scripts/netlog-parser.mjs';
import { getLinesAfterGlobal, getMaxLineId } from './db';

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
  /** De dónde salen las líneas cuando activo: socket propio o SQLite del ingestor. */
  fuente: 'udp' | 'sqlite' | null;
  puerto: number;
  error: string | null;
  vitaIp: string | null;
  ultimoPaquete: string | null;
  totalPaquetes: number;
  xrce: XrceHitos;
}

type Suscriptor = (e: LogEntry) => void;

const MAX_BUFFER = 500;
const TAIL_INTERVALO_MS = 1000;
const REINTENTO_BIND_MS = 15_000;
/** Cuántas líneas históricas de SQLite se sirven como backlog al arrancar. */
const TAIL_BACKLOG = 100;

/** 'YYYY-MM-DD HH:MM:SS' (UTC de SQLite) -> ISO. */
const sqliteAIso = (dt: string) => dt.replace(' ', 'T') + '.000Z';

class Netlog {
  private socket: Socket | null = null;
  private buffer: LogEntry[] = [];
  private subs = new Set<Suscriptor>();
  private contador = 0;
  private tailTimer: ReturnType<typeof setInterval> | null = null;
  private reintentoTimer: ReturnType<typeof setInterval> | null = null;
  private ultimaLineaId = 0;

  estado: NetlogEstado = {
    activo: false,
    fuente: null,
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
    if (process.env.NETLOG_MODE === 'sqlite') {
      this.iniciarTail(null);
      return;
    }
    this.abrir();
  }

  private abrir() {
    const s = createSocket('udp4');
    s.on('error', (err: NodeJS.ErrnoException) => {
      s.close();
      this.socket = null;
      if (err.code === 'EADDRINUSE') {
        // Otro receptor (ingestor o netlog-listen.sh) tiene el puerto:
        // degradar a leer de SQLite y reintentar el socket periódicamente.
        this.iniciarTail(
          `Puerto ${this.estado.puerto} ocupado por otro receptor; mostrando lo que llega a SQLite y reintentando cada ${REINTENTO_BIND_MS / 1000} s.`,
        );
        this.programarReintento();
      } else {
        this.estado.activo = false;
        this.estado.fuente = null;
        this.estado.error = String(err.message ?? err);
      }
    });
    s.on('listening', () => {
      this.detenerTail();
      this.detenerReintento();
      this.estado.activo = true;
      this.estado.fuente = 'udp';
      this.estado.error = null;
    });
    s.on('message', (msg, rinfo) => this.recibir(msg, rinfo.address));
    s.bind(this.estado.puerto);
    this.socket = s;
  }

  private programarReintento() {
    if (this.reintentoTimer) return;
    this.reintentoTimer = setInterval(() => this.abrir(), REINTENTO_BIND_MS);
  }

  private detenerReintento() {
    if (!this.reintentoTimer) return;
    clearInterval(this.reintentoTimer);
    this.reintentoTimer = null;
  }

  private recibir(msg: Buffer, ip: string) {
    const ahora = new Date().toISOString();
    let hayTexto = false;
    for (const cruda of msg.toString('utf8').split('\n')) {
      const texto = cleanLine(cruda);
      if (!texto) continue;
      hayTexto = true;
      this.emitir({ n: ++this.contador, ts: ahora, ip, texto });
    }
    // La basura binaria de otros dispositivos no cuenta como señal de la
    // Vita: solo los paquetes con texto real actualizan la salud.
    if (hayTexto) {
      this.estado.vitaIp = ip;
      this.estado.ultimoPaquete = ahora;
      this.estado.totalPaquetes++;
    }
  }

  // ---- modo 'sqlite': seguir las líneas que escribe el ingestor ----

  private iniciarTail(nota: string | null) {
    if (this.tailTimer) return;
    this.estado.activo = true;
    this.estado.fuente = 'sqlite';
    this.estado.error = nota;
    this.ultimaLineaId = Math.max(0, getMaxLineId() - TAIL_BACKLOG);
    const tick = () => {
      try {
        for (const l of getLinesAfterGlobal(this.ultimaLineaId)) {
          this.ultimaLineaId = l.id;
          const ts = sqliteAIso(l.received_at);
          this.estado.vitaIp = l.source_ip?.split(':')[0] ?? this.estado.vitaIp;
          this.estado.ultimoPaquete = ts;
          this.estado.totalPaquetes++;
          this.emitir({
            n: ++this.contador,
            ts,
            ip: this.estado.vitaIp ?? '?',
            texto: l.raw_text,
          });
        }
      } catch (err) {
        this.estado.error = `Error leyendo SQLite: ${String(err)}`;
      }
    };
    tick();
    this.tailTimer = setInterval(tick, TAIL_INTERVALO_MS);
  }

  private detenerTail() {
    if (!this.tailTimer) return;
    clearInterval(this.tailTimer);
    this.tailTimer = null;
  }

  // ---- común a ambas fuentes ----

  private emitir(entry: LogEntry) {
    if (entry.texto.includes('SESION XRCE ESTABLECIDA'))
      this.estado.xrce.sesionEstablecida = entry.ts;
    if (entry.texto.includes('/pc_hello recibido'))
      this.estado.xrce.pcHelloRecibido = entry.ts;

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
