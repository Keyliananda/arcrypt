CREATE TABLE IF NOT EXISTS relay_mailboxes (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  mailbox_id_hash CHAR(64) NOT NULL,
  pop_key_commitment CHAR(64) NOT NULL,
  created_at DATETIME NOT NULL,
  updated_at DATETIME NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_relay_mailbox_hash (mailbox_id_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS relay_messages (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  message_id VARCHAR(64) NOT NULL,
  mailbox_id_hash CHAR(64) NOT NULL,
  ciphertext LONGBLOB NOT NULL,
  size_bytes INT UNSIGNED NOT NULL,
  client_msg_id VARCHAR(128) DEFAULT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'queued',
  created_at DATETIME NOT NULL,
  expires_at DATETIME NOT NULL,
  acked_at DATETIME DEFAULT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_relay_message_id (message_id),
  UNIQUE KEY uniq_relay_mailbox_client_msg (mailbox_id_hash, client_msg_id),
  KEY idx_relay_messages_mailbox_created (mailbox_id_hash, created_at, id),
  KEY idx_relay_messages_expires_at (expires_at),
  KEY idx_relay_messages_acked_at (acked_at),
  CONSTRAINT fk_relay_messages_mailbox
    FOREIGN KEY (mailbox_id_hash)
    REFERENCES relay_mailboxes(mailbox_id_hash)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

CREATE TABLE IF NOT EXISTS relay_nonces (
  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  mailbox_id_hash CHAR(64) NOT NULL,
  nonce VARCHAR(96) NOT NULL,
  seen_at DATETIME NOT NULL,
  expires_at DATETIME NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uniq_relay_nonce (mailbox_id_hash, nonce),
  KEY idx_relay_nonces_expires_at (expires_at),
  CONSTRAINT fk_relay_nonces_mailbox
    FOREIGN KEY (mailbox_id_hash)
    REFERENCES relay_mailboxes(mailbox_id_hash)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
