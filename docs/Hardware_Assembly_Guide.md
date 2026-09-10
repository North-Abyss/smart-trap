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
| **RST** | **D15** | Reset Pin |
| **SDA (SS)**| **D13** | Slave Select |
| **MOSI** | **D23** | Standard ESP32 SPI MOSI |
| **MISO** | **D19** | Standard ESP32 SPI MISO |
| **SCK** | **D18** | Standard ESP32 SPI Clock |
| **IRQ** | *Unconnected* | Not used in this project |

### 2. 16x2 LCD with I2C Backpack Connections
Since you are using an I2C backpack (as pictured), you only need 4 wires to connect the LCD. This saves a lot of pins!


| I2C Backpack Pin | ESP32 Connection | Notes |
| :--- | :--- | :--- |
| **GND** | **GND** | Ground |
| **VCC** | **VIN (5V)** | Power (5V is required for the backlight and LCD contrast) |
| **SDA** | **D21** | I2C Data Line (Default) |
| **SCL** | **D22** | I2C Clock Line (Default) |

*(Note: The potentiometer on the blue I2C backpack can be turned with a small Phillips screwdriver to adjust the screen's contrast if the text is not visible).*

### 3. Button Connections
The buttons are configured with `INPUT_PULLUP` in the code, which means you do **not** need external resistors. 

| Button | Leg 1 (Signal) | Leg 2 (Ground) |
| :--- | :--- | :--- |
| **Green Button (DONE)** | **D4** | **GND** |
| **Blue Button (SKIP)** | **D5** | **GND** |

*Note: When a button is pressed, it connects the GPIO pin to Ground, pulling the signal `LOW`. The Green button logs the scan as "DONE", and the Blue button logs it as "NOT DONE".*

---

## 🔋 Powering the Device
For actual field deployment with sanitation workers:
- **During the shift:** Connect the ESP32 to a standard USB power bank or use a lithium battery shield. The device operates entirely offline.
- **End of shift:** Plug the ESP32's micro-USB/USB-C port directly into the Municipal Depot Computer to sync data via the Flutter Desktop App.

## 🛠️ Assembly Tips
- **Keep SPI wires short:** Long wires between the ESP32 and the MFRC522 can degrade the SPI signal and cause card reading failures.
- **Adjust Contrast:** If the LCD turns on but you see solid white blocks or nothing at all, turn the potentiometer knob until the text appears clearly.
