const router = require('express').Router();
const { pool } = require('../db');
const { wrap } = require('../util');

router.get('/', wrap(async (req, res) => {
  const [items] = await pool.query(
    'SELECT notification_id, type, title, message, related_id, is_read, created_at FROM notifications WHERE user_id = ? ORDER BY created_at DESC, notification_id DESC LIMIT 100',
    [req.user.id]);
  res.json(items);
}));

router.get('/unread-count', wrap(async (req, res) => {
  const [[r]] = await pool.query('SELECT COUNT(*) AS c FROM notifications WHERE user_id = ? AND is_read = FALSE', [req.user.id]);
  res.json({ count: Number(r.c) });
}));

router.post('/read-all', wrap(async (req, res) => {
  await pool.query('UPDATE notifications SET is_read = TRUE WHERE user_id = ?', [req.user.id]);
  res.json({ ok: true });
}));

router.post('/:id/read', wrap(async (req, res) => {
  await pool.query('UPDATE notifications SET is_read = TRUE WHERE notification_id = ? AND user_id = ?', [req.params.id, req.user.id]);
  res.json({ ok: true });
}));

module.exports = router;
