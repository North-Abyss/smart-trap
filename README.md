# SMART-TRAP Municipal System

**Statutory Municipal Architecture for Resource-Recovery & Tracking via Tax-Linked Recycling & Neighborhood Accountability Policy (SMART-TRAP)**

SMART-TRAP is an end-to-end IoT and software policy architecture designed to enforce and reward household waste segregation in Tier-2/3 Indian Municipal Bodies (like Vellore, Ranipet, and Hosur). It uses offline RFID scanning and an electricity-bill incentive loop without requiring residents to download any apps.

## 🏗️ System Architecture (Minimal Stack)

The system is built on a highly portable, minimal tech stack consisting of three core components:

1. **Hardware Edge (ESP32)**: A custom handheld scanner carried by sanitation workers. It scans passive RFID gate tags, logs compliance (GREEN/RED), and securely signs the offline data using HMAC-SHA256 to prevent tampering.
2. **Backend (PocketBase)**: A single-file, zero-configuration backend (using embedded SQLite) that runs locally on the municipal depot computer. It handles the database, API, and automatic monthly compliance score calculations via cron jobs.
3. **Desktop App (Flutter)**: A cross-platform desktop application that acts as a bridge. When the ESP32 is plugged in via USB, the Flutter app reads the offline logs over Serial, verifies the cryptographic hashes, and syncs the data to PocketBase. It also serves as the Municipal Dashboard for viewing compliance metrics.

---

## 🚀 Getting Started

### 1. Running the Backend (PocketBase)
The backend is completely self-contained. It requires no external database installations like PostgreSQL.

```bash
cd backend
./pocketbase serve
```
* The REST API runs at: `http://127.0.0.1:8090/api/`
* The Admin UI runs at: `http://127.0.0.1:8090/_/` (You will be prompted to create an admin account on your first visit).

**Note:** The database schema (Collections for Wards, Workers, Scanners, Properties, and Audit Logs) is automatically created on startup via the `pb_migrations` scripts.

### 2. Running the Desktop App (Flutter)
Ensure you have the Flutter SDK installed for Linux/Windows.

```bash
cd smart_trap_app
flutter run -d linux
```
The desktop app has two tabs:
- **Depot Sync Tool**: Used at the end of a shift. Plug in the ESP32 via USB and click "Start Sync" to securely upload the day's offline scan records to PocketBase.
- **Compliance Dashboard**: View real-time scanning history and identify which properties are eligible for their utility tax rebates.

### 3. ESP32 Firmware
The C++ source code for the handheld scanner is located in the `esp32_scanner/` directory.
- Open `esp32_scanner.ino` in the Arduino IDE.
- Install required libraries: `MFRC522`, `ArduinoJson`.
- Flash to your ESP32 board.

---

## 🔒 Security & Tamper-Proofing
The system operates offline during the collection shift (no WiFi or SIM cards). To prevent data manipulation (e.g., workers manually changing RED scans to GREEN scans on the SD card), the ESP32 calculates an `HMAC-SHA256` signature for every record using a secret key.

During the USB sync process, the Flutter app recalculates this hash. If the hashes do not match, the record is flagged as tampered and rejected.

---

## 🔄 Version Control & Syncing
This repository is equipped with an automated git-sync script to easily commit and push your changes to GitHub without needing to remember git commands.

To save your work and push to GitHub, simply run:
```bash
./git-sync.sh
```
