"use strict";

const mysql = require("mysql2/promise");

function toMysqlDatetime(date) {
  return date.toISOString().slice(0, 19).replace("T", " ");
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

  async upsertToken({ token, topic, env, lastSeen }) {
    const now = toMysqlDatetime(lastSeen);
    const sql =
      "INSERT INTO device_tokens (token, topic, env, last_seen, created_at) " +
      "VALUES (?, ?, ?, ?, ?) " +
      "ON DUPLICATE KEY UPDATE " +
      "topic = VALUES(topic), " +
      "env = VALUES(env), " +
      "last_seen = VALUES(last_seen), " +
      "id = LAST_INSERT_ID(id)";
    const [result] = await this.pool.execute(sql, [token, topic, env, now, now]);
    return result.insertId;
  }

  async deleteToken(token) {
    const [result] = await this.pool.execute(
      "DELETE FROM device_tokens WHERE token = ?",
      [token]
    );
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
}

module.exports = { MysqlStore };
