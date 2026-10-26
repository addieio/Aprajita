# Aprajita, Weather & Safety Keychain — XIAO ESP32-C6 + OLED + MPU-6050

This Arduino project features:
- **18 Animated Emotion Clips** for Aprajita on a 128×64 SSD1306 OLED display.
- **Single-Screen Weather Dashboard** with real-time temperature, condition, feels-like, humidity, and weather icon.
- **Notifications Demo Screen** (3rd screen) displaying incoming notifications and system link status.
- **MPU-6050 Fall & Quick Movement Detection**: Automatically senses drops, impacts, and sudden environmental shocks.
- **SOS Emergency System**: 5-second countdown with visual progress bar and immediate button cancel.
- **Twilio Emergency SMS Dispatch**: Automatically dispatches distress SMS with live Google Maps coordinates.
- **Bluetooth (BLE) Companion Link**: Pairs with the **Aprajita Safety App** (`Aprajita_Companion_App.apk`) to stream live Phone GPS and trigger alerts.
- **Interactive Action Menu**: Switch between **CALL** (📞) and **REPORT** (📋) options, select with long-press, or return with double-click.
- **Non-Repeating Wi-Fi Connect**: Auto-connects once at startup without blocking or repeating connection screens.

---

## Hardware Wiring Table

| Component | Pin | XIAO ESP32-C6 Pin | Notes |
|---|---|---|---|
| **OLED** | GND | **GND** | Ground |
| **OLED** | VCC / VIN | **3V3** | 3.3V Power |
| **OLED** | SDA | **D4** (GPIO 22) | Shared I²C Data |
| **OLED** | SCL | **D5** (GPIO 23) | Shared I²C Clock |
| **MPU-6050** | GND | **GND** | Ground |
| **MPU-6050** | VCC | **3V3** | 3.3V Power |
| **MPU-6050** | SDA | **D4** (GPIO 22) | Shared I²C Data |
| **MPU-6050** | SCL | **D5** (GPIO 23) | Shared I²C Clock |
| **MPU-6050** | AD0 | **GND** (or 3V3) | Auto-detects 0x68 / 0x69 |
| **Push Button** | Leg 1 | **D2** (GPIO 2) | Active LOW (configurable) |
| **Push Button** | Leg 2 | **GND** | Ground |

---

## Screen & Button Navigation Flow

```
   [ Aprajita Face Animations ]
              │ (Click)
              ▼
    [ Weather Dashboard ]
              │ (Click)
              ▼
  [ Notifications Demo Page ]
              │ (Click)
              ▼
   [ Aprajita Face Animations ]
```

### 1. During Normal Animations (Aprajita Faces)
- **Single Press:** Opens the **Weather Dashboard**.
- **Fall / Rapid Shock Detected:** Instantly launches **Big SOS Countdown**.

### 2. Weather Dashboard
- **Single Press:** Advances to the **Notifications Demo Page**.
- **Fall Detected:** Immediately interrupts and launches **Big SOS Countdown**.

### 3. Notifications Demo Page
- Displays 3 notifications (`Mom: Reach home safe?`, `BLE: Paired & Armed`, `Twilio: SMS Online`).
- **Single Press:** Returns to **Aprajita Face Animations**.

### 4. SOS Countdown (5 Seconds)
- Screen shows big **SOS**, "FALL DETECTED!", countdown seconds (5s → 0s), and a progress bar.
- **Press Button within 5s:** Instantly **Cancels SOS** and opens the **Action Menu**.
- **If 5s Expires:** Emergency alert is triggered:
  - Dispatches **Twilio SMS** directly over Wi-Fi with live Google Maps link.
  - Notifies **Aprajita Mobile App** over BLE to dispatch alerts using phone network & GPS.

### 5. Action Menu (After Cancelling SOS)
- Two interactive cards: **CALL** (📞) and **REPORT** (📋).
- **Single Click:** Switch / toggle between **CALL** and **REPORT**.
- **Long Press (Hold ≥ 0.65s):** Select and trigger the highlighted action (Sends Twilio SMS alert).
- **Double Click:** Return directly to the **Aprajita Face Animations**!

---

## Android Companion App APK

The updated Android companion app is located at:
`c:\Users\adity\OneDrive\Documents\IIITDWOMENS\Aprajita_Companion_App.apk`

- Install it on your Android smartphone.
- It connects to the keychain via Bluetooth (`"SURAKSHA-KEY"`).
- Streams live high-accuracy Phone GPS coordinates to the keychain.
- Receives SOS events from the keychain and automatically dispatches emergency alerts with your live location.

---

## Required Libraries (Arduino IDE)
1. **Adafruit SSD1306**
2. **Adafruit GFX Library**
3. **ArduinoJson** (Version 6 or 7)
*(MPU-6050 uses direct lightweight I²C Wire commands — no extra bulky library needed!)*

---

## Uploading the Code
1. Open [`Aprajita_ESP32C6_Keychain.ino`](file:///c:/Users/adity/OneDrive/Documents/IIITDWOMENS/Aprajita_ESP32C6_Keychain/Aprajita_ESP32C6_Keychain.ino) in Arduino IDE.
2. Select Board: **Seeed Studio XIAO ESP32C6**.
3. Select your device's COM port.
4. Click **Upload**.
5. Open Serial Monitor at **115200 baud** to see real-time MPU sensor diagnostics, BLE pairing status, and button events.
