ATtiny flashing
Hardware / programmer

I reccomend that the ATtiny85 should be flashed over ISP (In-System Programmer) using an Atmel-ICE.
There are ways to use an Arduino as ISP if you dont have the Atmel-ICE but i did not test these.  

First you will need to solder header pins onto your powerblock / connect to the header pins

Compile the new firmware in arduino ide.

Known-good Arduino IDE settings
Use:

Board: ATtiny25/45/85
Chip: ATtiny85
Clock: 8 MHz internal
Programmer: Atmel-ICE (AVR)
Action: Upload Using Programmer
Known fuse values

Original fuses observed:

lfuse = 0xE2
hfuse = 0xDF
efuse = 0xFF
lock = 0xFF
Recommended flashing workflow
Connect Atmel-ICE over ISP
Read chip with avrdude
Back up:
flash
EEPROM
fuses
Build firmware in Arduino IDE
Use Upload Using Programmer
Verify operation on hardware
Recommended backup checklist

Before uploading the new firmware, also recommend back up the original in case:
This makes rollback for any reason easy.

These are the key commands you need to use: 
#check the connection to the attiny by reading the chip signature
avrdude -c atmelice_isp -p t85 -v

#backup the existing firmware
avrdude -c atmelice_isp -p t85   \
  -U flash:r:powerblock_flash.hex:i   \
  -U eeprom:r:powerblock_eeprom.hex:i   \
  -U lfuse:r:lfuse.txt:h   \
  -U hfuse:r:hfuse.txt:h   \
  -U efuse:r:efuse.txt:h   \ 
  -U lock:r:lock.txt:h

#restore the existing firmware if necessary
avrdude -c atmelice_isp -p t85 \
  -U flash:w:powerblock_flash.hex:i \
  -U eeprom:w:powerblock_eeprom.hex:i \
  -U lfuse:w:0xE2:m \
  -U hfuse:w:0xDF:m \
  -U efuse:w:0xFF:m

Note the new firmware will operate as the old stock firmware even withot the additonal extended rpi software.
