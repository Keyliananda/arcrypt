"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const http = require("http");
const { WebSocket } = require("ws");
const {
  createApp,
  computeMailboxProof,
  hashMailboxProofBody
} = require("../src/app");
const { RelayRealtimeHub, REALTIME_PATH } = require("../src/realtime");
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

function signSubscribe(mailboxId, ts, nonce) {
  const unsigned = {
    type: "subscribe",
    mailbox_id: mailboxId,
    ts,
    nonce
  };
  const proof = computeMailboxProof(mailboxId, {
    method: "WS",
    path: REALTIME_PATH,
    ts,
    nonce,
    bodySha256Hex: hashMailboxProofBody(unsigned)
  });
  return { ...unsigned, proof };
}

async function createRelayHarness(overrides = {}) {
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
    wake: {
      tokenTtlSec: 2592000
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
      },
      realtime: {
        pingIntervalMs: 0,
        subscribeTimeoutMs: 1000
      }
    },
    apns: { enabled: false }
  };
  const config = deepMerge(baseConfig, overrides);

  let realtimeHub;
  const app = createApp({
    store,
    config,
    now: () => FIXED_NOW,
    onRelayMessageStored: async (message) => {
      realtimeHub.publishMailboxUpdate({
        mailboxIdHash: message.mailbox_id_hash,
        messageId: message.message_id
      });
    }
  });

  const server = http.createServer(async (req, res) => {
    const chunks = [];
    for await (const chunk of req) {
      chunks.push(chunk);
    }
    const response = await app.handle({
      method: req.method,
      path: new URL(req.url, "http://localhost").pathname,
      headers: req.headers,
      body: Buffer.concat(chunks).toString("utf8"),
      ip: req.socket.remoteAddress || "127.0.0.1"
    });
    res.writeHead(response.status, response.headers);
    res.end(response.body || "");
  });

  realtimeHub = new RelayRealtimeHub({
    server,
    store,
    config,
    now: () => FIXED_NOW
  });

  await new Promise((resolve) => {
    server.listen(0, "127.0.0.1", resolve);
  });

  const address = server.address();
  const port = address.port;
  const baseUrl = `http://127.0.0.1:${port}`;

  return {
    store,
    baseUrl,
    async close() {
      await realtimeHub.close();
      await new Promise((resolve, reject) => {
        server.close((error) => {
          if (error) {
            reject(error);
            return;
          }
          resolve();
        });
      });
    }
  };
}

async function postJson(baseUrl, path, payload) {
  const response = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(payload)
  });
  return {
    status: response.status,
    json: await response.json()
  };
}

test("websocket relay emits mailbox_update after push", async () => {
  const harness = await createRelayHarness();
  try {
    const mailboxId = makeMailboxId("ws-receiver");
    const ts = Math.floor(FIXED_NOW / 1000);
    const nonce = makeNonce("subscribe");
    const subscribePayload = signSubscribe(mailboxId, ts, nonce);

    const ready = new Promise((resolve, reject) => {
      const socket = new WebSocket(harness.baseUrl.replace("http", "ws") + REALTIME_PATH);

      socket.once("error", reject);
      socket.on("open", () => {
        socket.send(JSON.stringify(subscribePayload));
      });
      socket.on("message", (raw) => {
        const payload = JSON.parse(raw.toString("utf8"));
        if (payload.type === "ready") {
          resolve(socket);
        } else if (payload.type === "error") {
          reject(new Error(payload.error));
        }
      });
    });

    const socket = await ready;

    const update = new Promise((resolve, reject) => {
      socket.once("error", reject);
      socket.on("message", (raw) => {
        const payload = JSON.parse(raw.toString("utf8"));
        if (payload.type === "mailbox_update") {
          resolve(payload);
        }
      });
    });

    const pushBody = signMailboxBody(
      "/v1/mailbox/push",
      {
        ciphertext: Buffer.from("hello", "utf8").toString("base64"),
        client_msg_id: "ws_push_1"
      },
      mailboxId,
      ts,
      makeNonce("push")
    );
    const pushed = await postJson(harness.baseUrl, "/v1/mailbox/push", pushBody);
    assert.equal(pushed.status, 202);
    assert.equal(pushed.json.ok, true);

    const payload = await Promise.race([
      update,
      new Promise((_, reject) => setTimeout(() => reject(new Error("timeout")), 1500))
    ]);
    assert.equal(payload.type, "mailbox_update");
    assert.equal(typeof payload.message_id, "string");

    socket.close();
  } finally {
    await harness.close();
  }
});
