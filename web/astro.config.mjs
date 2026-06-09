// astro.config.mjs — configuración del sitio.
//
// output: 'server' + adaptador Node "standalone": el build produce un
// servidor Node autocontenido (dist/server/entry.mjs) que sirve páginas
// prerenderizadas Y los endpoints dinámicos (/api/*, respaldados por
// SQLite). Es lo que corre dentro del contenedor Docker.
import node from '@astrojs/node';
import { defineConfig } from 'astro/config';

export default defineConfig({
  output: 'server',
  adapter: node({ mode: 'standalone' }),
  // Dominio previsto (subdominio dedicado bajo jcrex999.com); ajustar si
  // el subdominio final cambia. Solo afecta a URLs canónicas/sitemap.
  site: 'https://psvita-ros.jcrex999.com',
  server: {
    host: true,
    port: 4321,
  },
});
