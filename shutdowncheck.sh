#!/bin/bash
# ATXRaspi BOOTOK + SHUTDOWN handler. Mirrors LowPowerLab's shutdowncheck.sh
# behaviour using libgpiod (kernel 6.6+ / Pi 5 compatible).
#
# - Drives BOOTOK HIGH for the life of the backgrounded gpioset child.
#   On script exit, the gpioset is intentionally NOT killed: it's left as
#   an orphan, holding BOOTOK HIGH through the rest of systemd's shutdown
#   sequence. systemd-shutdown reaps it in its final kill phase, dropping
#   BOOTOK at the truly last moment before the kernel halts.
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

PIDFILE=/run/atxraspi-bootok.pid

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

# Reap any leftover gpioset from a previous run (crash, manual stop, or a
# normal restart) so the new request below isn't blocked by a stale holder
# of the BOOTOK line. Briefly drops BOOTOK to LOW between the kill and the
# new request below; the ATXRaspi's input debounce makes this transient
# invisible in practice.
if [ -f "$PIDFILE" ]; then
  oldpid=$(cat "$PIDFILE" 2>/dev/null || true)
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    kill "$oldpid" 2>/dev/null || true
    sleep 0.5
  fi
  rm -f "$PIDFILE"
fi

# Hold BOOTOK HIGH in the background. --mode=signal keeps gpioset alive
# until it receives a signal. KillMode=process on the service unit means
# systemd will not signal this child when the main script is stopped;
# instead the gpioset survives until systemd-shutdown's final kill phase.
gpioset --mode=signal "$CHIP" "$BOOTOK=1" &
BOOTOK_PID=$!
echo "$BOOTOK_PID" > "$PIDFILE"

echo "ATXRaspi shutdowncheck: $CHIP, BOOTOK=$BOOTOK HIGH (PID $BOOTOK_PID), watching SHUTDOWN=$SHUTDOWN"

now_ms() { date +%s%3N; }

while true; do
  # Block until SHUTDOWN goes HIGH (efficient, no busy-poll).
  # --bias=pull-down ensures a disconnected/floating SHUTDOWN line reads LOW
  # so a missing/broken ATXRaspi can't trigger a spurious poweroff.
  gpiomon --rising-edge --num-events=1 --silent --bias=pull-down "$CHIP" "$SHUTDOWN" >/dev/null

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
