"use strict";

function toInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toBool(value, fallback) {
  if (value === undefined) {
    return fallback;
  }
  const normalized = String(value).trim().toLowerCase();
  if (["1", "true", "yes", "on"].includes(normalized)) {
    return true;
  }
  if (["0", "false", "no", "off"].includes(normalized)) {
    return false;
  }
  return fallback;
}

const config = {
  port: toInt(process.env.PORT, 3000),
  maxBodyBytes: toInt(process.env.MAX_BODY_BYTES, 128 * 1024),
  security: {
    tlsOnly: toBool(process.env.SECURITY_TLS_ONLY, false),
    trustProxy: toBool(process.env.SECURITY_TRUST_PROXY, true),
    hstsEnabled: toBool(process.env.SECURITY_HSTS_ENABLED, false),
    hstsMaxAgeSec: toInt(process.env.SECURITY_HSTS_MAX_AGE_SEC, 15552000),
    hstsIncludeSubdomains: toBool(process.env.SECURITY_HSTS_INCLUDE_SUBDOMAINS, false),
    hstsPreload: toBool(process.env.SECURITY_HSTS_PRELOAD, false)
  },
  hmacSecret: process.env.HMAC_SECRET || "",
  hmacMaxSkewSec: toInt(process.env.HMAC_MAX_SKEW_SEC, 300),
  rateLimit: {
    windowSec: toInt(process.env.RATE_LIMIT_WINDOW_SEC, 3600),
    perToken: toInt(process.env.RATE_LIMIT_TOKEN_PER_WINDOW, 30),
    perIp: toInt(process.env.RATE_LIMIT_IP_PER_WINDOW, 120)
  },
  db: {
    driver: process.env.DB_DRIVER || "memory",
    filename: process.env.DB_FILENAME || "./data.sqlite",
    host: process.env.DB_HOST || "localhost",
    port: toInt(process.env.DB_PORT, 3306),
    user: process.env.DB_USER || "",
    password: process.env.DB_PASSWORD || "",
    database: process.env.DB_NAME || ""
  },
  relay: {
    ackDeleteGraceSec: toInt(process.env.RELAY_ACK_DELETE_GRACE_SEC, 900),
    proofMaxSkewSec: toInt(process.env.RELAY_PROOF_MAX_SKEW_SEC, 300),
    nonceTtlSec: toInt(process.env.RELAY_NONCE_TTL_SEC, 900),
    defaultExpirySec: toInt(process.env.RELAY_DEFAULT_EXPIRY_SEC, 86400),
    minExpirySec: toInt(process.env.RELAY_MIN_EXPIRY_SEC, 60),
    maxExpirySec: toInt(process.env.RELAY_MAX_EXPIRY_SEC, 604800),
    maxCiphertextBytes: toInt(process.env.RELAY_MAX_CIPHERTEXT_BYTES, 64 * 1024),
    maxPullLimit: toInt(process.env.RELAY_PULL_LIMIT_MAX, 100),
    defaultPullLimit: toInt(process.env.RELAY_PULL_LIMIT_DEFAULT, 50),
    maxAckMessageIds: toInt(process.env.RELAY_ACK_MAX_IDS, 100),
    rateLimit: {
      pushPerMailbox: toInt(process.env.RELAY_RATE_LIMIT_PUSH_PER_MAILBOX, 120),
      pullPerMailbox: toInt(process.env.RELAY_RATE_LIMIT_PULL_PER_MAILBOX, 360),
      ackPerMailbox: toInt(process.env.RELAY_RATE_LIMIT_ACK_PER_MAILBOX, 360),
      pushPerIp: toInt(process.env.RELAY_RATE_LIMIT_PUSH_PER_IP, 1200),
      pullPerIp: toInt(process.env.RELAY_RATE_LIMIT_PULL_PER_IP, 1200),
      ackPerIp: toInt(process.env.RELAY_RATE_LIMIT_ACK_PER_IP, 1200)
    }
  },
  apns: {
    enabled: toBool(process.env.APNS_ENABLED, true),
    env: process.env.APNS_ENV || "sandbox",
    keyId: process.env.APNS_KEY_ID || "",
    teamId: process.env.APNS_TEAM_ID || "",
    topic: process.env.APNS_TOPIC || "",
    keyPath: process.env.APNS_KEY_PATH || "",
    timeoutMs: toInt(process.env.APNS_TIMEOUT_MS, 5000)
  }
};

module.exports = { config };
