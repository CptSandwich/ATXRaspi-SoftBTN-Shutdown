# ATXRaspi-SoftBTN-Shutdown

Pi-side software for the [LowPowerLab ATXRaspi](https://lowpowerlab.com/guide/atxraspi/), rewritten with `libgpiod` and `systemd` so it works on Pi 5 and kernel 6.6+ (Bookworm and later). Adds a SoftBTN pulse on poweroff so the ATXRaspi cuts power for all software-initiated shutdowns too, not just the physical button.

> Tested on Pi 4 (Bookworm). Should work on Pi 1/2/3/Zero/5 but unverified.

## Install

```bash
git clone https://github.com/CptSandwich/ATXRaspi-SoftBTN-Shutdown.git
cd ATXRaspi-SoftBTN-Shutdown
sudo ./install.sh
```

The installer detects and offers to disable any LowPowerLab stock script in `/etc/rc.local`, installs `gpiod` and `device-tree-compiler` if missing, prompts for the three BCM pins (defaults: SoftBTN=10, BOOTOK=8, SHUTDOWN=7), and starts `shutdowncheck.service` immediately.

A reboot is required after install (or after changing the BOOTOK pin) for the BOOTOK gpio-leds overlay to take effect. Until then, `shutdowncheck.service` holds BOOTOK via libgpiod. Re-run any time to change pins.

## Recovery

If the ATXRaspi is removed or fails, drop an empty file named `atxraspi-disable` at the root of the FAT boot partition (from any machine). Both scripts detect it and exit without touching any GPIO. 

Delete to re-enable.

## Pins

| Name     | Direction     | Behaviour                                      | Default |
| -------- | ------------- | ---------------------------------------------- | ------- |
| BOOTOK   | Pi → ATXRaspi | HIGH while running; drops late in shutdown.    | BCM 8   |
| SHUTDOWN | ATXRaspi → Pi | Long HIGH pulse → poweroff, short → reboot.    | BCM 7   |
| SoftBTN  | Pi → ATXRaspi | Pulsed HIGH for ~1 s on poweroff (not reboot). | BCM 10  |

## Known limitation: journal corruption on shutdown

After a `sudo poweroff`, journald reports its previous journal as `corrupted or uncleanly shut down` on next boot.

This is **cosmetic in the cases we've tested** -- `fsck` reports the EXT4 root clean, no orphaned inodes, no journal recovery, and applications like Klipper / Moonraker see their working trees as clean. journald simply did not get to write its clean-shutdown marker before the kernel halted; it gracefully renames the affected file and starts a new one.

We verified this is not caused by the ATXRaspi cutting power too early: the corruption occurs even with `softbtn.service` disabled and power cut manually after the Pi has fully halted. journald does not finish its final sync before the kernel halts regardless of when or how power is cut. This appears to be inherent to Pi 4 / Bookworm.

## Uninstall

```bash
sudo systemctl disable --now softbtn.service shutdowncheck.service
sudo rm /etc/systemd/system/{softbtn,shutdowncheck}.service /sbin/{softbtn,shutdowncheck}.sh
sudo systemctl daemon-reload
```

## Acknowledgements

The [ATXRaspi hardware](https://lowpowerlab.com/shop/product/118) is
designed and sold by LowPowerLab, and their original [shutdown script](https://github.com/LowPowerLab/ATX-Raspi) was the launching pad for this project. The Pi-side software here is a clean rewrite using libgpiod and systemd, but it would not exist without their work.

## License

MIT. See [LICENSE](LICENSE).
