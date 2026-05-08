#!/bin/bash
# ATXRaspi BOOTOK + SHUTDOWN handler. Mirrors LowPowerLab's shutdowncheck.sh
# behaviour using libgpiod for the SHUTDOWN watcher and (configurably)
# either libgpiod or sysfs for the BOOTOK assertion.
#
# - Drives BOOTOK HIGH while the system is up. Two methods:
#     gpiod  (default): backgrounded gpioset --mode=signal. Released when
#                       this script exits (i.e. early in shutdown).
#     sysfs:           sets the line via /sys/class/gpio. Pin state is
#                       owned by the kernel and persists after this script
#                       exits, so BOOTOK stays HIGH later into shutdown -
#                       until the kernel itself releases it during halt.
# - Watches the SHUTDOWN line driven by the ATXRaspi (always libgpiod):
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

# How to assert BOOTOK HIGH. Set by install.sh; one of: gpiod, sysfs.
BOOTOK_METHOD=gpiod

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

# --- Assert BOOTOK HIGH -----------------------------------------------------
case "$BOOTOK_METHOD" in
  sysfs)
    # Find the chip's sysfs base by matching pinctrl- label, then offset by BCM
    # pin number. Required because kernel 6.6+ shifted sysfs pin numbering
    # (e.g. BCM 4 appears as gpio516 instead of gpio4).
    SYSFS_BASE=""
    for d in /sys/class/gpio/gpiochip*; do
      [ -r "$d/label" ] || continue
      case "$(cat "$d/label")" in
        pinctrl-*)
          SYSFS_BASE=$(cat "$d/base")
          break
          ;;
      esac
    done
    if [ -z "$SYSFS_BASE" ]; then
      echo "ATXRaspi: could not find a pinctrl- chip in /sys/class/gpio; aborting." >&2
      exit 1
    fi
    SYSFS_PIN=$((SYSFS_BASE + BOOTOK))
    if [ ! -d "/sys/class/gpio/gpio$SYSFS_PIN" ]; then
      echo "$SYSFS_PIN" > /sys/class/gpio/export 2>/dev/null || true
    fi
    echo out > "/sys/class/gpio/gpio$SYSFS_PIN/direction"
    echo 1   > "/sys/class/gpio/gpio$SYSFS_PIN/value"
    echo "ATXRaspi shutdowncheck: $CHIP, BOOTOK=$BOOTOK (sysfs gpio$SYSFS_PIN) HIGH, watching SHUTDOWN=$SHUTDOWN"
    # No holding process; the kernel preserves the value until something
    # explicitly changes it or the kernel itself halts.
    ;;

  gpiod|*)
    gpioset --mode=signal "$CHIP" "$BOOTOK=1" &
    BOOTOK_PID=$!
    echo "ATXRaspi shutdowncheck: $CHIP, BOOTOK=$BOOTOK (gpiod) HIGH, watching SHUTDOWN=$SHUTDOWN"
    ;;
esac

# On SIGTERM/SIGINT, kill the gpiomon child (if any) and the BOOTOK gpioset
# (if running) so bash can exit promptly. Without this trap, bash queues
# signals until the foreground command returns - and gpiomon blocks until a
# rising edge that may never come, so a `systemctl restart` would hang
# until TimeoutStopSec elapses.
cleanup() {
  if [ -n "${GPIOMON_PID:-}" ]; then
    kill "$GPIOMON_PID" 2>/dev/null || true
  fi
  if [ -n "${BOOTOK_PID:-}" ]; then
    kill "$BOOTOK_PID" 2>/dev/null || true
  fi
}
trap cleanup INT TERM EXIT

# --- SHUTDOWN watcher (always libgpiod) -------------------------------------
now_ms() { date +%s%3N; }

while true; do
  # Block until SHUTDOWN goes HIGH (efficient, no busy-poll).
  # --bias=pull-down ensures a disconnected/floating SHUTDOWN line reads LOW
  # so a missing/broken ATXRaspi can't trigger a spurious poweroff.
  # Run gpiomon in the background and `wait` for it so the trap above can
  # interrupt the wait on SIGTERM; running it in the foreground would let
  # the signal queue until the (potentially never-arriving) rising edge.
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
