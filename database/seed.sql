USE jeevandan;
-- All demo accounts use password: Demo@1234

INSERT INTO roles(role_name) VALUES ('ADMIN'),('STAFF'),('DONOR'),('PATIENT');
INSERT INTO blood_groups(label) VALUES ('A+'),('A-'),('B+'),('B-'),('AB+'),('AB-'),('O+'),('O-');
INSERT INTO organ_types(organ_name) VALUES ('Kidney'),('Liver'),('Heart'),('Lungs'),('Pancreas'),('Cornea'),('Skin');

INSERT INTO hospitals(name, facility_type, license_no, city, address, phone, is_transplant_center) VALUES
 ('Narmada Care Hospital',   'HOSPITAL',   'MP-HOS-1001', 'Bhopal',   'Arera Colony, Bhopal',       '07552000001', TRUE),
 ('Sanjeevani Blood Bank',   'BLOOD_BANK', 'MP-BB-2001',  'Bhopal',   'MP Nagar, Bhopal',           '07552000002', FALSE),
 ('Vindhya Medical Centre',  'HOSPITAL',   'MP-HOS-1002', 'Indore',   'Vijay Nagar, Indore',        '07312000003', FALSE),
 ('Malwa Heart Institute',   'HOSPITAL',   'MP-HOS-1003', 'Indore',   'Palasia, Indore',            '07312000004', TRUE),
 ('Satpura General Hospital','HOSPITAL',   'MP-HOS-1004', 'Jabalpur', 'Napier Town, Jabalpur',      '07612000005', FALSE);

INSERT INTO users(role_id, full_name, email, phone, password_hash) VALUES
 (1,'Admin User',    'admin@jeevandan.test',    '9000000001','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (2,'Rakesh Verma',  'staff1@jeevandan.test',   '9000000002','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (2,'Anita Joshi',   'staff2@jeevandan.test',   '9000000003','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (2,'Imran Khan',    'staff3@jeevandan.test',   '9000000004','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (3,'Aarav Sharma',  'donor1@jeevandan.test',   '9000000005','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (3,'Priya Patel',   'donor2@jeevandan.test',   '9000000006','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (3,'Rohan Mehta',   'donor3@jeevandan.test',   '9000000007','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (3,'Sneha Iyer',    'donor4@jeevandan.test',   '9000000008','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (3,'Karan Singh',   'donor5@jeevandan.test',   '9000000009','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (3,'Meera Nair',    'donor6@jeevandan.test',   '9000000010','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (3,'Vikram Rao',    'donor7@jeevandan.test',   '9000000011','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (3,'Divya Gupta',   'donor8@jeevandan.test',   '9000000012','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (4,'Neha Kulkarni', 'patient1@jeevandan.test', '9000000013','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca'),
 (4,'Arjun Das',     'patient2@jeevandan.test', '9000000014','611c5e02d50eb057cfd3c8e5fe2cf003:3031bdefe804fa3bb7b0aee51b417398c0d4b80eebb6d7c2ce4aab9ae5787536ce3c2cc9f596bae624c70991ea50b365deb37918144e03fc3380bd0e32e8f1ca');

INSERT INTO hospital_staff(user_id, hospital_id, designation) VALUES
 (2,1,'Blood Bank Officer'),(3,2,'Chief Technologist'),(4,3,'Transfusion Officer');

-- bg ids: A+=1 A-=2 B+=3 B-=4 AB+=5 AB-=6 O+=7 O-=8
INSERT INTO donors(user_id, bg_id, date_of_birth, gender, weight_kg, city) VALUES
 (5, 8,'1995-04-12','M',72,'Bhopal'),
 (6, 7,'1992-09-03','F',58,'Bhopal'),
 (7, 1,'1990-01-25','M',80,'Indore'),
 (8, 3,'1998-07-19','F',55,'Bhopal'),
 (9, 5,'1988-11-30','M',85,'Jabalpur'),
 (10,2,'1994-02-14','F',60,'Indore'),
 (11,4,'1985-06-08','M',78,'Bhopal'),
 (12,7,'1996-12-01','F',62,'Bhopal');

-- Donation history (trigger keeps donors.last_donation_date current). Donor 8 donated 10 days ago => not eligible.
INSERT INTO donations(donor_id, hospital_id, units, donated_on, recorded_by) VALUES
 (2,2,1,DATE_SUB(CURDATE(), INTERVAL 220 DAY),3),
 (2,2,1,DATE_SUB(CURDATE(), INTERVAL 120 DAY),3),
 (3,3,1,DATE_SUB(CURDATE(), INTERVAL 95  DAY),4),
 (4,2,1,DATE_SUB(CURDATE(), INTERVAL 150 DAY),3),
 (5,5,1,DATE_SUB(CURDATE(), INTERVAL 200 DAY),4),
 (7,1,1,DATE_SUB(CURDATE(), INTERVAL 100 DAY),2),
 (8,1,1,DATE_SUB(CURDATE(), INTERVAL 10  DAY),2);

-- Stock. Hospital 1 has an expired O+ batch and a B+ batch expiring in 3 days (for the demo).
INSERT INTO inventory_batches(hospital_id, bg_id, units_total, units_available, collected_on, expiry_date) VALUES
 (1,7,10,8, DATE_SUB(CURDATE(),INTERVAL 10 DAY), DATE_ADD(CURDATE(),INTERVAL 25 DAY)),
 (1,8, 4,2, DATE_SUB(CURDATE(),INTERVAL 20 DAY), DATE_ADD(CURDATE(),INTERVAL 15 DAY)),
 (1,1, 6,5, DATE_SUB(CURDATE(),INTERVAL 15 DAY), DATE_ADD(CURDATE(),INTERVAL 20 DAY)),
 (1,3, 4,3, DATE_SUB(CURDATE(),INTERVAL 32 DAY), DATE_ADD(CURDATE(),INTERVAL 3  DAY)),
 (1,7, 2,2, DATE_SUB(CURDATE(),INTERVAL 40 DAY), DATE_SUB(CURDATE(),INTERVAL 5  DAY)),
 (2,1,12,12,DATE_SUB(CURDATE(),INTERVAL 5  DAY), DATE_ADD(CURDATE(),INTERVAL 30 DAY)),
 (2,2, 3,3, DATE_SUB(CURDATE(),INTERVAL 8  DAY), DATE_ADD(CURDATE(),INTERVAL 27 DAY)),
 (2,3,10,10,DATE_SUB(CURDATE(),INTERVAL 6  DAY), DATE_ADD(CURDATE(),INTERVAL 29 DAY)),
 (2,4, 5,5, DATE_SUB(CURDATE(),INTERVAL 9  DAY), DATE_ADD(CURDATE(),INTERVAL 26 DAY)),
 (2,5, 4,4, DATE_SUB(CURDATE(),INTERVAL 12 DAY), DATE_ADD(CURDATE(),INTERVAL 23 DAY)),
 (2,6, 2,2, DATE_SUB(CURDATE(),INTERVAL 7  DAY), DATE_ADD(CURDATE(),INTERVAL 28 DAY)),
 (2,7,15,15,DATE_SUB(CURDATE(),INTERVAL 4  DAY), DATE_ADD(CURDATE(),INTERVAL 31 DAY)),
 (2,8, 6,6, DATE_SUB(CURDATE(),INTERVAL 11 DAY), DATE_ADD(CURDATE(),INTERVAL 24 DAY)),
 (3,7, 5,5, DATE_SUB(CURDATE(),INTERVAL 9  DAY), DATE_ADD(CURDATE(),INTERVAL 26 DAY)),
 (3,1, 4,4, DATE_SUB(CURDATE(),INTERVAL 13 DAY), DATE_ADD(CURDATE(),INTERVAL 22 DAY)),
 (3,6, 3,3, DATE_SUB(CURDATE(),INTERVAL 14 DAY), DATE_ADD(CURDATE(),INTERVAL 21 DAY)),
 (4,7, 6,6, DATE_SUB(CURDATE(),INTERVAL 6  DAY), DATE_ADD(CURDATE(),INTERVAL 29 DAY)),
 (4,3, 4,4, DATE_SUB(CURDATE(),INTERVAL 8  DAY), DATE_ADD(CURDATE(),INTERVAL 27 DAY)),
 (5,1, 3,3, DATE_SUB(CURDATE(),INTERVAL 10 DAY), DATE_ADD(CURDATE(),INTERVAL 25 DAY)),
 (5,8, 2,2, DATE_SUB(CURDATE(),INTERVAL 12 DAY), DATE_ADD(CURDATE(),INTERVAL 23 DAY));

INSERT INTO organ_consents(donor_id, organ_id, status, consent_date, family_informed, witness_name) VALUES
 (1,1,'GIVEN',DATE_SUB(CURDATE(),INTERVAL 60 DAY),TRUE,'Sunita Sharma'),
 (1,6,'GIVEN',DATE_SUB(CURDATE(),INTERVAL 60 DAY),TRUE,'Sunita Sharma'),
 (2,6,'GIVEN',DATE_SUB(CURDATE(),INTERVAL 30 DAY),TRUE,'Ramesh Patel'),
 (2,2,'GIVEN',DATE_SUB(CURDATE(),INTERVAL 30 DAY),TRUE,'Ramesh Patel'),
 (3,1,'GIVEN',DATE_SUB(CURDATE(),INTERVAL 45 DAY),TRUE,'Kavita Mehta'),
 (4,6,'GIVEN',DATE_SUB(CURDATE(),INTERVAL 15 DAY),TRUE,'Lakshmi Iyer');

-- Blood requests (triggers create notifications + audit rows)
INSERT INTO blood_requests(requester_id, hospital_id, bg_id, units_needed, priority, patient_name, reason) VALUES
 (13,1,8,3,'EMERGENCY','Ramesh Kulkarni','Post-surgery haemorrhage'),
 (14,2,1,2,'NORMAL',   'Arjun Das',       'Scheduled surgery'),
 (13,1,3,1,'URGENT',   'Ramesh Kulkarni', 'Severe anaemia'),
 (14,3,7,1,'NORMAL',   'Arjun Das',       'Thalassemia transfusion');
UPDATE blood_requests SET status='APPROVED', reviewed_by=4, remarks='Verified with doctor' WHERE request_id=4;

INSERT INTO organ_requests(hospital_id, organ_id, bg_id, patient_name, patient_age, urgency, requested_by) VALUES
 (1,1,3,'Sunil Rao',45,'URGENT',2);
