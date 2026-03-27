# PowerBlockExtended

PowerBlockExtended extends the PetRockBlock PowerBlock with:

* **EEPROM-based restore-after-power-loss**
* **Reboot without cutting power** using a reboot-intent pulse
* Clean integration with the standard PowerBlock Raspberry Pi service

---

## Features

### Power control

* Press button → power on  
* Press button while running → graceful shutdown  
* Hold button (5s) → immediate hard power off  

### Shutdown behavior

* `shutdown -h now` → power off  
* Button shutdown → power off  

### Reboot behavior

* `reboot` → **power stays ON**
* Achieved via a reboot-intent pulse sent during system shutdown

### Power loss recovery

* Unexpected power loss → system restores previous ON state using EEPROM when power is restored  

---

## ⚙️ How reboot detection works (new design)

PowerBlockExtended uses a **systemd drop-in** to extend the native PowerBlock service:

* Hooks into `powerblock.service` shutdown
* Uses `ExecStopPost=` to run after the service releases GPIO
* Sends the reboot-intent pulse at the correct time

### Why this is reliable

This avoids:

* ❌ wrapper scripts (`reboot`)
* ❌ race conditions with GPIO ownership
* ❌ fragile process killing (`pkill`)

Instead it:

* ✅ runs **after PowerBlock releases BCM17**
* ✅ is triggered by **systemd’s shutdown sequence**
* ✅ works regardless of how reboot is initiated (CLI, GUI, service, etc.)

---

## 🔌 System Flow (Reboot Path)

    +----------------------+
    |   User / System      |
    |  (reboot command)    |
    +----------+-----------+
               |
               v
    +----------------------+
    |   systemd            |
    |  begins shutdown     |
    +----------+-----------+
               |
               v
    +----------------------+
    | powerblock.service   |
    | stops                |
    | (releases BCM17)     |
    +----------+-----------+
               |
               v
    +-------------------------------+
    | ExecStopPost (drop-in)        |
    | reboot-intent script          |
    +----------+--------------------+
               |
               v
    +----------------------+
    | gpioset sends pulse  |
    | on BCM17             |
    +----------+-----------+
               |
               v
    +----------------------+
    | ATtiny85 detects     |
    | reboot intent        |
    +----------+-----------+
               |
               v
    +----------------------+
    | Pi powers down       |
    | BUT power stays ON   |
    +----------+-----------+
               |
               v
    +----------------------+
    | Pi boots again       |
    +----------------------+

---

## ⚡ GPIO Pulse Timing

    BCM17 (Pi → ATtiny PB3)

    HIGH  ────────┐     ┌────┐     ┌────┐     ┌────┐     ┌────┐
                  │     │    │     │    │     │    │     │    │
    LOW   ────────┴─────┘    └─────┘    └─────┘    └─────┘    └───

            500ms   300ms   300ms   300ms   300ms
             ↑        ↑       ↑       ↑       ↑
           pulse1   pulse2  pulse3  pulse4  pulse5

    ~80ms gaps between pulses

---

## 🧠 Logic Summary

    If reboot:
        send pulse pattern
        → ATtiny keeps power ON

    If shutdown:
        no pulse
        → ATtiny cuts power

---

## Hardware mapping (ATtiny85)

| ATtiny pin | Port | Function                          |
| ---------- | ---: | --------------------------------- |
| 5          |  PB0 | Button input (active low)         |
| 6          |  PB1 | LED                               |
| 7          |  PB2 | Shutdown request → Pi (BCM18)     |
| 2          |  PB3 | Status / pulse input ← Pi (BCM17) |
| 3          |  PB4 | Power control                     |
| 1          |  PB5 | Reset / ISP                       |

---

## EEPROM behavior

EEPROM byte `0` stores power state:

| Value  | Meaning    |
| ------ | ---------- |
| `0xA5` | System ON  |
| `0x00` | System OFF |

Rules:

* Set to **ON** when Pi is confirmed running  
* Set to **OFF** on intentional shutdown  
* Used only for restore-after-power-loss  

---

## Reboot pulse protocol

The Raspberry Pi sends a pulse on **BCM17 → PB3**.

Pattern:

* 5 pulses total  
* first pulse ≈ 500 ms  
* remaining pulses ≈ 300 ms  

Effect:

* Arms a **one-shot reboot flag**  
* Next Pi-down is treated as reboot  
* Power is kept on  

Timeout: ~30 seconds  

### LED indication

* Quick LED blip → reboot intent received  

---

## Repository structure

    PowerBlockExtended/
    ├── README.md
    ├── install.sh
    ├── uninstall.sh
    ├── firmware/
    │   ├── flashing.md
    │   └── PowerBlockExtended/
    │       ├── PowerBlockExtended.ino
    │       ├── Interface.cpp
    │       ├── Interface.h
    │       ├── Powerled.*
    │       └── SimpleTimer.*
    └── rpi/
        ├── powerblock-reboot-intent-dropin.service
        ├── powerblock-send-reboot-intent-if-reboot.sh
        └── test-reboot.sh

---

## Installation

### 1. Flash ATtiny firmware

Using Arduino IDE:

* Board: `ATtiny25/45/85`
* Chip: `ATtiny85`
* Clock: `8 MHz internal`
* Programmer: `Atmel-ICE (AVR)`

Use **Upload Using Programmer**  
See `firmware/flashing.md` for details.

---

### 2. Install standard PowerBlock service

Install the original PetRockBlock PowerBlock service:

- https://github.com/petrockblog/PowerBlock  
- or fork: https://github.com/andyengria/PowerBlock  

---

### 3. Install reboot integration

Tested on Debian Trixie (Raspberry Pi Desktop), but supports older releases (see compatibility below).

#### Quick install

    wget -O - https://raw.githubusercontent.com/andyengria/PowerBlockExtended/main/install.sh | sudo bash

OR:

    git clone https://github.com/andyengria/PowerBlockExtended.git
    cd PowerBlockExtended
    sudo ./install.sh

### What gets installed

* `/usr/local/bin/powerblock-send-reboot-intent-if-reboot.sh`
* `/etc/systemd/system/powerblock.service.d/powerblock-reboot-intent.conf`

Then:

* systemd daemon is reloaded  
* `powerblock.service` is restarted  

### Uninstall

    sudo ./uninstall.sh

---

## Compatibility

### systemd

Compatible with:

* Debian Bullseye  
* Debian Bookworm  
* Debian Trixie  

Uses:

    ExecStopPost=

---

### GPIO (libgpiod)

| System        | libgpiod | Support |
|--------------|---------|--------|
| Bullseye     | 1.x     | ✅ fallback mode |
| Bookworm     | 1.x     | ✅ fallback mode |
| Trixie       | 2.x     | ✅ native (`--toggle`) |

The script automatically detects support for:

    gpioset --toggle

---

## Operation

### Normal usage

| Action             | Result               |
|------------------|--------------------|
| Button press (off) | Power ON             |
| Button press (on)  | Shutdown + power OFF |
| `shutdown -h now`  | Power OFF            |
| `reboot`           | Power stays ON       |

---

## Testing

### Basic

1. Power on via button  
2. Wait for full boot  
3. Press button → shutdown → power off  

### Reboot

    sudo reboot

Expected:

* quick LED blip before reboot  
* Pi restarts  
* power remains ON  

### Power loss

1. Power on system  
2. Cut input power  
3. Restore power  

Expected:

* system powers back on automatically  

---

## Notes

* Reboot detection happens during **service shutdown**
* EEPROM is used only for ON/OFF restore state  
* Reboot mode is **not persistent** and must be signaled each time  
* Works regardless of how reboot is triggered  

---

## Summary

PowerBlockExtended preserves standard PowerBlock behavior while adding:

* reliable power loss / restore  
* clean reboot without power interruption  

The new design uses **systemd-native hooks instead of wrappers**, making it:

* more reliable  
* race-condition free  
* compatible across Debian/Raspberry Pi OS versions  
