"use strict";

const { MemoryStore } = require("./memory");

function createStore(dbConfig) {
  if (dbConfig.driver === "mysql") {
    // Lazy require so memory mode does not need mysql2 installed.
    const { MysqlStore } = require("./mysql");
    return new MysqlStore(dbConfig);
  }

  if (dbConfig.driver === "sqlite") {
    const { SqliteStore } = require("./sqlite");
    return new SqliteStore({ filename: dbConfig.filename });
  }

  return new MemoryStore();
}

module.exports = { createStore };
