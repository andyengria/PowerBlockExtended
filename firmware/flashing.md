# ATtiny85 Flashing Guide

## Hardware / Programmer

It is recommended to flash the ATtiny85 over **ISP (In-System Programming)** using an **Atmel-ICE**.

Other methods (such as using an Arduino as ISP) may work, but were not tested as part of this project.

Before flashing:

* Solder header pins onto the PowerBlock (if not already present)
* Connect the programmer to the ISP header

---

## Arduino IDE Setup

Compile the firmware using the Arduino IDE with the following settings:

```
Board: ATtiny25/45/85
Chip: ATtiny85
Clock: 8 MHz internal
Programmer: Atmel-ICE (AVR)
```

Then use:

```
Upload Using Programmer
```

---

## Known Fuse Values

Original fuse values observed:

```
lfuse = 0xE2
hfuse = 0xDF
efuse = 0xFF
lock  = 0xFF
```

---

## Recommended Flashing Workflow

1. Connect Atmel-ICE over ISP
2. Verify connection with `avrdude`
3. Back up existing firmware and EEPROM
4. Build firmware in Arduino IDE
5. Upload using programmer
6. Verify operation on hardware

---

## Backup (Strongly Recommended)

Before uploading new firmware, back up the original contents.

This allows easy rollback if needed.

---

## avrdude Commands

### Check connection

```bash
avrdude -c atmelice_isp -p t85 -v
```

---

### Backup existing firmware

```bash
avrdude -c atmelice_isp -p t85 \
  -U flash:r:powerblock_flash.hex:i \
  -U eeprom:r:powerblock_eeprom.hex:i \
  -U lfuse:r:lfuse.txt:h \
  -U hfuse:r:hfuse.txt:h \
  -U efuse:r:efuse.txt:h \
  -U lock:r:lock.txt:h
```

---

### Restore original firmware (if required)

```bash
avrdude -c atmelice_isp -p t85 \
  -U flash:w:powerblock_flash.hex:i \
  -U eeprom:w:powerblock_eeprom.hex:i \
  -U lfuse:w:0xE2:m \
  -U hfuse:w:0xDF:m \
  -U efuse:w:0xFF:m
```

---

## Notes

* The extended firmware remains compatible with the standard PowerBlock service
* The system will continue to behave like stock firmware unless reboot integration is installed on the Raspberry Pi
* Always verify wiring and programmer connections before flashing

---

