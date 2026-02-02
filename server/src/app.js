"use strict";

const crypto = require("crypto");

const MAX_TOKEN_LENGTH = 512;
const MAX_TOPIC_LENGTH = 255;
const ALLOWED_ENVS = new Set(["sandbox", "prod"]);

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

function computeHmac(secret, token, ts) {
  return crypto
    .createHmac("sha256", secret)
    .update(`${token}:${ts}`)
    .digest("hex");
}

function windowStartDate(nowMs, windowSec) {
  const nowSec = Math.floor(nowMs / 1000);
  const startSec = Math.floor(nowSec / windowSec) * windowSec;
  return new Date(startSec * 1000);
}

function createApp({ store, config, now = Date.now }) {
  async function applyRateLimit(scope, key, limit, windowStart) {
    if (!key || limit <= 0) {
      return { allowed: true };
    }
    const count = await store.incrementRateLimit(scope, key, windowStart);
    return { allowed: count <= limit, count, limit, scope };
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
    const tokenLimit = await applyRateLimit(
      "token",
      token,
      config.rateLimit.perToken,
      windowStart
    );
    if (!tokenLimit.allowed) {
      return errorResponse(429, "rate_limit", { scope: "token", limit: tokenLimit.limit });
    }
    const ipLimit = await applyRateLimit(
      "ip",
      ip,
      config.rateLimit.perIp,
      windowStart
    );
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
    const ts = Number.isInteger(body.ts) ? body.ts : Number.parseInt(body.ts, 10);

    if (!token || !proof || !Number.isFinite(ts)) {
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
    const tokenLimit = await applyRateLimit(
      "token",
      token,
      config.rateLimit.perToken,
      windowStart
    );
    if (!tokenLimit.allowed) {
      return errorResponse(429, "rate_limit", { scope: "token", limit: tokenLimit.limit });
    }
    const ipLimit = await applyRateLimit(
      "ip",
      ip,
      config.rateLimit.perIp,
      windowStart
    );
    if (!ipLimit.allowed) {
      return errorResponse(429, "rate_limit", { scope: "ip", limit: ipLimit.limit });
    }

    const tokenRecord = await store.getTokenByValue(token);
    if (!tokenRecord) {
      return errorResponse(404, "token_not_found");
    }

    const createdAt = new Date(nowMs);
    const wakeId = await store.createWakeRequest(tokenRecord.id, createdAt);
    return jsonResponse(202, { ok: true, wake_id: wakeId, status: "queued" });
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

    return errorResponse(404, "not_found");
  }

  return { handle };
}

module.exports = { createApp, computeHmac };
