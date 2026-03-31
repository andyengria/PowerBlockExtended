/*  PowerBlockExtended.ino
 *
 *  Raspberry PI PetRockBlock PowerBlockExtended (Arduino ATtiny85)
 *
 *  Created on: 26/03/2026
 *      Author: Andy Young (powerblocke@hammert.anonaddy.me)
 *
 *  Based on Vagner Panarello PI PowerController code.
 *
 *  Features:
 *    - EEPROM-based restore-after-power-loss
 *    - EEPROM-persisted switch type (momentary / latched)
 *    - reboot-without-power-cut using a one-shot reboot-intent pulse
 *    - clean integration with the standard PetRockBlock Raspberry Pi service
 *    - automatic momentary vs latched slide-switch detection
 *    - emergency hard power-off by 3 quick user actions
 *    - slide-switch OFF cancels reboot intent
 *    - slide-switch ON before cut cancels pending power-off
 *
 *  Notes on switch handling
 *  ------------------------------------------------
 *    - EEPROM switch mode is treated as a hint for restore policy
 *    - live detection still re-validates switch type after power-on
 *    - while revalidation is active, momentary-only actions are suppressed
 *      so stale EEPROM state cannot trigger false long-press shutdowns
 *
 *  Momentary switch behavior
 *    - press while OFF          => power on
 *    - short press while ON     => request clean shutdown
 *    - long press while ON      => force immediate power off
 *    - 3 quick presses while ON => force immediate power off
 *
 *  Latched slide switch behavior
 *    - switch ON while OFF            => power on
 *    - switch remains ON              => keep power on
 *    - switch OFF while ON            => request clean shutdown, then power off
 *    - switch OFF cancels reboot intent
 *    - switch ON again before cut     => cancel pending power-off, keep power on
 *    - 3 quick OFF toggles while ON   => force immediate power off
 *
 *  Restore-after-power-loss behavior
 *  ------------------------------------------------
 *    - if last saved power state was OFF, stay OFF
 *    - if last saved power state was ON and switch type is MOMENTARY, restore ON
 *    - if last saved power state was ON and switch type is LATCHED,
 *      restore ON only if the physical switch is currently ON
 *
 *  Reboot intent pulse on IN_RPI (PB3)
 *  ------------------------------------------------
 *    - one deliberate LOW pulse on PB3 while line normally idles HIGH
 *    - LOW pulse width must be within configured min/max window
 *
 *  LED behavior for reboot intent
 *  ------------------------------------------------
 *    - when reboot intent is armed, LED pulses continuously like boot-up
 *    - this continues through the reboot cycle
 *    - when the Pi fully comes back up, LED returns solid ON
 *    - if reboot intent is cancelled, times out, or power is removed,
 *      LED returns to the normal state immediately
 */

#include <EEPROM.h>
#include "Powerled.h"
#include "Interface.h"
#include "SimpleTimer.h"

#define EEPROM_STATE_ADDR               0
#define EEPROM_SWITCH_MODE_ADDR         1

#define STATE_OFF                       0x00
#define STATE_ON                        0xA5

#define SWITCH_EEPROM_UNKNOWN           0x00
#define SWITCH_EEPROM_MOMENTARY         0xA1
#define SWITCH_EEPROM_LATCHED           0xB2

#define OUT_LED                         1

#define RPI_FAILURE_TIMEOUT_MS          180000L
#define AFTER_RPI_SHUTDOWN_POWEROFF_MS  8000
#define FORCE_OFF_HOLD_MS               5000UL

#define REBOOT_LOW_PULSE_MIN_MS         180
#define REBOOT_LOW_PULSE_MAX_MS         600
#define REBOOT_PENDING_TIMEOUT_MS       180000UL

#define SWITCH_TYPE_DETECT_MS           10000UL

#define HARD_OFF_MULTI_WINDOW_MS        4000UL
#define HARD_OFF_MULTI_COUNT            3

Powerled pl;
Interface hw;
SimpleTimer st;

bool systemIsUp = false;
bool systemTurnedOn = false;
bool rpiBootUpDetectionFailure = false;

bool powerOffPending = false;
bool bootTimeoutPending = false;

// reboot intent
bool rebootPending = false;
bool rebootFlashActive = false;

// reboot pulse measurement
bool lowPulseActive = false;
unsigned long lowPulseStartedMs = 0;
unsigned long rebootPendingArmedMs = 0;

// long-press state
bool switchPressActive = false;
bool longPressTriggered = false;
unsigned long switchPressStartMs = 0;

// switch mode
enum SwitchMode {
  SWITCH_MODE_UNKNOWN = 0,
  SWITCH_MODE_MOMENTARY,
  SWITCH_MODE_LATCHED
};

SwitchMode switchMode = SWITCH_MODE_UNKNOWN;

// live switch-type detection
bool switchDetectActive = false;
bool switchDetectStartedFromUserPress = false;
unsigned long switchDetectStartMs = 0;

// shared multi-action hard-off state
uint8_t hardOffActionCount = 0;
unsigned long hardOffWindowStartMs = 0;

// -----------------------------------------------------------------------------

void turnPowerSupplyOff();
void delayedPowerOffCheck();
void rpiBootTimeOut();

// -----------------------------------------------------------------------------
// EEPROM helpers
// -----------------------------------------------------------------------------

void markStateOn() {
  EEPROM.update(EEPROM_STATE_ADDR, STATE_ON);
  delay(5);
}

void markStateOff() {
  EEPROM.update(EEPROM_STATE_ADDR, STATE_OFF);
  delay(5);
}

void saveSwitchModeToEeprom(SwitchMode mode) {
  uint8_t v = SWITCH_EEPROM_UNKNOWN;

  if (mode == SWITCH_MODE_MOMENTARY) {
    v = SWITCH_EEPROM_MOMENTARY;
  } else if (mode == SWITCH_MODE_LATCHED) {
    v = SWITCH_EEPROM_LATCHED;
  }

  EEPROM.update(EEPROM_SWITCH_MODE_ADDR, v);
  delay(5);
}

SwitchMode loadSwitchModeFromEeprom() {
  uint8_t v = EEPROM.read(EEPROM_SWITCH_MODE_ADDR);

  if (v == SWITCH_EEPROM_MOMENTARY) return SWITCH_MODE_MOMENTARY;
  if (v == SWITCH_EEPROM_LATCHED)   return SWITCH_MODE_LATCHED;
  return SWITCH_MODE_UNKNOWN;
}

// -----------------------------------------------------------------------------
// Switch detection helpers
// -----------------------------------------------------------------------------

void resetSwitchModeDetection() {
  switchDetectActive = false;
  switchDetectStartedFromUserPress = false;
  switchDetectStartMs = 0;
}

void startSwitchModeDetection(bool startedFromUserPress) {
  switchDetectActive = true;
  switchDetectStartedFromUserPress = startedFromUserPress;
  switchDetectStartMs = millis();
}

void classifyAsLatchedIfHeld() {
  if (!switchDetectActive) return;
  if (!IS_MAIN_SWITCH_ON) return;

  unsigned long now = millis();
  if ((now - switchDetectStartMs) >= SWITCH_TYPE_DETECT_MS) {
    switchMode = SWITCH_MODE_LATCHED;
    saveSwitchModeToEeprom(switchMode);
    resetSwitchModeDetection();
  }
}

// -----------------------------------------------------------------------------
// Shared multi-action hard-off helpers
// -----------------------------------------------------------------------------

void resetHardOffSequence() {
  hardOffActionCount = 0;
  hardOffWindowStartMs = 0;
}

bool recordHardOffActionAndCheckTrigger() {
  unsigned long now = millis();

  if (hardOffActionCount == 0 ||
      (now - hardOffWindowStartMs) > HARD_OFF_MULTI_WINDOW_MS) {
    hardOffActionCount = 1;
    hardOffWindowStartMs = now;
    return false;
  }

  hardOffActionCount++;

  if (hardOffActionCount >= HARD_OFF_MULTI_COUNT) {
    resetHardOffSequence();
    return true;
  }

  return false;
}

// -----------------------------------------------------------------------------
// LED / reboot helpers
// -----------------------------------------------------------------------------

void resetPulseSequence() {
  lowPulseActive = false;
  lowPulseStartedMs = 0;
}

void restoreNormalLedState() {
  if (systemTurnedOn) {
    pl.setFrequency(LED_CYCLE_1S);
    pl.setState(LED_ON);
  } else {
    pl.setState(LED_OFF);
  }
}

void indicateRebootIntentArmed() {
  rebootFlashActive = true;
  pl.setFrequency(LED_CYCLE_1S);
  pl.setState(LED_BLINKING);
}

void clearRebootPending() {
  rebootPending = false;
  rebootPendingArmedMs = 0;

  if (rebootFlashActive) {
    rebootFlashActive = false;
    restoreNormalLedState();
  }
}

void consumeRebootPendingForReboot() {
  rebootPending = false;
  rebootPendingArmedMs = 0;
  // Keep rebootFlashActive and LED blinking until rpiUp()
}

void armRebootPending() {
  if (rebootPending) return;

  rebootPending = true;
  rebootPendingArmedMs = millis();
  indicateRebootIntentArmed();
}

void pollRebootPendingTimeout() {
  if (!rebootPending) return;

  unsigned long now = millis();
  if ((now - rebootPendingArmedMs) >= REBOOT_PENDING_TIMEOUT_MS) {
    clearRebootPending();
  }
}

// -----------------------------------------------------------------------------
// Core power control
// -----------------------------------------------------------------------------

void beginPowerOnSequence(bool startedFromUserPress) {
  systemTurnedOn = true;
  systemIsUp = false;
  rpiBootUpDetectionFailure = false;
  powerOffPending = false;

  clearRebootPending();
  resetPulseSequence();
  resetHardOffSequence();

  switchPressActive = false;
  longPressTriggered = false;

  if (IS_MAIN_SWITCH_ON) {
    startSwitchModeDetection(startedFromUserPress);
  } else {
    resetSwitchModeDetection();
  }

  pl.setFrequency(LED_CYCLE_1S);
  pl.setState(LED_BLINKING);

  RPI_SHUTDOWN_REQUEST_CLEAR;
  delay(20);
  POWER_SUPPLY_ON;

  if (!bootTimeoutPending) {
    bootTimeoutPending = true;
    st.setTimeout(RPI_FAILURE_TIMEOUT_MS, &rpiBootTimeOut);
  }
}

void cancelLatchedShutdownRequest() {
  powerOffPending = false;
  RPI_SHUTDOWN_REQUEST_CLEAR;

  if (systemIsUp) {
    pl.setFrequency(LED_CYCLE_1S);
    pl.setState(LED_ON);
  } else {
    pl.setFrequency(LED_CYCLE_1S);
    pl.setState(LED_BLINKING);
  }
}

void requestShutdownFromUserAction() {
  clearRebootPending();
  markStateOff();

  pl.setFrequency(LED_CYCLE_256MS);
  pl.setState(LED_BLINKING);

  RPI_SHUTDOWN_REQUEST;

  if (rpiBootUpDetectionFailure) {
    turnPowerSupplyOff();
    return;
  }

  if (!systemIsUp && !powerOffPending) {
    powerOffPending = true;
    st.setTimeout(AFTER_RPI_SHUTDOWN_POWEROFF_MS, &delayedPowerOffCheck);
  }
}

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
  resetHardOffSequence();
  resetSwitchModeDetection();
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

  if (switchMode == SWITCH_MODE_LATCHED) {
    if (IS_MAIN_SWITCH_ON) {
      return;
    }
    turnPowerSupplyOff();
    return;
  }

  if (rebootPending) {
    consumeRebootPendingForReboot();
    return;
  }

  turnPowerSupplyOff();
}

void turnPowerSupplyOff() {
  markStateOff();

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
  resetHardOffSequence();
  resetSwitchModeDetection();

  systemTurnedOn = false;
}

// -----------------------------------------------------------------------------
// External event handlers
// -----------------------------------------------------------------------------

void turnedOn() {
  if (!systemTurnedOn) {
    beginPowerOnSequence(true);
    return;
  }

  // While revalidating switch type, do not trust stale EEPROM mode yet.
  if (switchDetectActive) {
    return;
  }

  if (switchMode == SWITCH_MODE_MOMENTARY) {
    if (recordHardOffActionAndCheckTrigger()) {
      forceImmediatePowerOff();
      return;
    }

    requestShutdownFromUserAction();
    return;
  }

  if (switchMode == SWITCH_MODE_LATCHED) {
    cancelLatchedShutdownRequest();
    return;
  }

  // UNKNOWN: do nothing on asserted state while already on
}

void turnedOff() {
  if (!systemTurnedOn) return;

  if (switchDetectActive) {
    if (switchDetectStartedFromUserPress) {
      switchMode = SWITCH_MODE_MOMENTARY;
      saveSwitchModeToEeprom(switchMode);
      resetSwitchModeDetection();
      return;
    } else {
      if (switchMode != SWITCH_MODE_LATCHED) {
        switchMode = SWITCH_MODE_LATCHED;
        saveSwitchModeToEeprom(switchMode);
      }
      resetSwitchModeDetection();
      // continue into latched OFF handling
    }
  }

  if (switchMode == SWITCH_MODE_LATCHED) {
    clearRebootPending();

    if (recordHardOffActionAndCheckTrigger()) {
      forceImmediatePowerOff();
      return;
    }

    requestShutdownFromUserAction();
  }
}

void rpiUp() {
  if (systemTurnedOn && !systemIsUp) {
    systemIsUp = true;
    rpiBootUpDetectionFailure = false;
    powerOffPending = false;

    rebootPending = false;
    rebootPendingArmedMs = 0;
    rebootFlashActive = false;

    markStateOn();

    pl.setFrequency(LED_CYCLE_1S);
    pl.setState(LED_ON);

    resetPulseSequence();
    resetHardOffSequence();
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
// Reboot pulse detector on PB3
// -----------------------------------------------------------------------------

void rpiEdge(bool rpiIsUpNow) {
  unsigned long now = millis();

  if (!rpiIsUpNow) {
    lowPulseActive = true;
    lowPulseStartedMs = now;
    return;
  }

  if (lowPulseActive) {
    unsigned long lowDt = now - lowPulseStartedMs;
    lowPulseActive = false;
    lowPulseStartedMs = 0;

    if (lowDt >= REBOOT_LOW_PULSE_MIN_MS &&
        lowDt <= REBOOT_LOW_PULSE_MAX_MS) {
      armRebootPending();
    }
  }
}

void pollPulseDecoder() {
  if (!lowPulseActive) return;

  unsigned long now = millis();
  if ((now - lowPulseStartedMs) > REBOOT_LOW_PULSE_MAX_MS) {
    lowPulseActive = false;
    lowPulseStartedMs = 0;
  }
}

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

  // Do not allow momentary-style long-press while switch type is being revalidated.
  if (switchDetectActive) {
    switchPressActive = false;
    longPressTriggered = false;
    return;
  }

  if (switchMode != SWITCH_MODE_MOMENTARY) {
    switchPressActive = false;
    longPressTriggered = false;
    return;
  }

  if (pressed) {
    if (!switchPressActive) {
      switchPressActive = true;
      switchPressStartMs = now;
      longPressTriggered = false;
    } else if (!longPressTriggered &&
               (now - switchPressStartMs >= FORCE_OFF_HOLD_MS)) {
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

  uint8_t savedState = EEPROM.read(EEPROM_STATE_ADDR);
  bool switchCurrentlyOn = IS_MAIN_SWITCH_ON;

  switchMode = loadSwitchModeFromEeprom();

  // Restore-after-power-loss policy
  if (savedState == STATE_ON) {
    if (switchMode == SWITCH_MODE_LATCHED) {
      if (switchCurrentlyOn) {
        beginPowerOnSequence(false);
        return;
      } else {
        pl.setState(LED_OFF);
        return;
      }
    }

    // Momentary or unknown: preserve restore-on-power-return behavior
    beginPowerOnSequence(false);
    return;
  }

  // Important:
  // even if EEPROM currently says MOMENTARY, a physically asserted switch
  // at boot should still be allowed to power on so the firmware can relearn
  // that the hardware is actually a latched slide switch.
  if (switchCurrentlyOn) {
    beginPowerOnSequence(false);
    return;
  }

  pl.setState(LED_OFF);
}

void loop() {
  pollRunningStatePersistence();
  pollLongPressForceOff();
  pollRebootPendingTimeout();
  classifyAsLatchedIfHeld();
  pl.thread();
  hw.thread();
  st.thread();
  pollPulseDecoder();
}
