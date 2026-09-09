# SMART-TRAP Hardware Assembly Guide

This guide details how to wire and solder the components for the ESP32 Handheld Scanner.

## Components Required
- 1x ESP32 Development Board (e.g., ESP32-WROOM-32)
- 1x MFRC522 RFID Reader Module
- 2x Push Buttons (Green and Red)
- Jumper wires and soldering equipment
- 3.3V Portable Power Bank or Battery Shield (for field use)

---

## 🔌 Wiring Diagram

### 1. MFRC522 RFID Reader Connections
The MFRC522 uses the standard hardware SPI interface (VSPI) on the ESP32.

| MFRC522 Pin | ESP32 Pin | Notes |
| :--- | :--- | :--- |
| **3.3V** | **3.3V** | ⚠️ **DO NOT CONNECT TO 5V**, this will burn the MFRC522! |
| **GND** | **GND** | Ground |
| **RST** | **GPIO 9** | Reset Pin (as defined in `esp32_scanner.ino`) |
| **SDA (SS)**| **GPIO 10** | Slave Select (as defined in `esp32_scanner.ino`) |
| **MOSI** | **GPIO 23** | Standard ESP32 SPI MOSI |
| **MISO** | **GPIO 19** | Standard ESP32 SPI MISO |
| **SCK** | **GPIO 18** | Standard ESP32 SPI Clock |
| **IRQ** | *Unconnected* | Not used in this project |

### 2. Button Connections
The buttons are configured with `INPUT_PULLUP` in the code, which means you do **not** need external resistors. 

| Button | Leg 1 (Signal) | Leg 2 (Ground) |
| :--- | :--- | :--- |
| **GREEN Button** (Compliant) | **GPIO 4** | **GND** |
| **RED Button** (Non-Compliant) | **GPIO 5** | **GND** |

*Note: When the button is pressed, it connects the GPIO pin to Ground, pulling the signal `LOW`. The code detects this `LOW` signal to log the scan.*

---

## 🔋 Powering the Device
For actual field deployment with sanitation workers:
- **During the shift:** Connect the ESP32 to a standard USB power bank or use a lithium battery shield (like the Wemos 18650 shield). The device operates entirely offline.
- **End of shift:** Plug the ESP32's micro-USB/USB-C port directly into the Municipal Depot Computer to sync data via the Flutter Desktop App.

## 🛠️ Assembly Tips
- **Keep SPI wires short:** Long wires between the ESP32 and the MFRC522 can degrade the SPI signal and cause card reading failures.
- **Debouncing:** The button debouncing is handled by a 5-second polling window in the software (`delay(10)` loop). If you experience "double scans", you can add a 100nF capacitor across the button legs in hardware.
