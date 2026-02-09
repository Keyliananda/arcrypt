CREATE TABLE IF NOT EXISTS relay_mailboxes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  mailbox_id_hash TEXT NOT NULL UNIQUE,
  pop_key_commitment TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS relay_messages (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  message_id TEXT NOT NULL UNIQUE,
  mailbox_id_hash TEXT NOT NULL,
  ciphertext BLOB NOT NULL,
  size_bytes INTEGER NOT NULL,
  client_msg_id TEXT,
  status TEXT NOT NULL DEFAULT 'queued',
  created_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  acked_at TEXT,
  FOREIGN KEY (mailbox_id_hash) REFERENCES relay_mailboxes(mailbox_id_hash) ON DELETE CASCADE,
  UNIQUE (mailbox_id_hash, client_msg_id)
);

CREATE TABLE IF NOT EXISTS relay_nonces (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  mailbox_id_hash TEXT NOT NULL,
  nonce TEXT NOT NULL,
  seen_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  FOREIGN KEY (mailbox_id_hash) REFERENCES relay_mailboxes(mailbox_id_hash) ON DELETE CASCADE,
  UNIQUE (mailbox_id_hash, nonce)
);

CREATE INDEX IF NOT EXISTS idx_relay_messages_mailbox_created
  ON relay_messages (mailbox_id_hash, created_at, id);

CREATE INDEX IF NOT EXISTS idx_relay_messages_expires_at
  ON relay_messages (expires_at);

CREATE INDEX IF NOT EXISTS idx_relay_messages_acked_at
  ON relay_messages (acked_at);

CREATE INDEX IF NOT EXISTS idx_relay_nonces_expires_at
  ON relay_nonces (expires_at);
