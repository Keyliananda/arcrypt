"use strict";

const sqlite3 = require("sqlite3");

function toIso(value) {
  if (!value) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return date.toISOString();
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

  async upsertToken({ token, topic, env, lastSeen }) {
    const now = toIso(lastSeen);
    await this.run(
      "INSERT OR IGNORE INTO device_tokens (token, topic, env, last_seen, created_at) VALUES (?, ?, ?, ?, ?)",
      [token, topic, env, now, now]
    );
    await this.run(
      "UPDATE device_tokens SET topic = ?, env = ?, last_seen = ? WHERE token = ?",
      [topic, env, now, token]
    );
    const row = await this.get(
      "SELECT id FROM device_tokens WHERE token = ? LIMIT 1",
      [token]
    );
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
