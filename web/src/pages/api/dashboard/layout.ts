// /api/dashboard/layout — persistencia del layout de widgets (SQLite).
//
// GET  + header x-client-id           -> { layout: string[] | null }
// POST { layout: string[] } + header  -> { ok: true }
// Mismo patrón de client-id anónimo que /api/checklist.
import type { APIRoute } from 'astro';
import { getDashboardLayout, setDashboardLayout } from '../../../lib/db';

export const prerender = false;

const CLIENT_RE = /^[0-9a-f-]{36}$/i;
export const WIDGETS_VALIDOS = ['estado', 'logs', 'topics'];

function clientId(request: Request): string | null {
  const id = request.headers.get('x-client-id');
  return id && CLIENT_RE.test(id) ? id : null;
}

export const GET: APIRoute = ({ request }) => {
  const client = clientId(request);
  if (!client) return new Response(JSON.stringify({ error: 'bad request' }), { status: 400 });
  return new Response(JSON.stringify({ layout: getDashboardLayout(client) }), {
    headers: { 'content-type': 'application/json' },
  });
};

export const POST: APIRoute = async ({ request }) => {
  const client = clientId(request);
  let body: { layout?: unknown };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad json' }), { status: 400 });
  }
  const layout = body.layout;
  const valido =
    Array.isArray(layout) &&
    layout.length <= 12 &&
    layout.every((w) => typeof w === 'string' && WIDGETS_VALIDOS.includes(w));
  if (!client || !valido) {
    return new Response(JSON.stringify({ error: 'bad request' }), { status: 400 });
  }
  setDashboardLayout(client, layout as string[]);
  return new Response(JSON.stringify({ ok: true }), {
    headers: { 'content-type': 'application/json' },
  });
};
