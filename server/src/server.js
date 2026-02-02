"use strict";

require("dotenv").config();

const http = require("http");
const { createApp } = require("./app");
const { createStore } = require("./store");
const { config } = require("./config");

function readBody(req, maxBytes) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on("data", (chunk) => {
      size += chunk.length;
      if (size > maxBytes) {
        const error = new Error("body_too_large");
        error.code = "body_too_large";
        req.destroy(error);
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      resolve(Buffer.concat(chunks).toString("utf8"));
    });
    req.on("error", (error) => {
      reject(error);
    });
  });
}

function getClientIp(req) {
  const forwarded = req.headers["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim()) {
    return forwarded.split(",")[0].trim();
  }
  return req.socket && req.socket.remoteAddress ? req.socket.remoteAddress : "";
}

async function startServer() {
  const store = createStore(config.db);
  const app = createApp({ store, config });

  const server = http.createServer(async (req, res) => {
    let body = "";
    try {
      body = await readBody(req, config.maxBodyBytes);
    } catch (error) {
      if (error && error.code === "body_too_large") {
        res.writeHead(413, { "content-type": "application/json; charset=utf-8" });
        res.end(JSON.stringify({ ok: false, error: "body_too_large" }));
        return;
      }
      res.writeHead(500, { "content-type": "application/json; charset=utf-8" });
      res.end(JSON.stringify({ ok: false, error: "read_error" }));
      return;
    }

    const url = new URL(req.url, "http://localhost");
    const response = await app.handle({
      method: req.method,
      path: url.pathname,
      headers: req.headers,
      body,
      ip: getClientIp(req)
    });

    res.writeHead(response.status, response.headers);
    res.end(response.body || "");
  });

  server.listen(config.port, () => {
    process.stdout.write(`Server listening on ${config.port}\n`);
  });
}

if (require.main === module) {
  startServer();
}

module.exports = { startServer };
