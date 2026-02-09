"use strict";

require("dotenv").config();

const { createStore } = require("../src/store");
const { config } = require("../src/config");

async function main() {
  const store = createStore(config.db);
  const ackGraceSec = config.relay.ackDeleteGraceSec;

  if (typeof store.cleanupExpiredRelayData !== "function") {
    throw new Error(`cleanup is not supported for DB driver ${config.db.driver}`);
  }

  const result = await store.cleanupExpiredRelayData(new Date(), ackGraceSec);

  if (typeof store.close === "function") {
    await store.close();
  }

  process.stdout.write(
    JSON.stringify(
      {
        ok: true,
        driver: config.db.driver,
        ack_delete_grace_sec: ackGraceSec,
        ...result
      },
      null,
      2
    ) + "\n"
  );
}

main().catch((error) => {
  process.stderr.write(`Relay cleanup failed: ${error.message}\n`);
  process.exitCode = 1;
});
