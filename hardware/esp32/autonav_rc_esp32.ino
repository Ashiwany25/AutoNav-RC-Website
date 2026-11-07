// AutoNav RC — ESP32 protocol-validation scaffold (NO MOTOR OUTPUT ENABLED)
// Requires Arduino-ESP32. No sensor, motor driver or encoder code is present.
// Wire a normally closed emergency-stop loop between GPIO27 and GND.
// OPEN loop => emergency stop. Do not substitute a software-only switch.
// This example is for desk testing SERIAL PROTOCOL ONLY, not autonomous motion.
#include <Arduino.h>

static constexpr uint8_t ESTOP_PIN = 27;
static constexpr unsigned long DEADLINE_MS = 250;
static constexpr size_t MAX_LINE = 96;
char linebuf[MAX_LINE + 1];
size_t count = 0;
char session[17] = {0};
uint32_t lastSeq = 0;
unsigned long lastDrive = 0;
bool armed = false;
bool moving = false;

// A real motor driver needs tested pin mapping, enable/disable logic and a
// physical E-STOP wired to the motor power stage. Intentionally disabled.
static void motorOutputDisabled(int left, int right) {
  (void)left;
  (void)right;
  // Never write motor GPIOs in this scaffold.
}

static void forceStop() {
  motorOutputDisabled(0, 0);
  moving = false;
  lastDrive = 0;
}

static void disarm() {
  forceStop();
  armed = false;
  session[0] = '\0';
}

static bool estopClosed() { return digitalRead(ESTOP_PIN) == LOW; }

static bool validNonce(const char* s) {
  if (strlen(s) != 16) return false;
  for (int i = 0; i < 16; ++i) {
    if (!((s[i] >= '0' && s[i] <= '9') || (s[i] >= 'a' && s[i] <= 'f')))
      return false;
  }
  return true;
}

static void handleLine(const char* raw) {
  if (strcmp(raw, "STOP") == 0) {
    disarm();
    Serial.println("STOPPED");
    return;
  }
  if (!estopClosed()) {
    disarm();
    Serial.println("ESTOP_OPEN");
    return;
  }
  char nonce[22] = {0};
  char trailing[2] = {0};
  if (sscanf(raw, "ARM %21s %1s", nonce, trailing) == 1 &&
      validNonce(nonce)) {
    disarm();
    strncpy(session, nonce, 16);
    session[16] = '\0';
    lastSeq = 0;
    armed = true;
    Serial.println("ARMED_PROTOCOL_ONLY");
    return;
  }
  unsigned long seq = 0;
  long left = 0, right = 0;
  int fields = sscanf(raw, "DRV %21s %lu %ld %ld %1s", nonce, &seq, &left, &right, trailing);
  if (fields == 4 && armed && strcmp(nonce, session) == 0 &&
      seq > lastSeq && seq <= UINT32_MAX &&
      left >= -100 && left <= 100 && right >= -100 && right <= 100) {
    lastSeq = static_cast<uint32_t>(seq);
    lastDrive = millis();
    moving = (left != 0 || right != 0);
    motorOutputDisabled(static_cast<int>(left), static_cast<int>(right));
    Serial.println("ACCEPTED_NO_MOTOR_OUTPUT");
    return;
  }
  disarm();
  Serial.println("REJECTED_DISARMED");
}

void setup() {
  pinMode(ESTOP_PIN, INPUT_PULLUP);
  Serial.begin(115200);
  disarm();
  Serial.println("AUTONAV_PROTOCOL_ONLY_MOTORS_DISABLED");
}

void loop() {
  if (!estopClosed()) disarm();
  if (armed && moving && (unsigned long)(millis() - lastDrive) >= DEADLINE_MS) {
    disarm();
    Serial.println("WATCHDOG_STOP");
  }
  while (Serial.available()) {
    char ch = static_cast<char>(Serial.read());
    if (ch == '\n') {
      linebuf[count] = '\0';
      handleLine(linebuf);
      count = 0;
    } else if (ch != '\r') {
      if (count >= MAX_LINE) {
        count = 0;
        disarm();
        Serial.println("OVERFLOW_STOP");
      } else {
        linebuf[count++] = ch;
      }
    }
  }
}
