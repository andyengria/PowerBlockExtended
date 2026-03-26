#ifndef INTERFACE_H_
#define INTERFACE_H_

#include "Arduino.h"

// Corrected pin map from measurement
//
// ATtiny85 physical pins:
// 1 = PB5 / RESET
// 2 = PB3  <- Pi BCM17 status input
// 3 = PB4  -> Power control
// 4 = GND
// 5 = PB0  <- Momentary switch input
// 6 = PB1  -> LED
// 7 = PB2  -> Pi BCM18 shutdown request
// 8 = VCC

#define OUT_RPI                        2   // PB2, chip pin 7
#define IN_RPI                         3   // PB3, chip pin 2
#define IN_SWITCH                      0   // PB0, chip pin 5
#define OUT_POWER_CONTROL              4   // PB4, chip pin 3

#define DEBOUNCING_TIMEOUT_MS          100
#define RPI_STATE_STABLE_MS            800

#define READ_STATE_PIN(pin)            (((PINB) >> (pin)) & 0x01)
#define SET_OUTPUT_PIN(pin)            DDRB |= (1 << (pin))
#define SET_INPUT_PIN(pin)             DDRB &= ~(1 << (pin))
#define SET_TO_HIGH_PIN(pin)           PORTB |= (1 << (pin))
#define SET_TO_LOW_PIN(pin)            PORTB &= ~(1 << (pin))
#define SET_PULLUP_RESISTOR(pin)       PORTB |= (1 << (pin))
#define TOGGLE_OUTPUT_PIN(pin)         PORTB ^= (1 << (pin))

#define DISABLE_PIN_CHANGE_INTERRUPT   GIMSK &= ~(1 << PCIE)
#define ENABLE_PIN_CHANGE_INTERRUPT    GIMSK |= (1 << PCIE)
#define MAP_PIN_CHANGE_INTERRUPT(pin)  PCMSK |= (1 << (pin))

#define POWER_SUPPLY_ON                SET_TO_HIGH_PIN(OUT_POWER_CONTROL)
#define POWER_SUPPLY_OFF               SET_TO_LOW_PIN(OUT_POWER_CONTROL)

// Stock Pi scripts expect BCM18 HIGH for shutdown request
#define RPI_SHUTDOWN_REQUEST           SET_TO_HIGH_PIN(OUT_RPI)
#define RPI_SHUTDOWN_REQUEST_CLEAR     SET_TO_LOW_PIN(OUT_RPI)

// Pi BCM17 is high while system is up
#define IS_RPI_SYSTEM_UP               (READ_STATE_PIN(IN_RPI))

// switch from PB0 to GND = active low
#define IS_MAIN_SWITCH_ON              (!READ_STATE_PIN(IN_SWITCH))

class Interface {
  private:
    static Interface *thisInstance;
    unsigned long callbackTimeout = 0;

    bool lastStateSwitch = false;

    // PB3 raw-edge state vs committed stable state
    bool rpiRawState = false;
    bool rpiStableState = false;
    bool rpiPendingStableCommit = false;
    unsigned long rpiLastRawChangeMs = 0;

    void (*pointerCallback)(void) = 0;

    void (*functionTurnedOff)(void) = 0;
    void (*functionTurnedOn)(void) = 0;
    void (*rpiGoDown)(void) = 0;
    void (*rpiGoUp)(void) = 0;
    void (*rpiEdge)(bool) = 0;

    void pinChanceIntHandler();

  public:
    Interface();

    static inline void pinChangeInterrupt();
    void functionToReturn(void);
    static void containerToCallback(void);

    void setCallback(void (*pointerFunction)(void), long _delay);

    void setFunctionTurnedOff(void (*funcPointer)(void));
    void setFunctionTurnedOn(void (*funcPointer)(void));
    void setRpiGoDown(void (*funcPointer)(void));
    void setRpiGoUp(void (*funcPointer)(void));
    void setRpiEdge(void (*funcPointer)(bool));

    void thread();
};

#endif /* INTERFACE_H_ */
