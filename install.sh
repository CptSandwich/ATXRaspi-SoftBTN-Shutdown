#!/bin/bash
# Installer for ATXRaspi-SoftBTN-Shutdown.
#
# Installs:
#   /sbin/softbtn.sh                       - 1s SoftBTN pulse on poweroff
#   /sbin/shutdowncheck.sh                 - asserts BOOTOK, watches SHUTDOWN
#   /etc/systemd/system/softbtn.service
#   /etc/systemd/system/shutdowncheck.service
#
# Ensures gpiod is present and prompts for the three GPIO pins.

set -e

SRCDIR="$(dirname "$(readlink -f "$0")")"
SOFTBTN_SH_SRC="$SRCDIR/softbtn.sh"
SHUTDOWNCHECK_SH_SRC="$SRCDIR/shutdowncheck.sh"
SOFTBTN_SVC_SRC="$SRCDIR/softbtn.service"
SHUTDOWNCHECK_SVC_SRC="$SRCDIR/shutdowncheck.service"

SOFTBTN_SH_DST="/sbin/softbtn.sh"
SHUTDOWNCHECK_SH_DST="/sbin/shutdowncheck.sh"
SOFTBTN_SVC_DST="/etc/systemd/system/softbtn.service"
SHUTDOWNCHECK_SVC_DST="/etc/systemd/system/shutdowncheck.service"

DEFAULT_SOFTBTN=10
DEFAULT_BOOTOK=8
DEFAULT_SHUTDOWN=7

# --- Require root -----------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "This installer needs root. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

echo "ATXRaspi SoftBTN + Shutdown installer"
echo "====================================="
echo

# --- Verify source files ----------------------------------------------------
for f in "$SOFTBTN_SH_SRC" "$SHUTDOWNCHECK_SH_SRC" "$SOFTBTN_SVC_SRC" "$SHUTDOWNCHECK_SVC_SRC"; do
  if [ ! -f "$f" ]; then
    echo "Error: missing source file: $f" >&2
    exit 1
  fi
done

# --- Detect LowPowerLab stock scripts ---------------------------------------
# LPL's installer adds a line to /etc/rc.local launching either
# /etc/shutdowncheck.sh or /etc/shutdownirq.py. Both drive BOOTOK and watch
# SHUTDOWN, so leaving them in place will fight our shutdowncheck.service.
LPL_RC_RE='shutdowncheck\.sh|shutdownirq\.py'
if [ -f /etc/rc.local ] && grep -qE "$LPL_RC_RE" /etc/rc.local; then
  echo "Detected LowPowerLab's stock shutdown script referenced in /etc/rc.local:"
  grep -nE "$LPL_RC_RE" /etc/rc.local | sed 's/^/  /'
  echo
  echo "Leaving these active will conflict with shutdowncheck.service (both will"
  echo "drive BOOTOK and watch SHUTDOWN)."
  read -rp "Comment out the LPL line(s) in /etc/rc.local now? [Y/n] " yn
  yn=${yn:-Y}
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    cp /etc/rc.local /etc/rc.local.bak
    sed -i -E "/$LPL_RC_RE/ s/^([[:space:]]*)([^#[:space:]])/\\1#\\2/" /etc/rc.local
    echo "Done. Original saved to /etc/rc.local.bak."
  else
    echo "Skipped. You will need to disable the LPL line manually for this"
    echo "installation to work correctly."
  fi
  echo
fi

# --- Install gpiod if missing -----------------------------------------------
if ! command -v gpioset >/dev/null 2>&1; then
  echo "gpiod not found. Installing..."
  apt-get update
  apt-get install -y gpiod
else
  echo "gpiod is already installed."
fi
echo

# --- Detect GPIO chip (informational) ---------------------------------------
echo "Detected GPIO chips:"
gpiodetect | sed 's/^/  /'
DETECTED_CHIP=$(gpiodetect | awk '/pinctrl-/{print $1; exit}')
DETECTED_CHIP=${DETECTED_CHIP:-gpiochip0}
echo
echo "Scripts will use: $DETECTED_CHIP (auto-detected at runtime)"
echo
echo "Note: on Raspberry Pi 5, some firmware revisions list two pinctrl-rp1"
echo "      chips. The scripts pick the first one, which is correct on all"
echo "      current firmware. If signals never fire on a Pi 5, run"
echo "      'gpiodetect' manually and edit CHIP= in the installed scripts."
echo

# --- Prompt for pins --------------------------------------------------------
prompt_pin() {
  local label="$1" default="$2" varname="$3" pin
  while true; do
    read -rp "BCM GPIO pin for $label [default $default]: " pin
    pin=${pin:-$default}
    if [[ "$pin" =~ ^[0-9]+$ ]] && [ "$pin" -ge 0 ] && [ "$pin" -le 53 ]; then
      printf -v "$varname" '%s' "$pin"
      return
    fi
    echo "  Please enter a number between 0 and 53."
  done
}

echo "Pin assignments (BCM numbering, matches LowPowerLab convention):"
prompt_pin "SoftBTN  (Pi -> ATXRaspi BTN, pulsed at poweroff)" "$DEFAULT_SOFTBTN" SOFTBTN_PIN
prompt_pin "BOOTOK   (Pi -> ATXRaspi BOOTOK, held HIGH while running)" "$DEFAULT_BOOTOK" BOOTOK_PIN
prompt_pin "SHUTDOWN (ATXRaspi -> Pi, monitored for poweroff/reboot)" "$DEFAULT_SHUTDOWN" SHUTDOWN_PIN
echo

# --- Install scripts --------------------------------------------------------
echo "Installing $SOFTBTN_SH_DST (SOFTBTN=$SOFTBTN_PIN)..."
sed "s/^SOFTBTN=.*/SOFTBTN=$SOFTBTN_PIN/" "$SOFTBTN_SH_SRC" > "$SOFTBTN_SH_DST"
chmod +x "$SOFTBTN_SH_DST"

echo "Installing $SHUTDOWNCHECK_SH_DST (BOOTOK=$BOOTOK_PIN, SHUTDOWN=$SHUTDOWN_PIN)..."
sed -e "s/^BOOTOK=.*/BOOTOK=$BOOTOK_PIN/" \
    -e "s/^SHUTDOWN=.*/SHUTDOWN=$SHUTDOWN_PIN/" \
    "$SHUTDOWNCHECK_SH_SRC" > "$SHUTDOWNCHECK_SH_DST"
chmod +x "$SHUTDOWNCHECK_SH_DST"

# --- Install services -------------------------------------------------------
echo "Installing $SOFTBTN_SVC_DST..."
cp "$SOFTBTN_SVC_SRC" "$SOFTBTN_SVC_DST"

echo "Installing $SHUTDOWNCHECK_SVC_DST..."
cp "$SHUTDOWNCHECK_SVC_SRC" "$SHUTDOWNCHECK_SVC_DST"

# --- Enable services --------------------------------------------------------
echo "Reloading systemd and enabling services..."
systemctl daemon-reload
systemctl enable softbtn.service
systemctl enable shutdowncheck.service

# Start shutdowncheck.service immediately so BOOTOK is asserted now and the
# SHUTDOWN watcher is live without requiring a reboot. softbtn.service is a
# oneshot triggered by shutdown.target -- starting it now would fire the
# pulse, so we leave it enabled but not started; it will run automatically
# at the next poweroff.
echo "Starting (or restarting) shutdowncheck.service..."
systemctl restart shutdowncheck.service

# --- Summary ----------------------------------------------------------------
echo
echo "Done."
echo "  SoftBTN pulse:  $SOFTBTN_SH_DST  (BCM $SOFTBTN_PIN)"
echo "  Shutdowncheck:  $SHUTDOWNCHECK_SH_DST  (BOOTOK=BCM $BOOTOK_PIN, SHUTDOWN=BCM $SHUTDOWN_PIN)"
echo "  Services:       softbtn.service, shutdowncheck.service"
echo "  Chip:           $DETECTED_CHIP (auto-detected each boot)"
echo
echo "shutdowncheck.service is now running; softbtn.service will fire on next poweroff."
echo "Re-run this installer any time to change pins."
