USE jeevandan;
DELIMITER $$

-- 1. Inventory can never go negative; keep batch status in sync with stock
CREATE TRIGGER trg_batch_bu BEFORE UPDATE ON inventory_batches FOR EACH ROW
BEGIN
  IF NEW.units_available < 0 THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Inventory cannot go negative';
  END IF;
  IF NEW.status <> 'EXPIRED' THEN
    IF NEW.units_available = 0 THEN
      SET NEW.status = 'DEPLETED';
    ELSE
      SET NEW.status = 'AVAILABLE';
    END IF;
  END IF;
END$$

-- 2. Low-stock alert (< 5 usable units of a group at a hospital)
CREATE TRIGGER trg_batch_au AFTER UPDATE ON inventory_batches FOR EACH ROW
BEGIN
  DECLARE v_total INT DEFAULT 0;
  DECLARE v_label VARCHAR(3);
  IF NEW.units_available < OLD.units_available THEN
    SELECT COALESCE(SUM(units_available), 0) INTO v_total FROM inventory_batches
     WHERE hospital_id = NEW.hospital_id AND bg_id = NEW.bg_id
       AND status = 'AVAILABLE' AND expiry_date >= CURDATE();
    IF v_total < 5 THEN
      SELECT label INTO v_label FROM blood_groups WHERE bg_id = NEW.bg_id;
      INSERT INTO notifications(user_id, type, title, message, related_id)
      SELECT hs.user_id, 'LOW_STOCK', 'Low stock alert',
             CONCAT('Only ', v_total, ' unit(s) of ', v_label, ' left'), NEW.hospital_id
        FROM hospital_staff hs
       WHERE hs.hospital_id = NEW.hospital_id
         AND NOT EXISTS (SELECT 1 FROM notifications n
                          WHERE n.user_id = hs.user_id AND n.type = 'LOW_STOCK' AND n.is_read = FALSE
                            AND n.related_id = NEW.hospital_id AND n.message LIKE CONCAT('% ', v_label, ' left'));
    END IF;
  END IF;
END$$

-- 3. Expired or missing stock can never be allocated
CREATE TRIGGER trg_alloc_bi BEFORE INSERT ON request_allocations FOR EACH ROW
BEGIN
  DECLARE v_exp DATE;
  SELECT expiry_date INTO v_exp FROM inventory_batches WHERE batch_id = NEW.batch_id;
  IF v_exp IS NULL OR v_exp < CURDATE() THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Cannot allocate expired or missing stock';
  END IF;
END$$

-- 4. Blood request lifecycle: only legal transitions, terminal states are final
CREATE TRIGGER trg_req_bu BEFORE UPDATE ON blood_requests FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    IF NOT ((OLD.status = 'PENDING'  AND NEW.status IN ('APPROVED','REJECTED'))
         OR (OLD.status = 'APPROVED' AND NEW.status IN ('FULFILLED','REJECTED'))) THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Invalid request status transition';
    END IF;
  END IF;
END$$

CREATE TRIGGER trg_req_ai AFTER INSERT ON blood_requests FOR EACH ROW
BEGIN
  INSERT INTO notifications(user_id, type, title, message, related_id)
  SELECT hs.user_id, 'REQUEST',
         IF(NEW.priority = 'EMERGENCY', 'EMERGENCY blood request', 'New blood request'),
         CONCAT(NEW.units_needed, ' unit(s) needed for ', NEW.patient_name, ' (', NEW.priority, ')'),
         NEW.request_id
    FROM hospital_staff hs WHERE hs.hospital_id = NEW.hospital_id;
  INSERT INTO audit_logs(user_id, action, entity, entity_id, details)
  VALUES (NEW.requester_id, 'REQUEST_CREATED', 'blood_request', NEW.request_id,
          CONCAT('priority=', NEW.priority, ', units=', NEW.units_needed));
END$$

CREATE TRIGGER trg_req_au AFTER UPDATE ON blood_requests FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO audit_logs(user_id, action, entity, entity_id, details)
    VALUES (COALESCE(@app_user_id, NEW.reviewed_by), CONCAT('REQUEST_', NEW.status), 'blood_request',
            NEW.request_id, CONCAT(OLD.status, ' -> ', NEW.status));
    INSERT INTO notifications(user_id, type, title, message, related_id)
    VALUES (NEW.requester_id, 'REQUEST', CONCAT('Request #', NEW.request_id, ' ', LOWER(NEW.status)),
            CONCAT('Blood request for ', NEW.patient_name, ' is now ', NEW.status, '.'), NEW.request_id);
  END IF;
END$$

-- 5. Donation keeps donor's last_donation_date current and is audited
CREATE TRIGGER trg_donation_ai AFTER INSERT ON donations FOR EACH ROW
BEGIN
  UPDATE donors
     SET last_donation_date = CASE WHEN last_donation_date IS NULL OR last_donation_date < NEW.donated_on
                                   THEN NEW.donated_on ELSE last_donation_date END
   WHERE donor_id = NEW.donor_id;
  INSERT INTO audit_logs(user_id, action, entity, entity_id, details)
  VALUES (COALESCE(@app_user_id, NEW.recorded_by), 'DONATION_RECORDED', 'donation', NEW.donation_id,
          CONCAT('donor=', NEW.donor_id, ', units=', NEW.units));
END$$

-- 6. Transfers: notify both sides, audit status changes
CREATE TRIGGER trg_transfer_ai AFTER INSERT ON transfers FOR EACH ROW
BEGIN
  DECLARE v_label VARCHAR(3);
  SELECT label INTO v_label FROM blood_groups WHERE bg_id = NEW.bg_id;
  INSERT INTO notifications(user_id, type, title, message, related_id)
  SELECT hs.user_id, 'TRANSFER', 'Transfer requested',
         CONCAT(NEW.units, ' unit(s) of ', v_label, ' requested from your stock'), NEW.transfer_id
    FROM hospital_staff hs WHERE hs.hospital_id = NEW.from_hospital_id;
  INSERT INTO audit_logs(user_id, action, entity, entity_id, details)
  VALUES (NEW.requested_by, 'TRANSFER_REQUESTED', 'transfer', NEW.transfer_id,
          CONCAT(v_label, 'x', NEW.units, ' from hospital ', NEW.from_hospital_id, ' to ', NEW.to_hospital_id));
END$$

CREATE TRIGGER trg_transfer_au AFTER UPDATE ON transfers FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO notifications(user_id, type, title, message, related_id)
    SELECT hs.user_id, 'TRANSFER', CONCAT('Transfer ', LOWER(NEW.status)),
           CONCAT('Transfer #', NEW.transfer_id, ' is now ', NEW.status), NEW.transfer_id
      FROM hospital_staff hs WHERE hs.hospital_id = NEW.to_hospital_id;
    INSERT INTO audit_logs(user_id, action, entity, entity_id, details)
    VALUES (@app_user_id, CONCAT('TRANSFER_', NEW.status), 'transfer', NEW.transfer_id,
            CONCAT(OLD.status, ' -> ', NEW.status));
  END IF;
END$$

-- 7. Organ request verification is audited
CREATE TRIGGER trg_organ_au AFTER UPDATE ON organ_requests FOR EACH ROW
BEGIN
  IF NEW.status <> OLD.status THEN
    INSERT INTO audit_logs(user_id, action, entity, entity_id, details)
    VALUES (COALESCE(@app_user_id, NEW.verified_by), CONCAT('ORGAN_REQUEST_', NEW.status), 'organ_request',
            NEW.organ_request_id, CONCAT(OLD.status, ' -> ', NEW.status));
    INSERT INTO notifications(user_id, type, title, message, related_id)
    VALUES (NEW.requested_by, 'ORGAN', CONCAT('Organ request #', NEW.organ_request_id, ' ', LOWER(NEW.status)),
            CONCAT('Eligibility review status changed to ', NEW.status), NEW.organ_request_id);
  END IF;
END$$

DELIMITER ;
