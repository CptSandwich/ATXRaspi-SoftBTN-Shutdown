#!/bin/bash
# ATXRaspi BOOTOK + SHUTDOWN handler. Mirrors LowPowerLab's shutdowncheck.sh
# behaviour using libgpiod (kernel 6.6+ / Pi 5 compatible).
#
# - Drives BOOTOK HIGH for the life of this process (released on exit, which
#   is what the ATXRaspi watches for as the "Pi has halted" signal).
# - Watches the SHUTDOWN line driven by the ATXRaspi:
#     pulse HIGH > 600 ms          -> poweroff
#     pulse HIGH 200-600 ms        -> reboot
#     pulse HIGH < 200 ms          -> ignored (debounce)
#
# Requires: gpiod  (sudo apt install gpiod)

set -u

BOOTOK=8
SHUTDOWN=7
REBOOTPULSEMINIMUM=200
REBOOTPULSEMAXIMUM=600

# Recovery escape hatch: if a marker file is present on the boot partition,
# exit immediately without touching any GPIO. Lets you boot a system whose
# ATXRaspi has been removed or failed by dropping an empty file named
# 'atxraspi-disable' onto the FAT boot partition from another machine.
for marker in /boot/firmware/atxraspi-disable /boot/atxraspi-disable; do
  if [ -e "$marker" ]; then
    echo "ATXRaspi: disabled by $marker, exiting."
    exit 0
  fi
done

# Auto-detect the 40-pin header GPIO chip.
#   - Pi 1/2/3/4/Zero: pinctrl-bcm2835/2711/etc -> usually gpiochip0
#   - Pi 5:            pinctrl-rp1               -> usually gpiochip0
CHIP=$(gpiodetect | awk '/pinctrl-/{print $1; exit}')
CHIP=${CHIP:-gpiochip0}

cleanup() {
  trap '' INT TERM EXIT
  if [ -n "${GPIOMON_PID:-}" ]; then
    kill "$GPIOMON_PID" 2>/dev/null || true
  fi
  if [ -n "${BOOTOK_PID:-}" ]; then
    kill "$BOOTOK_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup INT TERM EXIT

# Assert BOOTOK HIGH. Prefer the gpio-leds overlay: the kernel's leds-gpio
# driver holds the pin without a userspace process and retains it through
# shutdown via retain-state-shutdown. Fall back to libgpiod if the overlay
# isn't loaded yet (e.g. before the first reboot after install, or on Pi 5).
BOOTOK_LED=/sys/class/leds/atxraspi-bootok/brightness
if [ -f "$BOOTOK_LED" ]; then
  echo 1 > "$BOOTOK_LED"
  echo "ATXRaspi shutdowncheck: BOOTOK via gpio-leds, watching SHUTDOWN=$SHUTDOWN"
else
  gpioset --mode=signal "$CHIP" "$BOOTOK=1" &
  BOOTOK_PID=$!
  echo "ATXRaspi shutdowncheck: BOOTOK=$BOOTOK via libgpiod (fallback), watching SHUTDOWN=$SHUTDOWN on $CHIP"
fi

now_ms() { date +%s%3N; }

while true; do
  # Block until SHUTDOWN goes HIGH (efficient, no busy-poll).
  # --bias=pull-down ensures a disconnected/floating SHUTDOWN line reads LOW
  # so a missing/broken ATXRaspi can't trigger a spurious poweroff.
  # Run gpiomon in the background and `wait` for it so the trap can interrupt
  # on SIGTERM; running it in the foreground would let the signal queue until
  # the (potentially never-arriving) rising edge, which causes systemctl
  # restart to hang for TimeoutStopSec.
  gpiomon --rising-edge --num-events=1 --silent --bias=pull-down "$CHIP" "$SHUTDOWN" >/dev/null &
  GPIOMON_PID=$!
  wait "$GPIOMON_PID" 2>/dev/null || true
  unset GPIOMON_PID

  start=$(now_ms)
  # Measure how long the pulse stays HIGH.
  while [ "$(gpioget --bias=pull-down "$CHIP" "$SHUTDOWN")" = "1" ]; do
    elapsed=$(( $(now_ms) - start ))
    if [ "$elapsed" -gt "$REBOOTPULSEMAXIMUM" ]; then
      echo "ATXRaspi: SHUTDOWN held > ${REBOOTPULSEMAXIMUM}ms -> poweroff"
      systemctl poweroff
      exit 0
    fi
    sleep 0.02
  done

  elapsed=$(( $(now_ms) - start ))
  if [ "$elapsed" -gt "$REBOOTPULSEMINIMUM" ]; then
    echo "ATXRaspi: SHUTDOWN pulse ${elapsed}ms -> reboot"
    systemctl reboot
    exit 0
  fi
done
