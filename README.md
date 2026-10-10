# JEEVANDAN – Blood & Organ Donation Management System

Flutter app → Node.js/Express REST API → MySQL. The app never touches the database; credentials live only in `backend/.env`.

```
jeevandan/
├── database/   schema.sql  views.sql  triggers.sql  seed.sql  queries.sql
├── backend/    Express API (npm run setup builds the DB, npm start runs the API)
├── flutter_app/ lib/ + pubspec.yaml  (copy into a fresh Flutter project, see step 3)
└── docs/       ER_DIAGRAM.md  DBMS_NOTES.md
```

## Requirements
MySQL 8.0.16+ (CHECK constraints), Node.js 18+, Flutter 3.16+ (Dart 3), Android Studio with an emulator or a phone.

## 1. Database + backend
```bash
cd backend
cp .env.example .env        # Windows: copy .env.example .env
# edit .env: DB_PASSWORD and a long random JWT_SECRET
npm install
npm run setup               # drops/recreates database `jeevandan`, tables, views, triggers, demo data
npm start                   # http://localhost:3000   (check: http://localhost:3000/api/health)
```
No Node? You can run the SQL files in MySQL Workbench in this order: `schema.sql`, `views.sql`, `triggers.sql` (it uses `DELIMITER $$`), `seed.sql`.

## 1b. Website (no Flutter needed)
After `npm start`, just open **http://localhost:3000** in a browser. The site lives in `backend/public/` and is served by the same Express server (same API, same demo accounts).

## 2. Flutter app (Android Studio)
```bash
flutter create --org com.jeevandan --project-name jeevandan_app jeevandan_app
# copy flutter_app/lib/ and flutter_app/pubspec.yaml over the generated ones
# delete jeevandan_app/test/widget_test.dart (it references the template app)
cd jeevandan_app
flutter pub get
```
Edit `android/app/src/main/AndroidManifest.xml` (needed because the dev API is plain http):
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<application
    android:usesCleartextTraffic="true"
    ... existing attributes ...>
```
Run: open the `jeevandan_app` folder in Android Studio and press ▶, or `flutter run`.

* **Emulator:** works as-is (the app uses `http://10.0.2.2:3000`, the emulator's alias for your PC).
* **Real phone:** same Wi-Fi as your PC, allow port 3000 in the firewall, then tap the ⚙ icon on the login screen and enter `http://<your-PC-LAN-IP>:3000`.

## 3. Build an APK
```bash
flutter build apk --release        # build/app/outputs/flutter-apk/app-release.apk
# or bake in the server address:
flutter build apk --release --dart-define=API_URL=http://192.168.1.5:3000
```
For anything beyond a college demo, serve the API over HTTPS and remove `usesCleartextTraffic`.

## Demo accounts (password for all: `Demo@1234`)
| Role | Email | Notes |
|---|---|---|
| Admin | admin@jeevandan.test | dashboard, audit logs, organ verification |
| Staff | staff1@jeevandan.test | Narmada Care Hospital (Bhopal, transplant centre, **low O- stock**) |
| Staff | staff2@jeevandan.test | Sanjeevani Blood Bank (Bhopal, large stock) |
| Staff | staff3@jeevandan.test | Vindhya Medical Centre (Indore) |
| Donor | donor1@jeevandan.test … donor8 | donor1 = O-, never donated; donor8 donated 10 days ago (not eligible) |
| Patient | patient1@jeevandan.test, patient2 | patient1 has an open EMERGENCY O- request at Narmada Care |

## Test scenarios
**A. Main demo flow – emergency → matching → fulfilment → inventory update**
1. Login as `staff1` → Dashboard shows the EMERGENCY O- request (3 units needed, hospital has only 2: "✖ short").
2. Open it → **Verify & approve** → status APPROVED.
3. Try **Fulfil from stock** → fails with "Insufficient unexpired stock: short by 1 unit(s)" (transaction rolled back, inventory unchanged).
4. Fix it either way:
   * *Transfer:* Transfers → Request stock → from Sanjeevani Blood Bank, O-, 2 units. Login `staff2` → Transfers → **Dispatch**. Both inventories update in one transaction. `staff1` fulfils the request → FULFILLED, stock drops, low-stock alert appears.
   * *Donor:* in the request, tick `Aarav Sharma (O-)` → Notify. Login `donor1` → accept the invitation.
5. Login `patient1` → request shows FULFILLED + notification. Login `admin` → Audit Logs show every step.

**B. Donor registration & donation:** Register as a donor (new account) → login `staff2` → Donors → tap the new donor → Save donation → batch created with 35-day expiry; the donor can't donate again for 90 days (try twice: second attempt is refused).

**C. Expiry protection:** `staff1` → Our Inventory shows an EXPIRED O+ batch and a B+ batch expiring in 3 days. Fulfil the B+ URGENT request: only unexpired batches are used. (DB trigger `trg_alloc_bi` also blocks allocating expired stock.)

**D. Search:** login `patient1` → Find Blood → choose A+ → compatible groups (O-, O+, A-, A+) from all facilities, exact match first. Tap a hospital to raise a request.

**E. Organ workflow:** `donor1` → Organ Pledge → pledge Kidney (family-informed box required). `staff1` → Organ Requests → existing Kidney request. `admin` → open it → Start review → Verify eligibility (notes required) → "Compatible pledged donors" lists anonymised candidates for clinical review. No allocation happens anywhere in the app.

**F. Duplicate processing:** open the same fulfilled request on two devices and press Fulfil on both → second gets "already fulfilled" (row lock + status guard + trigger).

## Security notes
scrypt password hashes (salted), JWT (12 h), role checks on every route, parameterised SQL only, login throttling, `helmet`, personal data limited by role (donor phone numbers only for staff/admin; organ candidates have no contact data). The token is stored in SharedPreferences – use `flutter_secure_storage` for production.

## Assumptions
* Blood is stored in "units" (1 unit ≈ 1 bag); shelf life 35 days; donor interval 90 days; low-stock threshold 5 units; expiry warning 5 days.
* Request fulfilment is from the *requested* hospital's stock, using compatible red-cell groups, exact group first, earliest expiry first.
* Staff accounts are created by admin (`POST /api/admin/staff`) or seed data; public sign-up is for donors/patients only.
* Organ module = pledge records + eligibility verification workflow only; the admin acts as the authorised verifier/committee.
