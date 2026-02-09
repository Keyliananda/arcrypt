"use strict";

const mysql = require("mysql2/promise");

function toMysqlDatetime(date) {
  const normalized = date instanceof Date ? date : new Date(date);
  return normalized.toISOString().slice(0, 19).replace("T", " ");
}

class MysqlStore {
  constructor(options) {
    this.pool = mysql.createPool({
      host: options.host,
      port: options.port,
      user: options.user,
      password: options.password,
      database: options.database,
      connectionLimit: options.connectionLimit || 5,
      timezone: "Z"
    });
  }

  async upsertToken({ token, topic, env, lastSeen, expiresAt = null }) {
    const now = toMysqlDatetime(lastSeen);
    const expiry = expiresAt ? toMysqlDatetime(expiresAt) : null;
    const sql =
      "INSERT INTO device_tokens (token, topic, env, last_seen, created_at, expires_at) " +
      "VALUES (?, ?, ?, ?, ?, ?) " +
      "ON DUPLICATE KEY UPDATE " +
      "topic = VALUES(topic), " +
      "env = VALUES(env), " +
      "last_seen = VALUES(last_seen), " +
      "expires_at = VALUES(expires_at), " +
      "id = LAST_INSERT_ID(id)";
    const [result] = await this.pool.execute(sql, [token, topic, env, now, now, expiry]);
    return result.insertId;
  }

  async deleteToken(token) {
    const [result] = await this.pool.execute("DELETE FROM device_tokens WHERE token = ?", [token]);
    return result.affectedRows > 0;
  }

  async getTokenByValue(token) {
    const [rows] = await this.pool.execute(
      "SELECT id, token, topic, env, last_seen, expires_at FROM device_tokens WHERE token = ? LIMIT 1",
      [token]
    );
    return rows[0] || null;
  }

  async createWakeRequest(tokenId, createdAt) {
    const created = toMysqlDatetime(createdAt);
    const [result] = await this.pool.execute(
      "INSERT INTO wake_requests (token_id, status, attempts, created_at) VALUES (?, ?, ?, ?)",
      [tokenId, "queued", 0, created]
    );
    return result.insertId;
  }

  async incrementRateLimit(scope, key, windowStart) {
    const windowStartValue = toMysqlDatetime(windowStart);
    const insertSql =
      "INSERT INTO rate_limits (scope, rate_key, window_start, count) VALUES (?, ?, ?, 1) " +
      "ON DUPLICATE KEY UPDATE count = count + 1";
    await this.pool.execute(insertSql, [scope, key, windowStartValue]);
    const [rows] = await this.pool.execute(
      "SELECT count FROM rate_limits WHERE scope = ? AND rate_key = ? AND window_start = ?",
      [scope, key, windowStartValue]
    );
    return rows[0] ? rows[0].count : 1;
  }

  async cleanupExpiredDeviceTokens(now = new Date()) {
    const nowValue = toMysqlDatetime(now instanceof Date ? now : new Date(now));
    const [expired] = await this.pool.execute(
      "DELETE FROM device_tokens WHERE expires_at IS NOT NULL AND expires_at <= ?",
      [nowValue]
    );
    return {
      tokens_expired: expired.affectedRows || 0
    };
  }

  async getRelayMailbox(mailboxIdHash) {
    const [rows] = await this.pool.execute(
      "SELECT id, mailbox_id_hash, pop_key_commitment, created_at, updated_at FROM relay_mailboxes WHERE mailbox_id_hash = ? LIMIT 1",
      [mailboxIdHash]
    );
    return rows[0] || null;
  }

  async upsertRelayMailbox(mailboxIdHash, popKeyCommitment, now) {
    const nowValue = toMysqlDatetime(now);
    const sql =
      "INSERT INTO relay_mailboxes (mailbox_id_hash, pop_key_commitment, created_at, updated_at) VALUES (?, ?, ?, ?) " +
      "ON DUPLICATE KEY UPDATE updated_at = VALUES(updated_at)";
    await this.pool.execute(sql, [mailboxIdHash, popKeyCommitment, nowValue, nowValue]);

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
    const [rows] = await this.pool.execute(
      "SELECT expires_at FROM relay_nonces WHERE mailbox_id_hash = ? AND nonce = ? LIMIT 1",
      [mailboxIdHash, nonce]
    );

    const seenValue = toMysqlDatetime(seenAt);
    const expiresValue = toMysqlDatetime(expiresAt);

    if (rows.length > 0) {
      const existingExpiry = new Date(rows[0].expires_at).getTime();
      const seenMs = new Date(seenValue).getTime();
      if (existingExpiry > seenMs) {
        return false;
      }

      await this.pool.execute(
        "UPDATE relay_nonces SET seen_at = ?, expires_at = ? WHERE mailbox_id_hash = ? AND nonce = ?",
        [seenValue, expiresValue, mailboxIdHash, nonce]
      );
      return true;
    }

    await this.pool.execute(
      "INSERT INTO relay_nonces (mailbox_id_hash, nonce, seen_at, expires_at) VALUES (?, ?, ?, ?)",
      [mailboxIdHash, nonce, seenValue, expiresValue]
    );
    return true;
  }

  async getRelayMessageByClientMsgId(mailboxIdHash, clientMsgId) {
    const [rows] = await this.pool.execute(
      "SELECT id, message_id, mailbox_id_hash, ciphertext, size_bytes, client_msg_id, status, created_at, expires_at, acked_at FROM relay_messages WHERE mailbox_id_hash = ? AND client_msg_id = ? LIMIT 1",
      [mailboxIdHash, clientMsgId]
    );
    return rows[0] || null;
  }

  async insertRelayMessage(message) {
    const [result] = await this.pool.execute(
      "INSERT INTO relay_messages (message_id, mailbox_id_hash, ciphertext, size_bytes, client_msg_id, status, created_at, expires_at, acked_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
      [
        message.message_id,
        message.mailbox_id_hash,
        message.ciphertext,
        message.size_bytes,
        message.client_msg_id || null,
        message.status || "queued",
        toMysqlDatetime(message.created_at),
        toMysqlDatetime(message.expires_at),
        message.acked_at ? toMysqlDatetime(message.acked_at) : null
      ]
    );

    const [rows] = await this.pool.execute(
      "SELECT id, message_id, mailbox_id_hash, ciphertext, size_bytes, client_msg_id, status, created_at, expires_at, acked_at FROM relay_messages WHERE id = ? LIMIT 1",
      [result.insertId]
    );
    return rows[0] || null;
  }

  async listRelayMessages(mailboxIdHash, { afterId = 0, limit = 50, now = new Date() }) {
    const [rows] = await this.pool.execute(
      "SELECT id, message_id, ciphertext, size_bytes, created_at, expires_at FROM relay_messages WHERE mailbox_id_hash = ? AND acked_at IS NULL AND expires_at > ? AND id > ? ORDER BY id ASC LIMIT ?",
      [mailboxIdHash, toMysqlDatetime(now), afterId, limit + 1]
    );

    const hasMore = rows.length > limit;
    return {
      messages: hasMore ? rows.slice(0, limit) : rows,
      has_more: hasMore
    };
  }

  async ackRelayMessages(mailboxIdHash, messageIds, ackedAt) {
    const ackedAtValue = toMysqlDatetime(ackedAt);
    const acked = [];
    const unknown = [];
    const alreadyAcked = [];

    for (const messageId of messageIds) {
      const [rows] = await this.pool.execute(
        "SELECT acked_at FROM relay_messages WHERE mailbox_id_hash = ? AND message_id = ? LIMIT 1",
        [mailboxIdHash, messageId]
      );

      if (rows.length === 0) {
        unknown.push(messageId);
        continue;
      }

      if (rows[0].acked_at) {
        alreadyAcked.push(messageId);
        continue;
      }

      const [result] = await this.pool.execute(
        "UPDATE relay_messages SET status = 'acked', acked_at = ? WHERE mailbox_id_hash = ? AND message_id = ? AND acked_at IS NULL",
        [ackedAtValue, mailboxIdHash, messageId]
      );

      if (result.affectedRows > 0) {
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
    const nowDate = now instanceof Date ? now : new Date(now);
    const nowValue = toMysqlDatetime(nowDate);
    const ackCutoff = new Date(nowDate.getTime() - ackGraceSec * 1000);
    const ackCutoffValue = toMysqlDatetime(ackCutoff);

    const [expiredMessages] = await this.pool.execute(
      "DELETE FROM relay_messages WHERE expires_at <= ?",
      [nowValue]
    );
    const [ackedMessages] = await this.pool.execute(
      "DELETE FROM relay_messages WHERE acked_at IS NOT NULL AND acked_at <= ?",
      [ackCutoffValue]
    );
    const [expiredNonces] = await this.pool.execute(
      "DELETE FROM relay_nonces WHERE expires_at <= ?",
      [nowValue]
    );

    return {
      messages_expired: expiredMessages.affectedRows || 0,
      messages_acked: ackedMessages.affectedRows || 0,
      nonces_expired: expiredNonces.affectedRows || 0
    };
  }

  async close() {
    await this.pool.end();
  }
}

module.exports = { MysqlStore };
