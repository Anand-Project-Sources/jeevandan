require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const { pool } = require('./db');
const { authenticate, errorHandler, wrap } = require('./util');
const { housekeeping } = require('./jobs');
const path = require('path');

if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 16) {
  console.error('Set JWT_SECRET (16+ chars) in backend/.env');
  process.exit(1);
}

const app = express();
app.use(helmet({ contentSecurityPolicy: { useDefaults: true, directives: { 'upgrade-insecure-requests': null } } }));
app.use(cors());
app.use(express.json({ limit: '100kb' }));
app.use(express.static(path.join(__dirname, '..', 'public'))); // website at http://localhost:3000

app.get('/api/health', wrap(async (req, res) => { await pool.query('SELECT 1'); res.json({ status: 'ok' }); }));

app.use('/api', require('./routes/auth'));                       // register, login, me, lookups
app.use('/api/donors',        authenticate, require('./routes/donors'));
app.use('/api/inventory',     authenticate, require('./routes/inventory'));
app.use('/api/requests',      authenticate, require('./routes/requests'));
app.use('/api/organ',         authenticate, require('./routes/organ'));
app.use('/api/transfers',     authenticate, require('./routes/transfers'));
app.use('/api/notifications', authenticate, require('./routes/notifications'));
app.use('/api/admin',         authenticate, require('./routes/admin'));

app.use((req, res) => res.status(404).json({ error: 'Not found' }));
app.use(errorHandler);

const port = Number(process.env.PORT || 3000);
app.listen(port, '0.0.0.0', async () => {
  console.log(`JEEVANDAN API listening on http://0.0.0.0:${port}`);
  await housekeeping();
  setInterval(housekeeping, 60 * 60 * 1000);
});
