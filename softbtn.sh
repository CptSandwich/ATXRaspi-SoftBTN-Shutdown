#!/bin/bash

BUTTON=22

#setup GPIO $BUTTON as output and set to HIGH
echo "$BUTTON" > /sys/class/gpio/export;
echo "out" > /sys/class/gpio/gpio$BUTTON/direction
echo "1" > /sys/class/gpio/gpio$BUTTON/value

/bin/sleep 1

#restore GPIO $BUTTON
echo "0" > /sys/class/gpio/gpio$BUTTON/value