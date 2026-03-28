#include <EEPROM.h>
#include "Powerled.h"
#include "Interface.h"
#include "SimpleTimer.h"

#define EEPROM_STATE_ADDR 0
#define STATE_OFF 0x00
#define STATE_ON  0xA5

#define OUT_LED 1

#define RPI_FAILURE_TIMEOUT_MS          180000L
#define AFTER_RPI_SHUTDOWN_POWEROFF_MS  8000
#define FORCE_OFF_HOLD_MS               5000UL

// Reboot-intent pulse protocol on IN_RPI (PB3)
//
// One-shot reboot intent:
//   4 pulses total
//   first pulse ~280 ms
//   remaining pulses ~120 ms
//   gaps ~100 ms
//
// Meaning:
//   If this pattern is seen while the Pi is up, the NEXT Pi-down is treated
//   as a reboot and power is kept on.
//
// No pulse = legacy behavior (Pi-down => power off)

#define FIRST_LONG_MIN_MS               220
#define FIRST_LONG_MAX_MS               450

#define NORMAL_EDGE_MIN_MS               70
#define NORMAL_EDGE_MAX_MS              220

#define MIN_SHORT_INTERVALS_FOR_REBOOT   3
#define MAX_INVALID_INTERVALS            0

#define PULSE_SEQUENCE_TIMEOUT_MS       700
#define REBOOT_PENDING_TIMEOUT_MS     30000UL

Powerled pl;
Interface hw;
SimpleTimer st;

bool systemIsUp = false;
bool systemTurnedOn = false;
bool rpiBootUpDetectionFailure = false;

bool powerOffPending = false;
bool bootTimeoutPending = false;

// one-shot reboot intent
bool rebootPending = false;
bool rebootFlashActive = false;

// pulse decoder state
bool pulseDebugBlinking = false;//#TEST
bool pulseSeqActive = false;
bool pulseSawLongFirst = false;
uint8_t pulseShortIntervalCount = 0;
uint8_t pulseInvalidIntervalCount = 0;
unsigned long pulseFirstEdgeMs = 0;
unsigned long pulseLastEdgeMs = 0;
unsigned long pulseFirstIntervalMs = 0;
unsigned long rebootPendingArmedMs = 0;

// long-press state
bool switchPressActive = false;
bool longPressTriggered = false;
unsigned long switchPressStartMs = 0;

// -----------------------------------------------------------------------------

void markStateOn() {
  EEPROM.update(EEPROM_STATE_ADDR, STATE_ON);
  delay(5);
}

void markStateOff() {
  EEPROM.update(EEPROM_STATE_ADDR, STATE_OFF);
  delay(5);
}

void resetPulseSequence() {
  pulseSeqActive = false;
  pulseSawLongFirst = false;
  pulseShortIntervalCount = 0;
  pulseInvalidIntervalCount = 0;
  pulseFirstEdgeMs = 0;
  pulseLastEdgeMs = 0;
  pulseFirstIntervalMs = 0;
}

void finishRebootIntentFlash() {
  rebootFlashActive = false;
  pl.setFrequency(LED_CYCLE_1S);
  pl.setState(LED_ON);
}

void indicateRebootIntentArmed() {
  rebootFlashActive = true;
  pl.setFrequency(LED_CYCLE_256MS);
  pl.setState(LED_OFF);
  st.setTimeout(800, &finishRebootIntentFlash);
}

void clearRebootPending() {
  rebootPending = false;
  rebootPendingArmedMs = 0;
}

void armRebootPending() {
  rebootPending = true;
  rebootPendingArmedMs = millis();

  // Debug mode: hold LED blinking instead of quick blip
  pl.setFrequency(LED_CYCLE_256MS);
  pl.setState(LED_BLINKING);
}

void pollRebootPendingTimeout() {
  if (!rebootPending) return;

  unsigned long now = millis();
  if ((now - rebootPendingArmedMs) >= REBOOT_PENDING_TIMEOUT_MS) {
    clearRebootPending();
  }
}

void turnPowerSupplyOff();

void forceImmediatePowerOff() {
  markStateOff();
  clearRebootPending();

  pl.setState(LED_OFF);
  RPI_SHUTDOWN_REQUEST_CLEAR;
  POWER_SUPPLY_OFF;

  systemIsUp = false;
  systemTurnedOn = false;
  rpiBootUpDetectionFailure = false;
  powerOffPending = false;
  rebootFlashActive = false;
  switchPressActive = false;
  longPressTriggered = false;

  resetPulseSequence();
}

void rpiBootTimeOut() {
  bootTimeoutPending = false;

  if (!systemIsUp && systemTurnedOn) {
    rpiBootUpDetectionFailure = true;
    systemIsUp = true;
    pl.setFrequency(LED_CYCLE_1S);
    pl.setState(LED_ON);
  }
}

void delayedPowerOffCheck() {
  powerOffPending = false;

  if (!systemTurnedOn || systemIsUp) return;

  // One-shot reboot intent wins only for the next Pi-down.
  if (rebootPending) {
    clearRebootPending();
    return; // keep power on, assume reboot
  }

  // Default behavior is legacy: Pi-down => power off
  turnPowerSupplyOff();//#TEST
}

void handleButtonPress() {
  if (!systemTurnedOn) {
    // power on
    systemTurnedOn = true;
    systemIsUp = false;
    rpiBootUpDetectionFailure = false;
    powerOffPending = false;
    rebootFlashActive = false;

    clearRebootPending();
    resetPulseSequence();

    pl.setFrequency(LED_CYCLE_1S);
    pl.setState(LED_BLINKING);

    RPI_SHUTDOWN_REQUEST_CLEAR;
    delay(20);
    POWER_SUPPLY_ON;

    if (!bootTimeoutPending) {
      bootTimeoutPending = true;
      st.setTimeout(RPI_FAILURE_TIMEOUT_MS, &rpiBootTimeOut);
    }
  } else {
    // short press while already on = normal shutdown request
    // this is NOT reboot intent
    clearRebootPending();
    markStateOff();

    pl.setFrequency(LED_CYCLE_256MS);
    pl.setState(LED_BLINKING);

    RPI_SHUTDOWN_REQUEST;

    if (rpiBootUpDetectionFailure) {
      turnPowerSupplyOff();//#TEST
    }
  }
}

void turnedOn() {
  handleButtonPress();
}

void turnedOff() {
  // release ignored for momentary pushbutton
}

void rpiUp() {
  if (systemTurnedOn && !systemIsUp) {
    systemIsUp = true;
    rpiBootUpDetectionFailure = false;
    powerOffPending = false;

    clearRebootPending();
    markStateOn();

    if (!rebootFlashActive) {
      pl.setFrequency(LED_CYCLE_1S);
      pl.setState(LED_ON);
    }

    resetPulseSequence();
  }
}

void turnPowerSupplyOff() {
  pl.setState(LED_OFF);
  RPI_SHUTDOWN_REQUEST_CLEAR;
  POWER_SUPPLY_OFF;

  systemIsUp = false;
  rpiBootUpDetectionFailure = false;
  powerOffPending = false;
  rebootFlashActive = false;
  switchPressActive = false;
  longPressTriggered = false;

  clearRebootPending();
  resetPulseSequence();

  if (systemTurnedOn) {
    systemTurnedOn = false;
  }
}

void rpiDown() {
  systemIsUp = false;

  if (!powerOffPending) {
    powerOffPending = true;
    st.setTimeout(AFTER_RPI_SHUTDOWN_POWEROFF_MS, &delayedPowerOffCheck);
  }
}

// -----------------------------------------------------------------------------
// Pulse decoder for one-shot reboot intent on IN_RPI
// -----------------------------------------------------------------------------

void rpiEdge(bool rpiIsUpNow) {
  if (!systemTurnedOn) return;//#TEST

  unsigned long now = millis();

  // Ignore meaningless low edges before the Pi has ever been seen up.
  if (!systemIsUp && !rpiIsUpNow) {
    return;
  }

  if (!pulseSeqActive) {
    pulseSeqActive = true;
    pulseSawLongFirst = false;
    pulseShortIntervalCount = 0;
    pulseInvalidIntervalCount = 0;
    pulseFirstEdgeMs = now;
    pulseLastEdgeMs = now;
    pulseFirstIntervalMs = 0;
    return;
  }

  unsigned long dt = now - pulseLastEdgeMs;
  pulseLastEdgeMs = now;

  // First measured interval must be the special long interval.
  if (!pulseSawLongFirst) {
    if (dt >= FIRST_LONG_MIN_MS && dt <= FIRST_LONG_MAX_MS) {
      pulseSawLongFirst = true;
      pulseFirstIntervalMs = dt;
      return;
    }

    // If we got a non-long interval instead, restart sequence from here.
    pulseSeqActive = true;
    pulseSawLongFirst = false;
    pulseShortIntervalCount = 0;
    pulseInvalidIntervalCount = 0;
    pulseFirstEdgeMs = now;
    pulseLastEdgeMs = now;
    pulseFirstIntervalMs = 0;
    return;
  }

  // After the long-first interval, count good short intervals.
  if (dt >= NORMAL_EDGE_MIN_MS && dt <= NORMAL_EDGE_MAX_MS) {
    pulseShortIntervalCount++;
    return;
  }

  // Any bad interval weakens confidence.
  pulseInvalidIntervalCount++;

  // Too much garbage => abandon and restart from this edge.
  if (pulseInvalidIntervalCount > MAX_INVALID_INTERVALS) {
    pulseSeqActive = true;
    pulseSawLongFirst = false;
    pulseShortIntervalCount = 0;
    pulseInvalidIntervalCount = 0;
    pulseFirstEdgeMs = now;
    pulseLastEdgeMs = now;
    pulseFirstIntervalMs = 0;
  }
}


void pollPulseDecoder() {
  if (!pulseSeqActive) return;

  unsigned long now = millis();
  if ((now - pulseLastEdgeMs) < PULSE_SEQUENCE_TIMEOUT_MS) return;

  bool validSequence =
      pulseSawLongFirst &&
      pulseShortIntervalCount >= MIN_SHORT_INTERVALS_FOR_REBOOT &&
      pulseInvalidIntervalCount <= MAX_INVALID_INTERVALS;

  if (validSequence) {
    armRebootPending();
  }

  resetPulseSequence();
}
/*
//#TEST
void pollPulseDecoder() {
  if (!pulseSeqActive) return;

  unsigned long now = millis();
  if ((now - pulseLastEdgeMs) < PULSE_SEQUENCE_TIMEOUT_MS) return;

  // Debug: every completed pulse sequence flips the LED mode
  pulseDebugBlinking = !pulseDebugBlinking;
  pl.setFrequency(LED_CYCLE_1S);
  pl.setState(pulseDebugBlinking ? LED_BLINKING : LED_ON);

  // Normal decoder logic can stay, or you can temporarily return here
  // if you only want to test whether a sequence is being seen at all.

  bool validSequence =
      pulseSawLongFirst &&
      pulseShortIntervalCount >= MIN_SHORT_INTERVALS_FOR_REBOOT &&
      pulseInvalidIntervalCount <= MAX_INVALID_INTERVALS;

  if (validSequence) {
    armRebootPending();
  }

  resetPulseSequence();
}
*/
// -----------------------------------------------------------------------------
// Polling helpers
// -----------------------------------------------------------------------------

void pollRunningStatePersistence() {
  if (systemTurnedOn && systemIsUp) {
    if (EEPROM.read(EEPROM_STATE_ADDR) != STATE_ON) {
      markStateOn();
    }
  }
}

void pollLongPressForceOff() {
  bool pressed = IS_MAIN_SWITCH_ON;
  unsigned long now = millis();

  if (!systemTurnedOn) {
    switchPressActive = false;
    longPressTriggered = false;
    return;
  }

  if (pressed) {
    if (!switchPressActive) {
      switchPressActive = true;
      switchPressStartMs = now;
      longPressTriggered = false;
    } else if (!longPressTriggered && (now - switchPressStartMs >= FORCE_OFF_HOLD_MS)) {
      longPressTriggered = true;
      forceImmediatePowerOff();
    }
  } else {
    switchPressActive = false;
    longPressTriggered = false;
  }
}

// -----------------------------------------------------------------------------

void setup() {
  pl = Powerled(OUT_LED);

  hw.setFunctionTurnedOff(&turnedOff);
  hw.setFunctionTurnedOn(&turnedOn);
  hw.setRpiGoDown(&rpiDown);
  hw.setRpiGoUp(&rpiUp);
  hw.setRpiEdge(&rpiEdge);

  if (EEPROM.read(EEPROM_STATE_ADDR) == STATE_ON) {
    handleButtonPress();
  } else {
    pl.setState(LED_OFF);
  }
}

void loop() {
  pollRunningStatePersistence();
  pollLongPressForceOff();
  pl.thread();
  hw.thread();
  st.thread();
  pollPulseDecoder();
}
