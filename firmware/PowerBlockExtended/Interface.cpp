/*  Interface.cpp
 *   
 *  Raspberry PI petrockblock PowerBlockExtended (Arduino ATtiny85)
 *
 *  Created on: 26/03/2026
 *      Author: Andy Young (powerblocke@hammert.anonaddy.me)
 *
 *  Based on Vagner Panarello PI PowerController code.
 *
 * This library is free software; you can redistribute it
 * and/or modify it under the terms of the GNU Lesser
 * General Public License as published by the Free Software
 * Foundation; either version 2.1 of the License, or (at
 * your option) any later version.
 *
 * This library is distributed in the hope that it will
 * be useful, but WITHOUT ANY WARRANTY; without even the
 * implied warranty of MERCHANTABILITY or FITNESS FOR A
 * PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser
 * General Public License along with this library; if not,
 * write to the Free Software Foundation, Inc.,
 * 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
 *
 */
#include "Interface.h"

Interface *Interface::thisInstance = 0;

ISR (PCINT0_vect) {
  Interface::pinChangeInterrupt();
}

void Interface::pinChangeInterrupt() {
  if (thisInstance) thisInstance->pinChanceIntHandler();
}

Interface::Interface () {
  SET_INPUT_PIN(IN_RPI);
  SET_INPUT_PIN(IN_SWITCH);

  // switch is active-low to ground
  SET_PULLUP_RESISTOR(IN_SWITCH);

  // preload outputs before making them outputs
  POWER_SUPPLY_OFF;
  RPI_SHUTDOWN_REQUEST_CLEAR;

  SET_OUTPUT_PIN(OUT_POWER_CONTROL);
  SET_OUTPUT_PIN(OUT_RPI);

  MAP_PIN_CHANGE_INTERRUPT(IN_RPI);
  MAP_PIN_CHANGE_INTERRUPT(IN_SWITCH);

  ENABLE_PIN_CHANGE_INTERRUPT;

  lastStateSwitch = IS_MAIN_SWITCH_ON;

  switchDebouncePending = false;
  switchDebounceDeadlineMs = 0;

  rpiRawState = IS_RPI_SYSTEM_UP;
  rpiStableState = rpiRawState;
  rpiPendingStableCommit = false;
  rpiLastRawChangeMs = millis();

  thisInstance = this;
}

void Interface::setFunctionTurnedOff(void (*funcPointer)(void)) {
  this->functionTurnedOff = funcPointer;
}

void Interface::setFunctionTurnedOn(void (*funcPointer)(void)) {
  this->functionTurnedOn = funcPointer;
}

void Interface::setRpiGoDown(void (*funcPointer)(void)) {
  this->rpiGoDown = funcPointer;
}

void Interface::setRpiGoUp(void (*funcPointer)(void)) {
  this->rpiGoUp = funcPointer;
}

void Interface::setRpiEdge(void (*funcPointer)(bool)) {
  this->rpiEdge = funcPointer;
}

void Interface::pinChanceIntHandler() {
  unsigned long now = millis();

  // Sample both inputs immediately.
  bool rpiIsUp = IS_RPI_SYSTEM_UP;
  bool switchPressed = IS_MAIN_SWITCH_ON;

  // PB3 / IN_RPI raw edge handling:
  // call the edge callback immediately so no edges are lost.
  if (rpiIsUp != this->rpiRawState) {
    this->rpiRawState = rpiIsUp;
    this->rpiLastRawChangeMs = now;
    this->rpiPendingStableCommit = true;

    if (rpiEdge) rpiEdge(rpiIsUp);
  }

  // PB0 / IN_SWITCH debounce handling:
  // only schedule debounce if the button state actually changed.
  if (switchPressed != this->lastStateSwitch) {
    this->switchDebouncePending = true;
    this->switchDebounceDeadlineMs = now + DEBOUNCING_TIMEOUT_MS;
  }
}

void Interface::thread() {
  unsigned long now = millis();

  // Debounced momentary pushbutton handling:
  // only react on press edge, ignore release edge
  if (this->switchDebouncePending &&
      (long)(now - this->switchDebounceDeadlineMs) >= 0) {

    bool switchPressed = IS_MAIN_SWITCH_ON;

    if (switchPressed != this->lastStateSwitch) {
      if (switchPressed) {
        if (functionTurnedOn) functionTurnedOn();
      } else {
        if (functionTurnedOff) functionTurnedOff();
      }
      this->lastStateSwitch = switchPressed;
    }

    this->switchDebouncePending = false;
  }

  // Only treat PB3 as a real Pi-up/Pi-down state change once it has
  // remained stable long enough. This prevents command pulse traffic
  // on PB3 from being mistaken for genuine shutdown/reboot state transitions.
  if (this->rpiPendingStableCommit &&
      (long)(now - this->rpiLastRawChangeMs) >= RPI_STATE_STABLE_MS) {

    if (this->rpiStableState != this->rpiRawState) {
      this->rpiStableState = this->rpiRawState;

      if (this->rpiStableState) {
        if (rpiGoUp) rpiGoUp();
      } else {
        if (rpiGoDown) rpiGoDown();
      }
    }

    this->rpiPendingStableCommit = false;
  }
}
