#!/bin/bash
# Installer for ATXRaspi-SoftBTN-Shutdown.
# Installs softbtn.sh to /sbin, the systemd unit to /etc/systemd/system,
# ensures gpiod is present, and lets you pick the BCM GPIO pin.

set -e

SCRIPT_SRC="$(dirname "$(readlink -f "$0")")/softbtn.sh"
SERVICE_SRC="$(dirname "$(readlink -f "$0")")/softbtn.service"
SCRIPT_DST="/sbin/softbtn.sh"
SERVICE_DST="/etc/systemd/system/softbtn.service"
DEFAULT_PIN=10

# --- Require root -----------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "This installer needs root. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

echo "ATXRaspi SoftBTN shutdown installer"
echo "==================================="
echo

# --- Verify source files ----------------------------------------------------
if [ ! -f "$SCRIPT_SRC" ] || [ ! -f "$SERVICE_SRC" ]; then
  echo "Error: softbtn.sh or softbtn.service not found next to install.sh." >&2
  exit 1
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
echo "softbtn.sh will use: $DETECTED_CHIP (auto-detected at runtime)"
echo
echo "Note: on Raspberry Pi 5, some firmware revisions list two pinctrl-rp1"
echo "      chips. The script picks the first one, which is correct on all"
echo "      current firmware. If your SoftBTN never fires on a Pi 5, run"
echo "      'gpiodetect' manually and edit CHIP= in $SCRIPT_DST."
echo

# --- Prompt for BCM pin -----------------------------------------------------
while true; do
  read -rp "BCM GPIO pin for ATXRaspi SoftBTN [default $DEFAULT_PIN]: " PIN
  PIN=${PIN:-$DEFAULT_PIN}
  if [[ "$PIN" =~ ^[0-9]+$ ]] && [ "$PIN" -ge 0 ] && [ "$PIN" -le 53 ]; then
    break
  fi
  echo "  Please enter a number between 0 and 53."
done
echo

# --- Install script (with chosen BUTTON value) ------------------------------
echo "Installing $SCRIPT_DST (BUTTON=$PIN)..."
sed "s/^BUTTON=.*/BUTTON=$PIN/" "$SCRIPT_SRC" > "$SCRIPT_DST"
chmod +x "$SCRIPT_DST"

# --- Install service --------------------------------------------------------
echo "Installing $SERVICE_DST..."
cp "$SERVICE_SRC" "$SERVICE_DST"

# --- Enable service ---------------------------------------------------------
echo "Reloading systemd and enabling softbtn.service..."
systemctl daemon-reload
systemctl enable softbtn.service

# --- Summary ----------------------------------------------------------------
echo
echo "Done."
echo "  Script:  $SCRIPT_DST"
echo "  Service: $SERVICE_DST"
echo "  Pin:     BCM GPIO $PIN"
echo "  Chip:    $DETECTED_CHIP (auto-detected each boot)"
echo
echo "Re-run this installer any time to change the pin."
