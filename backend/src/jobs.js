const { pool } = require('./db');

// Marks expired batches and raises expiry alerts (deduplicated). Runs at start-up and hourly.
async function housekeeping() {
  try {
    const [exp] = await pool.query(
      `UPDATE inventory_batches SET status = 'EXPIRED' WHERE status IN ('AVAILABLE') AND expiry_date < CURDATE()`);
    await pool.query(
      `INSERT INTO notifications(user_id, type, title, message, related_id)
       SELECT hs.user_id, 'EXPIRY', 'Blood units expiring soon',
              CONCAT(ib.units_available, ' unit(s) of ', b.label, ' expire on ', ib.expiry_date, ' (batch #', ib.batch_id, ')'),
              ib.batch_id
         FROM inventory_batches ib
         JOIN blood_groups b ON b.bg_id = ib.bg_id
         JOIN hospital_staff hs ON hs.hospital_id = ib.hospital_id
        WHERE ib.status = 'AVAILABLE' AND ib.units_available > 0
          AND ib.expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 5 DAY)
          AND NOT EXISTS (SELECT 1 FROM notifications n
                           WHERE n.user_id = hs.user_id AND n.type = 'EXPIRY' AND n.related_id = ib.batch_id
                             AND n.title = 'Blood units expiring soon')`);
    await pool.query(
      `INSERT INTO notifications(user_id, type, title, message, related_id)
       SELECT hs.user_id, 'EXPIRY', 'Blood units expired',
              CONCAT(ib.units_available, ' unit(s) of ', b.label, ' expired and were removed from stock (batch #', ib.batch_id, ')'),
              ib.batch_id
         FROM inventory_batches ib
         JOIN blood_groups b ON b.bg_id = ib.bg_id
         JOIN hospital_staff hs ON hs.hospital_id = ib.hospital_id
        WHERE ib.status = 'EXPIRED' AND ib.units_available > 0
          AND NOT EXISTS (SELECT 1 FROM notifications n
                           WHERE n.user_id = hs.user_id AND n.type = 'EXPIRY' AND n.related_id = ib.batch_id
                             AND n.title = 'Blood units expired')`);
    if (exp.affectedRows) console.log(`[jobs] marked ${exp.affectedRows} batch(es) expired`);
  } catch (e) { console.error('[jobs] housekeeping failed:', e.message); }
}
module.exports = { housekeeping };
