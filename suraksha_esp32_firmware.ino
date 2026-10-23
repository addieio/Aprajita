/*
 * ======================================================================================
 *  SURAKSHA KEY - ESP32 Physical Women's Safety Keychain Firmware (v3.2.0-3PRESS)
 *  Autonomous Physical SOS + SIMCom A7670C 4G + NEO-6M GPS + BLE Companion Link
 * ======================================================================================
 *  
 *  Target Hardware:
 *    - ESP32 Dev Module (ESP-WROOM-32)
 *    - SIMCom A7670C 4G LTE Cat-1 Modem (HardwareSerial 2: RX=16, TX=17)
 *    - u-blox NEO-6M GPS Module (HardwareSerial 1: RX=26, TX=27)
 *    - Physical SOS Button (GPIO 4: Active LOW with internal INPUT_PULLUP)
 *    - Non-Volatile Flash Memory (Preferences.h) for Autonomous Contact Storage
 * 
 *  GATT BLE Specifications:
 *    - Device Advertising Name: "SURAKSHA-KEY"
 *    - Service UUID:         4fafc201-1fb5-459e-8fcc-c5c9c331914b
 *    - CHAR_SOS_EVENT:       beb5483e-36e1-4688-b7f5-ea07361b26a8 (Notify)
 *    - CHAR_PHONE_GPS:       beb5483e-36e1-4688-b7f5-ea07361b26a9 (Write)
 *    - CHAR_SYNC_CONTACTS:   beb5483e-36e1-4688-b7f5-ea07361b26aa (Write)
 *    - CHAR_MODEM_STATUS:    beb5483e-36e1-4688-b7f5-ea07361b26ab (Read/Notify)
 * ======================================================================================
 */

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <HardwareSerial.h>
#include <TinyGPSPlus.h>
#include <Preferences.h>

// ---------- PIN DEFINITIONS ----------
#define PIN_SOS_BUTTON     4    // Tactile push button (Active LOW)
#define GSM_RX_PIN         16   // ESP32 RX2 <- A7670C TX
#define GSM_TX_PIN         17   // ESP32 TX2 -> A7670C RX
#define GPS_RX_PIN         26   // ESP32 RX1 <- NEO-6M TX
#define GPS_TX_PIN         27   // ESP32 TX1 -> NEO-6M RX

// ---------- BLE UUID CONSTANTS ----------
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_SOS_EVENT      "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_PHONE_GPS      "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define CHAR_SYNC_CONTACTS  "beb5483e-36e1-4688-b7f5-ea07361b26aa"
#define CHAR_MODEM_STATUS   "beb5483e-36e1-4688-b7f5-ea07361b26ab"

// ---------- HARDWARE SERIAL INSTANCES ----------
HardwareSerial modemSerial(2); // SIMCom A7670C 4G UART
HardwareSerial gpsSerial(1);   // u-blox NEO-6M GPS UART
TinyGPSPlus gps;
Preferences prefs;             // Non-Volatile Flash Storage

// ---------- RUNTIME STATE ----------
BLEServer* pServer = nullptr;
BLECharacteristic* pCharSos = nullptr;
BLECharacteristic* pCharModemStatus = nullptr;
bool bleConnected = false;

// Cached Phone GPS (streamed from companion Android app over BLE)
double phoneLat = 0.0;
double phoneLng = 0.0;
float phoneAccuracy = 0.0;
unsigned long phoneGpsTimestamp = 0;
bool hasValidPhoneGps = false;

// Stored Contacts Cache (loaded from Preferences Flash)
#define MAX_SAVED_CONTACTS 5
String savedContacts[MAX_SAVED_CONTACTS];
int savedContactCount = 0;

// Button Debounce & 3-Press Policy
int pressCount = 0;
unsigned long lastPressTime = 0;
const unsigned long MULTI_PRESS_WINDOW_MS = 1500; // Must press 3 times within 1.5 seconds

// Modem Cache
int modemCsq = 0;
String modemOperator = "";
String modemRegStatus = "SEARCHING";
bool modemSimReady = false;

// Function Prototypes
void triggerEmergencySos(const char* source);
void sendA7670cSms(const String& recipient, const String& message);
void queryModemStatus();

// BLE Callbacks
class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    bleConnected = true;
    Serial.println("🟢 Companion App Connected via BLE.");
  }
  void onDisconnect(BLEServer* pServer) {
    bleConnected = false;
    Serial.println("⚪ Companion App Disconnected. Restarting BLE advertising...");
    BLEDevice::startAdvertising();
  }
};

class PhoneGpsCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) {
    String val = pChar->getValue().c_str();
    if (val.length() > 0) {
      int c1 = val.indexOf(',');
      int c2 = val.indexOf(',', c1 + 1);
      if (c1 > 0 && c2 > c1) {
        phoneLat = val.substring(0, c1).toDouble();
        phoneLng = val.substring(c1 + 1, c2).toDouble();
        phoneAccuracy = val.substring(c2 + 1).toFloat();
        phoneGpsTimestamp = millis();
        hasValidPhoneGps = true;
        Serial.printf("📍 Phone GPS Received: %.6f, %.6f (±%.1fm)\n", phoneLat, phoneLng, phoneAccuracy);
      }
    }
  }
};

class SyncContactsCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) {
    String payload = pChar->getValue().c_str();
    // Format: COUNT:<N>;<NUM1>;<NUM2>...
    if (payload.startsWith("COUNT:")) {
      prefs.begin("suraksha", false);
      savedContactCount = 0;
      int startIdx = payload.indexOf(';') + 1;
      while (startIdx > 0 && savedContactCount < MAX_SAVED_CONTACTS) {
        int nextSemi = payload.indexOf(';', startIdx);
        String number = (nextSemi == -1) ? payload.substring(startIdx) : payload.substring(startIdx, nextSemi);
        number.trim();
        if (number.length() > 0) {
          savedContacts[savedContactCount] = number;
          String key = "c" + String(savedContactCount);
          prefs.putString(key.c_str(), number);
          savedContactCount++;
        }
        if (nextSemi == -1) break;
        startIdx = nextSemi + 1;
      }
      prefs.putInt("count", savedContactCount);
      prefs.end();
      Serial.printf("💾 %d Emergency Contacts Saved to ESP32 Flash Memory.\n", savedContactCount);
    }
  }
};

void setup() {
  Serial.begin(115200);
  delay(1000);
  Serial.println("\n--- SURAKSHA KEY INITIALIZING ---");

  // Push button with internal pull-up
  pinMode(PIN_SOS_BUTTON, INPUT_PULLUP);

  // A7670C 4G UART (115200 baud)
  modemSerial.begin(115200, SERIAL_8N1, GSM_RX_PIN, GSM_TX_PIN);

  // NEO-6M GPS UART (9600 baud)
  gpsSerial.begin(9600, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);

  // Load contacts from Flash
  prefs.begin("suraksha", true);
  savedContactCount = prefs.getInt("count", 0);
  for (int i = 0; i < savedContactCount && i < MAX_SAVED_CONTACTS; i++) {
    String key = "c" + String(i);
    savedContacts[i] = prefs.getString(key.c_str(), "");
  }
  prefs.end();
  Serial.printf("Loaded %d contacts from flash.\n", savedContactCount);

  // BLE Setup
  BLEDevice::init("SURAKSHA-KEY");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  pCharSos = pService->createCharacteristic(
    CHAR_SOS_EVENT,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharSos->addDescriptor(new BLE2902());

  BLECharacteristic* pCharPhoneGps = pService->createCharacteristic(
    CHAR_PHONE_GPS,
    BLECharacteristic::PROPERTY_WRITE
  );
  pCharPhoneGps->setCallbacks(new PhoneGpsCallbacks());

  BLECharacteristic* pCharSync = pService->createCharacteristic(
    CHAR_SYNC_CONTACTS,
    BLECharacteristic::PROPERTY_WRITE
  );
  pCharSync->setCallbacks(new SyncContactsCallbacks());

  pCharModemStatus = pService->createCharacteristic(
    CHAR_MODEM_STATUS,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pCharModemStatus->addDescriptor(new BLE2902());

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("✅ BLE GATT Server ready: Advertising 'SURAKSHA-KEY'");
}

// 3-PRESS PHYSICAL BUTTON MECHANISM
void handleThreePressButton() {
  static int lastButtonState = HIGH;
  int currentState = digitalRead(PIN_SOS_BUTTON);

  if (lastButtonState == HIGH && currentState == LOW) {
    delay(40); // Debounce
    if (digitalRead(PIN_SOS_BUTTON) == LOW) {
      unsigned long now = millis();
      if (now - lastPressTime > MULTI_PRESS_WINDOW_MS) {
        pressCount = 1;
      } else {
        pressCount++;
      }
      lastPressTime = now;
      Serial.printf("🔘 Physical Button Click #%d detected on GPIO 4\n", pressCount);

      if (pressCount >= 3) {
        pressCount = 0;
        triggerEmergencySos("PHYSICAL_BUTTON_3PRESS");
      }
    }
  }
  lastButtonState = currentState;

  if (pressCount > 0 && (millis() - lastPressTime > MULTI_PRESS_WINDOW_MS)) {
    Serial.printf("⚠️ 3-Press sequence timed out (%d of 3). False alarm discarded.\n", pressCount);
    pressCount = 0;
  }
}

void triggerEmergencySos(const char* source) {
  Serial.printf("\n🚨🚨🚨 EMERGENCY SOS TRIGGERED! Source: %s 🚨🚨🚨\n", source);

  // 1. Notify Phone over BLE if connected
  if (bleConnected && pCharSos != nullptr) {
    String event = "SOS:" + String(source);
    pCharSos->setValue(event.c_str());
    pCharSos->notify();
    Serial.println("Sent SOS notification to companion phone app.");
  }

  // 2. Resolve Best Coordinates
  double lat = 0.0;
  double lng = 0.0;
  String locSource = "NONE";

  if (hasValidPhoneGps && (millis() - phoneGpsTimestamp < 120000)) {
    lat = phoneLat;
    lng = phoneLng;
    locSource = "PHONE_GPS";
  } else if (gps.location.isValid()) {
    lat = gps.location.lat();
    lng = gps.location.lng();
    locSource = "NEO6M_GPS";
  }

  // 3. Format Distress SMS
  String mapLink = (lat != 0.0) 
      ? ("https://maps.google.com/?q=" + String(lat, 6) + "," + String(lng, 6))
      : "Location Acquiring";

  String alertMsg = "EMERGENCY SOS: I need help! My live location: " + mapLink + " (" + locSource + "). Sent via SURAKSHA KEY.";

  // 4. Send Cellular SMS via A7670C to all saved contacts
  Serial.printf("Dispatching cellular SMS to %d saved contacts...\n", savedContactCount);
  for (int i = 0; i < savedContactCount; i++) {
    sendA7670cSms(savedContacts[i], alertMsg);
  }
}

void sendA7670cSms(const String& recipient, const String& message) {
  Serial.printf("Sending SMS to %s...\n", recipient.c_str());
  modemSerial.print("AT+CMGF=1\r\n");
  delay(150);
  modemSerial.print("AT+CMGS=\"" + recipient + "\"\r\n");
  delay(250);
  modemSerial.print(message);
  delay(150);
  modemSerial.write(26); // Ctrl+Z to send
  delay(3000);
  Serial.println("SMS command submitted to A7670C modem.");
}

void loop() {
  handleThreePressButton();

  // Read GPS sentences
  while (gpsSerial.available() > 0) {
    gps.encode(gpsSerial.read());
  }

  delay(10);
}
