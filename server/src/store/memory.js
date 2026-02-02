"use strict";

function toIso(value) {
  if (!value) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return date.toISOString();
}

class MemoryStore {
  constructor() {
    this.tokensByValue = new Map();
    this.tokensById = new Map();
    this.wakeRequests = new Map();
    this.rateCounters = new Map();
    this.nextTokenId = 1;
    this.nextWakeId = 1;
  }

  async upsertToken({ token, topic, env, lastSeen }) {
    const existing = this.tokensByValue.get(token);
    if (existing) {
      existing.topic = topic;
      existing.env = env;
      existing.last_seen = toIso(lastSeen);
      this.tokensById.set(existing.id, existing);
      return existing.id;
    }

    const id = this.nextTokenId++;
    const record = {
      id,
      token,
      topic,
      env,
      last_seen: toIso(lastSeen),
      expires_at: null
    };
    this.tokensByValue.set(token, record);
    this.tokensById.set(id, record);
    return id;
  }

  async deleteToken(token) {
    const existing = this.tokensByValue.get(token);
    if (!existing) {
      return false;
    }
    this.tokensByValue.delete(token);
    this.tokensById.delete(existing.id);
    return true;
  }

  async getTokenByValue(token) {
    const existing = this.tokensByValue.get(token);
    return existing ? { ...existing } : null;
  }

  async createWakeRequest(tokenId, createdAt) {
    const id = this.nextWakeId++;
    const record = {
      id,
      token_id: tokenId,
      status: "queued",
      attempts: 0,
      created_at: toIso(createdAt)
    };
    this.wakeRequests.set(id, record);
    return id;
  }

  async getWakeRequestById(id) {
    const existing = this.wakeRequests.get(id);
    return existing ? { ...existing } : null;
  }

  async incrementRateLimit(scope, key, windowStart) {
    const counterKey = `${scope}:${key}:${toIso(windowStart)}`;
    const current = this.rateCounters.get(counterKey) || 0;
    const next = current + 1;
    this.rateCounters.set(counterKey, next);
    return next;
  }
}

module.exports = { MemoryStore };
