"use strict";

require("dotenv").config();

const { createStore } = require("../src/store");
const { config } = require("../src/config");

async function main() {
  const store = createStore(config.db);

  if (typeof store.cleanupExpiredDeviceTokens !== "function") {
    throw new Error(`wake token cleanup is not supported for DB driver ${config.db.driver}`);
  }

  const result = await store.cleanupExpiredDeviceTokens(new Date());

  if (typeof store.close === "function") {
    await store.close();
  }

  process.stdout.write(
    JSON.stringify(
      {
        ok: true,
        driver: config.db.driver,
        ...result
      },
      null,
      2
    ) + "\n"
  );
}

main().catch((error) => {
  process.stderr.write(`Wake token cleanup failed: ${error.message}\n`);
  process.exitCode = 1;
});
