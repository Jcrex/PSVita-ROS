// taller-client.ts — helper de NAVEGADOR para las páginas del taller:
// lanza un job (POST) y vuelca su salida SSE en un <pre> tipo consola.
export interface FinJob {
  estado: 'ok' | 'error';
  exitCode: number | null;
}

export async function lanzarJob(
  url: string,
  body: unknown,
  consola: HTMLElement,
  alTerminar?: (fin: FinJob) => void,
): Promise<void> {
  consola.textContent = '';
  const log = (l: string, cls?: string) => {
    const div = document.createElement('div');
    if (cls) div.className = cls;
    div.textContent = l;
    consola.appendChild(div);
    consola.scrollTop = consola.scrollHeight;
  };

  let res: Response;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch {
    log('No se pudo contactar con el backend.', 'err');
    return;
  }
  const datos = await res.json().catch(() => ({}));
  if (!res.ok) {
    log(`Error: ${datos.error ?? res.statusText}`, 'err');
    alTerminar?.({ estado: 'error', exitCode: null });
    return;
  }

  const es = new EventSource(`/api/taller/job/${datos.id}`);
  es.addEventListener('linea', (ev) => {
    const l = JSON.parse((ev as MessageEvent).data) as string;
    log(l.startsWith('! ') ? l.slice(2) : l, l.startsWith('! ') ? 'err' : undefined);
  });
  es.addEventListener('fin', (ev) => {
    const fin = JSON.parse((ev as MessageEvent).data) as FinJob;
    log(
      fin.estado === 'ok' ? '— terminado OK —' : `— terminado con error (exit ${fin.exitCode}) —`,
      fin.estado === 'ok' ? 'fin-ok' : 'err',
    );
    es.close();
    alTerminar?.(fin);
  });
  es.onerror = () => {
    // El servidor cierra el stream al acabar; si aún no vimos 'fin', avisar.
    if (es.readyState === EventSource.CLOSED) return;
    es.close();
    log('Stream interrumpido.', 'err');
    alTerminar?.({ estado: 'error', exitCode: null });
  };
}
