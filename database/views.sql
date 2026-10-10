USE jeevandan;

-- Non-expired stock per hospital x blood group (zeros included)
CREATE VIEW v_inventory_summary AS
SELECT h.hospital_id, h.name AS hospital_name, h.city, b.bg_id, b.label AS blood_group,
       COALESCE(SUM(ib.units_available), 0) AS units_available,
       MIN(CASE WHEN ib.units_available > 0 THEN ib.expiry_date END) AS nearest_expiry
FROM hospitals h
CROSS JOIN blood_groups b
LEFT JOIN inventory_batches ib
       ON ib.hospital_id = h.hospital_id AND ib.bg_id = b.bg_id
      AND ib.status = 'AVAILABLE' AND ib.expiry_date >= CURDATE()
GROUP BY h.hospital_id, h.name, h.city, b.bg_id, b.label;

CREATE VIEW v_request_details AS
SELECT r.request_id, r.requester_id, u.full_name AS requester_name, r.hospital_id, h.name AS hospital_name,
       h.city, r.bg_id, b.label AS blood_group, r.units_needed, r.priority, r.patient_name, r.reason,
       r.status, r.remarks, r.created_at, r.updated_at, r.fulfilled_at
FROM blood_requests r
JOIN users u ON u.user_id = r.requester_id
JOIN hospitals h ON h.hospital_id = r.hospital_id
JOIN blood_groups b ON b.bg_id = r.bg_id;

CREATE VIEW v_expiring_batches AS
SELECT ib.batch_id, ib.hospital_id, h.name AS hospital_name, b.label AS blood_group,
       ib.units_available, ib.expiry_date, DATEDIFF(ib.expiry_date, CURDATE()) AS days_left
FROM inventory_batches ib
JOIN hospitals h ON h.hospital_id = ib.hospital_id
JOIN blood_groups b ON b.bg_id = ib.bg_id
WHERE ib.status = 'AVAILABLE' AND ib.units_available > 0
  AND ib.expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 7 DAY);

CREATE VIEW v_donation_stats AS
SELECT DATE_FORMAT(donated_on, '%Y-%m') AS month, COUNT(*) AS donations, SUM(units) AS units
FROM donations
GROUP BY DATE_FORMAT(donated_on, '%Y-%m');
