CREATE TABLE IF NOT EXISTS uploads (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  caller TEXT NOT NULL,
  filename TEXT NOT NULL,
  bytes INTEGER NOT NULL,
  sha256 TEXT NOT NULL,
  b2_key TEXT NOT NULL,
  url TEXT NOT NULL,
  created_at TEXT NOT NULL,
  -- Populated only for uploads with media metadata (kind episode or movie)
  -- NULL for plain/generic uploads. Doubles as a catalog for /catalog.
  media_kind TEXT,
  title TEXT,
  year INTEGER,
  season_number INTEGER,
  episode_number INTEGER,
  episode_title TEXT
);

CREATE INDEX IF NOT EXISTS idx_uploads_caller_created_at ON uploads (caller, created_at);
CREATE INDEX IF NOT EXISTS idx_uploads_media_kind_title ON uploads (media_kind, title);
