# ATXRaspi-SoftBTN-Shutdown

A small systemd-driven script that signals a [LowPowerLab ATXRaspi](https://lowpowerlab.com/guide/atxraspi/)
to cut power once the Raspberry Pi has finished shutting down.

Works on **Raspberry Pi 1, 2, 3, 4, Zero, and Pi 5**, including Raspberry Pi
OS Bookworm and other distros on kernel 6.6+.

## What it does

ATXRaspi watches the **SoftBTN** GPIO line for a HIGH→LOW transition meaning
"OS is done, cut the 5V rail." This repo provides that pulse as a one-shot
systemd unit fired late in shutdown:

- `softbtn.sh` pulses the chosen GPIO HIGH for ~1s then LOW, using `gpioset`
  from `libgpiod`.
- `softbtn.service` runs `softbtn.sh` before `poweroff.target` /
  `halt.target`, and *not* on reboot.

Because it hooks into `shutdown.target`, it fires for **any** halt path:
`sudo shutdown`, `sudo poweroff`, the physical button via `gpio-shutdown`,
desktop "Shut Down" menus, or third-party apps and services that trigger a
shutdown through the normal system mechanism (e.g. a media-player web UI
with its own "Shut Down" button). LowPowerLab's stock script only runs when
explicitly invoked, so any of those paths would bypass it and leave the 5V
rail on.

The older `/sys/class/gpio` sysfs interface is deprecated and broke on kernel
6.6+ (pin numbering shifted, e.g. BCM 4 appears as `gpio516`); `gpioset` uses
the stable `/dev/gpiochip*` chardev instead.

## Install

The default pin is **BCM GPIO 22**. Change it during install if yours is
wired elsewhere.

### Automated (recommended)

```bash
git clone https://github.com/CptSandwich/ATXRaspi-SoftBTN-Shutdown.git
cd ATXRaspi-SoftBTN-Shutdown
sudo ./install.sh
```

The installer ensures `gpiod` is installed, shows detected GPIO chips, prompts
for the BCM pin, then installs the script and systemd unit. Re-run any time to
change the pin.

### Manual

```bash
sudo apt install -y gpiod
# Edit BUTTON= in softbtn.sh if not using BCM 22
sudo install -m 755 softbtn.sh /sbin/softbtn.sh
sudo install -m 644 softbtn.service /etc/systemd/system/softbtn.service
sudo systemctl daemon-reload
sudo systemctl enable softbtn.service
```

Confirm with `systemctl is-enabled softbtn.service`. To see it actually fire,
check `journalctl -u softbtn` after a real shutdown/power cycle.

## GPIO chip / Pi 5 note

`softbtn.sh` picks the chip via `gpiodetect`, choosing the first one whose
label starts with `pinctrl-` (the 40-pin header on every supported Pi). You
shouldn't normally need to change `CHIP=`, even when moving the SD card
between models.

The exception is **Pi 5**: some firmware lists two `pinctrl-rp1` entries.
Both currently work, but if SoftBTN never fires on a Pi 5, run `gpiodetect`
and set `CHIP=` explicitly in `/sbin/softbtn.sh` (e.g. `CHIP=gpiochip4`).
The BCM pin number itself is identical on every Pi model.

## Uninstall

```bash
sudo systemctl disable softbtn.service
sudo rm /etc/systemd/system/softbtn.service /sbin/softbtn.sh
sudo systemctl daemon-reload
```
