"use strict";

function toIso(value) {
  if (!value) {
    return null;
  }
  const date = value instanceof Date ? value : new Date(value);
  return date.toISOString();
}

function cloneRelayMessage(record) {
  return {
    ...record,
    ciphertext: Buffer.from(record.ciphertext)
  };
}

class MemoryStore {
  constructor() {
    this.tokensByValue = new Map();
    this.tokensById = new Map();
    this.wakeRequests = new Map();
    this.rateCounters = new Map();
    this.relayMailboxes = new Map();
    this.relayMessagesByRowId = new Map();
    this.relayMessageIdToRowId = new Map();
    this.relayMailboxMessageRows = new Map();
    this.relayClientMsgIndex = new Map();
    this.relayNonces = new Map();
    this.nextTokenId = 1;
    this.nextWakeId = 1;
    this.nextRelayMailboxId = 1;
    this.nextRelayMessageRowId = 1;
  }

  async upsertToken({ token, topic, env, lastSeen, expiresAt = null }) {
    const existing = this.tokensByValue.get(token);
    if (existing) {
      existing.topic = topic;
      existing.env = env;
      existing.last_seen = toIso(lastSeen);
      existing.expires_at = toIso(expiresAt);
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
      expires_at: toIso(expiresAt)
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

  async cleanupExpiredDeviceTokens(now = new Date()) {
    const nowMs = now instanceof Date ? now.getTime() : new Date(now).getTime();
    let removed = 0;

    for (const [token, record] of this.tokensByValue.entries()) {
      if (!record.expires_at) {
        continue;
      }
      if (Date.parse(record.expires_at) > nowMs) {
        continue;
      }
      this.tokensByValue.delete(token);
      this.tokensById.delete(record.id);
      for (const [wakeId, wake] of this.wakeRequests.entries()) {
        if (wake.token_id === record.id) {
          this.wakeRequests.delete(wakeId);
        }
      }
      removed += 1;
    }

    return {
      tokens_expired: removed
    };
  }

  async getRelayMailbox(mailboxIdHash) {
    const existing = this.relayMailboxes.get(mailboxIdHash);
    return existing ? { ...existing } : null;
  }

  async upsertRelayMailbox(mailboxIdHash, popKeyCommitment, now) {
    const nowIso = toIso(now);
    const existing = this.relayMailboxes.get(mailboxIdHash);
    if (existing) {
      if (existing.pop_key_commitment !== popKeyCommitment) {
        return null;
      }
      existing.updated_at = nowIso;
      return { ...existing };
    }

    const id = this.nextRelayMailboxId++;
    const created = {
      id,
      mailbox_id_hash: mailboxIdHash,
      pop_key_commitment: popKeyCommitment,
      created_at: nowIso,
      updated_at: nowIso
    };
    this.relayMailboxes.set(mailboxIdHash, created);
    return { ...created };
  }

  async insertRelayNonce(mailboxIdHash, nonce, seenAt, expiresAt) {
    const key = `${mailboxIdHash}:${nonce}`;
    const existing = this.relayNonces.get(key);
    const nowMs = seenAt instanceof Date ? seenAt.getTime() : new Date(seenAt).getTime();
    if (existing) {
      const existingExpiry = Date.parse(existing.expires_at);
      if (existingExpiry > nowMs) {
        return false;
      }
    }

    this.relayNonces.set(key, {
      mailbox_id_hash: mailboxIdHash,
      nonce,
      seen_at: toIso(seenAt),
      expires_at: toIso(expiresAt)
    });
    return true;
  }

  async getRelayMessageByClientMsgId(mailboxIdHash, clientMsgId) {
    const indexKey = `${mailboxIdHash}:${clientMsgId}`;
    const rowId = this.relayClientMsgIndex.get(indexKey);
    if (!rowId) {
      return null;
    }
    const record = this.relayMessagesByRowId.get(rowId);
    return record ? cloneRelayMessage(record) : null;
  }

  async insertRelayMessage(message) {
    if (this.relayMessageIdToRowId.has(message.message_id)) {
      throw new Error("duplicate_message_id");
    }

    const rowId = this.nextRelayMessageRowId++;
    const record = {
      id: rowId,
      message_id: message.message_id,
      mailbox_id_hash: message.mailbox_id_hash,
      ciphertext: Buffer.from(message.ciphertext),
      size_bytes: message.size_bytes,
      client_msg_id: message.client_msg_id || null,
      status: message.status || "queued",
      created_at: toIso(message.created_at),
      expires_at: toIso(message.expires_at),
      acked_at: message.acked_at ? toIso(message.acked_at) : null
    };

    this.relayMessagesByRowId.set(rowId, record);
    this.relayMessageIdToRowId.set(record.message_id, rowId);

    if (!this.relayMailboxMessageRows.has(record.mailbox_id_hash)) {
      this.relayMailboxMessageRows.set(record.mailbox_id_hash, []);
    }
    this.relayMailboxMessageRows.get(record.mailbox_id_hash).push(rowId);

    if (record.client_msg_id) {
      const indexKey = `${record.mailbox_id_hash}:${record.client_msg_id}`;
      this.relayClientMsgIndex.set(indexKey, rowId);
    }

    return cloneRelayMessage(record);
  }

  async listRelayMessages(mailboxIdHash, { afterId = 0, limit = 50, now = new Date() }) {
    const rowIds = this.relayMailboxMessageRows.get(mailboxIdHash) || [];
    const nowMs = now instanceof Date ? now.getTime() : new Date(now).getTime();

    const collected = [];
    for (const rowId of rowIds) {
      if (rowId <= afterId) {
        continue;
      }

      const record = this.relayMessagesByRowId.get(rowId);
      if (!record) {
        continue;
      }
      if (record.acked_at) {
        continue;
      }
      if (Date.parse(record.expires_at) <= nowMs) {
        continue;
      }

      collected.push(cloneRelayMessage(record));
      if (collected.length >= limit + 1) {
        break;
      }
    }

    const hasMore = collected.length > limit;
    return {
      messages: hasMore ? collected.slice(0, limit) : collected,
      has_more: hasMore
    };
  }

  async ackRelayMessages(mailboxIdHash, messageIds, ackedAt) {
    const ackedAtIso = toIso(ackedAt);
    const acked = [];
    const unknown = [];
    const alreadyAcked = [];

    for (const messageId of messageIds) {
      const rowId = this.relayMessageIdToRowId.get(messageId);
      if (!rowId) {
        unknown.push(messageId);
        continue;
      }

      const record = this.relayMessagesByRowId.get(rowId);
      if (!record || record.mailbox_id_hash !== mailboxIdHash) {
        unknown.push(messageId);
        continue;
      }

      if (record.acked_at) {
        alreadyAcked.push(messageId);
        continue;
      }

      record.acked_at = ackedAtIso;
      record.status = "acked";
      acked.push(messageId);
    }

    return {
      acked,
      unknown,
      already_acked: alreadyAcked
    };
  }

  deleteRelayMessageByRowId(rowId) {
    const record = this.relayMessagesByRowId.get(rowId);
    if (!record) {
      return false;
    }

    this.relayMessagesByRowId.delete(rowId);
    this.relayMessageIdToRowId.delete(record.message_id);

    const mailboxRows = this.relayMailboxMessageRows.get(record.mailbox_id_hash) || [];
    const nextRows = mailboxRows.filter((id) => id !== rowId);
    this.relayMailboxMessageRows.set(record.mailbox_id_hash, nextRows);

    if (record.client_msg_id) {
      this.relayClientMsgIndex.delete(`${record.mailbox_id_hash}:${record.client_msg_id}`);
    }

    return true;
  }

  async cleanupExpiredRelayData(now = new Date(), ackGraceSec = 900) {
    const nowMs = now instanceof Date ? now.getTime() : new Date(now).getTime();
    const ackCutoffMs = nowMs - ackGraceSec * 1000;

    let messagesExpired = 0;
    let messagesAcked = 0;
    for (const [rowId, record] of this.relayMessagesByRowId.entries()) {
      if (Date.parse(record.expires_at) <= nowMs) {
        if (this.deleteRelayMessageByRowId(rowId)) {
          messagesExpired += 1;
        }
        continue;
      }

      if (record.acked_at && Date.parse(record.acked_at) <= ackCutoffMs) {
        if (this.deleteRelayMessageByRowId(rowId)) {
          messagesAcked += 1;
        }
      }
    }

    let noncesExpired = 0;
    for (const [key, record] of this.relayNonces.entries()) {
      if (Date.parse(record.expires_at) <= nowMs) {
        this.relayNonces.delete(key);
        noncesExpired += 1;
      }
    }

    return {
      messages_expired: messagesExpired,
      messages_acked: messagesAcked,
      nonces_expired: noncesExpired
    };
  }
}

module.exports = { MemoryStore };
