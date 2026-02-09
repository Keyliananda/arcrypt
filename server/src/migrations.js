"use strict";

const fs = require("node:fs");
const path = require("node:path");
const sqlite3 = require("sqlite3");

const MIGRATIONS = {
  sqlite: [
    {
      id: "20260208_srv003_message_relay_v1",
      file: path.join(
        __dirname,
        "..",
        "migrations",
        "sqlite",
        "20260208_srv003_message_relay_v1.sql"
      )
    }
  ],
  mysql: [
    {
      id: "20260208_srv003_message_relay_v1",
      file: path.join(
        __dirname,
        "..",
        "migrations",
        "mysql",
        "20260208_srv003_message_relay_v1.sql"
      )
    }
  ]
};

function nowIso() {
  return new Date().toISOString();
}

function createSqliteHelpers(db) {
  function run(sql, params = []) {
    return new Promise((resolve, reject) => {
      db.run(sql, params, function onRun(err) {
        if (err) {
          reject(err);
          return;
        }
        resolve(this);
      });
    });
  }

  function get(sql, params = []) {
    return new Promise((resolve, reject) => {
      db.get(sql, params, (err, row) => {
        if (err) {
          reject(err);
          return;
        }
        resolve(row || null);
      });
    });
  }

  function exec(sql) {
    return new Promise((resolve, reject) => {
      db.exec(sql, (err) => {
        if (err) {
          reject(err);
          return;
        }
        resolve();
      });
    });
  }

  return { run, get, exec };
}

async function runSqliteMigrations(dbConfig) {
  const filename = dbConfig.filename || ":memory:";
  const db = new sqlite3.Database(filename);
  const { run, get, exec } = createSqliteHelpers(db);
  const result = { driver: "sqlite", applied: [], skipped: [] };

  try {
    await exec(
      "CREATE TABLE IF NOT EXISTS schema_migrations (id TEXT PRIMARY KEY, applied_at TEXT NOT NULL)"
    );

    for (const migration of MIGRATIONS.sqlite) {
      const existing = await get(
        "SELECT id FROM schema_migrations WHERE id = ? LIMIT 1",
        [migration.id]
      );
      if (existing) {
        result.skipped.push(migration.id);
        continue;
      }

      const sql = fs.readFileSync(migration.file, "utf8");
      await exec("BEGIN");
      try {
        await exec(sql);
        await run(
          "INSERT INTO schema_migrations (id, applied_at) VALUES (?, ?)",
          [migration.id, nowIso()]
        );
        await exec("COMMIT");
        result.applied.push(migration.id);
      } catch (error) {
        await exec("ROLLBACK");
        throw error;
      }
    }

    return result;
  } finally {
    await new Promise((resolve, reject) => {
      db.close((err) => {
        if (err) {
          reject(err);
          return;
        }
        resolve();
      });
    });
  }
}

function resolveMysql() {
  try {
    return require("mysql2/promise");
  } catch (error) {
    if (error && error.code === "MODULE_NOT_FOUND") {
      const missing = new Error(
        "mysql2 is not installed. Install it to run mysql migrations."
      );
      missing.code = "mysql2_missing";
      throw missing;
    }
    throw error;
  }
}

async function runMysqlMigrations(dbConfig) {
  const mysql = resolveMysql();
  const result = { driver: "mysql", applied: [], skipped: [] };
  const pool = mysql.createPool({
    host: dbConfig.host,
    port: dbConfig.port,
    user: dbConfig.user,
    password: dbConfig.password,
    database: dbConfig.database,
    connectionLimit: dbConfig.connectionLimit || 2,
    timezone: "Z",
    multipleStatements: true
  });

  try {
    await pool.execute(
      "CREATE TABLE IF NOT EXISTS schema_migrations (id VARCHAR(128) NOT NULL, applied_at DATETIME NOT NULL, PRIMARY KEY (id)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4"
    );

    for (const migration of MIGRATIONS.mysql) {
      const [rows] = await pool.execute(
        "SELECT id FROM schema_migrations WHERE id = ? LIMIT 1",
        [migration.id]
      );
      if (rows.length > 0) {
        result.skipped.push(migration.id);
        continue;
      }

      const sql = fs.readFileSync(migration.file, "utf8");
      const connection = await pool.getConnection();
      try {
        await connection.beginTransaction();
        await connection.query(sql);
        await connection.execute(
          "INSERT INTO schema_migrations (id, applied_at) VALUES (?, UTC_TIMESTAMP())",
          [migration.id]
        );
        await connection.commit();
        result.applied.push(migration.id);
      } catch (error) {
        await connection.rollback();
        throw error;
      } finally {
        connection.release();
      }
    }

    return result;
  } finally {
    await pool.end();
  }
}

async function runMigrations(dbConfig) {
  const driver = (dbConfig && dbConfig.driver) || "memory";

  if (driver === "sqlite") {
    return runSqliteMigrations(dbConfig);
  }

  if (driver === "mysql") {
    return runMysqlMigrations(dbConfig);
  }

  return { driver, applied: [], skipped: [] };
}

module.exports = { runMigrations };
