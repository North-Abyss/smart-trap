#include <SPI.h>
#include <MFRC522.h>
#include <FS.h>
#include <LittleFS.h>
#include <ArduinoJson.h>
#include <mbedtls/md.h>
#include <LiquidCrystal_I2C.h>
#include "driver/gpio.h"

#define RST_PIN         15
#define SS_PIN          13
#define BTN_GREEN_PIN   4
#define BTN_BLUE_PIN    5

MFRC522 mfrc522(SS_PIN, RST_PIN);
LiquidCrystal_I2C lcd(0x27, 16, 2); // Set the LCD address to 0x27 for a 16 chars and 2 line display

const String SCANNER_ID = "SCN-014-003";
const String SECRET_KEY = "super_secret_hmac_key_for_demo"; // In production, store in secure enclave
const String DATA_FILE = "/records.jsonl";

void setup() {
  Serial.begin(115200);
  
  lcd.init();
  lcd.backlight();
  lcd.clear();
  lcd.print("Booting...");

  // CRITICAL: GPIO 13 and 15 are HSPI peripheral pins on the ESP32.
  // We must detach them from the HSPI hardware before using them as regular GPIO
  // for the MFRC522's CS and RST lines.
  gpio_reset_pin(GPIO_NUM_13);
  gpio_reset_pin(GPIO_NUM_15);
  
  // Set SPI pins explicitly: SCK=18, MISO=19, MOSI=23
  // Pass -1 for SS so hardware SPI doesn't claim any CS pin (we use D13 manually)
  SPI.begin(18, 19, 23, -1);
  
  // Hard reset the MFRC522 via RST pin
  pinMode(RST_PIN, OUTPUT);
  digitalWrite(RST_PIN, LOW);
  delay(50);
  digitalWrite(RST_PIN, HIGH);
  delay(100);
  
  // Software reset (critical for some clone chips that don't respond to hard reset alone)
  mfrc522.PCD_Reset();
  delay(100);
  
  mfrc522.PCD_Init();
  delay(200); // Give the MFRC522 time to fully initialize
  
  // Debug: Check if the MFRC522 is connected properly
  Serial.print(F("MFRC522 Firmware Version: 0x"));
  byte v = mfrc522.PCD_ReadRegister(mfrc522.VersionReg);
  Serial.println(v, HEX);
  if (v == 0x00 || v == 0xFF) {
    Serial.println(F("WARNING: Communication failure, is the MFRC522 properly connected?"));
    lcd.clear();
    lcd.print("RFID Error!");
    lcd.setCursor(0, 1);
    lcd.print("Check Wiring");
    delay(3000);
  } else {
    Serial.println(F("MFRC522 connected OK! (Clone chip detected, skipping self-test)"));
  }
  
  // Explicitly turn the antenna ON (critical for clone chips!)
  mfrc522.PCD_AntennaOn();
  delay(50);
  
  // Boost antenna gain to maximum for better card detection range
  mfrc522.PCD_SetAntennaGain(mfrc522.RxGain_max);
  Serial.print(F("Antenna Gain set to: 0x"));
  Serial.println(mfrc522.PCD_GetAntennaGain(), HEX);
  
  // Verify antenna drivers are actually ON by reading TxControlReg
  byte txControl = mfrc522.PCD_ReadRegister(mfrc522.TxControlReg);
  Serial.print(F("TxControlReg: 0x"));
  Serial.println(txControl, HEX);
  if ((txControl & 0x03) != 0x03) {
    Serial.println(F("WARNING: Antenna drivers OFF! Forcing ON..."));
    mfrc522.PCD_WriteRegister(mfrc522.TxControlReg, txControl | 0x03);
    Serial.println(F("Antenna drivers forced ON."));
  } else {
    Serial.println(F("Antenna drivers confirmed ON."));
  }
  
  pinMode(BTN_GREEN_PIN, INPUT_PULLUP);
  pinMode(BTN_BLUE_PIN, INPUT_PULLUP);

  if(!LittleFS.begin(true)){
    Serial.println("LittleFS Mount Failed");
    lcd.clear();
    lcd.print("FS Mount Failed!");
    return;
  }
  
  lcd.clear();
  lcd.print("Ready to Scan...");
}

// Debug: print a heartbeat every 3 seconds so we know the loop is running
unsigned long lastHeartbeat = 0;
unsigned long lastReinit = 0;

void loop() {
  handleSerialCommands();

  // Re-enable antenna every 30 seconds (clone chip workaround — some clones
  // silently disable their antenna drivers after prolonged idle)
  if (millis() - lastReinit > 30000) {
    lastReinit = millis();
    mfrc522.PCD_AntennaOn();
    mfrc522.PCD_SetAntennaGain(mfrc522.RxGain_max);
    Serial.println(F("[DEBUG] Antenna re-initialized (clone chip keepalive)"));
  }

  if (millis() - lastHeartbeat > 3000) {
    lastHeartbeat = millis();
    Serial.println(F("[DEBUG] Waiting for card..."));
  }

  // Look for new cards
  if ( ! mfrc522.PICC_IsNewCardPresent()) return;
  Serial.println(F("[DEBUG] Card detected! Attempting to read..."));
  if ( ! mfrc522.PICC_ReadCardSerial()) return;
  Serial.println(F("[DEBUG] Card UID read successfully!"));

  String tagUID = "";
  for (byte i = 0; i < mfrc522.uid.size; i++) {
    tagUID += String(mfrc522.uid.uidByte[i] < 0x10 ? "0" : "");
    tagUID += String(mfrc522.uid.uidByte[i], HEX);
  }
  tagUID.toUpperCase();
  
  mfrc522.PICC_HaltA(); // Stop reading

  lcd.clear();
  lcd.setCursor(0, 0);
  lcd.print("Tag Scanned!");
  lcd.setCursor(0, 1);
  lcd.print("Grn:DONE Blu:SKP");

  // Wait for button press (timeout after 5 seconds)
  unsigned long startTime = millis();
  int status = 0; // Default to 0 (Not Done)
  while(millis() - startTime < 5000) {
    if (digitalRead(BTN_GREEN_PIN) == LOW) {
      status = 1;
      break;
    }
    if (digitalRead(BTN_BLUE_PIN) == LOW) {
      status = 0;
      break;
    }
    delay(10);
  }

  saveRecord(tagUID, status);
  
  lcd.clear();
  lcd.setCursor(0, 0);
  if (status == 1) {
    lcd.print("Success: DONE");
  } else {
    lcd.print("Saved: NOT DONE");
  }
  delay(2000);
  
  lcd.clear();
  lcd.print("Ready to Scan...");
}

void saveRecord(String tagUID, int status) {
  // Use a pseudo-RTC timestamp (since ESP32 is offline, we'd normally need a real RTC module)
  // For this demo without RTC hardware, we'll use millis() as a placeholder timestamp.
  unsigned long timestamp = millis(); 
  
  // Create payload string for hashing
  String payload = SCANNER_ID + tagUID + String(timestamp) + String(status);
  String hmac = calculateHMAC(payload);

  JsonDocument doc;
  doc["scanner_id"] = SCANNER_ID;
  doc["tag_uid"] = "0x" + tagUID;
  doc["timestamp"] = timestamp;
  doc["status"] = status;
  doc["hmac"] = hmac;

  String output;
  serializeJson(doc, output);
  
  File file = LittleFS.open(DATA_FILE, FILE_APPEND);
  if(!file){
    Serial.println("Failed to open file for appending");
    return;
  }
  file.println(output);
  file.close();
}

String calculateHMAC(String payload) {
  byte hmacResult[32];
  mbedtls_md_context_t ctx;
  mbedtls_md_type_t md_type = MBEDTLS_MD_SHA256;
  
  const size_t payloadLength = payload.length();
  const size_t keyLength = SECRET_KEY.length();
  
  mbedtls_md_init(&ctx);
  mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(md_type), 1);
  mbedtls_md_hmac_starts(&ctx, (const unsigned char *) SECRET_KEY.c_str(), keyLength);
  mbedtls_md_hmac_update(&ctx, (const unsigned char *) payload.c_str(), payloadLength);
  mbedtls_md_hmac_finish(&ctx, hmacResult);
  mbedtls_md_free(&ctx);
  
  String hexStr = "";
  for(int i= 0; i< sizeof(hmacResult); i++) {
    char str[3];
    sprintf(str, "%02x", (int)hmacResult[i]);
    hexStr += str;
  }
  return hexStr;
}

void handleSerialCommands() {
  if (Serial.available() > 0) {
    String cmd = Serial.readStringUntil('\n');
    cmd.trim();
    
    if (cmd == "PING") {
      Serial.println("PONG");
    } 
    else if (cmd == "COUNT") {
      int count = 0;
      File file = LittleFS.open(DATA_FILE);
      if(file) {
        while(file.available()) {
          file.readStringUntil('\n');
          count++;
        }
        file.close();
      }
      Serial.print("COUNT:");
      Serial.println(count);
    }
    else if (cmd == "DUMP") {
      File file = LittleFS.open(DATA_FILE);
      if(!file){
        Serial.println("END");
        return;
      }
      while(file.available()){
        String line = file.readStringUntil('\n');
        line.trim();
        if (line.length() > 0) {
          Serial.print("DATA:");
          Serial.println(line);
        }
      }
      file.close();
      Serial.println("END");
    }
    else if (cmd == "CLEAR") {
      LittleFS.remove(DATA_FILE);
      Serial.println("CLEARED");
    }
  }
}
