"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  createApp,
  computeHmac,
  computeMailboxProof,
  hashMailboxProofBody
} = require("../src/app");
const { MemoryStore } = require("../src/store/memory");

const FIXED_NOW = new Date("2026-02-02T12:00:00Z").getTime();

function isObject(value) {
  return value && typeof value === "object" && !Array.isArray(value);
}

function deepMerge(base, overrides) {
  if (!isObject(overrides)) {
    return overrides === undefined ? base : overrides;
  }

  const merged = { ...base };
  for (const key of Object.keys(overrides)) {
    if (isObject(base[key]) && isObject(overrides[key])) {
      merged[key] = deepMerge(base[key], overrides[key]);
    } else {
      merged[key] = overrides[key];
    }
  }
  return merged;
}

function makeApp(overrides = {}) {
  const store = new MemoryStore();
  const baseConfig = {
    security: {
      tlsOnly: false,
      trustProxy: true,
      hstsEnabled: false,
      hstsMaxAgeSec: 15552000,
      hstsIncludeSubdomains: false,
      hstsPreload: false
    },
    hmacSecret: "test-secret",
    hmacMaxSkewSec: 300,
    rateLimit: {
      windowSec: 3600,
      perToken: 30,
      perIp: 120
    },
    relay: {
      proofMaxSkewSec: 300,
      nonceTtlSec: 900,
      defaultExpirySec: 86400,
      minExpirySec: 60,
      maxExpirySec: 604800,
      maxCiphertextBytes: 65536,
      maxPullLimit: 100,
      defaultPullLimit: 50,
      maxAckMessageIds: 100,
      rateLimit: {
        pushPerMailbox: 120,
        pullPerMailbox: 360,
        ackPerMailbox: 360,
        pushPerIp: 1200,
        pullPerIp: 1200,
        ackPerIp: 1200
      }
    },
    apns: { enabled: false }
  };
  const config = deepMerge(baseConfig, overrides);

  const app = createApp({
    store,
    config,
    now: () => FIXED_NOW
  });

  return { app, store, config };
}

async function call(app, payload) {
  const response = await app.handle({
    method: payload.method || "POST",
    path: payload.path,
    headers: payload.headers || {},
    body: payload.body || "",
    ip: payload.ip || "203.0.113.10"
  });
  return {
    status: response.status,
    headers: response.headers || {},
    json: response.body ? JSON.parse(response.body) : null
  };
}

function makeMailboxId(label) {
  return Buffer.from(`mailbox-${label}`.padEnd(20, "x")).toString("base64url");
}

function makeNonce(label) {
  return Buffer.from(`nonce-${label}`.padEnd(18, "y")).toString("base64url");
}

function signMailboxBody(path, body, mailboxId, ts, nonce) {
  const unsigned = {
    ...body,
    mailbox_id: mailboxId,
    ts,
    nonce
  };
  const proof = computeMailboxProof(mailboxId, {
    method: "POST",
    path,
    ts,
    nonce,
    bodySha256Hex: hashMailboxProofBody(unsigned)
  });
  return { ...unsigned, proof };
}

test("health endpoint responds ok", async () => {
  const { app } = makeApp();
  const result = await call(app, { path: "/v1/health" });
  assert.equal(result.status, 200);
  assert.deepEqual(result.json, { ok: true, status: "ok" });
});

test("tls only rejects non-tls requests", async () => {
  const { app } = makeApp({
    security: {
      tlsOnly: true
    }
  });
  const result = await call(app, { path: "/v1/health" });
  assert.equal(result.status, 426);
  assert.equal(result.json.error, "tls_required");
});

test("tls-only accepts forwarded https and adds hsts when enabled", async () => {
  const { app } = makeApp({
    security: {
      tlsOnly: true,
      hstsEnabled: true,
      hstsMaxAgeSec: 86400,
      hstsIncludeSubdomains: true
    }
  });
  const result = await call(app, {
    path: "/v1/health",
    headers: { "x-forwarded-proto": "https" }
  });
  assert.equal(result.status, 200);
  assert.equal(
    result.headers["strict-transport-security"],
    "max-age=86400; includeSubDomains"
  );
});

test("register validates fields", async () => {
  const { app } = makeApp();
  const result = await call(app, { path: "/v1/register", body: JSON.stringify({}) });
  assert.equal(result.status, 400);
  assert.equal(result.json.error, "missing_fields");
});

test("register then unregister removes token", async () => {
  const { app, store } = makeApp();
  const token = "apns-token-1";

  const register = await call(app, {
    path: "/v1/register",
    body: JSON.stringify({ token, topic: "com.example.app", env: "sandbox" })
  });
  assert.equal(register.status, 200);

  const stored = await store.getTokenByValue(token);
  assert.equal(stored.token, token);

  const unregister = await call(app, {
    path: "/v1/unregister",
    body: JSON.stringify({ token })
  });
  assert.equal(unregister.status, 200);

  const missing = await store.getTokenByValue(token);
  assert.equal(missing, null);
});

test("wake requires configured hmac", async () => {
  const { app } = makeApp({ hmacSecret: "" });
  const response = await call(app, {
    path: "/v1/wake",
    body: JSON.stringify({ token: "t", ts: 1, proof: "00" })
  });
  assert.equal(response.status, 503);
  assert.equal(response.json.error, "hmac_not_configured");
});

test("wake rejects stale timestamp", async () => {
  const { app } = makeApp();
  const token = "apns-token-2";
  const stale = Math.floor(FIXED_NOW / 1000) - 1000;
  const proof = computeHmac("test-secret", token, stale);
  const response = await call(app, {
    path: "/v1/wake",
    body: JSON.stringify({ token, ts: stale, proof })
  });
  assert.equal(response.status, 401);
  assert.equal(response.json.error, "timestamp_out_of_range");
});

test("wake rejects invalid proof", async () => {
  const { app } = makeApp();
  const token = "apns-token-3";
  const ts = Math.floor(FIXED_NOW / 1000);
  const response = await call(app, {
    path: "/v1/wake",
    body: JSON.stringify({ token, ts, proof: "deadbeef" })
  });
  assert.equal(response.status, 401);
  assert.equal(response.json.error, "invalid_proof");
});

test("wake queues request for valid proof", async () => {
  const { app, store } = makeApp();
  const token = "apns-token-4";

  await call(app, {
    path: "/v1/register",
    body: JSON.stringify({ token, topic: "com.example.app", env: "sandbox" })
  });

  const ts = Math.floor(FIXED_NOW / 1000);
  const proof = computeHmac("test-secret", token, ts);
  const response = await call(app, {
    path: "/v1/wake",
    body: JSON.stringify({ token, ts, proof })
  });

  assert.equal(response.status, 202);
  assert.equal(response.json.status, "queued");
  assert.ok(response.json.wake_id);

  const wake = await store.getWakeRequestById(response.json.wake_id);
  assert.equal(wake.token_id > 0, true);
});

test("rate limit blocks repeated register", async () => {
  const { app } = makeApp({
    rateLimit: { windowSec: 3600, perToken: 1, perIp: 100 }
  });
  const token = "apns-token-5";

  const first = await call(app, {
    path: "/v1/register",
    body: JSON.stringify({ token, topic: "com.example.app", env: "sandbox" })
  });
  assert.equal(first.status, 200);

  const second = await call(app, {
    path: "/v1/register",
    body: JSON.stringify({ token, topic: "com.example.app", env: "sandbox" })
  });
  assert.equal(second.status, 429);
  assert.equal(second.json.error, "rate_limit");
});

test("mailbox push pull ack flow works", async () => {
  const { app } = makeApp();
  const mailboxId = makeMailboxId("flow");
  const ts = Math.floor(FIXED_NOW / 1000);

  const pushBody = signMailboxBody(
    "/v1/mailbox/push",
    {
      ciphertext: Buffer.from("hello-relay").toString("base64"),
      client_msg_id: "client-1"
    },
    mailboxId,
    ts,
    makeNonce("push1")
  );

  const push = await call(app, {
    path: "/v1/mailbox/push",
    body: JSON.stringify(pushBody)
  });
  assert.equal(push.status, 202);
  assert.ok(push.json.message_id);

  const pullBody = signMailboxBody(
    "/v1/mailbox/pull",
    {
      cursor: null,
      limit: 10
    },
    mailboxId,
    ts,
    makeNonce("pull1")
  );

  const pull = await call(app, {
    path: "/v1/mailbox/pull",
    body: JSON.stringify(pullBody)
  });
  assert.equal(pull.status, 200);
  assert.equal(pull.json.messages.length, 1);
  assert.equal(pull.json.messages[0].message_id, push.json.message_id);

  const ackBody = signMailboxBody(
    "/v1/mailbox/ack",
    {
      message_ids: [push.json.message_id]
    },
    mailboxId,
    ts,
    makeNonce("ack1")
  );

  const ack = await call(app, {
    path: "/v1/mailbox/ack",
    body: JSON.stringify(ackBody)
  });
  assert.equal(ack.status, 200);
  assert.deepEqual(ack.json.acked, [push.json.message_id]);

  const ackAgainBody = signMailboxBody(
    "/v1/mailbox/ack",
    {
      message_ids: [push.json.message_id]
    },
    mailboxId,
    ts,
    makeNonce("ack2")
  );

  const ackAgain = await call(app, {
    path: "/v1/mailbox/ack",
    body: JSON.stringify(ackAgainBody)
  });
  assert.equal(ackAgain.status, 200);
  assert.deepEqual(ackAgain.json.already_acked, [push.json.message_id]);
});

test("mailbox rejects nonce replay", async () => {
  const { app } = makeApp();
  const mailboxId = makeMailboxId("replay");
  const ts = Math.floor(FIXED_NOW / 1000);
  const nonce = makeNonce("same");

  const firstBody = signMailboxBody(
    "/v1/mailbox/push",
    {
      ciphertext: Buffer.from("first").toString("base64"),
      client_msg_id: "cmid-1"
    },
    mailboxId,
    ts,
    nonce
  );

  const first = await call(app, {
    path: "/v1/mailbox/push",
    body: JSON.stringify(firstBody)
  });
  assert.equal(first.status, 202);

  const secondBody = signMailboxBody(
    "/v1/mailbox/push",
    {
      ciphertext: Buffer.from("second").toString("base64"),
      client_msg_id: "cmid-2"
    },
    mailboxId,
    ts,
    nonce
  );

  const second = await call(app, {
    path: "/v1/mailbox/push",
    body: JSON.stringify(secondBody)
  });
  assert.equal(second.status, 401);
  assert.equal(second.json.error, "nonce_replay");
});

test("mailbox push rate limit is enforced", async () => {
  const { app } = makeApp({
    relay: {
      rateLimit: {
        pushPerMailbox: 1,
        pushPerIp: 1000
      }
    }
  });
  const mailboxId = makeMailboxId("rl");
  const ts = Math.floor(FIXED_NOW / 1000);

  const firstBody = signMailboxBody(
    "/v1/mailbox/push",
    {
      ciphertext: Buffer.from("one").toString("base64"),
      client_msg_id: "rl-1"
    },
    mailboxId,
    ts,
    makeNonce("rl1")
  );

  const first = await call(app, {
    path: "/v1/mailbox/push",
    body: JSON.stringify(firstBody)
  });
  assert.equal(first.status, 202);

  const secondBody = signMailboxBody(
    "/v1/mailbox/push",
    {
      ciphertext: Buffer.from("two").toString("base64"),
      client_msg_id: "rl-2"
    },
    mailboxId,
    ts,
    makeNonce("rl2")
  );

  const second = await call(app, {
    path: "/v1/mailbox/push",
    body: JSON.stringify(secondBody)
  });
  assert.equal(second.status, 429);
  assert.equal(second.json.error, "rate_limit");
  assert.equal(second.json.details.scope, "mailbox");
});

test("mailbox push rejects oversized ciphertext", async () => {
  const { app } = makeApp({
    relay: {
      maxCiphertextBytes: 4
    }
  });
  const mailboxId = makeMailboxId("size");
  const ts = Math.floor(FIXED_NOW / 1000);

  const pushBody = signMailboxBody(
    "/v1/mailbox/push",
    {
      ciphertext: Buffer.from("too-big").toString("base64"),
      client_msg_id: "size-1"
    },
    mailboxId,
    ts,
    makeNonce("size1")
  );

  const response = await call(app, {
    path: "/v1/mailbox/push",
    body: JSON.stringify(pushBody)
  });

  assert.equal(response.status, 413);
  assert.equal(response.json.error, "ciphertext_too_large");
});

test("mailbox pull for unknown mailbox returns 404", async () => {
  const { app } = makeApp();
  const mailboxId = makeMailboxId("missing");
  const ts = Math.floor(FIXED_NOW / 1000);

  const pullBody = signMailboxBody(
    "/v1/mailbox/pull",
    {
      cursor: null,
      limit: 5
    },
    mailboxId,
    ts,
    makeNonce("missing")
  );

  const response = await call(app, {
    path: "/v1/mailbox/pull",
    body: JSON.stringify(pullBody)
  });

  assert.equal(response.status, 404);
  assert.equal(response.json.error, "mailbox_not_found");
});
