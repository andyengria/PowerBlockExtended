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
* Achieved via a reboot-intent pulse sent before reboot

### Power loss recovery

* Unexpected power loss → system restores previous ON state using EEPROM when power is restored

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

```text
PowerBlockExtended/
├── README.md
├── install.sh
├── firmware/
│   ├── flashing.md
│   └── PowerBlockExtended/
│       ├── PowerBlockExtended.ino
│       ├── Interface.cpp
│       ├── Interface.h
│       ├── Powerled.*
│       └── SimpleTimer.*
└── rpi/
    ├── powerblock-reboot-intent.service
    ├── powerblock-send-reboot-intent.sh
    └── test-reboot.sh
```

---

## Installation

### 1. Flash ATtiny firmware

Using Arduino IDE:

* Board: `ATtiny25/45/85`
* Chip: `ATtiny85`
* Clock: `8 MHz internal`
* Programmer: `Atmel-ICE (AVR)`

Use **Upload Using Programmer**
Also see the firmware/flashing.md document for further details. 

---

### 2. Install standard PowerBlock service

Install the original PetRockBlock PowerBlock service.
Available here: https://github.com/petrockblog/PowerBlock
or my fork: https://github.com/andyengria/PowerBlock

---

### 3. Install reboot integration

## Quick install

Run the following command on your Raspberry Pi:

```bash
wget -O - https://raw.githubusercontent.com/andyengria/PowerBlockExtended/main/install.sh | sudo bash
```

OR clone the repo to your pi

From repo root:

```bash
sudo ./install.sh
```

This installs:

* `/usr/local/bin/powerblock-send-reboot-intent.sh`
* `/etc/systemd/system/powerblock-reboot-intent.service`

and enables the reboot-intent service.

To uninstall the service you can simply call sudo ./uninstall.sh from within the PowerBlockEntended directory.

---

## Operation

### Normal usage

| Action             | Result               |
| ------------------ | -------------------- |
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

```bash
sudo reboot
```

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

* Reboot behavior depends on the reboot-intent service being installed
* EEPROM is used only for ON/OFF restore state
* Reboot mode is **not persistent** and must be signaled each time

---

## Summary

PowerBlockExtended preserves standard PowerBlock behavior while adding:

* reliable power loss / restore
* clean reboot without power interruption

Designed for real-world use with minimal configuration and predictable behavior.
Used successfully on a homebrew RPI NAS server based upon OpenMediaVault

