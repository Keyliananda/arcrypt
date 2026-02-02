"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const sqlite3 = require("sqlite3");
const { SqliteStore } = require("../src/store/sqlite");

const schemaPath = path.join(__dirname, "..", "schema_sqlite.sql");

function initSchema(filename) {
  const schema = fs.readFileSync(schemaPath, "utf8");
  return new Promise((resolve, reject) => {
    const db = new sqlite3.Database(filename);
    db.exec(schema, (err) => {
      if (err) {
        db.close(() => reject(err));
        return;
      }
      db.close((closeErr) => {
        if (closeErr) {
          reject(closeErr);
          return;
        }
        resolve();
      });
    });
  });
}

test("sqlite store smoke", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "silent-wake-"));
  const filename = path.join(dir, "test.sqlite");

  await initSchema(filename);

  const store = new SqliteStore({ filename });
  try {
    const tokenId = await store.upsertToken({
      token: "apns-token-sqlite",
      topic: "com.example.app",
      env: "sandbox",
      lastSeen: new Date("2026-02-02T12:00:00Z")
    });

    const token = await store.getTokenByValue("apns-token-sqlite");
    assert.equal(token.id, tokenId);

    const wakeId = await store.createWakeRequest(tokenId, new Date("2026-02-02T12:01:00Z"));
    const wake = await store.getWakeRequestById(wakeId);
    assert.equal(wake.id, wakeId);

    const count = await store.incrementRateLimit(
      "token",
      "apns-token-sqlite",
      new Date("2026-02-02T12:00:00Z")
    );
    assert.equal(count, 1);
  } finally {
    await store.close();
  }
});
