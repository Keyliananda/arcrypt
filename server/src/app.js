"use strict";

const crypto = require("crypto");
const { sendSilentPush, isApnsConfigured } = require("./apns");

const MAX_TOKEN_LENGTH = 512;
const MAX_TOPIC_LENGTH = 255;
const MAX_MAILBOX_ID_LENGTH = 128;
const MAX_CLIENT_MSG_ID_LENGTH = 128;
const ALLOWED_ENVS = new Set(["sandbox", "prod"]);
const HEX_64_RE = /^[0-9a-f]{64}$/i;
const BASE64URL_RE = /^[A-Za-z0-9_-]+$/;
const BASE64_RE = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;

function jsonResponse(status, payload) {
  return {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8"
    },
    body: JSON.stringify(payload)
  };
}

function errorResponse(status, code, details) {
  const payload = { ok: false, error: code };
  if (details) {
    payload.details = details;
  }
  return jsonResponse(status, payload);
}

function parseJsonBody(body) {
  if (body === undefined || body === null || String(body).trim() === "") {
    return { ok: true, value: {} };
  }
  try {
    return { ok: true, value: JSON.parse(body) };
  } catch (error) {
    return { ok: false, error: "invalid_json" };
  }
}

function readString(value, maxLength) {
  if (typeof value !== "string") {
    return null;
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return null;
  }
  if (maxLength && trimmed.length > maxLength) {
    return null;
  }
  return trimmed;
}

function readInteger(value) {
  if (Number.isInteger(value)) {
    return value;
  }
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : null;
}

function readMailboxId(value) {
  const mailboxId = readString(value, MAX_MAILBOX_ID_LENGTH);
  if (!mailboxId || !BASE64URL_RE.test(mailboxId)) {
    return null;
  }
  let decoded;
  try {
    decoded = Buffer.from(mailboxId, "base64url");
  } catch (error) {
    return null;
  }
  if (decoded.length < 16 || decoded.length > 48) {
    return null;
  }
  return mailboxId;
}

function readNonce(value) {
  const nonce = readString(value, 128);
  if (!nonce || !BASE64URL_RE.test(nonce)) {
    return null;
  }
  let decoded;
  try {
    decoded = Buffer.from(nonce, "base64url");
  } catch (error) {
    return null;
  }
  if (decoded.length < 16 || decoded.length > 64) {
    return null;
  }
  return nonce;
}

function readCiphertext(value, maxBytes) {
  if (typeof value !== "string") {
    return { ok: false, error: "missing_fields" };
  }
  const trimmed = value.trim();
  if (!trimmed) {
    return { ok: false, error: "missing_fields" };
  }
  if (!BASE64_RE.test(trimmed)) {
    return { ok: false, error: "invalid_field", details: { field: "ciphertext" } };
  }

  const decoded = Buffer.from(trimmed, "base64");
  if (decoded.length > maxBytes) {
    return { ok: false, error: "ciphertext_too_large" };
  }

  return { ok: true, decoded, encoded: trimmed };
}

function asIsoString(value) {
  if (!value) {
    return null;
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  return new Date(value).toISOString();
}

function isHexString(value) {
  return typeof value === "string" && value.length % 2 === 0 && /^[0-9a-fA-F]+$/.test(value);
}

function timingSafeEqualHex(expectedHex, providedHex) {
  if (!isHexString(providedHex) || expectedHex.length !== providedHex.length) {
    return false;
  }
  const expected = Buffer.from(expectedHex, "hex");
  const provided = Buffer.from(providedHex, "hex");
  return crypto.timingSafeEqual(expected, provided);
}

function sha256Hex(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function stableJsonStringify(value) {
  if (value === null || typeof value !== "object") {
    return JSON.stringify(value);
  }

  if (Array.isArray(value)) {
    const serialized = value.map((entry) => stableJsonStringify(entry));
    return `[${serialized.join(",")}]`;
  }

  const keys = Object.keys(value).sort();
  const entries = [];
  for (const key of keys) {
    entries.push(`${JSON.stringify(key)}:${stableJsonStringify(value[key])}`);
  }
  return `{${entries.join(",")}}`;
}

function hashMailboxProofBody(body) {
  const withoutProof = { ...body };
  delete withoutProof.proof;
  return sha256Hex(stableJsonStringify(withoutProof));
}

function computeHmac(secret, token, ts) {
  return crypto
    .createHmac("sha256", secret)
    .update(`${token}:${ts}`)
    .digest("hex");
}

function computeMailboxProof(mailboxPopKey, { method, path, ts, nonce, bodySha256Hex }) {
  const canonical = `${method}\n${path}\n${ts}\n${nonce}\n${bodySha256Hex}`;
  return crypto.createHmac("sha256", mailboxPopKey).update(canonical).digest("hex");
}

function windowStartDate(nowMs, windowSec) {
  const nowSec = Math.floor(nowMs / 1000);
  const startSec = Math.floor(nowSec / windowSec) * windowSec;
  return new Date(startSec * 1000);
}

function encodeCursor(id) {
  return Buffer.from(String(id), "utf8").toString("base64url");
}

function decodeCursor(value) {
  if (value === null || value === undefined) {
    return 0;
  }
  if (typeof value !== "string" || !value.trim()) {
    return null;
  }

  try {
    const decoded = Buffer.from(value, "base64url").toString("utf8");
    const parsed = Number.parseInt(decoded, 10);
    if (!Number.isFinite(parsed) || parsed < 0) {
      return null;
    }
    return parsed;
  } catch (error) {
    return null;
  }
}

function relayConfigFrom(config) {
  const relay = config.relay || {};
  const rateLimit = relay.rateLimit || {};
  return {
    proofMaxSkewSec: Number.isFinite(relay.proofMaxSkewSec) ? relay.proofMaxSkewSec : 300,
    nonceTtlSec: Number.isFinite(relay.nonceTtlSec) ? relay.nonceTtlSec : 900,
    defaultExpirySec: Number.isFinite(relay.defaultExpirySec) ? relay.defaultExpirySec : 86400,
    minExpirySec: Number.isFinite(relay.minExpirySec) ? relay.minExpirySec : 60,
    maxExpirySec: Number.isFinite(relay.maxExpirySec) ? relay.maxExpirySec : 604800,
    maxCiphertextBytes: Number.isFinite(relay.maxCiphertextBytes) ? relay.maxCiphertextBytes : 65536,
    maxPullLimit: Number.isFinite(relay.maxPullLimit) ? relay.maxPullLimit : 100,
    defaultPullLimit: Number.isFinite(relay.defaultPullLimit) ? relay.defaultPullLimit : 50,
    maxAckMessageIds: Number.isFinite(relay.maxAckMessageIds) ? relay.maxAckMessageIds : 100,
    rateLimit: {
      pushPerMailbox: Number.isFinite(rateLimit.pushPerMailbox) ? rateLimit.pushPerMailbox : 120,
      pullPerMailbox: Number.isFinite(rateLimit.pullPerMailbox) ? rateLimit.pullPerMailbox : 360,
      ackPerMailbox: Number.isFinite(rateLimit.ackPerMailbox) ? rateLimit.ackPerMailbox : 360,
      pushPerIp: Number.isFinite(rateLimit.pushPerIp) ? rateLimit.pushPerIp : 1200,
      pullPerIp: Number.isFinite(rateLimit.pullPerIp) ? rateLimit.pullPerIp : 1200,
      ackPerIp: Number.isFinite(rateLimit.ackPerIp) ? rateLimit.ackPerIp : 1200
    }
  };
}

function createApp({ store, config, now = Date.now }) {
  const relayConfig = relayConfigFrom(config);

  async function applyRateLimit(scope, key, limit, windowStart) {
    if (!key || limit <= 0) {
      return { allowed: true };
    }
    const count = await store.incrementRateLimit(scope, key, windowStart);
    return { allowed: count <= limit, count, limit, scope };
  }

  async function verifyRelayAuth(body, path, ip, action, requireExistingMailbox) {
    const mailboxId = readMailboxId(body.mailbox_id);
    const nonce = readNonce(body.nonce);
    const proof = readString(body.proof, 128);
    const ts = readInteger(body.ts);

    if (!mailboxId || !nonce || !proof || ts === null) {
      return { error: errorResponse(400, "missing_fields") };
    }
    if (!HEX_64_RE.test(proof)) {
      return { error: errorResponse(400, "invalid_field", { field: "proof" }) };
    }

    const nowMs = now();
    const nowSec = Math.floor(nowMs / 1000);
    if (Math.abs(nowSec - ts) > relayConfig.proofMaxSkewSec) {
      return { error: errorResponse(401, "timestamp_out_of_range") };
    }

    const bodySha256Hex = hashMailboxProofBody(body);
    // v1 bootstrap: mailbox_id acts as mailbox-local PoP key material.
    const expected = computeMailboxProof(mailboxId, {
      method: "POST",
      path,
      ts,
      nonce,
      bodySha256Hex
    });

    if (!timingSafeEqualHex(expected, proof)) {
      return { error: errorResponse(401, "invalid_proof") };
    }

    const mailboxIdHash = sha256Hex(mailboxId);
    const popKeyCommitment = sha256Hex(`pop:${mailboxId}`);

    let mailbox = await store.getRelayMailbox(mailboxIdHash);
    if (!mailbox && requireExistingMailbox) {
      return { error: errorResponse(404, "mailbox_not_found") };
    }

    if (!mailbox) {
      mailbox = await store.upsertRelayMailbox(mailboxIdHash, popKeyCommitment, new Date(nowMs));
    }

    if (!mailbox || mailbox.pop_key_commitment !== popKeyCommitment) {
      return { error: errorResponse(401, "invalid_proof") };
    }

    const seenAt = new Date(nowMs);
    const expiresAt = new Date(nowMs + relayConfig.nonceTtlSec * 1000);
    const nonceStored = await store.insertRelayNonce(mailboxIdHash, nonce, seenAt, expiresAt);
    if (!nonceStored) {
      return { error: errorResponse(401, "nonce_replay") };
    }

    const windowSec =
      config.rateLimit && Number.isFinite(config.rateLimit.windowSec)
        ? config.rateLimit.windowSec
        : 3600;
    const windowStart = windowStartDate(nowMs, windowSec);

    const mailboxLimits = {
      push: relayConfig.rateLimit.pushPerMailbox,
      pull: relayConfig.rateLimit.pullPerMailbox,
      ack: relayConfig.rateLimit.ackPerMailbox
    };
    const ipLimits = {
      push: relayConfig.rateLimit.pushPerIp,
      pull: relayConfig.rateLimit.pullPerIp,
      ack: relayConfig.rateLimit.ackPerIp
    };

    const mailboxLimit = await applyRateLimit(
      `relay_mailbox_${action}`,
      mailboxIdHash,
      mailboxLimits[action],
      windowStart
    );
    if (!mailboxLimit.allowed) {
      return {
        error: errorResponse(429, "rate_limit", {
          scope: "mailbox",
          limit: mailboxLimit.limit
        })
      };
    }

    const ipLimit = await applyRateLimit(`relay_ip_${action}`, ip, ipLimits[action], windowStart);
    if (!ipLimit.allowed) {
      return {
        error: errorResponse(429, "rate_limit", {
          scope: "ip",
          limit: ipLimit.limit
        })
      };
    }

    return {
      mailboxIdHash,
      nowMs
    };
  }

  async function handleRegister(body, ip) {
    const token = readString(body.token, MAX_TOKEN_LENGTH);
    const topic = readString(body.topic, MAX_TOPIC_LENGTH);
    const env = readString(body.env, 16);

    if (!token || !topic || !env) {
      return errorResponse(400, "missing_fields");
    }
    if (!ALLOWED_ENVS.has(env)) {
      return errorResponse(400, "invalid_env");
    }

    const nowMs = now();
    const windowStart = windowStartDate(nowMs, config.rateLimit.windowSec);
    const tokenLimit = await applyRateLimit("token", token, config.rateLimit.perToken, windowStart);
    if (!tokenLimit.allowed) {
      return errorResponse(429, "rate_limit", { scope: "token", limit: tokenLimit.limit });
    }
    const ipLimit = await applyRateLimit("ip", ip, config.rateLimit.perIp, windowStart);
    if (!ipLimit.allowed) {
      return errorResponse(429, "rate_limit", { scope: "ip", limit: ipLimit.limit });
    }

    const lastSeen = new Date(nowMs);
    await store.upsertToken({ token, topic, env, lastSeen });
    return jsonResponse(200, { ok: true });
  }

  async function handleUnregister(body) {
    const token = readString(body.token, MAX_TOKEN_LENGTH);
    if (!token) {
      return errorResponse(400, "missing_fields");
    }
    await store.deleteToken(token);
    return jsonResponse(200, { ok: true });
  }

  async function handleWake(body, ip) {
    const token = readString(body.token, MAX_TOKEN_LENGTH);
    const proof = readString(body.proof, 256);
    const ts = readInteger(body.ts);

    if (!token || !proof || ts === null) {
      return errorResponse(400, "missing_fields");
    }
    if (!config.hmacSecret) {
      return errorResponse(503, "hmac_not_configured");
    }

    const nowMs = now();
    const nowSec = Math.floor(nowMs / 1000);
    if (Math.abs(nowSec - ts) > config.hmacMaxSkewSec) {
      return errorResponse(401, "timestamp_out_of_range");
    }

    const expected = computeHmac(config.hmacSecret, token, ts);
    if (!timingSafeEqualHex(expected, proof)) {
      return errorResponse(401, "invalid_proof");
    }

    const windowStart = windowStartDate(nowMs, config.rateLimit.windowSec);
    const tokenLimit = await applyRateLimit("token", token, config.rateLimit.perToken, windowStart);
    if (!tokenLimit.allowed) {
      return errorResponse(429, "rate_limit", { scope: "token", limit: tokenLimit.limit });
    }
    const ipLimit = await applyRateLimit("ip", ip, config.rateLimit.perIp, windowStart);
    if (!ipLimit.allowed) {
      return errorResponse(429, "rate_limit", { scope: "ip", limit: ipLimit.limit });
    }

    const tokenRecord = await store.getTokenByValue(token);
    if (!tokenRecord) {
      return errorResponse(404, "token_not_found");
    }

    const createdAt = new Date(nowMs);
    const wakeId = await store.createWakeRequest(tokenRecord.id, createdAt);

    let apnsInfo = null;
    const apnsConfig = config.apns || {};
    if (isApnsConfigured(apnsConfig)) {
      const result = await sendSilentPush({
        token: tokenRecord.token,
        topic: apnsConfig.topic,
        env: apnsConfig.env || tokenRecord.env,
        keyId: apnsConfig.keyId,
        teamId: apnsConfig.teamId,
        keyPath: apnsConfig.keyPath,
        timeoutMs: apnsConfig.timeoutMs
      });
      if (result.ok) {
        apnsInfo = {
          status: "sent",
          apns_id: result.apnsId,
          http_status: result.status
        };
      } else {
        apnsInfo = {
          status: "failed",
          reason: result.reason || result.error,
          http_status: result.status || 0
        };
      }
    } else if (apnsConfig.enabled) {
      apnsInfo = { status: "skipped", reason: "not_configured" };
    }

    const responsePayload = {
      ok: true,
      wake_id: wakeId,
      status: apnsInfo && apnsInfo.status === "sent" ? "sent" : "queued"
    };
    if (apnsInfo) {
      responsePayload.apns = apnsInfo;
    }
    return jsonResponse(202, responsePayload);
  }

  async function handleMailboxPush(body, path, ip) {
    const auth = await verifyRelayAuth(body, path, ip, "push", false);
    if (auth.error) {
      return auth.error;
    }

    const ciphertext = readCiphertext(body.ciphertext, relayConfig.maxCiphertextBytes);
    if (!ciphertext.ok) {
      if (ciphertext.error === "missing_fields") {
        return errorResponse(400, "missing_fields");
      }
      if (ciphertext.error === "ciphertext_too_large") {
        return errorResponse(413, "ciphertext_too_large");
      }
      return errorResponse(400, ciphertext.error, ciphertext.details);
    }

    let expiresInSec = relayConfig.defaultExpirySec;
    if (body.expires_in_sec !== undefined && body.expires_in_sec !== null) {
      const parsed = readInteger(body.expires_in_sec);
      if (
        parsed === null ||
        parsed < relayConfig.minExpirySec ||
        parsed > relayConfig.maxExpirySec
      ) {
        return errorResponse(400, "invalid_field", { field: "expires_in_sec" });
      }
      expiresInSec = parsed;
    }

    let clientMsgId = null;
    if (body.client_msg_id !== undefined && body.client_msg_id !== null) {
      clientMsgId = readString(body.client_msg_id, MAX_CLIENT_MSG_ID_LENGTH);
      if (!clientMsgId) {
        return errorResponse(400, "invalid_field", { field: "client_msg_id" });
      }
    }

    if (clientMsgId) {
      const existing = await store.getRelayMessageByClientMsgId(auth.mailboxIdHash, clientMsgId);
      if (existing) {
        return jsonResponse(202, {
          ok: true,
          message_id: existing.message_id,
          expires_at: asIsoString(existing.expires_at),
          status: existing.status || "queued"
        });
      }
    }

    const createdAt = new Date(auth.nowMs);
    const expiresAt = new Date(auth.nowMs + expiresInSec * 1000);
    const messageId = `msg_${crypto.randomUUID().replace(/-/g, "")}`;

    const stored = await store.insertRelayMessage({
      message_id: messageId,
      mailbox_id_hash: auth.mailboxIdHash,
      ciphertext: ciphertext.decoded,
      size_bytes: ciphertext.decoded.length,
      client_msg_id: clientMsgId,
      status: "queued",
      created_at: createdAt,
      expires_at: expiresAt,
      acked_at: null
    });

    return jsonResponse(202, {
      ok: true,
      message_id: stored.message_id,
      expires_at: asIsoString(stored.expires_at),
      status: stored.status
    });
  }

  async function handleMailboxPull(body, path, ip) {
    const auth = await verifyRelayAuth(body, path, ip, "pull", true);
    if (auth.error) {
      return auth.error;
    }

    let limit = relayConfig.defaultPullLimit;
    if (body.limit !== undefined && body.limit !== null) {
      const parsed = readInteger(body.limit);
      if (parsed === null || parsed < 1 || parsed > relayConfig.maxPullLimit) {
        return errorResponse(400, "invalid_field", { field: "limit" });
      }
      limit = parsed;
    }

    const afterId = decodeCursor(body.cursor);
    if (afterId === null) {
      return errorResponse(400, "invalid_cursor");
    }

    const nowDate = new Date(auth.nowMs);
    const pulled = await store.listRelayMessages(auth.mailboxIdHash, {
      afterId,
      limit,
      now: nowDate
    });

    const messages = pulled.messages.map((message) => ({
      message_id: message.message_id,
      ciphertext: Buffer.from(message.ciphertext).toString("base64"),
      created_at: asIsoString(message.created_at),
      expires_at: asIsoString(message.expires_at),
      size_bytes: message.size_bytes
    }));

    const nextCursor = pulled.has_more
      ? encodeCursor(pulled.messages[pulled.messages.length - 1].id)
      : null;

    return jsonResponse(200, {
      ok: true,
      messages,
      next_cursor: nextCursor,
      has_more: pulled.has_more
    });
  }

  async function handleMailboxAck(body, path, ip) {
    const auth = await verifyRelayAuth(body, path, ip, "ack", true);
    if (auth.error) {
      return auth.error;
    }

    if (!Array.isArray(body.message_ids)) {
      return errorResponse(400, "missing_fields");
    }
    if (body.message_ids.length < 1 || body.message_ids.length > relayConfig.maxAckMessageIds) {
      return errorResponse(400, "invalid_field", { field: "message_ids" });
    }

    const messageIds = [];
    for (const messageIdRaw of body.message_ids) {
      const messageId = readString(messageIdRaw, 128);
      if (!messageId) {
        return errorResponse(400, "invalid_field", { field: "message_ids" });
      }
      messageIds.push(messageId);
    }

    const ackResult = await store.ackRelayMessages(
      auth.mailboxIdHash,
      messageIds,
      new Date(auth.nowMs)
    );

    return jsonResponse(200, {
      ok: true,
      acked: ackResult.acked,
      unknown: ackResult.unknown,
      already_acked: ackResult.already_acked
    });
  }

  async function handle({ method, path, headers, body, ip }) {
    if (method !== "POST") {
      return errorResponse(405, "method_not_allowed");
    }

    if (path === "/v1/health") {
      return jsonResponse(200, { ok: true, status: "ok" });
    }

    const parsed = parseJsonBody(body);
    if (!parsed.ok) {
      return errorResponse(400, parsed.error);
    }

    if (path === "/v1/register") {
      return handleRegister(parsed.value, ip);
    }

    if (path === "/v1/unregister") {
      return handleUnregister(parsed.value);
    }

    if (path === "/v1/wake") {
      return handleWake(parsed.value, ip);
    }

    if (path === "/v1/mailbox/push") {
      return handleMailboxPush(parsed.value, path, ip);
    }

    if (path === "/v1/mailbox/pull") {
      return handleMailboxPull(parsed.value, path, ip);
    }

    if (path === "/v1/mailbox/ack") {
      return handleMailboxAck(parsed.value, path, ip);
    }

    return errorResponse(404, "not_found");
  }

  return { handle };
}

module.exports = {
  createApp,
  computeHmac,
  computeMailboxProof,
  hashMailboxProofBody
};
