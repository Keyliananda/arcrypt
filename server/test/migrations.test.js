"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const sqlite3 = require("sqlite3");
const { runMigrations } = require("../src/migrations");
const { SqliteStore } = require("../src/store/sqlite");

const LEGACY_WAKE_SCHEMA = `
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
`;

function execSql(filename, sql) {
  return new Promise((resolve, reject) => {
    const db = new sqlite3.Database(filename);
    db.exec(sql, (err) => {
      if (err) {
        db.close(() => reject(err));
        return;
      }
      db.close((closeErr) => {
        if (closeErr) {
          reject(closeErr);
          return;
        }
        resolve();
      });
    });
  });
}

function readRows(filename, sql, params = []) {
  return new Promise((resolve, reject) => {
    const db = new sqlite3.Database(filename);
    db.all(sql, params, (err, rows) => {
      if (err) {
        db.close(() => reject(err));
        return;
      }
      db.close((closeErr) => {
        if (closeErr) {
          reject(closeErr);
          return;
        }
        resolve(rows);
      });
    });
  });
}

function tmpSqliteFile(prefix) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  return path.join(dir, "test.sqlite");
}

test("sqlite migrations apply once and are idempotent", async () => {
  const filename = tmpSqliteFile("relay-migrate-");
  await execSql(filename, LEGACY_WAKE_SCHEMA);

  const firstRun = await runMigrations({ driver: "sqlite", filename });
  assert.deepEqual(firstRun.applied, ["20260208_srv003_message_relay_v1"]);
  assert.deepEqual(firstRun.skipped, []);

  const secondRun = await runMigrations({ driver: "sqlite", filename });
  assert.deepEqual(secondRun.applied, []);
  assert.deepEqual(secondRun.skipped, ["20260208_srv003_message_relay_v1"]);

  const rows = await readRows(
    filename,
    "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
  );
  const tableNames = rows.map((row) => row.name);

  assert.ok(tableNames.includes("relay_mailboxes"));
  assert.ok(tableNames.includes("relay_messages"));
  assert.ok(tableNames.includes("relay_nonces"));
  assert.ok(tableNames.includes("schema_migrations"));
});

test("sqlite relay cleanup removes expired and stale acked rows", async () => {
  const filename = tmpSqliteFile("relay-cleanup-");
  await execSql(filename, LEGACY_WAKE_SCHEMA);
  await runMigrations({ driver: "sqlite", filename });

  const store = new SqliteStore({ filename });
  try {
    const now = new Date("2026-02-08T12:00:00Z");
    const mailbox = "a".repeat(64);

    await store.run(
      "INSERT INTO relay_mailboxes (mailbox_id_hash, pop_key_commitment, created_at, updated_at) VALUES (?, ?, ?, ?)",
      [mailbox, "b".repeat(64), now.toISOString(), now.toISOString()]
    );

    await store.run(
      "INSERT INTO relay_messages (message_id, mailbox_id_hash, ciphertext, size_bytes, status, created_at, expires_at, acked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [
        "msg-expired",
        mailbox,
        Buffer.from("expired"),
        7,
        "queued",
        "2026-02-08T11:00:00Z",
        "2026-02-08T11:30:00Z",
        null
      ]
    );

    await store.run(
      "INSERT INTO relay_messages (message_id, mailbox_id_hash, ciphertext, size_bytes, status, created_at, expires_at, acked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [
        "msg-active",
        mailbox,
        Buffer.from("active"),
        6,
        "queued",
        "2026-02-08T11:00:00Z",
        "2026-02-08T13:00:00Z",
        null
      ]
    );

    await store.run(
      "INSERT INTO relay_messages (message_id, mailbox_id_hash, ciphertext, size_bytes, status, created_at, expires_at, acked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [
        "msg-acked-old",
        mailbox,
        Buffer.from("acked"),
        5,
        "acked",
        "2026-02-08T10:00:00Z",
        "2026-02-08T13:00:00Z",
        "2026-02-08T11:44:00Z"
      ]
    );

    await store.run(
      "INSERT INTO relay_messages (message_id, mailbox_id_hash, ciphertext, size_bytes, status, created_at, expires_at, acked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
      [
        "msg-acked-recent",
        mailbox,
        Buffer.from("recent"),
        6,
        "acked",
        "2026-02-08T10:00:00Z",
        "2026-02-08T13:00:00Z",
        "2026-02-08T11:50:00Z"
      ]
    );

    await store.run(
      "INSERT INTO relay_nonces (mailbox_id_hash, nonce, seen_at, expires_at) VALUES (?, ?, ?, ?)",
      [mailbox, "nonce-expired", "2026-02-08T11:40:00Z", "2026-02-08T11:50:00Z"]
    );
    await store.run(
      "INSERT INTO relay_nonces (mailbox_id_hash, nonce, seen_at, expires_at) VALUES (?, ?, ?, ?)",
      [mailbox, "nonce-active", "2026-02-08T11:55:00Z", "2026-02-08T12:10:00Z"]
    );

    const result = await store.cleanupExpiredRelayData(now, 900);
    assert.deepEqual(result, {
      messages_expired: 1,
      messages_acked: 1,
      nonces_expired: 1
    });

    const messageCount = await store.get("SELECT COUNT(*) AS count FROM relay_messages");
    const nonceCount = await store.get("SELECT COUNT(*) AS count FROM relay_nonces");
    const expiredMessage = await store.get(
      "SELECT id FROM relay_messages WHERE message_id = ?",
      ["msg-expired"]
    );
    const oldAckMessage = await store.get(
      "SELECT id FROM relay_messages WHERE message_id = ?",
      ["msg-acked-old"]
    );
    const recentAckMessage = await store.get(
      "SELECT id FROM relay_messages WHERE message_id = ?",
      ["msg-acked-recent"]
    );

    assert.equal(messageCount.count, 2);
    assert.equal(nonceCount.count, 1);
    assert.equal(expiredMessage, null);
    assert.equal(oldAckMessage, null);
    assert.ok(recentAckMessage);
  } finally {
    await store.close();
  }
});
