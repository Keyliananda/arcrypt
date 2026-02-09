"use strict";

const sqlite3 = require("sqlite3");

function toIso(value) {
  if (!value) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return date.toISOString();
}

function toDate(value) {
  if (value instanceof Date) {
    return value;
  }
  return new Date(value);
}

class SqliteStore {
  constructor(options) {
    const filename = options.filename || ":memory:";
    this.db = new sqlite3.Database(filename);
    this.db.run("PRAGMA foreign_keys = ON");
  }

  run(sql, params = []) {
    return new Promise((resolve, reject) => {
      this.db.run(sql, params, function onRun(err) {
        if (err) {
          reject(err);
          return;
        }
        resolve(this);
      });
    });
  }

  get(sql, params = []) {
    return new Promise((resolve, reject) => {
      this.db.get(sql, params, (err, row) => {
        if (err) {
          reject(err);
          return;
        }
        resolve(row || null);
      });
    });
  }

  all(sql, params = []) {
    return new Promise((resolve, reject) => {
      this.db.all(sql, params, (err, rows) => {
        if (err) {
          reject(err);
          return;
        }
        resolve(rows || []);
      });
    });
  }

  async upsertToken({ token, topic, env, lastSeen, expiresAt = null }) {
    const now = toIso(lastSeen);
    const expires = toIso(expiresAt);
    await this.run(
      "INSERT OR IGNORE INTO device_tokens (token, topic, env, last_seen, created_at, expires_at) VALUES (?, ?, ?, ?, ?, ?)",
      [token, topic, env, now, now, expires]
    );
    await this.run(
      "UPDATE device_tokens SET topic = ?, env = ?, last_seen = ?, expires_at = ? WHERE token = ?",
      [topic, env, now, expires, token]
    );
    const row = await this.get("SELECT id FROM device_tokens WHERE token = ? LIMIT 1", [token]);
    return row ? row.id : null;
  }

  async deleteToken(token) {
    const result = await this.run("DELETE FROM device_tokens WHERE token = ?", [token]);
    return result.changes > 0;
  }

  async getTokenByValue(token) {
    return this.get(
      "SELECT id, token, topic, env, last_seen, expires_at FROM device_tokens WHERE token = ? LIMIT 1",
      [token]
    );
  }

  async createWakeRequest(tokenId, createdAt) {
    const created = toIso(createdAt);
    const result = await this.run(
      "INSERT INTO wake_requests (token_id, status, attempts, created_at) VALUES (?, ?, ?, ?)",
      [tokenId, "queued", 0, created]
    );
    return result.lastID;
  }

  async getWakeRequestById(id) {
    return this.get(
      "SELECT id, token_id, status, attempts, created_at FROM wake_requests WHERE id = ? LIMIT 1",
      [id]
    );
  }

  async incrementRateLimit(scope, key, windowStart) {
    const windowStartValue = toIso(windowStart);
    await this.run(
      "INSERT OR IGNORE INTO rate_limits (scope, rate_key, window_start, count) VALUES (?, ?, ?, 0)",
      [scope, key, windowStartValue]
    );
    await this.run(
      "UPDATE rate_limits SET count = count + 1 WHERE scope = ? AND rate_key = ? AND window_start = ?",
      [scope, key, windowStartValue]
    );
    const row = await this.get(
      "SELECT count FROM rate_limits WHERE scope = ? AND rate_key = ? AND window_start = ? LIMIT 1",
      [scope, key, windowStartValue]
    );
    return row ? row.count : 1;
  }

  async cleanupExpiredDeviceTokens(now = new Date()) {
    const nowIso = toIso(toDate(now));
    const expired = await this.run(
      "DELETE FROM device_tokens WHERE expires_at IS NOT NULL AND expires_at <= ?",
      [nowIso]
    );
    return {
      tokens_expired: expired.changes || 0
    };
  }

  async getRelayMailbox(mailboxIdHash) {
    return this.get(
      "SELECT id, mailbox_id_hash, pop_key_commitment, created_at, updated_at FROM relay_mailboxes WHERE mailbox_id_hash = ? LIMIT 1",
      [mailboxIdHash]
    );
  }

  async upsertRelayMailbox(mailboxIdHash, popKeyCommitment, now) {
    const nowIso = toIso(now);
    await this.run(
      "INSERT OR IGNORE INTO relay_mailboxes (mailbox_id_hash, pop_key_commitment, created_at, updated_at) VALUES (?, ?, ?, ?)",
      [mailboxIdHash, popKeyCommitment, nowIso, nowIso]
    );
    await this.run("UPDATE relay_mailboxes SET updated_at = ? WHERE mailbox_id_hash = ?", [
      nowIso,
      mailboxIdHash
    ]);

    const mailbox = await this.getRelayMailbox(mailboxIdHash);
    if (!mailbox) {
      return null;
    }
    if (mailbox.pop_key_commitment !== popKeyCommitment) {
      return null;
    }
    return mailbox;
  }

  async insertRelayNonce(mailboxIdHash, nonce, seenAt, expiresAt) {
    const seenIso = toIso(seenAt);
    const expiresIso = toIso(expiresAt);
    const existing = await this.get(
      "SELECT expires_at FROM relay_nonces WHERE mailbox_id_hash = ? AND nonce = ? LIMIT 1",
      [mailboxIdHash, nonce]
    );

    if (existing && Date.parse(existing.expires_at) > new Date(seenIso).getTime()) {
      return false;
    }

    if (existing) {
      await this.run(
        "UPDATE relay_nonces SET seen_at = ?, expires_at = ? WHERE mailbox_id_hash = ? AND nonce = ?",
        [seenIso, expiresIso, mailboxIdHash, nonce]
      );
      return true;
    }

    await this.run(
      "INSERT INTO relay_nonces (mailbox_id_hash, nonce, seen_at, expires_at) VALUES (?, ?, ?, ?)",
      [mailboxIdHash, nonce, seenIso, expiresIso]
    );
    return true;
  }

  async getRelayMessageByClientMsgId(mailboxIdHash, clientMsgId) {
    return this.get(
      "SELECT id, message_id, mailbox_id_hash, ciphertext, size_bytes, client_msg_id, status, created_at, expires_at, acked_at FROM relay_messages WHERE mailbox_id_hash = ? AND client_msg_id = ? LIMIT 1",
      [mailboxIdHash, clientMsgId]
    );
  }

  async insertRelayMessage(message) {
    await this.run(
      "INSERT INTO relay_messages (message_id, mailbox_id_hash, ciphertext, size_bytes, client_msg_id, status, created_at, expires_at, acked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [
        message.message_id,
        message.mailbox_id_hash,
        message.ciphertext,
        message.size_bytes,
        message.client_msg_id || null,
        message.status || "queued",
        toIso(message.created_at),
        toIso(message.expires_at),
        message.acked_at ? toIso(message.acked_at) : null
      ]
    );

    return this.get(
      "SELECT id, message_id, mailbox_id_hash, ciphertext, size_bytes, client_msg_id, status, created_at, expires_at, acked_at FROM relay_messages WHERE message_id = ? LIMIT 1",
      [message.message_id]
    );
  }

  async listRelayMessages(mailboxIdHash, { afterId = 0, limit = 50, now = new Date() }) {
    const rows = await this.all(
      "SELECT id, message_id, ciphertext, size_bytes, created_at, expires_at FROM relay_messages WHERE mailbox_id_hash = ? AND acked_at IS NULL AND expires_at > ? AND id > ? ORDER BY id ASC LIMIT ?",
      [mailboxIdHash, toIso(now), afterId, limit + 1]
    );

    const hasMore = rows.length > limit;
    return {
      messages: hasMore ? rows.slice(0, limit) : rows,
      has_more: hasMore
    };
  }

  async ackRelayMessages(mailboxIdHash, messageIds, ackedAt) {
    const ackedAtIso = toIso(ackedAt);
    const acked = [];
    const unknown = [];
    const alreadyAcked = [];

    for (const messageId of messageIds) {
      const row = await this.get(
        "SELECT acked_at FROM relay_messages WHERE mailbox_id_hash = ? AND message_id = ? LIMIT 1",
        [mailboxIdHash, messageId]
      );

      if (!row) {
        unknown.push(messageId);
        continue;
      }

      if (row.acked_at) {
        alreadyAcked.push(messageId);
        continue;
      }

      const update = await this.run(
        "UPDATE relay_messages SET status = 'acked', acked_at = ? WHERE mailbox_id_hash = ? AND message_id = ? AND acked_at IS NULL",
        [ackedAtIso, mailboxIdHash, messageId]
      );

      if (update.changes > 0) {
        acked.push(messageId);
      } else {
        alreadyAcked.push(messageId);
      }
    }

    return {
      acked,
      unknown,
      already_acked: alreadyAcked
    };
  }

  async cleanupExpiredRelayData(now = new Date(), ackGraceSec = 900) {
    const nowDate = toDate(now);
    const nowIso = toIso(nowDate);
    const ackCutoffIso = toIso(new Date(nowDate.getTime() - ackGraceSec * 1000));

    const expiredMessages = await this.run("DELETE FROM relay_messages WHERE expires_at <= ?", [nowIso]);
    const ackedMessages = await this.run(
      "DELETE FROM relay_messages WHERE acked_at IS NOT NULL AND acked_at <= ?",
      [ackCutoffIso]
    );
    const expiredNonces = await this.run("DELETE FROM relay_nonces WHERE expires_at <= ?", [nowIso]);

    return {
      messages_expired: expiredMessages.changes || 0,
      messages_acked: ackedMessages.changes || 0,
      nonces_expired: expiredNonces.changes || 0
    };
  }

  close() {
    return new Promise((resolve, reject) => {
      this.db.close((err) => {
        if (err) {
          reject(err);
          return;
        }
        resolve();
      });
    });
  }
}

module.exports = { SqliteStore };
