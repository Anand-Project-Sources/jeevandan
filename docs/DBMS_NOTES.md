# DBMS notes

## Relational schema (PK underlined by convention `*`, FK → target)
```
roles(role_id*, role_name UK)
blood_groups(bg_id*, label UK)
organ_types(organ_id*, organ_name UK)
hospitals(hospital_id*, name, facility_type, license_no UK, city, address, phone, is_transplant_center)
users(user_id*, role_id→roles, full_name, email UK, phone, password_hash, is_active)
hospital_staff(user_id*→users, hospital_id→hospitals, designation)
donors(donor_id*, user_id UK→users, bg_id→blood_groups, date_of_birth, gender, weight_kg, city, last_donation_date, is_available)
organ_consents(consent_id*, donor_id→donors, organ_id→organ_types, status, consent_date, family_informed, witness_name,  UK(donor_id, organ_id))
donations(donation_id*, donor_id→donors, hospital_id→hospitals, units, donated_on, recorded_by→users)
transfers(transfer_id*, from_hospital_id→hospitals, to_hospital_id→hospitals, bg_id→blood_groups, units, status, requested_by→users, created_at, completed_at)
inventory_batches(batch_id*, hospital_id→hospitals, bg_id→blood_groups, units_total, units_available, collected_on, expiry_date,
                  source_donation_id UK→donations, source_transfer_id→transfers, status)
blood_requests(request_id*, requester_id→users, hospital_id→hospitals, bg_id→blood_groups, units_needed, priority, patient_name, reason,
               status, reviewed_by→users, remarks, fulfilled_by→users, fulfilled_at, created_at, updated_at)
request_allocations(allocation_id*, request_id→blood_requests, batch_id→inventory_batches, units_allocated, UK(request_id, batch_id))
donor_matches(match_id*, request_id→blood_requests, donor_id→donors, status, notified_at, responded_at, UK(request_id, donor_id))
organ_requests(organ_request_id*, hospital_id→hospitals, organ_id→organ_types, bg_id→blood_groups, patient_name, patient_age, urgency, status,
               requested_by→users, verified_by→users, verification_notes)
notifications(notification_id*, user_id→users, type, title, message, related_id, is_read, created_at)
audit_logs(log_id*, user_id→users (SET NULL), action, entity, entity_id, details, created_at)
```

## Keys
* **Primary keys:** surrogate integer keys everywhere (`hospital_staff.user_id` is both PK and FK – a 1:1 subtype of users).
* **Candidate keys:** `users.email`, `hospitals.license_no`, `blood_groups.label`, `donors.user_id`; `roles.role_name`.
* **Composite candidate keys:** `(donor_id, organ_id)` in organ_consents, `(request_id, batch_id)` in request_allocations, `(request_id, donor_id)` in donor_matches. They stop duplicate pledges, duplicate allocation of a batch to one request, and duplicate invitations.
* **Foreign keys:** every relationship above; `ON DELETE CASCADE` only for owned child rows (donor profile, consents, notifications); `SET NULL` for audit logs; everything else `RESTRICT` (referential integrity).

## Normalisation
**1NF** – every column is atomic: no repeating groups. A request needing several batches is modelled as many rows in `request_allocations`, not a list column; staff, donors and consents are separate rows, not comma lists.

**2NF** – no partial dependency on part of a composite key. The only composite keys are in association tables (`organ_consents`, `request_allocations`, `donor_matches`); their non-key attributes (`consent_date`, `units_allocated`, `status` …) depend on the whole pair. Everything else has a single-column PK so 2NF holds trivially.

**3NF** – no transitive dependency on non-key attributes:
* hospital name/city live only in `hospitals` (requests store `hospital_id`, not the name);
* blood-group text lives only in `blood_groups`;
* role names only in `roles`; organ names only in `organ_types`;
* donor's blood group is stored once in `donors` – `donations` deliberately has **no** `bg_id` (it would be derivable via donor_id);
* contact/user data lives in `users`, not copied into donors/staff;
* totals (stock per group, request counts) are computed with aggregates/views, never stored.

*Deliberate, documented denormalisation:* `inventory_batches.bg_id` – a batch created by a transfer has no donation to inherit the group from, and stock must stay queryable without joins through donations. It is validated by the FK to `blood_groups`.

## Constraints used
* `CHECK`: units 1–2 per donation, 1–20 per request, `units_available BETWEEN 0 AND units_total`, `expiry_date > collected_on`, weight 30–250, `from_hospital_id <> to_hospital_id`, e-mail shape, blood-group label domain.
* `UNIQUE`, `NOT NULL`, `ENUM` for status/priority domains, indexes for search (`idx_ib_lookup`, `idx_br_queue`, `idx_donor_search`).

## Triggers (database/triggers.sql)
| Trigger | Purpose |
|---|---|
| `trg_batch_bu` | BEFORE UPDATE: block negative stock, auto-set DEPLETED/AVAILABLE |
| `trg_batch_au` | AFTER UPDATE: low-stock notification (<5 usable units) |
| `trg_alloc_bi` | BEFORE INSERT: refuse allocation of expired/missing batch |
| `trg_req_bu` | BEFORE UPDATE: only legal status transitions (PENDING→APPROVED/REJECTED, APPROVED→FULFILLED/REJECTED); terminal states are final → prevents duplicate processing |
| `trg_req_ai` / `trg_req_au` | request created/status-changed: notifications + audit log |
| `trg_donation_ai` | updates donor's last_donation_date, audit |
| `trg_transfer_ai` / `trg_transfer_au` | notify both hospitals, audit |
| `trg_organ_au` | audit + notify on verification status change |

## Views (database/views.sql)
`v_inventory_summary` (hospital × group, unexpired units, LEFT JOIN + GROUP BY), `v_request_details` (4-table join), `v_expiring_batches` (≤7 days), `v_donation_stats` (monthly aggregate).

## Transactions (backend/src/routes)
Every multi-step write runs in `withTx()` (`START TRANSACTION … COMMIT`, automatic `ROLLBACK` on any error):
* **Fulfil request:** `SELECT … FOR UPDATE` on the request and on the candidate batches (earliest expiry first, expired excluded) → insert allocations → guarded `UPDATE … WHERE units_available >= ?` → set FULFILLED. If stock is short, nothing changes.
* **Transfer completion:** locks transfer + source batches, deducts, creates destination batches with the same expiry, marks COMPLETED – atomically.
* **Record donation:** locks donor row, checks 90-day rule, inserts donation + batch + notification.
* **Registration:** user + donor profile + audit row together.
`@app_user_id` is set per transaction so triggers attribute audit rows to the acting user.

## Query demonstrations
See `database/queries.sql`: joins (INNER/LEFT), GROUP BY/HAVING, aggregates, IN-subquery, correlated subquery, views, explicit `START TRANSACTION … ROLLBACK / COMMIT`, and commented constraint/trigger violations to try.
