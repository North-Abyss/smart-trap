#include <SPI.h>
#include <MFRC522.h>
#include <FS.h>
#include <LittleFS.h>
#include <ArduinoJson.h>
#include <mbedtls/md.h>

#define RST_PIN         22
#define SS_PIN          21
#define GREEN_BTN_PIN   4
#define RED_BTN_PIN     5

MFRC522 mfrc522(SS_PIN, RST_PIN);

const String SCANNER_ID = "SCN-014-003";
const String SECRET_KEY = "super_secret_hmac_key_for_demo"; // In production, store in secure enclave
const String DATA_FILE = "/records.jsonl";

void setup() {
  Serial.begin(115200);
  while (!Serial);

  SPI.begin();
  mfrc522.PCD_Init();
  
  pinMode(GREEN_BTN_PIN, INPUT_PULLUP);
  pinMode(RED_BTN_PIN, INPUT_PULLUP);

  if(!LittleFS.begin(true)){
    Serial.println("LittleFS Mount Failed");
    return;
  }
}

void loop() {
  handleSerialCommands();

  // Look for new cards
  if ( ! mfrc522.PICC_IsNewCardPresent()) return;
  if ( ! mfrc522.PICC_ReadCardSerial()) return;

  String tagUID = "";
  for (byte i = 0; i < mfrc522.uid.size; i++) {
    tagUID += String(mfrc522.uid.uidByte[i] < 0x10 ? "0" : "");
    tagUID += String(mfrc522.uid.uidByte[i], HEX);
  }
  tagUID.toUpperCase();
  
  mfrc522.PICC_HaltA(); // Stop reading

  // Wait for button press (timeout after 5 seconds)
  unsigned long startTime = millis();
  int status = -1;
  while(millis() - startTime < 5000) {
    if (digitalRead(GREEN_BTN_PIN) == LOW) {
      status = 1;
      break;
    }
    if (digitalRead(RED_BTN_PIN) == LOW) {
      status = 0;
      break;
    }
    delay(10);
  }

  if (status != -1) {
    saveRecord(tagUID, status);
  }
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
