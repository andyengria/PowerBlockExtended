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

  rpiRawState = IS_RPI_SYSTEM_UP;
  rpiStableState = rpiRawState;
  rpiPendingStableCommit = false;
  rpiLastRawChangeMs = millis();

  thisInstance = this;
}

void Interface::containerToCallback(void) {
  thisInstance->functionToReturn();
}

void Interface::functionToReturn(void) {
  bool switchPressed = IS_MAIN_SWITCH_ON;
  bool rpiIsUp = IS_RPI_SYSTEM_UP;
  unsigned long now = millis();

  // Momentary pushbutton handling:
  // only react on press edge, ignore release edge
  if (switchPressed != this->lastStateSwitch) {
    if (switchPressed) {
      if (functionTurnedOn) functionTurnedOn();
    }
    this->lastStateSwitch = switchPressed;
  }

  // Raw PB3 edge handling:
  // - always feed pulse decoder immediately
  // - do NOT immediately commit Pi up/down state
  if (rpiIsUp != this->rpiRawState) {
    this->rpiRawState = rpiIsUp;
    this->rpiLastRawChangeMs = now;
    this->rpiPendingStableCommit = true;

    if (rpiEdge) rpiEdge(rpiIsUp);
  }
}

void Interface::setCallback(void (*pointerFunction)(void), long _delay) {
  this->pointerCallback = pointerFunction;
  this->callbackTimeout = millis() + _delay;
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
  if (!(this->pointerCallback)) {
    this->setCallback(Interface::containerToCallback, DEBOUNCING_TIMEOUT_MS);
  }
}

void Interface::thread() {
  unsigned long now = millis();

  if (this->pointerCallback && (long)(now - this->callbackTimeout) >= 0) {
    this->pointerCallback();
    this->pointerCallback = 0;
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
