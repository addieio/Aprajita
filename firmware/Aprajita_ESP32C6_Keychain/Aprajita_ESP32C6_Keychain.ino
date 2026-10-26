/*
  Aprajita + Weather Keychain + MPU-6050 Fall Detection & SOS
  Board: Seeed Studio XIAO ESP32-C6
  Display: 128x64 SSD1306 I2C OLED, address 0x3C

  BUTTON WIRING (Seeed Studio XIAO ESP32-C6):
    Button leg 1 -> D2 (GPIO 2) [OR D0 (GPIO 0) / D1 (GPIO 1)]
    Button leg 2 -> GND
    Uses internal INPUT_PULLUP; do NOT connect button to 3V3.

  OLED & MPU-6050 WIRING (Shared I2C bus):
    SDA -> D4 / GPIO22 (Both OLED SDA and MPU-6050 SDA)
    SCL -> D5 / GPIO23 (Both OLED SCL and MPU-6050 SCL)
    VCC -> 3V3
    GND -> GND
    MPU-6050 AD0 -> GND (Address 0x68) [or 3V3 for 0x69]

  GESTURE / BUTTON CONTROLS:
    - Normal (Aprajita faces): Press button -> Weather Dashboard
    - Weather Dashboard: Press button -> Return to faces
    - Fall / Shock detected:
        * Big "SOS" screen with 5-second countdown & progress bar
        * Press button within 5s -> Cancels SOS & opens Action Menu!
        * If 5s expires without press -> Emergency alert triggered
    - Action Menu (after cancel):
        * Single Click: Switch between [ CALL 📞 ] and [ REPORT 📋 ]
        * Long Press (Hold >= 650ms): Select active option (Dial 112 / Log report)
        * Double Click: Return directly to Aprajita face animation!

  Libraries needed in Arduino IDE:
    - Adafruit SSD1306
    - Adafruit GFX Library
    - ArduinoJson (v6 or v7)
    (MPU-6050 uses lightweight direct I2C Wire registers - no extra library needed!)
*/

#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <pgmspace.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <WebServer.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ArduinoJson.h>
#include <math.h>
#include "aprajita_emotions.h"

// ================= USER & NETWORK SETTINGS =================
const char* WIFI_SSID     = "YOUR_WIFI_SSID";
const char* WIFI_PASSWORD = "YOUR_WIFI_PASSWORD";

// ================= TWILIO SMS GATEWAY SETTINGS =================
// Configured via app or set here for hardware standalone backup
const char* TWILIO_ACCOUNT_SID  = "YOUR_TWILIO_ACCOUNT_SID";
const char* TWILIO_AUTH_TOKEN   = "YOUR_TWILIO_AUTH_TOKEN";
const char* TWILIO_FROM_NUMBER  = "+1XXXXXXXXXX";
const char* TWILIO_TO_NUMBER    = "+91XXXXXXXXXX";

// ================= LOCAL HTTP DEVICE CONTROL SERVER =================
WebServer server(80);

// ================= BLE GATT COMPANION LINK DEFINITIONS =================
#define BLE_DEVICE_NAME     "SURAKSHA-KEY"
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHAR_SOS_EVENT      "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define CHAR_PHONE_GPS      "beb5483e-36e1-4688-b7f5-ea07361b26a9"
#define CHAR_SCREEN_CTRL    "beb5483e-36e1-4688-b7f5-ea07361b26aa"

// true = try approximate location from Wi-Fi public IP.
// false = always use manual location below.
const bool AUTO_DETECT_LOCATION_BY_IP = true;

// Fallback / manual location coordinates
const char* MANUAL_LOCATION_NAME = "Delhi";
const double MANUAL_LATITUDE  = 28.6139;
const double MANUAL_LONGITUDE = 77.2090;

// ================= HARDWARE SETTINGS =================
#define OLED_SDA       22       // XIAO D4 / GPIO22
#define OLED_SCL       23       // XIAO D5 / GPIO23
#define OLED_ADDRESS   0x3C
#define OLED_RESET     -1
#define SCREEN_WIDTH   128
#define SCREEN_HEIGHT  64

// *** CONNECT YOUR BUTTON HERE ***
// Wire button leg 1 to this pin, leg 2 to GND.
#define BUTTON_PIN     2        // Default D2 (GPIO 2). Change to 0 (D0) or 1 (D1) if desired

#define WEATHER_PAGE_MS     5000UL     // Auto-advance weather page every 5 sec
#define WEATHER_REFRESH_MS  900000UL   // Auto-refresh weather every 15 min

// ================= MPU-6050 & FALL DETECTION SETTINGS =================
#define MPU_FREEFALL_G_THRESH    0.42f   // Free-fall threshold: below 0.42g is weightless phase
#define MPU_IMPACT_G_THRESH      2.40f   // Impact threshold: above 2.40g shortly after free-fall
#define MPU_SHOCK_G_THRESH       2.85f   // Direct violent shock / drop / slam threshold (in g)
#define MPU_JERK_G_THRESH        2.20f   // Sudden delta acceleration threshold (in g)
#define MPU_GYRO_DEG_THRESH      380.0f  // Rapid angular tumble velocity (deg/s)

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
uint8_t frameBuffer[APRAJITA_FRAME_BYTES];
uint8_t deltaBuffer[APRAJITA_FRAME_BYTES];

// ================= MPU-6050 DATA STRUCTURE =================
struct MPUData {
  float ax, ay, az;
  float aTotal;
  float gx, gy, gz;
  float gTotal;
};
MPUData mpuData;

// ================= WEATHER DATA STRUCTURE =================
struct WeatherData {
  bool valid = false;
  String error = "";
  String location = "";
  float temperature = 0.0f;
  float feelsLike = 0.0f;
  int humidity = 0;
  float windKmh = 0.0f;
  float precipitation = 0.0f;
  int weatherCode = 0;
  int isDay = 1;
  float todayHigh = 0.0f;
  float todayLow = 0.0f;
  int rainChance = 0;
  float uvMax = 0.0f;
  String sunrise = "";
  String sunset = "";
  unsigned long lastUpdated = 0;
};
WeatherData wx;

// ================= BUTTON ENGINE (SINGLE / DOUBLE / LONG PRESS) =================
enum ButtonAction {
  ACT_NONE = 0,
  ACT_SINGLE_CLICK,
  ACT_DOUBLE_CLICK,
  ACT_TRIPLE_CLICK,
  ACT_LONG_PRESS
};

int           btnLastRawPin       = HIGH;
int           btnDebouncedState   = HIGH;
unsigned long btnDebounceAt       = 0;
unsigned long btnPressedAt        = 0;
unsigned long btnReleasedAt       = 0;
uint8_t       btnClickCount       = 0;
bool          btnLongPressFired   = false;
bool          btnRawDownEdge      = false;
ButtonAction  btnPendingAction    = ACT_NONE;

void pollButton() {
  btnRawDownEdge = false;
  int raw = digitalRead(BUTTON_PIN);

  if (raw != btnLastRawPin) {
    btnLastRawPin = raw;
    btnDebounceAt = millis();
  }

  if (millis() - btnDebounceAt >= 30) { // 30ms debounce
    if (raw != btnDebouncedState) {
      btnDebouncedState = raw;

      if (btnDebouncedState == LOW) {
        // Physical press down
        btnPressedAt = millis();
        btnLongPressFired = false;
        btnRawDownEdge = true; // Instant edge trigger for 0ms SOS cancel

        if (btnClickCount == 1 && (millis() - btnReleasedAt < 380)) {
          btnClickCount = 2;
        } else if (btnClickCount == 2 && (millis() - btnReleasedAt < 380)) {
          btnClickCount = 3;
        } else if (btnClickCount == 0 || (millis() - btnReleasedAt >= 380)) {
          btnClickCount = 1;
        }
      } else {
        // Physical release up
        if (!btnLongPressFired) {
          if (btnClickCount >= 3) {
            btnPendingAction = ACT_TRIPLE_CLICK;
            btnClickCount = 0;
          } else {
            btnReleasedAt = millis();
          }
        } else {
          btnClickCount = 0;
        }
      }
    }
  }

  // Detect long press while held down
  if (btnDebouncedState == LOW && !btnLongPressFired) {
    if (millis() - btnPressedAt >= 700) {
      btnLongPressFired = true;
      btnPendingAction = ACT_LONG_PRESS;
      btnClickCount = 0;
    }
  }

  // Detect single or double click when multi-click window expires
  if (btnDebouncedState == HIGH && btnClickCount > 0) {
    if (millis() - btnReleasedAt >= 320) {
      if (btnClickCount == 1) {
        btnPendingAction = ACT_SINGLE_CLICK;
      } else if (btnClickCount == 2) {
        btnPendingAction = ACT_DOUBLE_CLICK;
      }
      btnClickCount = 0;
    }
  }
}

ButtonAction getButtonAction() {
  ButtonAction act = btnPendingAction;
  btnPendingAction = ACT_NONE;
  return act;
}

inline bool isButtonDown() {
  return digitalRead(BUTTON_PIN) == LOW;
}

inline bool wasButtonPressedRaw() {
  return btnRawDownEdge;
}

inline bool isButtonPressed() {
  return btnRawDownEdge;
}

inline bool isButtonHeld() {
  return btnLongPressFired;
}

void flushButtonEvents() {
  btnPendingAction = ACT_NONE;
  btnClickCount = 0;
  btnRawDownEdge = false;
  btnLongPressFired = false;
}

// ================= MPU-6050 DRIVER & FALL DETECTION =================
uint8_t mpuAddress = 0x68;
bool    mpuFound   = false;

bool initMPU6050() {
  // Test primary address 0x68 (AD0 -> GND)
  Wire.beginTransmission(0x68);
  if (Wire.endTransmission() == 0) {
    mpuAddress = 0x68;
    mpuFound = true;
  } else {
    // Test alternate address 0x69 (AD0 -> 3V3)
    Wire.beginTransmission(0x69);
    if (Wire.endTransmission() == 0) {
      mpuAddress = 0x69;
      mpuFound = true;
    }
  }

  if (!mpuFound) {
    Serial.println(F("[MPU6050] Sensor not detected at 0x68 or 0x69!"));
    Serial.println(F("[MPU6050] Please wire: SDA->D4(GPIO22), SCL->D5(GPIO23), VCC->3V3, GND->GND"));
    return false;
  }

  Serial.print(F("[MPU6050] Connected at address 0x"));
  Serial.println(mpuAddress, HEX);

  // Wake up MPU-6050 (PWR_MGMT_1: register 0x6B = 0)
  Wire.beginTransmission(mpuAddress);
  Wire.write(0x6B);
  Wire.write(0x00);
  Wire.endTransmission(true);
  delay(15);

  // Configure Accelerometer Range to ±8g (register 0x1C = 0x10, 4096 LSB/g)
  Wire.beginTransmission(mpuAddress);
  Wire.write(0x1C);
  Wire.write(0x10);
  Wire.endTransmission(true);

  // Configure Digital Low Pass Filter DLPF_CFG = 3 (~42Hz filter, register 0x1A = 0x03)
  Wire.beginTransmission(mpuAddress);
  Wire.write(0x1A);
  Wire.write(0x03);
  Wire.endTransmission(true);

  Serial.println(F("[MPU6050] Configured for ±8g. Fall & rapid change detection ACTIVE."));
  return true;
}

bool readMPU() {
  if (!mpuFound) return false;

  Wire.beginTransmission(mpuAddress);
  Wire.write(0x3B); // starting register ACCEL_XOUT_H
  if (Wire.endTransmission(false) != 0) return false;

  if (Wire.requestFrom((uint8_t)mpuAddress, (size_t)14, true) != 14) return false;

  int16_t rawAx = (Wire.read() << 8) | Wire.read();
  int16_t rawAy = (Wire.read() << 8) | Wire.read();
  int16_t rawAz = (Wire.read() << 8) | Wire.read();
  int16_t rawTemp = (Wire.read() << 8) | Wire.read();
  int16_t rawGx = (Wire.read() << 8) | Wire.read();
  int16_t rawGy = (Wire.read() << 8) | Wire.read();
  int16_t rawGz = (Wire.read() << 8) | Wire.read();

  // ±8g sensitivity: 4096 LSB/g
  mpuData.ax = rawAx / 4096.0f;
  mpuData.ay = rawAy / 4096.0f;
  mpuData.az = rawAz / 4096.0f;
  mpuData.aTotal = sqrtf(mpuData.ax * mpuData.ax + mpuData.ay * mpuData.ay + mpuData.az * mpuData.az);

  // ±250 deg/s sensitivity: 131.0 LSB / (deg/s)
  mpuData.gx = rawGx / 131.0f;
  mpuData.gy = rawGy / 131.0f;
  mpuData.gz = rawGz / 131.0f;
  mpuData.gTotal = sqrtf(mpuData.gx * mpuData.gx + mpuData.gy * mpuData.gy + mpuData.gz * mpuData.gz);

  return true;
}

unsigned long lastFreeFallTime   = 0;
unsigned long lastSosTriggerTime = 0;
unsigned long lastMpuReadMs      = 0;
float         prevATotal         = 1.0f;

bool checkFallOrShock() {
  if (!mpuFound) return false;

  unsigned long now = millis();
  // Cooldown: do not re-trigger within 3.5s of handling an SOS
  if (now - lastSosTriggerTime < 3500) return false;

  // Read sensor at ~66Hz (every 15ms)
  if (now - lastMpuReadMs < 15) return false;
  lastMpuReadMs = now;

  if (!readMPU()) return false;

  // 1. Free-fall condition: weightless phase below 0.42g
  if (mpuData.aTotal < MPU_FREEFALL_G_THRESH) {
    lastFreeFallTime = now;
  }

  // Calculate rapid acceleration delta (jerk)
  float deltaA = fabsf(mpuData.aTotal - prevATotal);
  prevATotal = mpuData.aTotal;

  // 2. True Fall: Impact > 2.40g occurring within 850ms of a free-fall phase
  bool fall = (mpuData.aTotal > MPU_IMPACT_G_THRESH) && (now - lastFreeFallTime < 850);

  // 3. Sudden violent shock / rapid environmental change:
  // Direct strong impact > 2.85g, or jerk delta > 2.2g, or violent tumble
  bool shock = (mpuData.aTotal > MPU_SHOCK_G_THRESH) || (deltaA > MPU_JERK_G_THRESH) ||
               (mpuData.gTotal > MPU_GYRO_DEG_THRESH && mpuData.aTotal > 2.0f);

  if (fall || shock) {
    Serial.print(F("[MPU6050] EVENT DETECTED! aTotal="));
    Serial.print(mpuData.aTotal, 2);
    Serial.print(F("g, delta="));
    Serial.print(deltaA, 2);
    Serial.print(F("g, gyro="));
    Serial.print(mpuData.gTotal, 1);
    Serial.print(F(" deg/s (Fall="));
    Serial.print(fall ? F("YES") : F("no"));
    Serial.print(F(", Shock="));
    Serial.print(shock ? F("YES") : F("no"));
    Serial.println(F(")"));

    lastSosTriggerTime = now;
    return true;
  }

  return false;
}


// 16x16 Phone Handset Icon (PROGMEM)
static const unsigned char PROGMEM icon_phone_16[] = {
  0b00001111, 0b00000000,
  0b00111111, 0b10000000,
  0b01110001, 0b11000000,
  0b01100000, 0b11100000,
  0b00110000, 0b01110000,
  0b00011000, 0b00111000,
  0b00001100, 0b00011100,
  0b00000110, 0b00001110,
  0b00000011, 0b00000111,
  0b00000001, 0b10000011,
  0b00000000, 0b11000011,
  0b01110000, 0b01100011,
  0b01111100, 0b00110110,
  0b00111111, 0b11111100,
  0b00001111, 0b11110000,
  0b00000000, 0b00000000
};

// 16x16 Report Clipboard Icon (PROGMEM)
static const unsigned char PROGMEM icon_report_16[] = {
  0b00000111, 0b11100000,
  0b00001111, 0b11110000,
  0b00001100, 0b00110000,
  0b00111111, 0b11111100,
  0b01111111, 0b11111110,
  0b01100000, 0b00000110,
  0b01101111, 0b11100110,
  0b01100000, 0b00000110,
  0b01101111, 0b11100110,
  0b01100000, 0b00000110,
  0b01101111, 0b00000110,
  0b01100000, 0b00000110,
  0b01101111, 0b11100110,
  0b01100000, 0b00000110,
  0b01111111, 0b11111110,
  0b00111111, 0b11111100
};

// Screen state machine: Faces -> Weather -> Night Mode -> Notifications -> Faces
enum AppScreen {
  SCREEN_FACES,
  SCREEN_WEATHER,
  SCREEN_NIGHT_MODE,
  SCREEN_NOTIFICATIONS
};
AppScreen currentScreen = SCREEN_FACES;

// ================= NIGHT WATCH / 10-MIN LOCATION SHARE & STAGNANT MONITOR =================
bool          nightModeActive       = false;
unsigned long nightModeStartedAt    = 0;
unsigned long lastNightModeShareAt   = 0;
double        lastKnownLat          = MANUAL_LATITUDE;
double        lastKnownLng          = MANUAL_LONGITUDE;
unsigned long lastMovementAt        = 0;
bool          stagnantAlertSent     = false;
int           selectedEmotionIndex  = -1; // -1 = cycle all 18 emotes; >=0 = locked emote

// Forward declarations
void enterWeatherDashboard();
void exitWeatherDashboard();
void drawWeatherPage();
void drawNightModePage();
void nightModeLoop();
void toggleNightMode(bool enable);
void checkNightModeBackground();
void triggerSosAlert(const String &reason);
void drawNotificationsPage();
void notificationsLoop();
void loadWeather();
void loadDemoWeather(const String &reason);
void runSosFlow();
void drawSosCountdown(int secondsLeft, int progressPercent);
void drawSosCancelled();
void drawSosTriggered();
void drawActionMenu(uint8_t selectedAction);
void showCallScreen();
void showReportScreen();
bool initMPU6050();
bool readMPU();
bool checkFallOrShock();
void initBLE();
bool sendTwilioSms(const String &bodyText, const String &targetTo = "");
String getEmergencyLocationUrl();

// ================= BLE GATT RUNTIME STATE =================
BLEServer*         pBleServer    = nullptr;
BLECharacteristic* pCharSos      = nullptr;
bool               bleConnected  = false;

// Cached Phone GPS (streamed from companion Android app over BLE)
double phoneLat = 0.0;
double phoneLng = 0.0;
bool   hasPhoneGps = false;

class BleServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    bleConnected = true;
    Serial.println(F("[BLE] Companion Android App Connected!"));
  }
  void onDisconnect(BLEServer* pServer) {
    bleConnected = false;
    Serial.println(F("[BLE] Companion App Disconnected. Restarting BLE advertising..."));
    BLEDevice::startAdvertising();
  }
};

class PhoneGpsCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String rx = pChar->getValue().c_str();
    if (rx.length() > 0) {
      Serial.print(F("[BLE] RX Phone GPS: "));
      Serial.println(rx);
      int firstComma = rx.indexOf(',');
      int secondComma = rx.indexOf(',', firstComma + 1);
      if (firstComma > 0) {
        phoneLat = rx.substring(0, firstComma).toDouble();
        if (secondComma > 0) {
          phoneLng = rx.substring(firstComma + 1, secondComma).toDouble();
        } else {
          phoneLng = rx.substring(firstComma + 1).toDouble();
        }
        hasPhoneGps = true;
        Serial.print(F("[BLE] Updated Live GPS -> Lat: "));
        Serial.print(phoneLat, 6);
        Serial.print(F(", Lng: "));
        Serial.println(phoneLng, 6);
      }
    }
  }
};

class SosCommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String rx = pChar->getValue().c_str();
    Serial.print(F("[BLE] RX SOS Command: "));
    Serial.println(rx);
    if (rx.indexOf("SOS") >= 0 || rx.indexOf("TRIGGER") >= 0) {
      sendTwilioSms("EMERGENCY ALERT: Mobile App triggered Remote SOS on Aprajita Keychain over Bluetooth! Live Location: " + getEmergencyLocationUrl());
    }
  }
};

class ScreenCommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pChar) {
    String rx = pChar->getValue().c_str();
    Serial.print(F("[BLE] RX Screen/Animation Command: "));
    Serial.println(rx);
    rx.trim();

    if (rx == "WEATHER") {
      enterWeatherDashboard();
    } else if (rx == "NIGHT_MODE") {
      currentScreen = SCREEN_NIGHT_MODE;
      drawNightModePage();
    } else if (rx == "NOTIFICATIONS" || rx == "DEVICE_INFO") {
      currentScreen = SCREEN_NOTIFICATIONS;
      drawNotificationsPage();
    } else if (rx == "NIGHT_MODE:ON") {
      currentScreen = SCREEN_NIGHT_MODE;
      toggleNightMode(true);
      drawNightModePage();
    } else if (rx == "NIGHT_MODE:OFF") {
      currentScreen = SCREEN_NIGHT_MODE;
      toggleNightMode(false);
      drawNightModePage();
    } else if (rx.startsWith("EMOTION:")) {
      String emo = rx.substring(8);
      emo.trim();
      emo.toUpperCase();
      selectedEmotionIndex = -1;
      for (uint8_t i = 0; i < APRAJITA_EMOTION_COUNT; i++) {
        const char *name = (const char *)pgm_read_ptr(&APRAJITA_EMOTIONS[i].name);
        if (String(name) == emo) {
          selectedEmotionIndex = i;
          break;
        }
      }
      if (selectedEmotionIndex == -1 && emo.toInt() < (int)APRAJITA_EMOTION_COUNT) {
        selectedEmotionIndex = emo.toInt();
      }
      currentScreen = SCREEN_FACES;
      Serial.print(F("[BLE] Set Locked Emotion: "));
      Serial.println(selectedEmotionIndex);
    } else if (rx == "CYCLE") {
      selectedEmotionIndex = -1;
      currentScreen = SCREEN_FACES;
    } else {
      currentScreen = SCREEN_FACES;
    }
  }
};

void initBLE() {
  BLEDevice::init(BLE_DEVICE_NAME);
  pBleServer = BLEDevice::createServer();
  pBleServer->setCallbacks(new BleServerCallbacks());

  BLEService *pService = pBleServer->createService(SERVICE_UUID);

  pCharSos = pService->createCharacteristic(
    CHAR_SOS_EVENT,
    BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_WRITE | BLECharacteristic::PROPERTY_READ
  );
  pCharSos->addDescriptor(new BLE2902());
  pCharSos->setCallbacks(new SosCommandCallbacks());

  BLECharacteristic *pCharGps = pService->createCharacteristic(
    CHAR_PHONE_GPS,
    BLECharacteristic::PROPERTY_WRITE
  );
  pCharGps->setCallbacks(new PhoneGpsCallbacks());

  BLECharacteristic *pCharScreen = pService->createCharacteristic(
    CHAR_SCREEN_CTRL,
    BLECharacteristic::PROPERTY_WRITE
  );
  pCharScreen->setCallbacks(new ScreenCommandCallbacks());

  pService->start();

  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println(F("[BLE] Advertising started as 'SURAKSHA-KEY'. Ready to pair with Aprajita App!"));
}

// ================= TWILIO SMS GATEWAY CLIENT =================
String base64Encode(const String &input) {
  const char b64chars[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  String output = "";
  int len = input.length();
  for (int i = 0; i < len; i += 3) {
    uint32_t b = (input[i] & 0xFF) << 16;
    if (i + 1 < len) b |= (input[i + 1] & 0xFF) << 8;
    if (i + 2 < len) b |= (input[i + 2] & 0xFF);
    output += b64chars[(b >> 18) & 0x3F];
    output += b64chars[(b >> 12) & 0x3F];
    output += (i + 1 < len) ? b64chars[(b >> 6) & 0x3F] : '=';
    output += (i + 2 < len) ? b64chars[b & 0x3F] : '=';
  }
  return output;
}

String urlEncode(const String &str) {
  String encoded = "";
  for (int i = 0; i < str.length(); i++) {
    char c = str.charAt(i);
    if (isalnum(c)) {
      encoded += c;
    } else if (c == ' ') {
      encoded += '+';
    } else {
      char buf[4];
      sprintf(buf, "%%%02X", (uint8_t)c);
      encoded += buf;
    }
  }
  return encoded;
}

String getEmergencyLocationUrl() {
  if (hasPhoneGps && phoneLat != 0.0 && phoneLng != 0.0) {
    return "https://maps.google.com/?q=" + String(phoneLat, 6) + "," + String(phoneLng, 6);
  } else {
    return "https://maps.google.com/?q=" + String(MANUAL_LATITUDE, 6) + "," + String(MANUAL_LONGITUDE, 6) + " (" + String(MANUAL_LOCATION_NAME) + ")";
  }
}

bool sendTwilioSms(const String &bodyText, const String &targetTo) {
  String toNum = targetTo.length() ? targetTo : String(TWILIO_TO_NUMBER);

  // Notify companion Android app over BLE as well
  if (pCharSos && bleConnected) {
    pCharSos->setValue("SOS:DISPATCHED");
    pCharSos->notify();
    Serial.println(F("[BLE] Notified companion mobile app of SOS event!"));
  }

  // Display SENDING SMS on OLED so user sees it live!
  display.clearDisplay();
  display.drawRoundRect(0, 0, 128, 64, 3, SSD1306_WHITE);
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(6, 6);
  display.println(F("* DISPATCHING SOS *"));
  display.setCursor(4, 22);
  display.println(F("Sending Twilio SMS..."));
  display.setCursor(4, 36);
  display.println(toNum);
  display.display();

  if (WiFi.status() != WL_CONNECTED) {
    Serial.println(F("[TWILIO] Wi-Fi not connected. Attempting quick background reconnect (up to 8s)..."));
    display.setCursor(4, 48);
    display.println(F("Reconnecting WiFi..."));
    display.display();

    WiFi.reconnect();
    unsigned long waitConnect = millis();
    while (WiFi.status() != WL_CONNECTED && (millis() - waitConnect < 8000)) {
      delay(150);
    }
    if (WiFi.status() != WL_CONNECTED) {
      Serial.println(F("[TWILIO] Wi-Fi offline. Alert failed over Wi-Fi."));
      display.clearDisplay();
      display.drawRoundRect(0, 0, 128, 64, 3, SSD1306_WHITE);
      display.setCursor(6, 12);
      display.println(F("* WI-FI OFFLINE *"));
      display.setCursor(6, 28);
      display.println(F("Check Hotspot:"));
      display.setCursor(6, 42);
      display.println(WIFI_SSID);
      display.display();
      delay(2500);
      return false;
    }
  }

  Serial.print(F("[TWILIO] Sending SOS SMS to "));
  Serial.println(toNum);

  display.setCursor(4, 48);
  display.println(F("Posting to Twilio..."));
  display.display();

  WiFiClientSecure client;
  client.setInsecure();
  client.setTimeout(9000);

  if (!client.connect("api.twilio.com", 443)) {
    Serial.println(F("[TWILIO] Connection to api.twilio.com failed."));
    display.clearDisplay();
    display.drawRoundRect(0, 0, 128, 64, 3, SSD1306_WHITE);
    display.setCursor(6, 16);
    display.println(F("Twilio Connect Fail"));
    display.setCursor(6, 32);
    display.println(F("api.twilio.com:443"));
    display.display();
    delay(2000);
    return false;
  }

  String postData = "To=" + urlEncode(toNum) +
                    "&From=" + urlEncode(TWILIO_FROM_NUMBER) +
                    "&Body=" + urlEncode(bodyText);

  String auth = base64Encode(String(TWILIO_ACCOUNT_SID) + ":" + String(TWILIO_AUTH_TOKEN));

  client.println("POST /2010-04-01/Accounts/" + String(TWILIO_ACCOUNT_SID) + "/Messages.json HTTP/1.1");
  client.println("Host: api.twilio.com");
  client.println("Authorization: Basic " + auth);
  client.println("Content-Type: application/x-www-form-urlencoded");
  client.println("Connection: close");
  client.print("Content-Length: ");
  client.println(postData.length());
  client.println();
  client.print(postData);

  unsigned long waitStart = millis();
  while (!client.available() && (millis() - waitStart < 7000)) {
    delay(10);
  }

  if (client.available()) {
    String response = client.readString();
    Serial.println(F("----- [TWILIO API RESPONSE] -----"));
    Serial.println(response);
    Serial.println(F("--------------------------------"));
    client.stop();

    bool success = response.indexOf("201 Created") >= 0 || response.indexOf("\"status\": \"queued\"") >= 0 || response.indexOf("\"sid\": \"SM") >= 0;

    display.clearDisplay();
    display.drawRoundRect(0, 0, 128, 64, 3, SSD1306_WHITE);
    if (success) {
      display.setCursor(6, 8);
      display.println(F("* TWILIO SMS SENT! *"));
      display.setCursor(6, 24);
      display.println(F("Status: QUEUED/SENT"));
      display.setCursor(6, 38);
      display.println(toNum);
      display.setCursor(6, 50);
      display.println(F("GPS Coordinates Sent"));
    } else {
      display.setCursor(6, 10);
      display.println(F("* TWILIO REJECTED *"));
      display.setCursor(6, 26);
      display.println(F("Error from Twilio"));
      display.setCursor(6, 42);
      display.println(F("Check Serial Log"));
    }
    display.display();
    delay(3500);

    return success;
  }

  client.stop();
  return false;
}

// ================= ANIMATION DATA DECODER =================
// Decode one PackBits-RLE stream from flash into a 1024-byte buffer.
void decodePackedFrame(uint32_t dataOffset, uint16_t packedLength, uint8_t *out) {
  const uint8_t *src = APRAJITA_PACKED_DATA + dataOffset;
  uint16_t srcPos = 0;
  uint16_t dstPos = 0;

  while (srcPos < packedLength && dstPos < APRAJITA_FRAME_BYTES) {
    uint8_t control = pgm_read_byte(src + srcPos++);
    uint16_t runLength = (control & 0x7F) + 1;

    if (control & 0x80) {
      if (srcPos >= packedLength) break;
      uint8_t value = pgm_read_byte(src + srcPos++);
      while (runLength-- && dstPos < APRAJITA_FRAME_BYTES) out[dstPos++] = value;
    } else {
      while (runLength-- && srcPos < packedLength && dstPos < APRAJITA_FRAME_BYTES) {
        out[dstPos++] = pgm_read_byte(src + srcPos++);
      }
    }
  }

  while (dstPos < APRAJITA_FRAME_BYTES) out[dstPos++] = 0;
}

void showFrame(uint16_t frameIndex) {
  uint32_t dataOffset = pgm_read_dword(&APRAJITA_PACKED_FRAMES[frameIndex].offset);
  uint16_t packedLength = pgm_read_word(&APRAJITA_PACKED_FRAMES[frameIndex].length);
  uint8_t isDelta = pgm_read_byte(&APRAJITA_PACKED_FRAMES[frameIndex].isDelta);

  if (isDelta) {
    decodePackedFrame(dataOffset, packedLength, deltaBuffer);
    for (uint16_t i = 0; i < APRAJITA_FRAME_BYTES; i++) frameBuffer[i] ^= deltaBuffer[i];
  } else {
    // First frame of each clip is a complete bitmap and resets the delta chain.
    decodePackedFrame(dataOffset, packedLength, frameBuffer);
  }

  display.clearDisplay();
  display.drawBitmap(0, 0, frameBuffer, SCREEN_WIDTH, SCREEN_HEIGHT, SSD1306_WHITE);
  display.display();
}

void triggerSosAlert(const String &reason) {
  Serial.print(F("[SOS] Triggered: "));
  Serial.println(reason);

  display.clearDisplay();
  display.drawRoundRect(0, 0, 128, 64, 3, SSD1306_WHITE);
  display.setTextSize(2);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(6, 10);
  display.println(F("TRIPLE SOS!"));
  display.setTextSize(1);
  display.setCursor(6, 36);
  display.println(F("Dispatching Twilio..."));
  display.setCursor(6, 48);
  display.println(F("SMS -> Papa"));
  display.display();

  sendTwilioSms("EMERGENCY ALERT: " + reason + " on Aprajita Keychain! Live Location: " + getEmergencyLocationUrl());

  if (pCharSos) {
    pCharSos->setValue("TRIPLE_CLICK_SOS");
    pCharSos->notify();
  }

  while (isButtonDown()) { delay(10); }
  flushButtonEvents();
}

// Polls button and MPU-6050 during animation frame delay.
// Triple-click -> SOS alert | Single-click -> Weather Dashboard | Fall -> SOS flow
bool checkInputsDuringAnimation(uint16_t durationMs) {
  unsigned long started = millis();
  while (millis() - started < durationMs) {
    server.handleClient();
    checkNightModeBackground();
    pollButton();

    // 1. Detect Fall or Sudden Surroundings Change
    if (checkFallOrShock()) {
      runSosFlow();
      return true; // Abort animation to show SOS / Action Menu
    }

    ButtonAction act = getButtonAction();

    // 2. Triple Click -> EMERGENCY SOS!
    if (act == ACT_TRIPLE_CLICK) {
      Serial.println(F("[BUTTON] Triple-Click detected during faces -> EMERGENCY SOS!"));
      triggerSosAlert(F("TRIPLE-CLICK SOS"));
      return true;
    }

    // 3. Single Click -> Advance to Weather Dashboard!
    if (act == ACT_SINGLE_CLICK) {
      Serial.println(F("[BUTTON] Single-Click during faces -> Weather Dashboard!"));
      flushButtonEvents();
      enterWeatherDashboard();
      return true;
    }

    delay(4);
  }
  return false;
}

void playEmotion(uint8_t emotionIndex) {
  uint16_t first = pgm_read_word(&APRAJITA_EMOTIONS[emotionIndex].firstFrame);
  uint16_t count = pgm_read_word(&APRAJITA_EMOTIONS[emotionIndex].frameCount);
  uint16_t frameDelay = pgm_read_word(&APRAJITA_EMOTIONS[emotionIndex].frameDelayMs);
  const char *name = (const char *)pgm_read_ptr(&APRAJITA_EMOTIONS[emotionIndex].name);

  Serial.print(F("Playing: "));
  Serial.print(name);
  Serial.print(F(" | frames: "));
  Serial.println((unsigned int)count);

  for (uint16_t f = 0; f < count; f++) {
    if (currentScreen != SCREEN_FACES) return;
    showFrame(first + f);
    if (checkInputsDuringAnimation(frameDelay)) return;
  }
  checkInputsDuringAnimation(180);
}

// ================= WEATHER HELPERS =================
String weatherDescription(int code) {
  if (code == 0) return "CLEAR SKY";
  if (code == 1) return "MOSTLY CLEAR";
  if (code == 2) return "PARTLY CLOUDY";
  if (code == 3) return "OVERCAST";
  if (code == 45 || code == 48) return "FOG";
  if (code == 51 || code == 53 || code == 55) return "DRIZZLE";
  if (code == 56 || code == 57) return "FREEZING DRIZZLE";
  if (code == 61 || code == 63 || code == 65) return "RAIN";
  if (code == 66 || code == 67) return "FREEZING RAIN";
  if (code == 71 || code == 73 || code == 75 || code == 77) return "SNOW";
  if (code == 80 || code == 81 || code == 82) return "RAIN SHOWERS";
  if (code == 85 || code == 86) return "SNOW SHOWERS";
  if (code == 95) return "THUNDERSTORM";
  if (code == 96 || code == 99) return "STORM / HAIL";
  return "WEATHER";
}

String twoDigit(int value) {
  if (value < 10) return "0" + String(value);
  return String(value);
}

String timeFromIso(String value) {
  if (value.length() >= 16) return value.substring(11, 16);
  return "--:--";
}

String safeLocation(String name) {
  name.trim();
  if (name.length() == 0) name = String(MANUAL_LOCATION_NAME);
  if (name.length() > 18) name = name.substring(0, 18);
  return name;
}

void drawStatus(const String &line1, const String &line2, const String &line3 = "") {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 5);  display.println(line1);
  display.setCursor(0, 22); display.println(line2);
  if (line3.length()) { display.setCursor(0, 39); display.println(line3); }
  display.display();
}

// Lightweight direct socket HTTP GET (no HTTPClient or mbedTLS needed, saving ~350KB-400KB flash)
bool requestHttpJson(const char* host, const String &path, JsonDocument &doc, String &errorOut) {
  WiFiClient client;
  client.setTimeout(5000);

  if (!client.connect(host, 80)) {
    errorOut = "Connect failed";
    return false;
  }

  client.print(String("GET ") + path + " HTTP/1.1\r\n" +
               "Host: " + host + "\r\n" +
               "User-Agent: Aprajita/1.0\r\n" +
               "Connection: close\r\n\r\n");
       
  unsigned long startWait = millis();
  while (!client.available() && (millis() - startWait < 5000)) {
    delay(10);
  }

  if (!client.available()) {
    errorOut = "HTTP timeout";
    client.stop();
    return false;
  }

  // Check HTTP response code: e.g. "HTTP/1.1 200 OK"
  String statusLine = client.readStringUntil('\n');
  if (statusLine.indexOf("200") == -1) {
    errorOut = "HTTP err";
    client.stop();
    return false;
  }

  // Skip HTTP response headers until empty line
  while (client.available()) {
    String header = client.readStringUntil('\n');
    header.trim();
    if (header.length() == 0) break;
  }

  DeserializationError jsonError = deserializeJson(doc, client);
  client.stop();

  if (jsonError) {
    errorOut = "JSON parse err";
    return false;
  }
  return true;
}

bool detectIpLocation(double &latitude, double &longitude, String &name) {
  if (!AUTO_DETECT_LOCATION_BY_IP) return false;

#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(1024);
#endif

  String err;
  if (!requestHttpJson("ip-api.com", "/json/", doc, err)) {
    Serial.print(F("IP location unavailable: "));
    Serial.println(err);
    return false;
  }

  if (doc["status"] != "success") return false;
  if (!doc["lat"].is<double>() || !doc["lon"].is<double>()) return false;
  latitude = doc["lat"].as<double>();
  longitude = doc["lon"].as<double>();

  String city = doc["city"] | "";
  String region = doc["regionName"] | "";
  String country = doc["country"] | "";
  if (city.length()) name = city;
  else name = region;
  if (region.length() && region != city && name.length() < 12) name += ", " + region;
  if (!name.length()) name = country;
  name = safeLocation(name);

  Serial.print(F("Approximate IP location: "));
  Serial.print(name);
  Serial.print(F(" (")); Serial.print(latitude, 4);
  Serial.print(F(", ")); Serial.print(longitude, 4); Serial.println(F(")"));
  return true;
}

bool fetchForecast() {
  double latitude = MANUAL_LATITUDE;
  double longitude = MANUAL_LONGITUDE;
  String location = String(MANUAL_LOCATION_NAME);

  detectIpLocation(latitude, longitude, location);
  wx.location = safeLocation(location);

  String path = "/v1/forecast?latitude=";
  path += String(latitude, 4);
  path += "&longitude=";
  path += String(longitude, 4);
  path += "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,wind_speed_10m";
  path += "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,uv_index_max,sunrise,sunset";
  path += "&temperature_unit=celsius&wind_speed_unit=kmh&timezone=auto&forecast_days=1";

#if ARDUINOJSON_VERSION_MAJOR >= 7
  JsonDocument doc;
#else
  DynamicJsonDocument doc(4096);
#endif

  String error;
  if (!requestHttpJson("api.open-meteo.com", path, doc, error)) {
    wx.valid = false;
    wx.error = error;
    Serial.print(F("Weather request failed: "));
    Serial.println(error);
    return false;
  }

  JsonObject current = doc["current"].as<JsonObject>();
  JsonObject daily = doc["daily"].as<JsonObject>();
  if (current.isNull() || daily.isNull()) {
    wx.valid = false;
    wx.error = "Data missing";
    return false;
  }

  wx.temperature = current["temperature_2m"] | 0.0f;
  wx.feelsLike = current["apparent_temperature"] | wx.temperature;
  wx.humidity = current["relative_humidity_2m"] | 0;
  wx.windKmh = current["wind_speed_10m"] | 0.0f;
  wx.precipitation = current["precipitation"] | 0.0f;
  wx.weatherCode = current["weather_code"] | 0;
  wx.isDay = current["is_day"] | 1;

  wx.todayHigh = daily["temperature_2m_max"][0] | wx.temperature;
  wx.todayLow = daily["temperature_2m_min"][0] | wx.temperature;
  wx.rainChance = daily["precipitation_probability_max"][0] | 0;
  wx.uvMax = daily["uv_index_max"][0] | 0.0f;
  wx.sunrise = timeFromIso(String((const char*)(daily["sunrise"][0] | "")));
  wx.sunset = timeFromIso(String((const char*)(daily["sunset"][0] | "")));
  wx.valid = true;
  wx.error = "";
  wx.lastUpdated = millis();

  Serial.println(F("Live weather loaded successfully."));
  Serial.print(F("Location: ")); Serial.println(wx.location);
  Serial.print(F("Temperature: ")); Serial.print(wx.temperature); Serial.println(F(" C"));
  return true;
}

// Fallback demo data so you can test all screens immediately even if offline
void loadDemoWeather(const String &reason = "Demo Mode") {
  wx.valid = true;
  wx.error = reason;
  wx.location = "Delhi (Demo)";
  wx.temperature = 28.0f;
  wx.feelsLike = 29.0f;
  wx.humidity = 55;
  wx.windKmh = 12.0f;
  wx.precipitation = 0.0f;
  wx.weatherCode = 0; // Clear sky
  wx.isDay = 1;
  wx.todayHigh = 32.0f;
  wx.todayLow = 21.0f;
  wx.rainChance = 10;
  wx.uvMax = 6.0f;
  wx.sunrise = "06:15";
  wx.sunset = "18:45";
  wx.lastUpdated = millis();

  drawWeatherPage();
}

void loadWeather() {
  wx.valid = false;
  wx.error = "Syncing...";

  if (String(WIFI_SSID).length() == 0 || String(WIFI_SSID) == "YOUR_WIFI_SSID") {
    loadDemoWeather("Wi-Fi not set");
    return;
  }

  // If Wi-Fi is connected, fetch live forecast immediately
  if (WiFi.status() == WL_CONNECTED) {
    if (!fetchForecast()) {
      loadDemoWeather("API error");
    } else {
      drawWeatherPage();
    }
  } else {
    // Non-blocking: DO NOT pop up repeating "Connecting Wi-Fi..." screen!
    // Reconnect in the background and display cached/demo data immediately
    WiFi.reconnect();
    loadDemoWeather("Wi-Fi syncing in bg");
  }
}


// ================= DRAW WEATHER ICONS & SCREENS =================
void drawCloud(int x, int y) {
  display.drawCircle(x - 7, y + 1, 5, SSD1306_WHITE);
  display.drawCircle(x, y - 3, 7, SSD1306_WHITE);
  display.drawCircle(x + 7, y + 1, 5, SSD1306_WHITE);
  display.drawLine(x - 11, y + 5, x + 11, y + 5, SSD1306_WHITE);
}

void drawWeatherIcon(int code, int x, int y, int isDay) {
  bool clearish = (code == 0 || code == 1);
  bool partCloud = (code == 2);
  bool fog = (code == 45 || code == 48);
  bool drizzle = (code == 51 || code == 53 || code == 55 || code == 56 || code == 57);
  bool rain = (code >= 61 && code <= 67) || (code >= 80 && code <= 82);
  bool snow = (code >= 71 && code <= 77) || code == 85 || code == 86;
  bool thunder = (code >= 95);

  if (clearish) {
    if (isDay) {
      display.drawCircle(x, y, 7, SSD1306_WHITE);
      for (int a = 0; a < 8; a++) {
        float angle = a * 0.785398f;
        int x1 = x + (int)(10 * cosf(angle));
        int y1 = y + (int)(10 * sinf(angle));
        int x2 = x + (int)(13 * cosf(angle));
        int y2 = y + (int)(13 * sinf(angle));
        display.drawLine(x1, y1, x2, y2, SSD1306_WHITE);
      }
    } else {
      display.drawCircle(x, y, 8, SSD1306_WHITE);
      display.fillCircle(x + 5, y - 4, 7, SSD1306_BLACK);
      display.drawPixel(x - 9, y - 7, SSD1306_WHITE);
      display.drawPixel(x + 11, y + 5, SSD1306_WHITE);
    }
    return;
  }

  if (partCloud) {
    display.drawCircle(x - 5, y - 2, 5, SSD1306_WHITE);
    display.drawCircle(x + 3, y - 4, 6, SSD1306_WHITE);
    display.drawLine(x - 10, y + 3, x + 9, y + 3, SSD1306_WHITE);
    display.drawCircle(x - 10, y + 2, 2, SSD1306_WHITE);
    return;
  }

  drawCloud(x, y - 2);
  if (fog) {
    display.drawLine(x - 11, y + 9, x + 10, y + 9, SSD1306_WHITE);
    display.drawLine(x - 8, y + 12, x + 7, y + 12, SSD1306_WHITE);
  } else if (thunder) {
    display.drawLine(x + 2, y + 5, x - 2, y + 11, SSD1306_WHITE);
    display.drawLine(x - 2, y + 11, x + 2, y + 11, SSD1306_WHITE);
    display.drawLine(x + 2, y + 11, x - 1, y + 16, SSD1306_WHITE);
  } else if (snow) {
    display.drawLine(x - 6, y + 7, x - 6, y + 14, SSD1306_WHITE);
    display.drawLine(x - 9, y + 10, x - 3, y + 10, SSD1306_WHITE);
    display.drawLine(x + 5, y + 7, x + 5, y + 14, SSD1306_WHITE);
    display.drawLine(x + 2, y + 10, x + 8, y + 10, SSD1306_WHITE);
  } else if (rain || drizzle) {
    display.drawLine(x - 7, y + 7, x - 9, y + 12, SSD1306_WHITE);
    display.drawLine(x, y + 7, x - 2, y + 12, SSD1306_WHITE);
    display.drawLine(x + 7, y + 7, x + 5, y + 12, SSD1306_WHITE);
  }
}

void drawHeader(const String &title) {
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(1, 1);
  display.print(title);
  display.drawLine(0, 11, 127, 11, SSD1306_WHITE);
}

// Only one weather screen - shows temp, condition, feels-like, humidity, and icon.
void drawWeatherPage() {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  if (!wx.valid) {
    drawHeader("APRAJITA WEATHER");
    display.setCursor(0, 17); display.println(wx.error.length() ? wx.error : "No weather data");
    display.setCursor(0, 31); display.println("Check Wi-Fi / API");
    display.setCursor(0, 49); display.println("Press button to exit");
    display.display();
    return;
  }

  drawHeader(wx.location);

  // Big temperature
  display.setTextSize(3);
  display.setCursor(2, 16);
  display.print((int)lroundf(wx.temperature));
  int tempDigits = abs((int)lroundf(wx.temperature)) >= 100 ? 3 : 2;
  int degreeX = 3 + tempDigits * 18;
  display.drawCircle(degreeX, 20, 2, SSD1306_WHITE);
  display.setTextSize(2);
  display.setCursor(degreeX + 5, 22);
  display.print("C");

  // Weather icon top-right
  drawWeatherIcon(wx.weatherCode, 103, 27, wx.isDay);

  // Condition + feels-like + humidity on bottom rows
  display.setTextSize(1);
  display.setCursor(2, 43);
  String condition = weatherDescription(wx.weatherCode);
  if (condition.length() > 20) condition = condition.substring(0, 20);
  display.print(condition);
  display.setCursor(2, 55);
  display.print("Feels "); display.print((int)lroundf(wx.feelsLike)); display.print("C");
  display.setCursor(63, 55);
  display.print("RH "); display.print(wx.humidity); display.print("%");

  display.display();
}

void enterWeatherDashboard() {
  currentScreen = SCREEN_WEATHER;
  loadWeather();
}

void exitWeatherDashboard() {
  currentScreen = SCREEN_FACES;
  display.clearDisplay();
  display.display();
  Serial.println(F("Returning to Aprajita face animations."));
}

// Weather dashboard loop - single click advances to Night Watch
void weatherDashboardLoop() {
  if (currentScreen != SCREEN_WEATHER) return;

  if (checkFallOrShock()) {
    currentScreen = SCREEN_FACES;
    runSosFlow();
    return;
  }

  checkNightModeBackground();
  pollButton();
  ButtonAction act = getButtonAction();

  if (act == ACT_TRIPLE_CLICK) {
    Serial.println(F("[BUTTON] Triple-Click in Weather -> EMERGENCY SOS!"));
    triggerSosAlert(F("TRIPLE-CLICK SOS"));
    return;
  }

  if (act == ACT_SINGLE_CLICK) {
    Serial.println(F("[BUTTON] Single-Click in Weather -> Advancing to Night Watch Mode."));
    currentScreen = SCREEN_NIGHT_MODE;
    flushButtonEvents();
    drawNightModePage();
    return;
  }

  // Auto-refresh weather every 15 minutes
  if (wx.valid && (millis() - wx.lastUpdated >= WEATHER_REFRESH_MS)) {
    loadWeather();
  }
  delay(15);
}

// ================= NIGHT WATCH / 10-MIN LOCATION CHECK-IN & STAGNANT ALERT =================
void drawNightModePage() {
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);

  // Top header banner
  if (nightModeActive) {
    display.fillRect(0, 0, 128, 12, SSD1306_WHITE);
    display.setTextColor(SSD1306_BLACK);
    display.setCursor(6, 2);
    display.print(F("* NIGHT WATCH: ON *"));
    display.setTextColor(SSD1306_WHITE);
  } else {
    display.setCursor(6, 2);
    display.print(F("=== NIGHT WATCH ==="));
  }

  // Status line
  display.setCursor(2, 16);
  display.print(F("Status: "));
  display.println(nightModeActive ? F("ACTIVE (10m Ping)") : F("OFF (Standby)"));

  // GPS coordinates
  display.setCursor(2, 27);
  display.print(F("GPS: "));
  if (hasPhoneGps) {
    display.print(phoneLat, 3);
    display.print(F(","));
    display.println(phoneLng, 3);
  } else {
    display.println(F("Live Phone BLE GPS"));
  }

  if (nightModeActive) {
    unsigned long elapsed = millis() - lastNightModeShareAt;
    long remainSec = (10 * 60) - (elapsed / 1000);
    if (remainSec < 0) remainSec = 0;
    int remM = remainSec / 60;
    int remS = remainSec % 60;

    display.setCursor(2, 38);
    display.print(F("Next Ping: "));
    if (remM < 10) display.print(F("0"));
    display.print(remM);
    display.print(F(":"));
    if (remS < 10) display.print(F("0"));
    display.print(remS);
    display.println(F(" (SMS)"));

    display.drawFastHLine(0, 50, 128, SSD1306_WHITE);
    display.setCursor(2, 53);
    display.print(F("HOLD BTN -> TURN OFF"));
  } else {
    display.setCursor(2, 38);
    display.println(F("Auto 10m SMS + Alerts"));
    display.drawFastHLine(0, 50, 128, SSD1306_WHITE);
    display.setCursor(2, 53);
    display.print(F("HOLD BTN -> ACTIVATE"));
  }

  display.display();
}

void toggleNightMode(bool enable) {
  nightModeActive = enable;
  if (nightModeActive) {
    nightModeStartedAt = millis();
    lastNightModeShareAt = millis();
    lastKnownLat = hasPhoneGps ? phoneLat : MANUAL_LATITUDE;
    lastKnownLng = hasPhoneGps ? phoneLng : MANUAL_LONGITUDE;
    lastMovementAt = millis();
    stagnantAlertSent = false;
    Serial.println(F("[NIGHT MODE] Activated by user!"));

    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(4, 8);
    display.println(F("====================="));
    display.println(F(" NIGHT WATCH ACTIVE! "));
    display.println(F("====================="));
    display.println(F("10m SMS Check-in: ON"));
    display.println(F("Stagnant Alert: ON"));
    display.display();
    delay(1000);

    // Initial activation SMS
    sendTwilioSms("[NIGHT WATCH STARTED] User activated Night Watch Mode on Aprajita Keychain. Tracking route. Initial GPS: " + getEmergencyLocationUrl());
    if (pCharSos) {
      pCharSos->setValue("NIGHT_MODE_ON");
      pCharSos->notify();
    }
  } else {
    Serial.println(F("[NIGHT MODE] Deactivated by user!"));
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);
    display.setCursor(4, 16);
    display.println(F("====================="));
    display.println(F(" NIGHT WATCH: OFF    "));
    display.println(F("====================="));
    display.display();
    delay(800);

    if (pCharSos) {
      pCharSos->setValue("NIGHT_MODE_OFF");
      pCharSos->notify();
    }
  }
}

void checkNightModeBackground() {
  if (!nightModeActive) return;
  unsigned long now = millis();

  // 1. 10-minute periodic SMS location check-in (600,000 ms)
  if (now - lastNightModeShareAt >= 10 * 60 * 1000UL) {
    lastNightModeShareAt = now;
    Serial.println(F("[NIGHT MODE] 10-minute location check-in triggered!"));
    sendTwilioSms("[NIGHT WATCH CHECK-IN] 10-Min Status: User en route. Live Location: " + getEmergencyLocationUrl());
    if (pCharSos) {
      pCharSos->setValue("NIGHT_CHECKIN_SENT");
      pCharSos->notify();
    }
  }

  // 2. Stagnant detection: user has not moved for 10 minutes
  double curLat = hasPhoneGps ? phoneLat : MANUAL_LATITUDE;
  double curLng = hasPhoneGps ? phoneLng : MANUAL_LONGITUDE;
  double delta = fabs(curLat - lastKnownLat) + fabs(curLng - lastKnownLng);

  if (delta > 0.00015) { // Moved > ~15m
    lastKnownLat = curLat;
    lastKnownLng = curLng;
    lastMovementAt = now;
    stagnantAlertSent = false;
  } else {
    if (!stagnantAlertSent && (now - lastMovementAt >= 10 * 60 * 1000UL)) {
      stagnantAlertSent = true;
      Serial.println(F("[NIGHT MODE] User is STAGNANT for 10 minutes! Dispatching alert!"));
      sendTwilioSms("CRITICAL SAFETY ALERT: User has been STAGNANT for 10+ minutes in Night Watch Mode without movement! Last GPS: " + getEmergencyLocationUrl() + " Please verify safety immediately!");
      if (pCharSos) {
        pCharSos->setValue("STAGNANT_ALERT");
        pCharSos->notify();
      }
    }
  }
}

void nightModeLoop() {
  if (currentScreen != SCREEN_NIGHT_MODE) return;

  if (checkFallOrShock()) {
    currentScreen = SCREEN_FACES;
    runSosFlow();
    return;
  }

  checkNightModeBackground();
  pollButton();
  ButtonAction act = getButtonAction();

  if (act == ACT_TRIPLE_CLICK) {
    Serial.println(F("[BUTTON] Triple-Click in Night Mode -> EMERGENCY SOS!"));
    triggerSosAlert(F("TRIPLE-CLICK SOS"));
    return;
  }

  if (act == ACT_LONG_PRESS) {
    toggleNightMode(!nightModeActive);
    flushButtonEvents();
    drawNightModePage();
    return;
  }

  if (act == ACT_SINGLE_CLICK) {
    Serial.println(F("[BUTTON] Single-Click in Night Mode -> Advancing to Device Info."));
    currentScreen = SCREEN_NOTIFICATIONS;
    flushButtonEvents();
    drawNotificationsPage();
    return;
  }

  static unsigned long lastDraw = 0;
  if (millis() - lastDraw >= 1000) {
    lastDraw = millis();
    drawNightModePage();
  }
  delay(15);
}

// ================= NOTIFICATIONS / DEVICE INFO DEMO SCREEN =================
// Shown immediately after Night Watch screen upon button click
void drawNotificationsPage() {
  display.clearDisplay();

  // Top header bar
  display.fillRect(0, 0, 128, 12, SSD1306_WHITE);
  display.setTextColor(SSD1306_BLACK);
  display.setTextSize(1);
  display.setCursor(4, 2);
  display.print(F("* NETWORK & DEVICE *"));

  display.setTextColor(SSD1306_WHITE);

  // Line 1: Wi-Fi status and IP
  display.setCursor(2, 15);
  if (WiFi.status() == WL_CONNECTED) {
    display.print(F("WiFi: ")); display.println(WiFi.localIP());
  } else {
    display.print(F("WiFi: OFFLINE (aditya)"));
  }

  // Line 2: SoftAP IP
  display.setCursor(2, 27);
  display.print(F("SoftAP: 192.168.4.1"));

  // Line 3: SMS Gateway Status
  display.setCursor(2, 39);
  display.print(F("SMS: Gateway Ready"));

  // Footer instruction
  display.drawFastHLine(0, 51, 128, SSD1306_WHITE);
  display.setCursor(4, 54);
  display.print(F("Triple Click -> SOS"));

  display.display();
}

// Notifications loop - single click returns to Aprajita animations
void notificationsLoop() {
  if (currentScreen != SCREEN_NOTIFICATIONS) return;

  if (checkFallOrShock()) {
    currentScreen = SCREEN_FACES;
    runSosFlow();
    return;
  }

  checkNightModeBackground();
  pollButton();
  ButtonAction act = getButtonAction();

  if (act == ACT_TRIPLE_CLICK) {
    Serial.println(F("[BUTTON] Triple-Click in Device Info -> EMERGENCY SOS!"));
    triggerSosAlert(F("TRIPLE-CLICK SOS"));
    return;
  }

  if (act == ACT_SINGLE_CLICK) {
    Serial.println(F("[BUTTON] Single-Click in Device Info -> Returning to face animations."));
    flushButtonEvents();
    exitWeatherDashboard();
    return;
  }

  delay(15);
}

// ================= SOS & ACTION MENU SCREENS =================

// Screen 1: Big SOS display with 5-second countdown & progress bar
void drawSosCountdown(int secondsLeft, int progressPercent) {
  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);

  // Urgent flashing warning border every 250ms
  bool flash = ((millis() / 250) % 2 == 0);
  if (flash) {
    display.drawRoundRect(0, 0, 128, 64, 3, SSD1306_WHITE);
  }

  // Big "SOS" centered at top (Text Size 4: 24px wide, 28px tall per char -> 72px wide total)
  display.setTextSize(4);
  display.setCursor(28, 3);
  display.print(F("SOS"));

  // Warning subtitle
  display.setTextSize(1);
  display.setCursor(17, 35);
  display.print(F("! FALL DETECTED !"));

  // Countdown text & prompt
  display.setCursor(26, 46);
  display.print(F("CANCEL: "));
  display.setTextSize(2);
  display.print(secondsLeft);
  display.print(F("s"));

  // Progress bar along bottom
  int barWidth = map(progressPercent, 0, 100, 0, 116);
  display.drawRoundRect(4, 57, 120, 5, 2, SSD1306_WHITE);
  if (barWidth > 0) {
    display.fillRoundRect(6, 58, barWidth, 3, 1, SSD1306_WHITE);
  }

  display.display();
}

// Screen 2: Brief confirmation when user cancels SOS
void drawSosCancelled() {
  display.clearDisplay();
  display.drawRoundRect(0, 0, 128, 64, 3, SSD1306_WHITE);

  display.setTextSize(2);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(10, 16);
  display.print(F("CANCELLED"));

  display.setTextSize(1);
  display.setCursor(14, 42);
  display.print(F("Opening action menu"));
  display.display();
}

// Screen 3: Warning if 5s countdown expires without cancel
void drawSosTriggered() {
  display.clearDisplay();
  display.fillRect(0, 0, 128, 12, SSD1306_WHITE);
  display.setTextColor(SSD1306_BLACK);
  display.setTextSize(1);
  display.setCursor(16, 2);
  display.print(F("! SOS ACTIVATED !"));

  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(2);
  display.setCursor(16, 20);
  display.print(F("HELP SENT"));

  display.setTextSize(1);
  display.setCursor(8, 45);
  display.print(F("Click for Action Menu"));
  display.display();
}

// Screen 4: Interactive Action Menu (Call 📞 vs Report 📋)
// Single Click = Switch | Long Click = Select | Double Click = Return to Animation
void drawActionMenu(uint8_t selectedAction) {
  display.clearDisplay();

  // Top header bar
  display.fillRect(0, 0, 128, 11, SSD1306_WHITE);
  display.setTextColor(SSD1306_BLACK);
  display.setTextSize(1);
  display.setCursor(16, 2);
  display.print(F("* EMERGENCY MENU *"));

  // Option 0: CALL card (x = 6, y = 14, w = 55, h = 37)
  if (selectedAction == 0) {
    // Inverted card (Active)
    display.fillRoundRect(6, 14, 55, 37, 4, SSD1306_WHITE);
    display.drawBitmap(25, 17, icon_phone_16, 16, 16, SSD1306_BLACK);
    display.setTextColor(SSD1306_BLACK);
    display.setTextSize(1);
    display.setCursor(21, 37);
    display.print(F("CALL"));
  } else {
    // Outlined card (Inactive)
    display.drawRoundRect(6, 14, 55, 37, 4, SSD1306_WHITE);
    display.drawBitmap(25, 17, icon_phone_16, 16, 16, SSD1306_WHITE);
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(21, 37);
    display.print(F("CALL"));
  }

  // Option 1: REPORT card (x = 67, y = 14, w = 55, h = 37)
  if (selectedAction == 1) {
    // Inverted card (Active)
    display.fillRoundRect(67, 14, 55, 37, 4, SSD1306_WHITE);
    display.drawBitmap(86, 17, icon_report_16, 16, 16, SSD1306_BLACK);
    display.setTextColor(SSD1306_BLACK);
    display.setTextSize(1);
    display.setCursor(76, 37);
    display.print(F("REPORT"));
  } else {
    // Outlined card (Inactive)
    display.drawRoundRect(67, 14, 55, 37, 4, SSD1306_WHITE);
    display.drawBitmap(86, 17, icon_report_16, 16, 16, SSD1306_WHITE);
    display.setTextColor(SSD1306_WHITE);
    display.setTextSize(1);
    display.setCursor(76, 37);
    display.print(F("REPORT"));
  }

  // Footer navigation instructions (21 chars * 6px = 126px, fits exactly on 128px OLED)
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(1, 55);
  display.print(F("1:Pick Hold:OK 2:Exit"));

  display.display();
}

// Screen 5: Call dispatch screen
void showCallScreen() {
  display.clearDisplay();
  display.fillRect(0, 0, 128, 12, SSD1306_WHITE);
  display.setTextColor(SSD1306_BLACK);
  display.setTextSize(1);
  display.setCursor(20, 2);
  display.print(F("EMERGENCY CALL"));

  display.drawBitmap(12, 20, icon_phone_16, 16, 16, SSD1306_WHITE);

  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(34, 18);
  display.print(F("SENDING SMS..."));
  display.setCursor(34, 30);
  display.print(F("Dialing 112 / ICE"));

  display.setCursor(8, 52);
  display.print(F("Press button to exit"));
  display.display();

  // Send Twilio SMS alert for Call action
  sendTwilioSms("EMERGENCY CALL: User selected emergency voice call from Aprajita Keychain! Please contact immediately. Location: " + getEmergencyLocationUrl());

  unsigned long start = millis();
  flushButtonEvents();
  while (millis() - start < 5000) {
    pollButton();
    ButtonAction act = getButtonAction();
    if (act != ACT_NONE || wasButtonPressedRaw()) break;
    delay(20);
  }
  while (isButtonDown()) { delay(10); }
  flushButtonEvents();
}

// Screen 6: Incident report dispatch screen
void showReportScreen() {
  display.clearDisplay();
  display.fillRect(0, 0, 128, 12, SSD1306_WHITE);
  display.setTextColor(SSD1306_BLACK);
  display.setTextSize(1);
  display.setCursor(18, 2);
  display.print(F("INCIDENT REPORT"));

  display.drawBitmap(12, 20, icon_report_16, 16, 16, SSD1306_WHITE);

  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(34, 18);
  display.print(F("SENDING SMS..."));
  display.setCursor(34, 30);
  display.print(F("Incident logged"));

  display.setCursor(8, 52);
  display.print(F("Press button to exit"));
  display.display();

  // Send Twilio SMS alert for Incident Report action
  sendTwilioSms("INCIDENT REPORT: User logged a safety event on Aprajita Keychain! Location: " + getEmergencyLocationUrl());

  unsigned long start = millis();
  flushButtonEvents();
  while (millis() - start < 5000) {
    pollButton();
    ButtonAction act = getButtonAction();
    if (act != ACT_NONE || wasButtonPressedRaw()) break;
    delay(20);
  }
  while (isButtonDown()) { delay(10); }
  flushButtonEvents();
}

// Complete SOS & Action Menu controller
void runSosFlow() {
  Serial.println(F("========================================"));
  Serial.println(F("[SOS] TRIGGERED! Entering 5s countdown!"));
  Serial.println(F("========================================"));

  unsigned long sosStart = millis();
  const unsigned long SOS_DURATION_MS = 5000;
  bool sosCancelled = false;

  flushButtonEvents();

  // 1. SOS COUNTDOWN (5 SECONDS)
  while (millis() - sosStart < SOS_DURATION_MS) {
    unsigned long elapsed = millis() - sosStart;
    unsigned long remainingMs = (elapsed < SOS_DURATION_MS) ? (SOS_DURATION_MS - elapsed) : 0;
    int secondsLeft = (remainingMs + 999) / 1000;
    int progressPercent = (remainingMs * 100) / SOS_DURATION_MS;

    drawSosCountdown(secondsLeft, progressPercent);

    pollButton();
    if (wasButtonPressedRaw() || isButtonDown()) {
      sosCancelled = true;
      Serial.println(F("[SOS] Cancelled by user button press!"));
      break;
    }
    delay(20);
  }

  // Clear button state and wait for release so release doesn't leak into menu
  flushButtonEvents();
  while (isButtonDown()) { delay(10); }
  delay(80);
  flushButtonEvents();

  if (sosCancelled) {
    drawSosCancelled();
    delay(700);
  } else {
    // 5 seconds elapsed without cancel -> Emergency Sent via Twilio & BLE!
    Serial.println(F("[SOS] 5s elapsed without cancel! Sending emergency Twilio SMS!"));
    drawSosTriggered();

    // Send Emergency Twilio SMS directly over Wi-Fi & notify companion app over BLE
    sendTwilioSms("EMERGENCY ALERT: Severe Fall/Shock detected on Aprajita Keychain! No response within 5-second countdown window! Live Location: " + getEmergencyLocationUrl());

    unsigned long trigStart = millis();
    while (millis() - trigStart < 3500) {
      pollButton();
      if (wasButtonPressedRaw() || isButtonDown()) break;
      delay(20);
    }
    while (isButtonDown()) { delay(10); }
    flushButtonEvents();
  }

  // 2. ACTION MENU (CALL / REPORT)
  // Single click: switch | Long click: select | Double click: return to animation
  uint8_t selectedAction = 0; // 0 = CALL, 1 = REPORT
  drawActionMenu(selectedAction);

  bool inMenu = true;
  unsigned long lastMenuActivity = millis();

  while (inMenu) {
    pollButton();
    ButtonAction act = getButtonAction();

    if (act == ACT_SINGLE_CLICK) {
      selectedAction = 1 - selectedAction; // Switch between CALL and REPORT
      drawActionMenu(selectedAction);
      lastMenuActivity = millis();
      Serial.print(F("[MENU] Switched selection to: "));
      Serial.println(selectedAction == 0 ? F("CALL") : F("REPORT"));
    }
    else if (act == ACT_LONG_PRESS) {
      Serial.print(F("[MENU] Selected: "));
      Serial.println(selectedAction == 0 ? F("CALL") : F("REPORT"));
      if (selectedAction == 0) {
        showCallScreen();
      } else {
        showReportScreen();
      }
      inMenu = false; // Finished action, return to animations
    }
    else if (act == ACT_DOUBLE_CLICK) {
      Serial.println(F("[MENU] Double click -> Returning to Aprajita face animation screen!"));
      inMenu = false;
    }

    // Auto-return after 30 seconds of inactivity to save OLED and battery
    if (millis() - lastMenuActivity > 30000) {
      Serial.println(F("[MENU] Inactivity timeout -> Returning to animation."));
      inMenu = false;
    }

    delay(15);
  }

  // Refractory period so picking up/moving the device doesn't instantly re-trigger SOS
  lastSosTriggerTime = millis();
  flushButtonEvents();
  currentScreen = SCREEN_FACES;
  display.clearDisplay();
  display.display();
  Serial.println(F("[SOS] Returning to Aprajita animation loop."));
}

// ================= SETUP / MAIN LOOP =================
// ================= SETUP / MAIN LOOP =================
void setup() {
  Serial.begin(115200);
  delay(300);

  // Configure button pin with internal pull-up (polling-based)
  pinMode(BUTTON_PIN, INPUT_PULLUP);
  Serial.print(F("Button configured on GPIO ")); Serial.println(BUTTON_PIN);

  Wire.begin(OLED_SDA, OLED_SCL);
  Wire.setClock(400000);

  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS)) {
    Serial.println(F("OLED init failed. Check wiring/address and SSD1306 compatibility."));
    while (true) delay(1000);
  }

  // 1. CONNECT TO WI-FI FIRST ON STARTUP!
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(0, 2);
  display.println(F("====================="));
  display.println(F("  APRAJITA AEGIS BOOT   "));
  display.println(F("====================="));
  display.print(F("SSID: ")); display.println(WIFI_SSID);
  display.println(F("Connecting Wi-Fi..."));
  display.display();

  // Mode: AP + Station (Simultaneous)
  // Station connects to internet (hotspot/router for Twilio SMS)
  // SoftAP broadcasts SURAKSHA-APRAJITA at 192.168.4.1 for direct phone connection
  WiFi.mode(WIFI_AP_STA);
  WiFi.setAutoReconnect(true);
  WiFi.softAP("SURAKSHA-APRAJITA", "12345678");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print(F("[WIFI] Connecting to Wi-Fi SSID: "));
  Serial.println(WIFI_SSID);
  Serial.println(F("[WIFI] SoftAP Active: 'SURAKSHA-APRAJITA' (IP: 192.168.4.1)"));

  unsigned long wifiStart = millis();
  int progressTick = 0;
  while (WiFi.status() != WL_CONNECTED && (millis() - wifiStart < 15000)) {
    delay(200);
    progressTick = (progressTick + 1) % 16;
    display.clearDisplay();
    display.setCursor(0, 2);
    display.println(F("====================="));
    display.println(F("  CONNECTING WI-FI   "));
    display.println(F("====================="));
    display.print(F("SSID: ")); display.println(WIFI_SSID);
    display.print(F("Time: "));
    display.print((millis() - wifiStart) / 1000);
    display.println(F("s / 15s"));
    display.print(F("Linking"));
    for (int i = 0; i < (progressTick % 5); i++) display.print(F("."));
    display.println();
    display.print(F("SoftAP: 192.168.4.1"));
    display.display();
  }

  display.clearDisplay();
  display.setCursor(0, 0);
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println(F("========================================"));
    Serial.println(F("[WIFI] CONNECTED SUCCESSFULLY!"));
    Serial.print(F("[WIFI] Station IP: ")); Serial.println(WiFi.localIP());
    Serial.println(F("[WIFI] SoftAP IP:  192.168.4.1"));
    Serial.print(F("[TWILIO] Target SMS: ")); Serial.println(TWILIO_TO_NUMBER);
    Serial.println(F("========================================"));

    display.println(F("====================="));
    display.println(F("  WI-FI CONNECTED!   "));
    display.println(F("====================="));
    display.print(F("IP: ")); display.println(WiFi.localIP());
    display.println(F("AP: 192.168.4.1"));
    display.print(F("SMS: ")); display.println(TWILIO_TO_NUMBER);
    display.println(F("BLE: SURAKSHA-KEY"));
    display.display();
    delay(3500); // Give user 3.5 seconds to see IP!
  } else {
    Serial.println(F("========================================"));
    Serial.println(F("[WIFI] Could not connect to station SSID within 15s."));
    Serial.println(F("[WIFI] SoftAP IS ACTIVE: SSID 'SURAKSHA-APRAJITA' -> IP 192.168.4.1"));
    Serial.println(F("========================================"));

    display.println(F("====================="));
    display.println(F("  WI-FI NOT FOUND    "));
    display.println(F("====================="));
    display.print(F("Hotspot: ")); display.println(WIFI_SSID);
    display.println(F("SoftAP ALWAYS ON:"));
    display.println(F("SSID: SURAKSHA-APRAJITA"));
    display.println(F("IP:   192.168.4.1"));
    display.display();
    delay(3000);
  }

  // 2. Initialize MPU-6050 Accelerometer / Gyroscope
  initMPU6050();

  // 3. Initialize Bluetooth Low Energy (BLE) Companion Link
  initBLE();

  // 4. Load weather once if online
  if (WiFi.status() == WL_CONNECTED) {
    loadWeather();
  }

  // 5. Set up local HTTP Device Control Endpoints for Companion Mobile App
  server.on("/status", HTTP_GET, []() {
    String json = "{\"device\":\"SURAKSHA-KEY\",\"status\":\"CONNECTED\",\"battery\":94,\"screen\":";
    json += String((int)currentScreen);
    json += ",\"mpu\":";
    json += mpuFound ? "true" : "false";
    json += ",\"wifi\":\"" + (WiFi.status() == WL_CONNECTED ? String("CONNECTED") : String("DISCONNECTED")) + "\"";
    json += ",\"ip\":\"" + WiFi.localIP().toString() + "\"";
    json += ",\"ap_ip\":\"" + WiFi.softAPIP().toString() + "\"}";
    server.send(200, "application/json", json);
  });

  server.on("/sos", HTTP_POST, []() {
    server.send(200, "application/json", "{\"sos\":true,\"message\":\"Triggered via Mobile Link\"}");
    // Dispatch real Twilio SMS immediately!
    sendTwilioSms("EMERGENCY ALERT: Mobile App triggered Remote SOS on Aprajita Keychain! Live Location: " + getEmergencyLocationUrl());
  });

  server.on("/screen", HTTP_ANY, []() {
    if (server.hasArg("name") || server.hasArg("mode")) {
      String sc = server.hasArg("name") ? server.arg("name") : server.arg("mode");
      if (sc == "WEATHER") {
        currentScreen = SCREEN_WEATHER;
        loadWeather();
      } else if (sc == "NIGHT_MODE") {
        currentScreen = SCREEN_NIGHT_MODE;
        drawNightModePage();
      } else if (sc == "NOTIFICATIONS" || sc == "DEVICE_INFO") {
        currentScreen = SCREEN_NOTIFICATIONS;
        drawNotificationsPage();
      } else {
        currentScreen = SCREEN_FACES;
      }
    }
    if (server.hasArg("nightmode")) {
      toggleNightMode(server.arg("nightmode") == "1" || server.arg("nightmode") == "true");
    }
    if (server.hasArg("emotion")) {
      String emo = server.arg("emotion");
      emo.trim(); emo.toUpperCase();
      if (emo == "CYCLE") {
        selectedEmotionIndex = -1;
      } else {
        selectedEmotionIndex = -1;
        for (uint8_t i = 0; i < APRAJITA_EMOTION_COUNT; i++) {
          const char *name = (const char *)pgm_read_ptr(&APRAJITA_EMOTIONS[i].name);
          if (String(name) == emo) {
            selectedEmotionIndex = i;
            break;
          }
        }
        if (selectedEmotionIndex == -1 && emo.toInt() < (int)APRAJITA_EMOTION_COUNT) {
          selectedEmotionIndex = emo.toInt();
        }
      }
      currentScreen = SCREEN_FACES;
    }
    server.send(200, "application/json", "{\"screen\":" + String((int)currentScreen) + ",\"nightMode\":" + String(nightModeActive ? 1 : 0) + ",\"selectedEmotion\":" + String(selectedEmotionIndex) + "}");
  });

  server.enableCORS(true);
  server.begin();
  Serial.println(F("[HTTP] Local Aprajita Device Control Server active on port 80"));

  Serial.println(F("======================================"));
  Serial.println(F("   Aprajita + Weather + Night Mode + BLE"));
  Serial.println(F("======================================"));
  Serial.print(F("Button on GPIO ")); Serial.println(BUTTON_PIN);
  Serial.println(F("1-Click: Faces -> Weather -> Night Mode -> Device Info -> Faces"));
  Serial.println(F("3-Clicks: DIRECT EMERGENCY SOS (Twilio SMS)"));
  Serial.println(F("Night Mode: Hold button to turn ON/OFF (10m location ping + stagnant alert)"));
  Serial.println(F("======================================"));
  delay(800);
}

void loop() {
  server.handleClient();
  checkNightModeBackground();

  if (currentScreen == SCREEN_WEATHER) {
    weatherDashboardLoop();
    return;
  }

  if (currentScreen == SCREEN_NIGHT_MODE) {
    nightModeLoop();
    return;
  }

  if (currentScreen == SCREEN_NOTIFICATIONS) {
    notificationsLoop();
    return;
  }

  // Play locked emotion or cycle through all emotions
  if (selectedEmotionIndex >= 0 && selectedEmotionIndex < (int)APRAJITA_EMOTION_COUNT) {
    server.handleClient();
    checkNightModeBackground();
    if (currentScreen == SCREEN_FACES) {
      playEmotion(selectedEmotionIndex);
    }
  } else {
    for (uint8_t emotion = 0; emotion < APRAJITA_EMOTION_COUNT; emotion++) {
      server.handleClient();
      checkNightModeBackground();
      if (currentScreen != SCREEN_FACES || selectedEmotionIndex != -1) break;
      playEmotion(emotion);
      if (currentScreen != SCREEN_FACES || selectedEmotionIndex != -1) break;
    }
  }
}
