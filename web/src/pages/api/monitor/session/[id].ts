import type { APIRoute } from 'astro';
import { getSession, getSessionLines } from '../../../../lib/db';

export const prerender = false;

export const GET: APIRoute = ({ params }) => {
  const id = Number(params.id);
  if (!Number.isInteger(id) || id <= 0) {
    return new Response(JSON.stringify({ error: 'bad id' }), { status: 400 });
  }
  const session = getSession(id);
  if (!session) {
    return new Response(JSON.stringify({ error: 'not found' }), { status: 404 });
  }
  return new Response(
    JSON.stringify({ session, lines: getSessionLines(id) }),
    { headers: { 'content-type': 'application/json' } },
  );
};
