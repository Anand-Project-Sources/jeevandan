USE jeevandan;
-- ===== JOINS =====
-- Open requests with hospital, group and requester (emergencies first)
SELECT r.request_id, r.priority, b.label, h.name AS hospital, u.full_name AS requester, r.status
FROM blood_requests r
JOIN blood_groups b ON b.bg_id = r.bg_id
JOIN hospitals h ON h.hospital_id = r.hospital_id
JOIN users u ON u.user_id = r.requester_id
WHERE r.status IN ('PENDING','APPROVED')
ORDER BY FIELD(r.priority,'EMERGENCY','URGENT','NORMAL'), r.created_at;

-- LEFT JOIN: hospitals with no usable O- stock
SELECT h.name FROM hospitals h
LEFT JOIN inventory_batches ib ON ib.hospital_id = h.hospital_id AND ib.bg_id = 8
     AND ib.units_available > 0 AND ib.expiry_date >= CURDATE()
WHERE ib.batch_id IS NULL;

-- ===== AGGREGATE + GROUP BY + HAVING =====
SELECT b.label, SUM(ib.units_available) AS total_units
FROM inventory_batches ib JOIN blood_groups b ON b.bg_id = ib.bg_id
WHERE ib.status = 'AVAILABLE' AND ib.expiry_date >= CURDATE()
GROUP BY b.label HAVING total_units < 15 ORDER BY total_units;

SELECT h.name, DATE_FORMAT(d.donated_on,'%Y-%m') AS month, COUNT(*) AS donations, SUM(d.units) AS units
FROM donations d JOIN hospitals h ON h.hospital_id = d.hospital_id
GROUP BY h.name, month ORDER BY month DESC, units DESC;

-- ===== SUBQUERIES =====
-- Donors eligible to donate again (never donated, or last donation >= 90 days ago)
SELECT u.full_name, d.last_donation_date
FROM donors d JOIN users u ON u.user_id = d.user_id
WHERE d.user_id IN (SELECT user_id FROM donors
                    WHERE last_donation_date IS NULL OR last_donation_date <= DATE_SUB(CURDATE(), INTERVAL 90 DAY));

-- Correlated subquery: pending requests that exact-group local stock cannot satisfy
SELECT r.request_id, r.units_needed,
       (SELECT COALESCE(SUM(ib.units_available), 0) FROM inventory_batches ib
         WHERE ib.hospital_id = r.hospital_id AND ib.bg_id = r.bg_id
           AND ib.status = 'AVAILABLE' AND ib.expiry_date >= CURDATE()) AS exact_group_stock
FROM blood_requests r WHERE r.status = 'PENDING'
HAVING exact_group_stock < r.units_needed;

-- ===== VIEWS =====
SELECT * FROM v_inventory_summary WHERE hospital_id = 1;
SELECT * FROM v_expiring_batches;
SELECT * FROM v_donation_stats;

-- ===== TRANSACTION DEMO: ROLLBACK then COMMIT =====
START TRANSACTION;
  UPDATE inventory_batches SET units_available = units_available - 1 WHERE batch_id = 1;
  SELECT batch_id, units_available FROM inventory_batches WHERE batch_id = 1;   -- 7
ROLLBACK;
SELECT batch_id, units_available FROM inventory_batches WHERE batch_id = 1;     -- back to 8

START TRANSACTION;
  UPDATE inventory_batches SET units_available = units_available - 1 WHERE batch_id = 1;
COMMIT;
SELECT batch_id, units_available FROM inventory_batches WHERE batch_id = 1;     -- 7 (persisted)

-- ===== CONSTRAINT / TRIGGER DEMOS (run one at a time; each must FAIL) =====
-- UPDATE inventory_batches SET units_available = -1 WHERE batch_id = 1;                       -- negative stock blocked
-- INSERT INTO request_allocations(request_id,batch_id,units_allocated) VALUES (2,5,1);        -- batch 5 expired: blocked
-- UPDATE blood_requests SET status='FULFILLED' WHERE request_id = 1;                          -- PENDING -> FULFILLED illegal
-- DELETE FROM hospitals WHERE hospital_id = 1;                                                -- FK violation
