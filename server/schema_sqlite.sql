CREATE TABLE IF NOT EXISTS device_tokens (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token TEXT NOT NULL UNIQUE,
  topic TEXT NOT NULL,
  env TEXT NOT NULL,
  created_at TEXT NOT NULL,
  last_seen TEXT,
  expires_at TEXT
);

CREATE TABLE IF NOT EXISTS wake_requests (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  token_id INTEGER NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  attempts INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  FOREIGN KEY (token_id) REFERENCES device_tokens(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS rate_limits (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  scope TEXT NOT NULL,
  rate_key TEXT NOT NULL,
  window_start TEXT NOT NULL,
  count INTEGER NOT NULL DEFAULT 0,
  UNIQUE (scope, rate_key, window_start)
);
