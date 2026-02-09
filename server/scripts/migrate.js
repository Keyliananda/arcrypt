"use strict";

require("dotenv").config();

const { config } = require("../src/config");
const { runMigrations } = require("../src/migrations");

async function main() {
  const result = await runMigrations(config.db);
  process.stdout.write(
    JSON.stringify(
      {
        ok: true,
        driver: result.driver,
        applied: result.applied,
        skipped: result.skipped
      },
      null,
      2
    ) + "\n"
  );
}

main().catch((error) => {
  process.stderr.write(`Migration failed: ${error.message}\n`);
  process.exitCode = 1;
});
