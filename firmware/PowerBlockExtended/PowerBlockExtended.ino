/*  PowerBlockExtended.ino
 *   
 *  Raspberry PI PetRockBlock PowerBlockExtended (Arduino ATtiny85)
 *
 *  Created on: 26/03/2026
 *      Author: Andy Young (powerblocke@hammert.anonaddy.me)
 *
 *  Based on Vagner Panarello PI PowerController code.
 *
 *  PowerBlockExtended adds:
 *    - EEPROM-based restore-after-power-loss
 *    - reboot-without-power-cut using a one-shot reboot-intent pulse
 *    - clean integration with the standard PetRockBlock Raspberry Pi service
 *
 *  Reboot-intent pulse protocol on IN_RPI (PB3)
 *  ------------------------------------------------
 *  One-shot reboot intent:
 *    - quick 4-pulse pattern on PB3
 *    - first interval is "long"
 *    - following intervals are "short"
 *
 *  Example Linux-side timing sequence:
 *    220,70,90,70,90,70,90
 *
 *  Meaning:
 *    - if this pattern is seen while the system is ON, the NEXT Pi-down is
 *      treated as a reboot and power is kept ON
 *    - no pulse = legacy behavior (Pi-down => power off)
 *
 *  Decoder behavior:
 *    - runs directly on PB3 edges
 *    - first interval must match the configured long window
 *    - then at least N valid short intervals must be seen
 *    - reboot intent is armed greedily as soon as enough valid intervals
 *      are received
 *    - exact edge count is not required
 *    - partial/invalid sequences time out and are discarded
 *
 *  Implementation notes:
 *    - requires updated Interface.cpp / Interface.h where:
 *        * PB3 edge handling is immediate
 *        * front-panel button debounce remains delayed
 *    - reboot intent is one-shot and is cleared after use or timeout
 *    - normal PowerBlock shutdown behavior is otherwise preserved
 *
 *  This library is free software; you can redistribute it
 *  and/or modify it under the terms of the GNU Lesser
 *  General Public License as published by the Free Software
 *  Foundation; either version 2.1 of the License, or (at
 *  your option) any later version.
 *
 *  This library is distributed in the hope that it will
 *  be useful, but WITHOUT ANY WARRANTY; without even the
 *  implied warranty of MERCHANTABILITY or FITNESS FOR A
 *  PARTICULAR PURPOSE.  See the GNU Lesser General Public
 *  License for more details.
 *
 *  You should have received a copy of the GNU Lesser
 *  General Public License along with this library; if not,
 *  write to the Free Software Foundation, Inc.,
 *  51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
 *
 */
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

// Reboot intent = one deliberate LOW pulse on PB3 while line normally idles HIGH
#define REBOOT_LOW_PULSE_MIN_MS         180
#define REBOOT_LOW_PULSE_MAX_MS         600

#define REBOOT_PENDING_TIMEOUT_MS     180000UL

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

// single-low-pulse decoder state
bool lowPulseActive = false;
unsigned long lowPulseStartedMs = 0;
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

void finishRebootIntentFlash() {
  rebootFlashActive = false;
  restoreNormalLedState();
}

void indicateRebootIntentArmed() {
  rebootFlashActive = true;

  // Very obvious debug confirmation
  pl.setFrequency(LED_CYCLE_256MS);
  pl.setState(LED_BLINKING);
  st.setTimeout(4000, &finishRebootIntentFlash);
}

void clearRebootPending() {
  rebootPending = false;
  rebootPendingArmedMs = 0;
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
  turnPowerSupplyOff();
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
    clearRebootPending();
    markStateOff();

    pl.setFrequency(LED_CYCLE_256MS);
    pl.setState(LED_BLINKING);

    RPI_SHUTDOWN_REQUEST;

    if (rpiBootUpDetectionFailure) {
      turnPowerSupplyOff();
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
// Single long-low reboot intent detector on IN_RPI / PB3
// -----------------------------------------------------------------------------
//
// PB3 normally idles HIGH while Pi is running.
// Reboot intent is a deliberate LOW pulse of valid length, then HIGH again.
//
// Falling edge: start timing low pulse
// Rising edge: measure low duration and arm reboot if in range
//

void rpiEdge(bool rpiIsUpNow) {
  // For diagnosis / simpler behavior, do not gate on systemTurnedOn here.
  // If you later want the old production restriction back, reintroduce it
  // after this simpler protocol is proven reliable.
  // if (!systemTurnedOn) return;

  unsigned long now = millis();

  if (!rpiIsUpNow) {
    // Line went LOW: begin measuring low pulse.
    lowPulseActive = true;
    lowPulseStartedMs = now;
    return;
  }

  // Line returned HIGH: if a low pulse was in progress, measure it.
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

  // If the low pulse never returned HIGH in time, abandon it.
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
  pollRebootPendingTimeout();
  pl.thread();
  hw.thread();
  st.thread();
  pollPulseDecoder();
}
