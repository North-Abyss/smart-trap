# SMART-TRAP Hardware Assembly Guide

This guide details how to wire and solder the components for the ESP32 Handheld Scanner.

## Components Required
- 1x ESP32 Development Board (38-pin version like ESP32-WROOM-32)
- 1x MFRC522 RFID Reader Module
- 1x 16x2 Character LCD (HD44780 compatible)
- 1x 10kΩ Potentiometer (for LCD contrast)
- 1x Push Button (Action Button)
- Jumper wires and breadboard/soldering equipment
- 3.3V/5V Portable Power Bank or Battery Shield (for field use)

---

## 🔌 Wiring Diagram

> [!IMPORTANT]
> **Voltage Requirements:** The **LCD must be connected to 5V (VIN)**, and the **MFRC522 must be connected to 3.3V**. Mixing these voltages will damage the components!

### 1. MFRC522 RFID Reader Connections
The MFRC522 uses the standard hardware SPI interface (VSPI) on the ESP32.

| MFRC522 Pin | ESP32 Pin | Notes |
| :--- | :--- | :--- |
| **3.3V** | **3.3V** | ⚠️ **DO NOT CONNECT TO 5V**, this will burn the MFRC522! |
| **GND** | **GND** | Ground |
| **RST** | **D22** | Reset Pin |
| **SDA (SS)**| **D21** | Slave Select |
| **MOSI** | **D23** | Standard ESP32 SPI MOSI |
| **MISO** | **D19** | Standard ESP32 SPI MISO |
| **SCK** | **D18** | Standard ESP32 SPI Clock |
| **IRQ** | *Unconnected* | Not used in this project |

### 2. 16x2 LCD Connections (4-Bit Parallel Mode)
The LCD is wired directly to the ESP32 using 6 GPIO pins for data and control.

| LCD Pin | Connection | Notes |
| :--- | :--- | :--- |
| **1 (VSS)** | **GND** | Ground |
| **2 (VDD)** | **VIN (5V)** | 5V Power for logic |
| **3 (V0)** | **Potentiometer Center Pin** | Contrast adjustment. Outer pins to 5V and GND. |
| **4 (RS)** | **D13** | Register Select |
| **5 (RW)** | **GND** | Read/Write (always ground to Write) |
| **6 (E)** | **D12** | Enable |
| **11 (D4)** | **D14** | Data line 4 |
| **12 (D5)** | **D27** | Data line 5 |
| **13 (D6)** | **D26** | Data line 6 |
| **14 (D7)** | **D25** | Data line 7 |
| **15 (A)** | **VIN (5V)** | Backlight Anode (+) |
| **16 (K)** | **GND** | Backlight Cathode (-) |

### 3. Button Connections
The button is configured with `INPUT_PULLUP` in the code, which means you do **not** need an external resistor. 

| Button | Leg 1 (Signal) | Leg 2 (Ground) |
| :--- | :--- | :--- |
| **Action Button** | **D4** | **GND** |

*Note: When the button is pressed, it connects the GPIO pin to Ground, pulling the signal `LOW`. The code detects this `LOW` signal to log the scan as "DONE".*

---

## 🔋 Powering the Device
For actual field deployment with sanitation workers:
- **During the shift:** Connect the ESP32 to a standard USB power bank or use a lithium battery shield. The device operates entirely offline.
- **End of shift:** Plug the ESP32's micro-USB/USB-C port directly into the Municipal Depot Computer to sync data via the Flutter Desktop App.

## 🛠️ Assembly Tips
- **Keep SPI wires short:** Long wires between the ESP32 and the MFRC522 can degrade the SPI signal and cause card reading failures.
- **Adjust Contrast:** If the LCD turns on but you see solid white blocks or nothing at all, turn the potentiometer knob until the text appears clearly.
