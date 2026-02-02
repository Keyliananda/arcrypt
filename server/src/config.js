"use strict";

function toInt(value, fallback) {
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

const config = {
  port: toInt(process.env.PORT, 3000),
  maxBodyBytes: toInt(process.env.MAX_BODY_BYTES, 8 * 1024),
  hmacSecret: process.env.HMAC_SECRET || "",
  hmacMaxSkewSec: toInt(process.env.HMAC_MAX_SKEW_SEC, 300),
  rateLimit: {
    windowSec: toInt(process.env.RATE_LIMIT_WINDOW_SEC, 3600),
    perToken: toInt(process.env.RATE_LIMIT_TOKEN_PER_WINDOW, 30),
    perIp: toInt(process.env.RATE_LIMIT_IP_PER_WINDOW, 120)
  },
  db: {
    driver: process.env.DB_DRIVER || "memory",
    filename: process.env.DB_FILENAME || "./data.sqlite",
    host: process.env.DB_HOST || "localhost",
    port: toInt(process.env.DB_PORT, 3306),
    user: process.env.DB_USER || "",
    password: process.env.DB_PASSWORD || "",
    database: process.env.DB_NAME || ""
  }
};

module.exports = { config };
