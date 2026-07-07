// /api/taller/ui/borrador — borrador del editor de UI por visitante (SQLite).
//
// GET  + header x-client-id            -> { layout: UiLayout | null }
// POST { layout: UiLayout } + header   -> { ok: true }
// Mismo patrón de client-id anónimo que /api/dashboard/layout.
import type { APIRoute } from 'astro';
import { getUiDraft, setUiDraft } from '../../../../lib/db';
import { validarLayout } from '../../../../lib/ui-layout';

export const prerender = false;

const CLIENT_RE = /^[0-9a-f-]{36}$/i;

function clientId(request: Request): string | null {
  const id = request.headers.get('x-client-id');
  return id && CLIENT_RE.test(id) ? id : null;
}

export const GET: APIRoute = ({ request }) => {
  const client = clientId(request);
  if (!client) return new Response(JSON.stringify({ error: 'bad request' }), { status: 400 });
  const json = getUiDraft(client);
  return new Response(JSON.stringify({ layout: json ? JSON.parse(json) : null }), {
    headers: { 'content-type': 'application/json' },
  });
};

export const POST: APIRoute = async ({ request }) => {
  const client = clientId(request);
  if (!client) return new Response(JSON.stringify({ error: 'bad request' }), { status: 400 });
  let body: { layout?: unknown };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad json' }), { status: 400 });
  }
  const res = validarLayout(body.layout);
  if (!res.ok) return new Response(JSON.stringify({ error: res.error }), { status: 400 });
  setUiDraft(client, JSON.stringify(res.layout));
  return new Response(JSON.stringify({ ok: true }), {
    headers: { 'content-type': 'application/json' },
  });
};
