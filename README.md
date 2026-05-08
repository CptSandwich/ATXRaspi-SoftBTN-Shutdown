# ATXRaspi-SoftBTN-Shutdown

Pi-side software for the [LowPowerLab ATXRaspi](https://lowpowerlab.com/guide/atxraspi/), rewritten with `libgpiod` and `systemd` so it works on Pi 5 and kernel 6.6+ (Bookworm and later). Adds a SoftBTN pulse on poweroff so the ATXRaspi cuts power for all software-initiated shutdowns too, not just the physical button.

> Tested on Pi 4 (Bookworm). Should work on Pi 1/2/3/Zero/5 but unverified.

## Install

```bash
git clone https://github.com/CptSandwich/ATXRaspi-SoftBTN-Shutdown.git
cd ATXRaspi-SoftBTN-Shutdown
sudo ./install.sh
```

The installer detects and offers to disable any LowPowerLab stock script in `/etc/rc.local`, installs `gpiod` if missing, prompts for the three BCM pins (defaults: SoftBTN=10, BOOTOK=8, SHUTDOWN=7), and starts `shutdowncheck.service` immediately. 

No reboot needed. Re-run any time to change pins.

## Recovery

If the ATXRaspi is removed or fails, drop an empty file named `atxraspi-disable` at the root of the FAT boot partition (from any machine). Both scripts detect it and exit without touching any GPIO. 

Delete to re-enable.

## Pins

| Name     | Direction     | Behaviour                                      | Default |
| -------- | ------------- | ---------------------------------------------- | ------- |
| BOOTOK   | Pi → ATXRaspi | HIGH while running; drops late in shutdown.    | BCM 8   |
| SHUTDOWN | ATXRaspi → Pi | Long HIGH pulse → poweroff, short → reboot.    | BCM 7   |
| SoftBTN  | Pi → ATXRaspi | Pulsed HIGH for ~1 s on poweroff (not reboot). | BCM 10  |

## Known limitation: BOOTOK drop timing

On at least Pi 4 / Bookworm, BOOTOK drops a moment before the kernel finishes its halt sequence (final disk syncs, filesystem unmounts), which means the ATXRaspi sees BOOTOK go LOW while there is still some disk activity in flight. After several `sudo poweroff` cycles, journald reports its previous journal as `corrupted or uncleanly shut down` on next boot.

This is **cosmetic in the cases we've tested** — `fsck` reports the EXT4 root clean, no orphaned inodes, no journal recovery, and applications like Klipper / Moonraker see their working trees as clean. journald simply didn't get to write its "clean shutdown" marker before the kernel halted; it gracefully renames the affected file and starts a new one.

We tried three software approaches to extend BOOTOK HIGH (libgpiod with an orphaned `gpioset`, sysfs, firmware-level `gpio=8=op,dh` in `config.txt`) and they all behave identically: the kernel itself releases the pin during `device_shutdown()` callbacks (likely the bcm2711 / pinctrl-rp1 driver's `.shutdown`), which runs as part of the reboot syscall. Userspace processes can't outlive that step, so no software-side trick produces a meaningfully later BOOTOK drop.

Moving the timing further requires hardware-level intervention or a change to the ATXRaspi's microcontroller firmware to extend its internal BOOTOK→cut-power delay. For typical use this isn't necessary.

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
