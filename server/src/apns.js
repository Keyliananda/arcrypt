"use strict";

const crypto = require("crypto");
const fs = require("fs");
const http2 = require("http2");

function base64UrlEncode(value) {
  const buffer = Buffer.isBuffer(value) ? value : Buffer.from(String(value));
  return buffer
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function buildJwt({ keyId, teamId, privateKey, nowSec }) {
  const header = base64UrlEncode(JSON.stringify({ alg: "ES256", kid: keyId }));
  const payload = base64UrlEncode(JSON.stringify({ iss: teamId, iat: nowSec }));
  const signer = crypto.createSign("SHA256");
  signer.update(`${header}.${payload}`);
  signer.end();
  const signature = signer.sign(privateKey);
  return `${header}.${payload}.${base64UrlEncode(signature)}`;
}

function isApnsConfigured(config) {
  return Boolean(
    config &&
      config.enabled &&
      config.keyId &&
      config.teamId &&
      config.keyPath &&
      config.topic
  );
}

function resolveHost(env) {
  const normalized = String(env || "").trim().toLowerCase();
  if (normalized === "prod" || normalized === "production") {
    return "api.push.apple.com";
  }
  return "api.sandbox.push.apple.com";
}

async function sendSilentPush({
  token,
  topic,
  env,
  keyId,
  teamId,
  keyPath,
  timeoutMs
}) {
  if (!token || !topic || !keyId || !teamId || !keyPath) {
    return { ok: false, error: "not_configured" };
  }

  let privateKey;
  try {
    privateKey = fs.readFileSync(keyPath, "utf8");
  } catch (error) {
    return { ok: false, error: "key_not_found", message: error.message };
  }

  const nowSec = Math.floor(Date.now() / 1000);
  const jwt = buildJwt({ keyId, teamId, privateKey, nowSec });
  const host = resolveHost(env);
  const payload = JSON.stringify({ aps: { "content-available": 1 } });

  return new Promise((resolve) => {
    let done = false;
    const finish = (result) => {
      if (done) {
        return;
      }
      done = true;
      resolve(result);
    };

    const client = http2.connect(`https://${host}`);

    client.on("error", (error) => {
      client.close();
      finish({ ok: false, error: "connection_failed", message: error.message });
    });

    const req = client.request({
      ":method": "POST",
      ":path": `/3/device/${token}`,
      "authorization": `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "background",
      "apns-priority": "5",
      "apns-expiration": "0",
      "content-type": "application/json"
    });

    let status = 0;
    let apnsId = "";
    let body = "";

    req.setEncoding("utf8");
    req.on("response", (headers) => {
      status = Number(headers[":status"] || 0);
      apnsId = headers["apns-id"] || "";
    });
    req.on("data", (chunk) => {
      body += chunk;
    });
    req.on("end", () => {
      client.close();
      let reason = "";
      if (body) {
        try {
          const parsed = JSON.parse(body);
          reason = parsed.reason || "";
        } catch (error) {
          reason = "";
        }
      }
      finish({ ok: status === 200, status, apnsId, reason });
    });
    req.on("error", (error) => {
      client.close();
      finish({ ok: false, error: "request_failed", message: error.message });
    });

    if (timeoutMs && timeoutMs > 0) {
      req.setTimeout(timeoutMs, () => {
        req.close();
        client.close();
        finish({ ok: false, error: "timeout" });
      });
    }

    req.end(payload);
  });
}

module.exports = { sendSilentPush, isApnsConfigured };
