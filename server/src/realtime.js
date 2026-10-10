"use strict";

const { WebSocket, WebSocketServer } = require("ws");
const {
  computeMailboxProof,
  hashMailboxProofBody,
  readInteger,
  readMailboxId,
  readNonce,
  readString,
  relayConfigFrom,
  sha256Hex,
  timingSafeEqualHex
} = require("./app");

const REALTIME_PATH = "/v1/mailbox/connect";
const DEFAULT_PING_INTERVAL_MS = 25000;
const DEFAULT_SUBSCRIBE_TIMEOUT_MS = 10000;
const HEX_64_RE = /^[0-9a-f]{64}$/i;

function getClientIp(req) {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim()) {
    return forwarded.split(",")[0].trim();
  }
  return req.socket && req.socket.remoteAddress ? req.socket.remoteAddress : "";
}

function makeCloseReason(code) {
  switch (code) {
    case "invalid_json":
      return "invalid_json";
    case "missing_fields":
      return "missing_fields";
    case "invalid_field":
      return "invalid_field";
    case "timestamp_out_of_range":
      return "timestamp_out_of_range";
    case "invalid_proof":
      return "invalid_proof";
    case "nonce_replay":
      return "nonce_replay";
    default:
      return "subscribe_failed";
  }
}

class RelayRealtimeHub {
  constructor({ server, store, config, now = Date.now, logger }) {
    this._store = store;
    this._config = config;
    this._relayConfig = relayConfigFrom(config);
    this._now = now;
    this._logger = logger;
    this._subscriptionsByMailbox = new Map();
    this._stateBySocket = new WeakMap();
    this._pingIntervalMs = Number.isFinite(config.relay?.realtime?.pingIntervalMs)
      ? config.relay.realtime.pingIntervalMs
      : DEFAULT_PING_INTERVAL_MS;
    this._subscribeTimeoutMs = Number.isFinite(config.relay?.realtime?.subscribeTimeoutMs)
      ? config.relay.realtime.subscribeTimeoutMs
      : DEFAULT_SUBSCRIBE_TIMEOUT_MS;

    this._wss = new WebSocketServer({ noServer: true });
    this._wss.on("connection", (ws, req) => {
      this._handleConnection(ws, req);
    });

    this._pingTimer = null;
    if (this._pingIntervalMs > 0) {
      this._pingTimer = setInterval(() => {
        this._pingClients();
      }, this._pingIntervalMs);
      this._pingTimer.unref?.();
    }

    server.on("upgrade", (req, socket, head) => {
      if (!this._isRealtimeUpgrade(req)) {
        socket.write("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n");
        socket.destroy();
        return;
      }

      this._wss.handleUpgrade(req, socket, head, (ws) => {
        this._wss.emit("connection", ws, req);
      });
    });
  }

  async close() {
    if (this._pingTimer) {
      clearInterval(this._pingTimer);
      this._pingTimer = null;
    }

    const closePromises = [];
    for (const ws of this._wss.clients) {
      closePromises.push(
        new Promise((resolve) => {
          ws.once("close", resolve);
          ws.close(1001, "server_shutdown");
        })
      );
    }
    await Promise.allSettled(closePromises);

    await new Promise((resolve) => {
      this._wss.close(resolve);
    });
  }

  publishMailboxUpdate({ mailboxIdHash, messageId }) {
    const subscribers = this._subscriptionsByMailbox.get(mailboxIdHash);
    if (!subscribers || subscribers.size === 0) {
      return;
    }

    const payload = JSON.stringify({
      type: "mailbox_update",
      mailbox_id_hash: mailboxIdHash,
      message_id: messageId
    });

    for (const ws of subscribers) {
      if (ws.readyState !== WebSocket.OPEN) {
        continue;
      }
      ws.send(payload);
    }
  }

  _isRealtimeUpgrade(req) {
    const upgradeHeader = String(req.headers.upgrade || "").trim().toLowerCase();
    if (upgradeHeader !== "websocket") {
      return false;
    }

    const url = new URL(req.url || "/", "http://localhost");
    return url.pathname === REALTIME_PATH;
  }

  _handleConnection(ws, req) {
    const state = {
      clientIp: getClientIp(req),
      isAlive: true,
      mailboxIdHash: null,
      subscribeTimer: setTimeout(() => {
        this._sendErrorAndClose(ws, "subscribe_timeout");
      }, this._subscribeTimeoutMs)
    };
    state.subscribeTimer.unref?.();

    this._stateBySocket.set(ws, state);

    ws.on("pong", () => {
      state.isAlive = true;
    });

    ws.on("message", async (raw) => {
      try {
        await this._handleMessage(ws, state, raw);
      } catch (error) {
        this._log(`Realtime message handling failed: ${error}`);
        this._sendErrorAndClose(ws, "subscribe_failed");
      }
    });

    ws.on("close", () => {
      this._clearSubscription(ws, state);
    });

    ws.on("error", (error) => {
      this._log(`Realtime socket error: ${error}`);
    });
  }

  async _handleMessage(ws, state, raw) {
    let payload;
    try {
      payload = JSON.parse(raw.toString("utf8"));
    } catch (error) {
      this._sendErrorAndClose(ws, "invalid_json");
      return;
    }

    if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
      this._sendErrorAndClose(ws, "invalid_json");
      return;
    }

    if (state.mailboxIdHash) {
      if (payload.type === "ping") {
        this._send(ws, { type: "pong" });
      }
      return;
    }

    if (payload.type !== "subscribe") {
      this._sendErrorAndClose(ws, "missing_fields");
      return;
    }

    const verified = await this._verifySubscribeRequest(payload, state.clientIp);
    if (verified.error) {
      this._sendErrorAndClose(ws, verified.error, verified.details);
      return;
    }

    clearTimeout(state.subscribeTimer);
    state.subscribeTimer = null;
    state.mailboxIdHash = verified.mailboxIdHash;

    if (!this._subscriptionsByMailbox.has(verified.mailboxIdHash)) {
      this._subscriptionsByMailbox.set(verified.mailboxIdHash, new Set());
    }
    this._subscriptionsByMailbox.get(verified.mailboxIdHash).add(ws);

    this._send(ws, {
      type: "ready",
      mailbox_id_hash: verified.mailboxIdHash
    });
    this._log(`Realtime subscribed mailbox=${verified.mailboxIdHash} ip=${state.clientIp}`);
  }

  async _verifySubscribeRequest(body, ip) {
    const mailboxId = readMailboxId(body.mailbox_id);
    const nonce = readNonce(body.nonce);
    const proof = readString(body.proof, 128);
    const ts = readInteger(body.ts);

    if (!mailboxId || !nonce || !proof || ts === null) {
      return { error: "missing_fields" };
    }
    if (!HEX_64_RE.test(proof)) {
      return { error: "invalid_field", details: { field: "proof" } };
    }

    const nowMs = this._now();
    const nowSec = Math.floor(nowMs / 1000);
    if (Math.abs(nowSec - ts) > this._relayConfig.proofMaxSkewSec) {
      return { error: "timestamp_out_of_range" };
    }

    const unsigned = {
      type: "subscribe",
      mailbox_id: mailboxId,
      ts,
      nonce
    };
    const expected = computeMailboxProof(mailboxId, {
      method: "WS",
      path: REALTIME_PATH,
      ts,
      nonce,
      bodySha256Hex: hashMailboxProofBody(unsigned)
    });
    if (!timingSafeEqualHex(expected, proof)) {
      return { error: "invalid_proof" };
    }

    const mailboxIdHash = sha256Hex(mailboxId);
    const popKeyCommitment = sha256Hex(`pop:${mailboxId}`);
    let mailbox = await this._store.getRelayMailbox(mailboxIdHash);
    if (!mailbox) {
      mailbox = await this._store.upsertRelayMailbox(
        mailboxIdHash,
        popKeyCommitment,
        new Date(nowMs)
      );
    }
    if (!mailbox || mailbox.pop_key_commitment !== popKeyCommitment) {
      return { error: "invalid_proof" };
    }

    const seenAt = new Date(nowMs);
    const expiresAt = new Date(nowMs + this._relayConfig.nonceTtlSec * 1000);
    const nonceStored = await this._store.insertRelayNonce(mailboxIdHash, nonce, seenAt, expiresAt);
    if (!nonceStored) {
      return { error: "nonce_replay" };
    }

    return { mailboxIdHash };
  }

  _send(ws, payload) {
    if (ws.readyState !== WebSocket.OPEN) {
      return;
    }
    ws.send(JSON.stringify(payload));
  }

  _sendErrorAndClose(ws, error, details) {
    this._send(ws, {
      type: "error",
      error,
      ...(details ? { details } : {})
    });
    ws.close(4401, makeCloseReason(error));
  }

  _clearSubscription(ws, state) {
    if (state.subscribeTimer) {
      clearTimeout(state.subscribeTimer);
      state.subscribeTimer = null;
    }

    if (!state.mailboxIdHash) {
      return;
    }

    const subscribers = this._subscriptionsByMailbox.get(state.mailboxIdHash);
    if (!subscribers) {
      return;
    }
    subscribers.delete(ws);
    if (subscribers.size === 0) {
      this._subscriptionsByMailbox.delete(state.mailboxIdHash);
    }
  }

  _pingClients() {
    for (const ws of this._wss.clients) {
      const state = this._stateBySocket.get(ws);
      if (!state) {
        continue;
      }
      if (!state.isAlive) {
        ws.terminate();
        continue;
      }
      state.isAlive = false;
      ws.ping();
    }
  }

  _log(message) {
    if (typeof this._logger === "function") {
      this._logger(`[RelayRealtimeHub] ${message}`);
    }
  }
}

module.exports = {
  REALTIME_PATH,
  RelayRealtimeHub
};
