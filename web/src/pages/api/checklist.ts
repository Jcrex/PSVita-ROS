// /api/checklist — endpoint dinámico (no prerenderizado) del checklist.
//
// GET  ?slug=<guia>     + header x-client-id  -> { stepId: boolean, ... }
// POST { slug, step, done } + header x-client-id -> { ok: true }
//
// El client-id es un UUID anónimo que genera el navegador; no hay cuentas
// ni datos personales. Validación estricta de entradas antes de tocar la DB.
import type { APIRoute } from 'astro';
import { getSteps, setStep } from '../../lib/db';
import { checklists } from '../../data/checklists';

export const prerender = false;

const CLIENT_RE = /^[0-9a-f-]{36}$/i;

function clientId(request: Request): string | null {
  const id = request.headers.get('x-client-id');
  return id && CLIENT_RE.test(id) ? id : null;
}

export const GET: APIRoute = ({ request, url }) => {
  const client = clientId(request);
  const slug = url.searchParams.get('slug') ?? '';
  if (!client || !(slug in checklists)) {
    return new Response(JSON.stringify({ error: 'bad request' }), { status: 400 });
  }
  return new Response(JSON.stringify(getSteps(client, slug)), {
    headers: { 'content-type': 'application/json' },
  });
};

export const POST: APIRoute = async ({ request }) => {
  const client = clientId(request);
  let body: { slug?: string; step?: string; done?: boolean };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'bad json' }), { status: 400 });
  }
  const { slug, step, done } = body;
  const validStep =
    typeof slug === 'string' &&
    slug in checklists &&
    typeof step === 'string' &&
    checklists[slug].some((s) => s.id === step);

  if (!client || !validStep || typeof done !== 'boolean') {
    return new Response(JSON.stringify({ error: 'bad request' }), { status: 400 });
  }
  setStep(client, slug, step, done);
  return new Response(JSON.stringify({ ok: true }), {
    headers: { 'content-type': 'application/json' },
  });
};
