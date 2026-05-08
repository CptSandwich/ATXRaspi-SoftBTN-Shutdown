# ATXRaspi-SoftBTN-Shutdown

A drop-in replacement for [LowPowerLab's](https://lowpowerlab.com/guide/atxraspi/)
`shutdowncheck` script, plus an extra SoftBTN pulse so software-initiated
shutdowns also trigger the ATXRaspi power-cut.

Works on **Raspberry Pi 1, 2, 3, 4, Zero, and Pi 5**, including Raspberry Pi
OS Bookworm and other distros on kernel 6.6+. Uses `libgpiod` (the modern
chardev interface). The older `/sys/class/gpio` sysfs interface is
deprecated and broke on kernel 6.6+ (pin numbering shifted, e.g. BCM 4
appears as `gpio516`).

## Pins

Three GPIO lines connect the Pi to the ATXRaspi. Names and defaults match
LowPowerLab's convention:

| Name     | Direction     | What this repo's code does                                        | Default BCM pin |
| -------- | ------------- | ----------------------------------------------------------------- | --------------- |
| BOOTOK   | Pi → ATXRaspi | Driven HIGH for the life of `shutdowncheck.service`.              | 8               |
| SHUTDOWN | ATXRaspi → Pi | Monitored for HIGH pulses; long pulse → poweroff, short → reboot. | 7               |
| SoftBTN  | Pi → ATXRaspi | Pulsed HIGH for ~1 s on poweroff (not on reboot).                 | 10              |

## What gets installed

Two scripts and two systemd services.

### `/sbin/shutdowncheck.sh` + `shutdowncheck.service`

Mirrors LowPowerLab's `shutdowncheck.sh` using libgpiod:

- Drives the **BOOTOK** line HIGH via a backgrounded `gpioset --mode=signal`.
  The line stays HIGH until the gpioset child is killed, which happens when
  the service is stopped at the very end of shutdown.
- Watches the **SHUTDOWN** line and reacts to HIGH pulses by duration:
  - `>600 ms`           → `systemctl poweroff`
  - `200–600 ms then LOW` → `systemctl reboot`
  - `<200 ms`           → ignored (debounce)

Started at boot (`WantedBy=multi-user.target`). The unit uses
`DefaultDependencies=no` plus explicit
`Conflicts=poweroff.target halt.target reboot.target` and
`Before=poweroff.target halt.target reboot.target`, so it is stopped only
when one of those targets activates, i.e. after `softbtn.service` has run
and after filesystems are remounted read-only. BOOTOK therefore drops late
in the shutdown sequence, matching LowPowerLab's stock-script behaviour
(their sysfs-based script holds BOOTOK HIGH until the kernel itself halts
the GPIO controller; ours releases it slightly earlier, but in the same
"shutdown is essentially complete" window).

### `/sbin/softbtn.sh` + `softbtn.service`

Pulses the **SoftBTN** line HIGH for ~1 s. The unit has
`Conflicts=reboot.target` and `Requires=poweroff.target`, so it runs only
on `poweroff` / `halt`, never on `reboot`. This pulse is what
LowPowerLab's stock setup doesn't provide. Without it, software-initiated
shutdowns (`sudo poweroff`, desktop "Shut Down", a media-player web UI,
Klipper / OctoPrint, etc.) leave the ATXRaspi with no "shutdown coming"
indication and the 5 V rail stays on.

The pulse fires before `poweroff.target` activates; `shutdowncheck.service`
is stopped *by* `poweroff.target` activating. The two are therefore
naturally ordered: SoftBTN pulse → poweroff.target activates → BOOTOK
drops.

## Install

```bash
git clone https://github.com/CptSandwich/ATXRaspi-SoftBTN-Shutdown.git
cd ATXRaspi-SoftBTN-Shutdown
sudo ./install.sh
```

The installer:

1. Ensures `gpiod` is installed.
2. Shows detected GPIO chips.
3. Prompts for the three BCM pins (defaults: SoftBTN=10, BOOTOK=8, SHUTDOWN=7).
4. Installs both scripts to `/sbin` and both services to
   `/etc/systemd/system`, then enables them.

Reboot to start `shutdowncheck.service`, or run
`sudo systemctl start shutdowncheck.service` to bring it up immediately.

Re-run any time to change pins.

### Manual

```bash
sudo apt install -y gpiod
# Edit pin variables at the top of softbtn.sh and shutdowncheck.sh
sudo install -m 755 softbtn.sh /sbin/softbtn.sh
sudo install -m 755 shutdowncheck.sh /sbin/shutdowncheck.sh
sudo install -m 644 softbtn.service /etc/systemd/system/softbtn.service
sudo install -m 644 shutdowncheck.service /etc/systemd/system/shutdowncheck.service
sudo systemctl daemon-reload
sudo systemctl enable softbtn.service shutdowncheck.service
sudo systemctl start shutdowncheck.service
```

## Verifying

```bash
systemctl status shutdowncheck.service          # should be active (running)
systemctl is-enabled softbtn.service            # should be enabled
journalctl -u shutdowncheck.service -b          # current boot
journalctl -u softbtn.service -b -1             # previous boot's shutdown
```

To test the SoftBTN pulse manually:

```bash
sudo /sbin/softbtn.sh
```

## GPIO chip / Pi 5 note

Both scripts pick the chip via `gpiodetect`, choosing the first one whose
label starts with `pinctrl-` (the 40-pin header on every supported Pi). You
shouldn't normally need to change `CHIP=`, even when moving the SD card
between models.

The exception is **Pi 5**: some firmware lists two `pinctrl-rp1` entries.
Both currently work, but if signals never fire on a Pi 5, run `gpiodetect`
and set `CHIP=` explicitly in the installed scripts (e.g. `CHIP=gpiochip4`).
The BCM pin numbers themselves are identical on every Pi model.

## Recovery: disabling the scripts without booting the Pi

If the ATXRaspi is removed or fails, the SHUTDOWN line may float HIGH and
trigger an immediate poweroff before you can log in. Both scripts check
for a marker file on the FAT boot partition and exit immediately without
touching any GPIO if it's present:

- `/boot/firmware/atxraspi-disable` (Bookworm and newer)
- `/boot/atxraspi-disable`           (older Pi OS)

Recovery flow:

1. Power off the Pi, pull the SD card.
2. Mount the SD card on another machine. The boot partition is FAT, so
   any OS can read/write it. Create an empty file named `atxraspi-disable`
   (no extension required) at the root of that partition.
3. Reinsert the SD card and boot. `shutdowncheck.service` will start, log
   that it's disabled, and exit cleanly. SoftBTN pulses are also skipped.

Delete the file to re-enable.

As a second layer of defence, `shutdowncheck.sh` configures the SHUTDOWN
line with an internal pull-down (`--bias=pull-down`), so a disconnected
line reads LOW and won't trigger a spurious poweroff on its own.

## Disabling LowPowerLab's stock script

If you previously installed LPL's `shutdowncheck.sh` / `shutdownirq.py` via
`/etc/rc.local`, comment that line out before installing this one. Both
will fight over BOOTOK and SHUTDOWN otherwise:

```bash
sudo sed -i '/shutdown/ s/^#*/#/' /etc/rc.local
```

## Uninstall

```bash
sudo systemctl disable --now softbtn.service shutdowncheck.service
sudo rm /etc/systemd/system/softbtn.service /etc/systemd/system/shutdowncheck.service
sudo rm /sbin/softbtn.sh /sbin/shutdowncheck.sh
sudo systemctl daemon-reload
```
