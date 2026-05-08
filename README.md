# ATXRaspi-SoftBTN-Shutdown

[LowPowerLab's ATXRaspi](https://lowpowerlab.com/guide/atxraspi/) is a great
little smart-power controller for the Raspberry Pi, and the
[stock setup script](https://github.com/LowPowerLab/ATX-Raspi) has served
the community well for years. This repo is a reimplementation of the
Pi-side software, written from scratch using `libgpiod` and `systemd` so it
works cleanly on kernel 6.6+, Bookworm, and the Pi 5 (where the original
`RPi.GPIO` / sysfs approach no longer works reliably). It remains fully
compatible with the existing ATXRaspi hardware.

It also adds an extra **SoftBTN pulse** on shutdown, so the ATXRaspi cuts
power even when shutdown is initiated from software (`sudo poweroff`,
desktop "Shut Down", a media-player web UI, Klipper / OctoPrint, etc.) and
not just from the physical button.

> **Tested on:** Raspberry Pi 4 (Bookworm). The libgpiod / chip-detection
> approach is model-agnostic and should work on Pi 1, 2, 3, Zero, and Pi 5
> as well, but those have not been verified by the author. Reports welcome.

## Install

```bash
git clone https://github.com/CptSandwich/ATXRaspi-SoftBTN-Shutdown.git
cd ATXRaspi-SoftBTN-Shutdown
sudo ./install.sh
```

The installer:

1. Detects (and offers to disable) any LowPowerLab stock script in `/etc/rc.local`.
2. Ensures `gpiod` is installed.
3. Prompts for the three BCM pins (defaults: SoftBTN=10, BOOTOK=8, SHUTDOWN=7).
4. Installs both scripts to `/sbin` and both services to `/etc/systemd/system`.
5. Enables both services and starts `shutdowncheck.service` immediately.

No reboot required. Re-run any time to change pins.

## Recovery escape hatch

If the ATXRaspi is removed or fails, the SHUTDOWN line could float HIGH and
trigger an immediate poweroff. To boot anyway:

1. Power off the Pi, pull the SD card.
2. On any other machine, create an empty file named `atxraspi-disable` at
   the root of the FAT boot partition.
3. Reinsert and boot. Both scripts detect the marker and exit without
   touching any GPIO. Delete the file to re-enable.

As a second layer of defence, `shutdowncheck.sh` sets `--bias=pull-down` on
the SHUTDOWN line so a disconnected line reads LOW.

---

## Details

### Pins

Three GPIO lines connect the Pi to the ATXRaspi. Names and defaults match
LowPowerLab's convention:

| Name     | Direction     | What this repo's code does                                        | Default BCM pin |
| -------- | ------------- | ----------------------------------------------------------------- | --------------- |
| BOOTOK   | Pi → ATXRaspi | Driven HIGH for the life of `shutdowncheck.service`.              | 8               |
| SHUTDOWN | ATXRaspi → Pi | Monitored for HIGH pulses; long pulse → poweroff, short → reboot. | 7               |
| SoftBTN  | Pi → ATXRaspi | Pulsed HIGH for ~1 s on poweroff (not on reboot).                 | 10              |

### What gets installed

**`/sbin/shutdowncheck.sh` + `shutdowncheck.service`**:

- Drives BOOTOK HIGH via a backgrounded `gpioset --mode=signal`.
- Watches SHUTDOWN with the same pulse-duration logic as LPL:
  - `>600 ms`             → `systemctl poweroff`
  - `200–600 ms then LOW` → `systemctl reboot`
  - `<200 ms`             → ignored (debounce)

The unit uses `DefaultDependencies=no` plus explicit
`Conflicts=poweroff.target halt.target reboot.target` and
`Before=poweroff.target halt.target reboot.target`, so it is stopped only
when one of those targets activates, i.e. after `softbtn.service` has run
and after filesystems are remounted read-only. BOOTOK therefore drops late
in the shutdown sequence.

**`/sbin/softbtn.sh` + `softbtn.service`** pulses SoftBTN HIGH for ~1 s.
The unit has `Conflicts=reboot.target` and `Requires=poweroff.target`, so
it runs only on `poweroff` / `halt`, never on `reboot`. Without this pulse,
software-initiated shutdowns leave the ATXRaspi with no "shutdown coming"
indication and the 5 V rail stays on.

The pulse fires before `poweroff.target` activates; `shutdowncheck.service`
is stopped *by* `poweroff.target` activating. The two are therefore
naturally ordered: SoftBTN pulse → poweroff.target activates → BOOTOK
drops.

### libgpiod vs sysfs

Uses `libgpiod` (the modern chardev interface). The older `/sys/class/gpio`
sysfs interface is deprecated and broke on kernel 6.6+ (pin numbering
shifted, e.g. BCM 4 appears as `gpio516`). `RPi.GPIO`, used by LPL's
Python script, is also broken on the Pi 5.

### GPIO chip / Pi 5 note

Both scripts pick the chip via `gpiodetect`, choosing the first one whose
label starts with `pinctrl-` (the 40-pin header on every supported Pi). You
shouldn't normally need to change `CHIP=`, even when moving the SD card
between models.

The exception is **Pi 5**: some firmware lists two `pinctrl-rp1` entries.
Both currently work, but if signals never fire on a Pi 5, run `gpiodetect`
and set `CHIP=` explicitly in the installed scripts (e.g. `CHIP=gpiochip4`).
The BCM pin numbers themselves are identical on every Pi model.

### Manual install

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

### Verifying

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

### Disabling LowPowerLab's stock script

The installer detects and offers to comment out any LPL line in
`/etc/rc.local` automatically. To do it manually:

```bash
sudo sed -i '/shutdown/ s/^#*/#/' /etc/rc.local
```

### Uninstall

```bash
sudo systemctl disable --now softbtn.service shutdowncheck.service
sudo rm /etc/systemd/system/softbtn.service /etc/systemd/system/shutdowncheck.service
sudo rm /sbin/softbtn.sh /sbin/shutdowncheck.sh
sudo systemctl daemon-reload
```

## Acknowledgements

The [ATXRaspi hardware](https://lowpowerlab.com/shop/product/118) is
designed and sold by LowPowerLab, and their original
[shutdown script](https://github.com/LowPowerLab/ATX-Raspi) was the
launching pad for this project. The Pi-side software here is a clean
rewrite using libgpiod and systemd, but it would not exist without their
work.

## License

MIT. See [LICENSE](LICENSE).
