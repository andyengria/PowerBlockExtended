# PowerBlockExtended

PowerBlockExtended extends the PetRockBlock PowerBlock with updated ATtiny85 firmware and a Raspberry Pi service providing reliable power control and reboot handling.

## Features

- Power on via front button  
- Graceful shutdown via button  
- Long-press hard power off  
- Restore previous power state after power loss (EEPROM)  
- Reboot without cutting power  
- systemd-based Raspberry Pi service  
- Automatic reboot detection across all reboot methods  

---

## ATtiny85 Firmware

### Hardware mapping

| ATtiny pin | Port | Function |
|---|---|---|
| 5 | PB0 | Front button input |
| 6 | PB1 | LED |
| 7 | PB2 | Shutdown request → Pi (BCM18) |
| 2 | PB3 | Pi status / reboot intent ← Pi (BCM17) |
| 3 | PB4 | Power control |
| 1 | PB5 | Reset |

---

### Power behaviour

- Button press while off → power on  
- Button press while running → graceful shutdown request  
- Long press (longer than 5 seconds) → hard power off  

---

### Restore after power loss

The last intended power state is stored in EEPROM:

| Value | Meaning |
|---|---|
| `0xA5` | ON |
| `0x00` | OFF |

---

### Reboot detection

Reboot is detected via a low pulse on PB3:

- PB3 is normally HIGH  
- A LOW pulse (180–600 ms) signals reboot intent  
- The next Pi shutdown is treated as a reboot  
- Power remains on  

---

## Raspberry Pi Service

### `powerblockenhanced.service`

The service:

- monitors BCM18 for shutdown requests  
- executes a shutdown script when requested  
- maintains signal continuity across service restarts  

---

### Holder process

A helper process maintains the BCM17 HIGH signal independently of the main service to prevent unintended power-off during service restarts.

---

### Reboot handling

Reboot intent is generated automatically during system shutdown using a systemd shutdown hook.

This ensures correct behaviour for:

- `reboot`
- `systemctl reboot`
- `shutdown -r now`
- desktop / GUI reboot  

Shutdown (`poweroff`) does not trigger reboot intent.

---

## GPIO Backends

Supported:

- libgpiod v2  
- libgpiod v1  
- sysfs fallback  

The installer selects the appropriate backend automatically.

---

## Installation

### 1. Flash firmware

Flash the ATtiny85 using Arduino IDE or an AVR programmer.

Typical Arduino settings:

- Board: ATtiny25/45/85  
- Chip: ATtiny85  
- Clock: 8 MHz internal  
- Upload method: Upload Using Programmer  

---

### 2. Install on Raspberry Pi

```bash
wget -O - https://raw.githubusercontent.com/andyengria/PowerBlockExtended/main/install.sh | sudo bash
````

Or:

```bash
git clone https://github.com/andyengria/PowerBlockExtended.git
cd PowerBlockExtended
sudo ./install.sh
```

---

### Installed components

* `/usr/local/sbin/powerblockenhanced`
* `/usr/local/sbin/powerblockenhanced-hold`
* `/etc/systemd/system/powerblockenhanced.service`
* `/usr/lib/systemd/system-shutdown/powerblockenhanced-reboot-pulse`

The service is enabled and started automatically.

---

## Configuration

Optional configuration file:

```
/etc/powerblockconfig.cfg
```

Example:

```ini
[powerblock]
activated=1
statuspin=17
shutdownpin=18
logging=1
shutdownscript=/etc/powerblockswitchoff.sh
```

### Options

| Option         | Description                         |
| -------------- | ----------------------------------- |
| activated      | Enable (1) or disable (0) service   |
| statuspin      | BCM pin used for Pi status          |
| shutdownpin    | BCM pin used for shutdown request   |
| logging        | Enable logging                      |
| shutdownscript | Script executed on shutdown request |

---

## Shutdown script

The configured script is executed when a shutdown is requested.

Default:

```bash
#!/bin/bash
exec /sbin/shutdown -h now "PowerBlockEnhanced requested shutdown"
```

Custom scripts can be used to perform additional actions before shutdown.

---

## Operation

| Action            | Result           |
| ----------------- | ---------------- |
| Button press      | Shutdown request |
| Long press        | Hard power off   |
| `shutdown -h now` | Power off        |
| `reboot`          | Power remains on |

---

## Service behaviour

Restarting the service does not interrupt power:

```bash
sudo systemctl restart powerblockenhanced.service
```

---

## Uninstall

```bash
sudo ./uninstall.sh
```

Removes service, binaries, and reboot hook.

Configuration and user scripts are preserved.

---

## Summary

PowerBlockExtended provides:

* reliable power control
* automatic reboot handling
* compatibility with modern Raspberry Pi systems
* simple configuration and deployment

