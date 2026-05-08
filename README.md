# ATXRaspi-SoftBTN-Shutdown

Pi-side software for the [LowPowerLab ATXRaspi](https://lowpowerlab.com/guide/atxraspi/), rewritten with `libgpiod` and `systemd` so it works on Pi 5 and kernel 6.6+ (Bookworm and later). Adds a SoftBTN pulse on poweroff so the ATXRaspi cuts power for all software-initiated shutdowns too, not just the physical button.

> Tested on Pi 4 (Bookworm). Should work on Pi 1/2/3/Zero/5 but unverified.

## Install

```bash
git clone https://github.com/CptSandwich/ATXRaspi-SoftBTN-Shutdown.git
cd ATXRaspi-SoftBTN-Shutdown
sudo ./install.sh
```

The installer detects and offers to disable any LowPowerLab stock script in `/etc/rc.local`, installs `gpiod` if missing, prompts for the three BCM pins (defaults: SoftBTN=10, BOOTOK=8, SHUTDOWN=7), asks how BOOTOK should be asserted (see below), and starts `shutdowncheck.service` immediately.

No reboot needed. Re-run any time to change pins or method.

## BOOTOK assertion: gpiod vs sysfs

The installer asks which kernel interface to use for holding BOOTOK HIGH:

- **`gpiod`** (default): a backgrounded `gpioset` process holds the line via the modern libgpiod chardev API. When `shutdowncheck.service` is stopped during shutdown, the process exits and BOOTOK is released early in the shutdown sequence. Modern, supported, and the kernel guarantees cleanup if anything crashes.
- **`sysfs`**: writes to `/sys/class/gpio/.../value`. The kernel takes ownership of the pin state itself, so no userspace process needs to be alive. BOOTOK stays HIGH past `shutdowncheck.service`'s exit and is only released when the kernel halts. The ATXRaspi sees BOOTOK drop later in shutdown, giving a wider margin between BOOTOK→LOW and the kernel completing its halt sequence. **sysfs is officially deprecated by the kernel maintainers** but is still present in current kernels (Bookworm and Trixie). Choose this if you observe premature power-cut with `gpiod`.

The SHUTDOWN watcher and SoftBTN pulse always use libgpiod regardless of which BOOTOK method you pick.

## Recovery

If the ATXRaspi is removed or fails, drop an empty file named `atxraspi-disable` at the root of the FAT boot partition (from any machine). Both scripts detect it and exit without touching any GPIO. 

Delete to re-enable.

## Pins

| Name     | Direction     | Behaviour                                      | Default |
| -------- | ------------- | ---------------------------------------------- | ------- |
| BOOTOK   | Pi → ATXRaspi | HIGH while running; drops late in shutdown.    | BCM 8   |
| SHUTDOWN | ATXRaspi → Pi | Long HIGH pulse → poweroff, short → reboot.    | BCM 7   |
| SoftBTN  | Pi → ATXRaspi | Pulsed HIGH for ~1 s on poweroff (not reboot). | BCM 10  |

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
