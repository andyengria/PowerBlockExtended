# RPI Testing

To test your backward-compatibility across the three mechanisms for GPIO access on Raspberry Pi, we target a combination of hardware and software setups that cover the following:

- libgpiod v2: Introduced in newer distributions, it is the current preferred library for GPIO access on modern Raspberry Pi systems.
- libgpiod v1: Older versions of libgpiod which are still supported on legacy systems.
- Sysfs fallback: The older GPIO access mechanism used by Raspbian before libgpiod was introduced.

### Hardware Choices for Testing:
- Raspberry Pi 4 Model B: This is the most current and widely used Raspberry Pi model, running the latest distributions of Raspberry Pi OS. It will give you the best insight into how your tool works with libgpiod v2.
- Raspberry Pi 3 Model B/B+: This model is a great choice because it is still widely in use and will run older versions of libgpiod v1 in its legacy distributions. It's a good bridge between older and newer models.
- Raspberry Pi Zero W: While this is a smaller form factor, it often runs older distributions of Raspberry Pi OS, which would help you test sysfs fallback. It is still a valid platform for GPIO projects, and it provides a test environment for the sysfs method.

Software & OS Versions:
- Raspberry Pi OS (Buster / Bullseye): On these releases, libgpiod v2 is supported natively.
- Raspbian Stretch (or earlier): For testing libgpiod v1 and sysfs fallback, we use this older OS version.

### Suggested Test Matrix:

Raspberry Pi 4 Model B (latest OS release, Bullseye):
- libgpiod v2 (default).
- Check if your tool works with the latest GPIO access method.

Raspberry Pi 3 Model B/B+ (Raspberry Pi OS Buster):
- Test with libgpiod v1 (legacy).
- Check fallback to sysfs if libgpiod v1 is not available.

Raspberry Pi Zero W (Raspbian Stretch or earlier):
- Test with sysfs fallback if the version of libgpiod is too old or absent.
- This should give you the best coverage of legacy hardware and software.

By testing across these combinations, we cover all three mechanisms: libgpiod v2, libgpiod v1, and sysfs.


Small bash script to verify versions on the Pi:

'''bash
echo "=== gpiochip devices ==="
ls /dev/gpiochip* 2>/dev/null || echo "none"

echo "=== libgpiod version ==="
if command -v gpioinfo >/dev/null 2>&1; then
    gpioinfo -v
elif command -v gpiodetect >/dev/null 2>&1; then
    gpiodetect -v
else
    echo "libgpiod tools not found"
fi

echo "=== sysfs status ==="
if [ -e /sys/class/gpio/export ]; then
    echo "sysfs GPIO present (deprecated)"
else
    echo "sysfs GPIO absent"
fi
'''
