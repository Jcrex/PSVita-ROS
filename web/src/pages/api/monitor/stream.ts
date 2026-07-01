import type { APIRoute } from 'astro';
import { getLatestSession, getLinesAfter } from '../../../lib/db';

export const prerender = false;

const POLL_MS = 400;

export const GET: APIRoute = () => {
  const encoder = new TextEncoder();
  let closed = false;
  let activeSessionId: number | null = null;
  let lastLineId = 0;
  let timer: ReturnType<typeof setTimeout>;

  const stream = new ReadableStream({
    start(controller) {
      const send = (event: string | null, data: unknown) => {
        const prefix = event ? `event: ${event}\n` : '';
        controller.enqueue(
          encoder.encode(`${prefix}data: ${JSON.stringify(data)}\n\n`),
        );
      };

      const tick = () => {
        if (closed) return;
        const latest = getLatestSession();
        if (!latest) {
          timer = setTimeout(tick, POLL_MS);
          return;
        }
        if (latest.id !== activeSessionId) {
          activeSessionId = latest.id;
          lastLineId = 0;
          send('session-changed', { sessionId: activeSessionId });
        }
        const newLines = getLinesAfter(activeSessionId, lastLineId);
        for (const line of newLines) {
          lastLineId = line.id;
          send(null, line);
        }
        timer = setTimeout(tick, POLL_MS);
      };
      tick();
    },
    cancel() {
      closed = true;
      clearTimeout(timer);
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
