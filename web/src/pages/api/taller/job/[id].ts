// /api/taller/job/[id] — salida en vivo de un job del taller (SSE):
// backlog + líneas nuevas + evento 'fin' con el estado final.
import type { APIRoute } from 'astro';
import { taller, tallerActivo } from '../../../../lib/taller';

export const prerender = false;

export const GET: APIRoute = ({ params, request }) => {
  if (!tallerActivo()) return new Response('taller desactivado', { status: 403 });
  const id = Number(params.id);
  const job = taller.getJob(id);
  if (!job) return new Response('job desconocido', { status: 404 });

  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    start(controller) {
      let limpio = false;
      let baja = () => {};
      const limpiar = () => {
        if (limpio) return;
        limpio = true;
        baja();
        try {
          controller.close();
        } catch {
          /* ya cerrado */
        }
      };
      const enviar = (evento: string, datos: unknown) => {
        try {
          controller.enqueue(encoder.encode(`event: ${evento}\ndata: ${JSON.stringify(datos)}\n\n`));
        } catch {
          limpiar();
        }
      };
      const fin = () =>
        enviar('fin', { estado: job.estado, exitCode: job.exitCode });

      for (const l of job.lineas) enviar('linea', l);
      if (job.estado !== 'corriendo') {
        fin();
        limpiar();
        return;
      }
      baja = taller.suscribir(id, (linea) => {
        if (linea === null) {
          fin();
          limpiar();
        } else {
          enviar('linea', linea);
        }
      });
      request.signal.addEventListener('abort', limpiar);
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
