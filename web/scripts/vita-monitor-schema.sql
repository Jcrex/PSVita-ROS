-- vita-monitor-schema.sql — esquema del dashboard /monitor (netlog en
-- vivo de la Vita). Un solo archivo, leído por dos consumidores:
--   - web/src/lib/db.ts (Astro): import ?raw de Vite, se inlinea en el
--     build, por eso no necesita resolver una ruta en runtime.
--   - web/scripts/netlog-ingester.mjs: proceso Node aparte, sin bundler,
--     lo lee con readFileSync relativo a su propio directorio.
CREATE TABLE IF NOT EXISTS vita_sessions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  started_at TEXT NOT NULL DEFAULT (datetime('now')),
  ended_at TEXT,
  source_ip TEXT,
  status TEXT NOT NULL DEFAULT 'en-curso'
);

CREATE TABLE IF NOT EXISTS vita_log_lines (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id INTEGER NOT NULL REFERENCES vita_sessions(id),
  received_at TEXT NOT NULL DEFAULT (datetime('now')),
  raw_text TEXT NOT NULL,
  kind TEXT NOT NULL DEFAULT 'normal'
);
