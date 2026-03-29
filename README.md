# PowerBlockExtended

PowerBlockExtended extends the PetRockBlock PowerBlock with an updated ATtiny85 firmware and a Raspberry Pi side integration that aims to preserve the original PowerBlock experience while adding:

- **EEPROM-based restore-after-power-loss**
- **Reboot without cutting power** using a reboot-intent signal on BCM17 → PB3
- A new **`powerblockenhanced`** Raspberry Pi service that replaces the legacy `powerblock.service`

## Current status

The firmware and Raspberry Pi service currently support:

- Button power on
- Button shutdown request
- Long-press hard power off
- EEPROM power-state restore
- Manual reboot-intent signaling from the Pi service
- A persistent BCM17 holder process so service restarts do not immediately drop the Pi-up signal

### Current reboot integration status

At the moment, reboot intent is working when it is triggered through the new service, for example by:

```bash
sudo systemctl kill --kill-whom=main -s SIGUSR1 powerblockenhanced.service
```

or:

```bash
sudo systemctl start powerblockenhanced-pulse.service
```

That means the **Pi-side pulse generation path is working**.

Automatic integration for **all** reboot paths, especially GUI reboot, is **not yet finalized** in this branch. A desktop GUI reboot may still look like a shutdown to the ATtiny if reboot intent is not sent first.

## Design summary

## ATtiny85 firmware

### Hardware mapping

| ATtiny pin | Port | Function |
| --- | ---: | --- |
| 5 | PB0 | Front button input (active low) |
| 6 | PB1 | LED |
| 7 | PB2 | Shutdown request to Pi (BCM18) |
| 2 | PB3 | Pi status / reboot-intent input from Pi (BCM17) |
| 3 | PB4 | Power control |
| 1 | PB5 | Reset / ISP |

### Power control behaviour

- Button press while off → power on
- Button press while running → graceful shutdown request
- Long press (~5s) → immediate hard power off

### EEPROM restore-after-power-loss

EEPROM byte `0` stores the last intended power state:

| Value | Meaning |
| --- | --- |
| `0xA5` | ON |
| `0x00` | OFF |

The firmware restores the previous ON state after unexpected input power loss.

### Reboot intent protocol

The firmware now uses a **single long low pulse** on **PB3**.

PB3 normally sits **HIGH** while the Pi is considered up.

A reboot intent is armed when PB3:

1. goes **LOW**
2. stays low for a valid interval
3. returns **HIGH**

Current firmware window:

- minimum low pulse: `180 ms`
- maximum low pulse: `600 ms`

Effect:

- a valid pulse arms a **one-shot** reboot flag
- the **next Pi-down** is treated as reboot
- power is kept on
- if no Pi-down follows, the arm times out

### Why the single-pulse design was chosen

The earlier multi-pulse decoder proved too fragile in practice. The single long low pulse is:

- easier to generate reliably on the Pi
- easier to inspect on a scope
- easier for the ATtiny to decode
- easier to distinguish from normal steady-high behaviour

## Raspberry Pi integration

## New service: `powerblockenhanced`

The old PetRockBlock setup uses a bash service that holds the status line high and polls the shutdown-request line. PowerBlockExtended keeps that overall pattern, but replaces the legacy service with a new native service layout.

### Service model

The Pi-side design is split into two roles:

1. **Policy service**: `powerblockenhanced.service`
2. **Status holder**: `powerblockenhanced-hold`

### Why there is a dedicated holder process

This is deliberate.

The holder process keeps **BCM17 high** independently of the policy loop. That means:

- restarting the service does not immediately drop BCM17
- package updates or service reloads are less likely to make the ATtiny think the Pi died
- reboot intent can be sent by temporarily switching the holder to LOW, then restoring HIGH

This mirrors the most useful behaviour observed in the legacy PetRockBlock setup, where a surviving `gpioset` process effectively kept the Pi-up signal asserted even after the service unit itself was considered stopped.

### Current Raspberry Pi service behaviour

`powerblockenhanced.service`:

- detects a GPIO backend
- starts a holder process to keep BCM17 high
- polls BCM18 for ATtiny shutdown requests
- triggers the configured shutdown script when the ATtiny requests shutdown
- can receive `SIGUSR1` to send the reboot-intent pulse

`powerblockenhanced-pulse.service`:

- is a simple manual helper
- sends `SIGUSR1` to the **main** process of `powerblockenhanced.service`
- is currently intended for manual testing and scripted use

## Supported Raspberry Pi GPIO backends

The new service is intended to preserve the upstream compatibility approach where possible.

Current implementation supports:

- `gpiod-v1`
- `gpiod-v2`
- `sysfs` fallback where appropriate

In practice, modern Raspberry Pi OS systems are expected to use libgpiod.

## Repository layout

```text
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
    ├── powerblockenhanced
    ├── powerblockenhanced-hold
    ├── powerblockenhanced.service
    ├── powerblockenhanced-pulse.service
    └── local-install.sh
```

## Installation

### 1. Flash the ATtiny85 firmware

Use Arduino IDE or your preferred AVR flashing workflow.

Typical Arduino IDE settings:

- Board: `ATtiny25/45/85`
- Chip: `ATtiny85`
- Clock: `8 MHz internal`
- Programmer: your ISP programmer

Use **Upload Using Programmer**.

See `firmware/flashing.md` for your board-specific wiring and flashing notes.

### 2. Install the Raspberry Pi service

Either install directly from the repository:

```bash
wget -O - https://raw.githubusercontent.com/andyengria/PowerBlockExtended/main/install.sh | sudo bash
```

Or clone the repository:  
```bash
git clone https://github.com/andyengria/PowerBlockExtended.git
```

From the project root:

```bash
cd PowerBlockExtended
sudo ./install.sh
```

This installs:

- `/usr/local/sbin/powerblockenhanced`
- `/usr/local/sbin/powerblockenhanced-hold`
- `/etc/systemd/system/powerblockenhanced.service`
- `/etc/systemd/system/powerblockenhanced-pulse.service`

and then:

- reloads systemd
- enables and starts `powerblockenhanced.service`

### 3. Disable the old PowerBlock service

`install.sh` disables and masks the legacy `powerblock.service` if it exists.

This is important because the old and new services must not fight over BCM17/BCM18.

## Uninstall

To remove the Raspberry Pi side service:

```bash
sudo ./uninstall.sh
```

This:

- stops and disables `powerblockenhanced.service`
- removes the installed unit files and helper binaries
- reloads systemd

It also uninstalls the manual pulse helper unit.

## Operation

### Normal operation

| Action | Result |
| --- | --- |
| Button press while off | Power on |
| Button press while running | Shutdown request |
| Long button hold | Hard power off |
| `shutdown -h now` | Power off |

### Manual reboot-intent test

```bash
sudo systemctl start powerblockenhanced-pulse.service
```

or:

```bash
sudo systemctl kill --kill-whom=main -s SIGUSR1 powerblockenhanced.service
```

Expected:

- BCM17 goes LOW briefly, then HIGH again
- the ATtiny LED indicates reboot-intent arm

### Service continuity test

A key design goal is that restarting the policy service should not immediately drop BCM17.

You can test that with:

```bash
sudo systemctl restart powerblockenhanced.service
```

Expected:

- the holder keeps BCM17 asserted high
- the Pi should remain powered

## Notes and limitations

- The current Raspberry Pi service path is working for **manual** reboot-intent signaling.
- Automatic reboot integration for **all** reboot entry points is still being refined.
- GUI reboot may currently be seen as shutdown if reboot intent is not sent first.
- The persistent holder design is intentional and is part of the safety model.

## Summary

PowerBlockExtended now uses:

- a simpler and more reliable ATtiny reboot detector
- a dedicated Pi-side holder process for BCM17
- a new `powerblockenhanced` service in place of the legacy `powerblock.service`

The project has moved away from the earlier `ExecStopPost=` drop-in approach and away from the older multi-pulse reboot protocol.

The current branch should be understood as:

- **firmware and manual Pi-side reboot signaling are working**
- **automatic GUI/desktop reboot integration is the remaining integration task**
