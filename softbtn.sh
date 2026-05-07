#!/bin/bash
# Pulses the ATXRaspi SoftBTN line HIGH for ~1 second, then drives it LOW.
# Triggered by softbtn.service on system shutdown so ATXRaspi cuts power
# cleanly after the OS halts.
#
# Requires: gpiod  (sudo apt install gpiod)

BUTTON=22

# Auto-detect the 40-pin header GPIO chip.
#   - Pi 1/2/3/4/Zero: labelled "pinctrl-bcm2835" (or similar) -> usually gpiochip0
#   - Pi 5:            labelled "pinctrl-rp1"                  -> usually gpiochip0 or gpiochip4
CHIP=$(gpiodetect | awk '/pinctrl-/{print $1; exit}')
CHIP=${CHIP:-gpiochip0}

# Hold the line HIGH for 1 second, then drive LOW.
gpioset --mode=time --sec=1 "$CHIP" "$BUTTON=1"
gpioset --mode=exit "$CHIP" "$BUTTON=0"
