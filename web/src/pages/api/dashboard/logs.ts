// /api/dashboard/logs — stream SSE de los logs UDP de la Vita (netlog).
//
// Manda el backlog al conectar y cada línea nueva en vivo. El cliente
// usa EventSource; heartbeat cada 15 s para que los proxies no corten.
import type { APIRoute } from 'astro';
import { netlog, type LogEntry } from '../../../lib/netlog';

export const prerender = false;

export const GET: APIRoute = ({ request }) => {
  const encoder = new TextEncoder();

  const stream = new ReadableStream({
    start(controller) {
      const enviar = (evento: string, datos: unknown) => {
        try {
          controller.enqueue(encoder.encode(`event: ${evento}\ndata: ${JSON.stringify(datos)}\n\n`));
        } catch {
          limpiar();
        }
      };

      const alRecibir = (e: LogEntry) => enviar('log', e);
      const baja = netlog.suscribir(alRecibir);
      const heartbeat = setInterval(() => {
        try {
          controller.enqueue(encoder.encode(': ping\n\n'));
        } catch {
          limpiar();
        }
      }, 15_000);

      let limpio = false;
      const limpiar = () => {
        if (limpio) return;
        limpio = true;
        baja();
        clearInterval(heartbeat);
        try {
          controller.close();
        } catch {
          /* ya cerrado */
        }
      };

      request.signal.addEventListener('abort', limpiar);

      enviar('estado', netlog.estado);
      for (const e of netlog.backlog()) enviar('log', e);
    },
  });

  return new Response(stream, {
    headers: {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache',
      connection: 'keep-alive',
    },
  });
};
