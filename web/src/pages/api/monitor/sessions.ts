import type { APIRoute } from 'astro';
import { listSessions } from '../../../lib/db';

export const prerender = false;

export const GET: APIRoute = () => {
  return new Response(JSON.stringify(listSessions()), {
    headers: { 'content-type': 'application/json' },
  });
};
