import type { APIRoute } from 'astro';
import { getLastReceivedAt } from '../../../lib/db';

export const prerender = false;

export const GET: APIRoute = () => {
  return new Response(
    JSON.stringify({ lastReceivedAt: getLastReceivedAt() }),
    { headers: { 'content-type': 'application/json' } },
  );
};
