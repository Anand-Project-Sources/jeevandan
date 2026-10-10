// Creates the database, tables, views, triggers and demo data.  Usage: npm run setup
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const mysql = require('mysql2/promise');

const dir = path.join(__dirname, '..', '..', 'database');
const read = (f) => fs.readFileSync(path.join(dir, f), 'utf8');

(async () => {
  const conn = await mysql.createConnection({
    host: process.env.DB_HOST || 'localhost',
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || '',
    ssl: process.env.DB_SSL ? { rejectUnauthorized: false } : undefined,
    multipleStatements: true,
  });
  try {
    console.log('Creating schema...');   await conn.query(read('schema.sql'));
    console.log('Creating views...');    await conn.query(read('views.sql'));
    console.log('Creating triggers...');
    const stmts = read('triggers.sql').replace(/^DELIMITER.*$/gm, '').split('$$').map((s) => s.trim()).filter(Boolean);
    for (const s of stmts) await conn.query(s);
    console.log('Loading demo data...'); await conn.query(read('seed.sql'));
    console.log('\nDone. Demo password for every account: Demo@1234');
  } catch (e) {
    console.error('Setup failed:', e.message);
    process.exitCode = 1;
  } finally { await conn.end(); }
})();
