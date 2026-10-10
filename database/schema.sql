-- JEEVANDAN schema (MySQL 8.0.16+). Re-running drops and recreates the database.
DROP DATABASE IF EXISTS jeevandan;
CREATE DATABASE jeevandan CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE jeevandan;

CREATE TABLE roles (
  role_id   TINYINT AUTO_INCREMENT PRIMARY KEY,
  role_name VARCHAR(20) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE blood_groups (
  bg_id TINYINT AUTO_INCREMENT PRIMARY KEY,
  label VARCHAR(3) NOT NULL UNIQUE,
  CONSTRAINT chk_bg_label CHECK (label IN ('A+','A-','B+','B-','AB+','AB-','O+','O-'))
) ENGINE=InnoDB;

CREATE TABLE organ_types (
  organ_id   TINYINT AUTO_INCREMENT PRIMARY KEY,
  organ_name VARCHAR(30) NOT NULL UNIQUE
) ENGINE=InnoDB;

CREATE TABLE hospitals (
  hospital_id          INT AUTO_INCREMENT PRIMARY KEY,
  name                 VARCHAR(120) NOT NULL,
  facility_type        ENUM('HOSPITAL','BLOOD_BANK') NOT NULL DEFAULT 'HOSPITAL',
  license_no           VARCHAR(40) NOT NULL UNIQUE,          -- candidate key
  city                 VARCHAR(60) NOT NULL,
  address              VARCHAR(200),
  phone                VARCHAR(15) NOT NULL,
  is_transplant_center BOOLEAN NOT NULL DEFAULT FALSE,
  created_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

CREATE TABLE users (
  user_id       INT AUTO_INCREMENT PRIMARY KEY,
  role_id       TINYINT NOT NULL,
  full_name     VARCHAR(100) NOT NULL,
  email         VARCHAR(120) NOT NULL UNIQUE,                 -- candidate key
  phone         VARCHAR(15) NOT NULL,
  password_hash VARCHAR(200) NOT NULL,
  is_active     BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_users_role FOREIGN KEY (role_id) REFERENCES roles(role_id),
  CONSTRAINT chk_users_email CHECK (email LIKE '%_@_%.__%')
) ENGINE=InnoDB;

CREATE TABLE hospital_staff (
  user_id     INT PRIMARY KEY,                                -- one hospital per staff user
  hospital_id INT NOT NULL,
  designation VARCHAR(60),
  CONSTRAINT fk_hs_user FOREIGN KEY (user_id) REFERENCES users(user_id),
  CONSTRAINT fk_hs_hosp FOREIGN KEY (hospital_id) REFERENCES hospitals(hospital_id)
) ENGINE=InnoDB;

CREATE TABLE donors (
  donor_id           INT AUTO_INCREMENT PRIMARY KEY,
  user_id            INT NOT NULL UNIQUE,
  bg_id              TINYINT NOT NULL,
  date_of_birth      DATE NOT NULL,
  gender             ENUM('M','F','O') NOT NULL,
  weight_kg          DECIMAL(5,2) NOT NULL,
  city               VARCHAR(60) NOT NULL,
  last_donation_date DATE NULL,
  is_available       BOOLEAN NOT NULL DEFAULT TRUE,
  CONSTRAINT fk_donor_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  CONSTRAINT fk_donor_bg   FOREIGN KEY (bg_id)   REFERENCES blood_groups(bg_id),
  CONSTRAINT chk_donor_wt  CHECK (weight_kg BETWEEN 30 AND 250),
  INDEX idx_donor_search (bg_id, city, is_available)
) ENGINE=InnoDB;

CREATE TABLE organ_consents (
  consent_id      INT AUTO_INCREMENT PRIMARY KEY,
  donor_id        INT NOT NULL,
  organ_id        TINYINT NOT NULL,
  status          ENUM('GIVEN','WITHDRAWN') NOT NULL DEFAULT 'GIVEN',
  consent_date    DATE NOT NULL,
  family_informed BOOLEAN NOT NULL DEFAULT FALSE,
  witness_name    VARCHAR(100),
  UNIQUE KEY uq_consent (donor_id, organ_id),                 -- composite candidate key
  CONSTRAINT fk_oc_donor FOREIGN KEY (donor_id) REFERENCES donors(donor_id) ON DELETE CASCADE,
  CONSTRAINT fk_oc_organ FOREIGN KEY (organ_id) REFERENCES organ_types(organ_id)
) ENGINE=InnoDB;

CREATE TABLE donations (
  donation_id INT AUTO_INCREMENT PRIMARY KEY,
  donor_id    INT NOT NULL,
  hospital_id INT NOT NULL,
  units       TINYINT NOT NULL,
  donated_on  DATE NOT NULL,
  recorded_by INT NOT NULL,
  CONSTRAINT fk_don_donor FOREIGN KEY (donor_id)    REFERENCES donors(donor_id),
  CONSTRAINT fk_don_hosp  FOREIGN KEY (hospital_id) REFERENCES hospitals(hospital_id),
  CONSTRAINT fk_don_user  FOREIGN KEY (recorded_by) REFERENCES users(user_id),
  CONSTRAINT chk_don_units CHECK (units BETWEEN 1 AND 2),
  INDEX idx_don_date (donated_on)
) ENGINE=InnoDB;

CREATE TABLE transfers (
  transfer_id      INT AUTO_INCREMENT PRIMARY KEY,
  from_hospital_id INT NOT NULL,
  to_hospital_id   INT NOT NULL,
  bg_id            TINYINT NOT NULL,
  units            SMALLINT NOT NULL,
  status           ENUM('PENDING','COMPLETED','CANCELLED') NOT NULL DEFAULT 'PENDING',
  requested_by     INT NOT NULL,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  completed_at     DATETIME NULL,
  CONSTRAINT fk_tr_from FOREIGN KEY (from_hospital_id) REFERENCES hospitals(hospital_id),
  CONSTRAINT fk_tr_to   FOREIGN KEY (to_hospital_id)   REFERENCES hospitals(hospital_id),
  CONSTRAINT fk_tr_bg   FOREIGN KEY (bg_id)            REFERENCES blood_groups(bg_id),
  CONSTRAINT fk_tr_user FOREIGN KEY (requested_by)     REFERENCES users(user_id),
  CONSTRAINT chk_tr_units CHECK (units BETWEEN 1 AND 50),
  CONSTRAINT chk_tr_diff  CHECK (from_hospital_id <> to_hospital_id)
) ENGINE=InnoDB;

CREATE TABLE inventory_batches (
  batch_id           INT AUTO_INCREMENT PRIMARY KEY,
  hospital_id        INT NOT NULL,
  bg_id              TINYINT NOT NULL,
  units_total        SMALLINT NOT NULL,
  units_available    SMALLINT NOT NULL,
  collected_on       DATE NOT NULL,
  expiry_date        DATE NOT NULL,
  source_donation_id INT NULL UNIQUE,
  source_transfer_id INT NULL,
  status             ENUM('AVAILABLE','DEPLETED','EXPIRED') NOT NULL DEFAULT 'AVAILABLE',
  CONSTRAINT fk_ib_hosp FOREIGN KEY (hospital_id)        REFERENCES hospitals(hospital_id),
  CONSTRAINT fk_ib_bg   FOREIGN KEY (bg_id)              REFERENCES blood_groups(bg_id),
  CONSTRAINT fk_ib_don  FOREIGN KEY (source_donation_id) REFERENCES donations(donation_id),
  CONSTRAINT fk_ib_tr   FOREIGN KEY (source_transfer_id) REFERENCES transfers(transfer_id),
  CONSTRAINT chk_ib_total  CHECK (units_total > 0),
  CONSTRAINT chk_ib_avail  CHECK (units_available >= 0 AND units_available <= units_total),
  CONSTRAINT chk_ib_expiry CHECK (expiry_date > collected_on),
  INDEX idx_ib_lookup (hospital_id, bg_id, status, expiry_date)
) ENGINE=InnoDB;

CREATE TABLE blood_requests (
  request_id   INT AUTO_INCREMENT PRIMARY KEY,
  requester_id INT NOT NULL,
  hospital_id  INT NOT NULL,
  bg_id        TINYINT NOT NULL,
  units_needed TINYINT NOT NULL,
  priority     ENUM('NORMAL','URGENT','EMERGENCY') NOT NULL DEFAULT 'NORMAL',
  patient_name VARCHAR(100) NOT NULL,
  reason       VARCHAR(255),
  status       ENUM('PENDING','APPROVED','FULFILLED','REJECTED') NOT NULL DEFAULT 'PENDING',
  reviewed_by  INT NULL,
  remarks      VARCHAR(255),
  fulfilled_by INT NULL,
  fulfilled_at DATETIME NULL,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_br_req  FOREIGN KEY (requester_id) REFERENCES users(user_id),
  CONSTRAINT fk_br_hosp FOREIGN KEY (hospital_id)  REFERENCES hospitals(hospital_id),
  CONSTRAINT fk_br_bg   FOREIGN KEY (bg_id)        REFERENCES blood_groups(bg_id),
  CONSTRAINT fk_br_rev  FOREIGN KEY (reviewed_by)  REFERENCES users(user_id),
  CONSTRAINT fk_br_ful  FOREIGN KEY (fulfilled_by) REFERENCES users(user_id),
  CONSTRAINT chk_br_units CHECK (units_needed BETWEEN 1 AND 20),
  INDEX idx_br_queue (status, priority, created_at),
  INDEX idx_br_hosp (hospital_id, status)
) ENGINE=InnoDB;

CREATE TABLE request_allocations (        -- fulfilment: which batch supplied how many units
  allocation_id   INT AUTO_INCREMENT PRIMARY KEY,
  request_id      INT NOT NULL,
  batch_id        INT NOT NULL,
  units_allocated SMALLINT NOT NULL,
  allocated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_alloc (request_id, batch_id),
  CONSTRAINT fk_ra_req   FOREIGN KEY (request_id) REFERENCES blood_requests(request_id),
  CONSTRAINT fk_ra_batch FOREIGN KEY (batch_id)   REFERENCES inventory_batches(batch_id),
  CONSTRAINT chk_ra_units CHECK (units_allocated > 0)
) ENGINE=InnoDB;

CREATE TABLE donor_matches (              -- donors invited for a request
  match_id     INT AUTO_INCREMENT PRIMARY KEY,
  request_id   INT NOT NULL,
  donor_id     INT NOT NULL,
  status       ENUM('NOTIFIED','ACCEPTED','DECLINED') NOT NULL DEFAULT 'NOTIFIED',
  notified_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  responded_at DATETIME NULL,
  UNIQUE KEY uq_match (request_id, donor_id),
  CONSTRAINT fk_dm_req   FOREIGN KEY (request_id) REFERENCES blood_requests(request_id),
  CONSTRAINT fk_dm_donor FOREIGN KEY (donor_id)   REFERENCES donors(donor_id)
) ENGINE=InnoDB;

CREATE TABLE organ_requests (
  organ_request_id   INT AUTO_INCREMENT PRIMARY KEY,
  hospital_id        INT NOT NULL,
  organ_id           TINYINT NOT NULL,
  bg_id              TINYINT NOT NULL,
  patient_name       VARCHAR(100) NOT NULL,
  patient_age        TINYINT UNSIGNED NOT NULL,
  urgency            ENUM('NORMAL','URGENT','CRITICAL') NOT NULL DEFAULT 'NORMAL',
  status             ENUM('PENDING','UNDER_REVIEW','VERIFIED','REJECTED','CLOSED') NOT NULL DEFAULT 'PENDING',
  requested_by       INT NOT NULL,
  verified_by        INT NULL,
  verification_notes VARCHAR(500),
  created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_or_hosp  FOREIGN KEY (hospital_id)  REFERENCES hospitals(hospital_id),
  CONSTRAINT fk_or_organ FOREIGN KEY (organ_id)     REFERENCES organ_types(organ_id),
  CONSTRAINT fk_or_bg    FOREIGN KEY (bg_id)        REFERENCES blood_groups(bg_id),
  CONSTRAINT fk_or_req   FOREIGN KEY (requested_by) REFERENCES users(user_id),
  CONSTRAINT fk_or_ver   FOREIGN KEY (verified_by)  REFERENCES users(user_id),
  CONSTRAINT chk_or_age  CHECK (patient_age BETWEEN 0 AND 120)
) ENGINE=InnoDB;

CREATE TABLE notifications (
  notification_id INT AUTO_INCREMENT PRIMARY KEY,
  user_id         INT NOT NULL,
  type            ENUM('REQUEST','LOW_STOCK','EXPIRY','TRANSFER','DONOR_MATCH','ORGAN','SYSTEM') NOT NULL,
  title           VARCHAR(120) NOT NULL,
  message         VARCHAR(300) NOT NULL,
  related_id      INT NULL,
  is_read         BOOLEAN NOT NULL DEFAULT FALSE,
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_n_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
  INDEX idx_n_user (user_id, is_read, created_at)
) ENGINE=InnoDB;

CREATE TABLE audit_logs (
  log_id     BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id    INT NULL,
  action     VARCHAR(40) NOT NULL,
  entity     VARCHAR(40) NOT NULL,
  entity_id  INT NULL,
  details    VARCHAR(500),
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_al_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE SET NULL,
  INDEX idx_al_time (created_at)
) ENGINE=InnoDB;
