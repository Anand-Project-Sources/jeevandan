require('dotenv').config();
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'jeevandan',
  waitForConnections: true,
  connectionLimit: 10,
  ssl: process.env.DB_SSL ? { rejectUnauthorized: false } : undefined, // cloud MySQL (Aiven) needs TLS
  dateStrings: true, // DATE/DATETIME come back as plain strings
});

// Runs fn inside a transaction. @app_user_id lets DB triggers attribute audit rows to the acting user.
async function withTx(userId, fn) {
  const conn = await pool.getConnection();
  try {
    await conn.beginTransaction();
    await conn.query('SET @app_user_id = ?', [userId == null ? null : userId]);
    const result = await fn(conn);
    await conn.commit();
    return result;
  } catch (e) {
    try { await conn.rollback(); } catch (_) { /* ignore */ }
    throw e;
  } finally {
    try { await conn.query('SET @app_user_id = NULL'); } catch (_) { /* ignore */ }
    conn.release();
  }
}

module.exports = { pool, withTx };
