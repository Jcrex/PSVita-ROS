// client-id.ts — identificador anónimo por navegador (localStorage), el
// mismo para el checklist de las guías y el layout del dashboard.
//
// Ojo: crypto.randomUUID() SOLO existe en contextos seguros (https o
// localhost). Al entrar por http://192.168.1.108:4321 desde otra máquina
// no está definido, y el TypeError tumbaba el script entero de la página
// (dashboard en blanco). Por eso aquí hay un fallback con Math.random():
// para un id anónimo de preferencias no hace falta aleatoriedad
// criptográfica, solo que no colisione y que cumpla el formato UUID que
// valida el backend (/^[0-9a-f-]{36}$/i).
export function obtenerClientId(): string {
  let id = localStorage.getItem('psvita-ros-client');
  if (!id) {
    id =
      typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function'
        ? crypto.randomUUID()
        : 'xxxxxxxx-xxxx-4xxx-8xxx-xxxxxxxxxxxx'.replace(/x/g, () =>
            Math.floor(Math.random() * 16).toString(16),
          );
    localStorage.setItem('psvita-ros-client', id);
  }
  return id;
}
