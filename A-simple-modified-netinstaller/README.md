# Simple modified netinstaller iso

TODOS:
- [ ] enable UEFI install, by creating a 2nd preseed
- [ ] set bootmenu keyboard layout to CH
- [ ] add postinstall.sh
- [x] fix md5sum, because of changes to grub.cfg (menu and txt are md5sum checked) ==> test if required at all. md5sum.txt could be for manual verification purposes only ==> not needed, it works well without.
- [ ] automate iso modification on server, triggered by changes to preseed or postinstall files or newer version of net-installer
- [ ] set timeout for boot menu
- [ ] Remove dialog to confirm that UEFI installation overwrites existing MBR from previous BIOS installation --> this seems to 'work' now, the dialog no longer appears. But I have to start the partitioning step from the menu now, it does not do so automatically
- [ ] test if system really gets installed to the disk selected form select-disk.sh. It presently does not seem to be the case!

Status of PoC:

| | hardware (USB) | optical (VM) |
|---|----|----|
|BIOS| OK | OK |
|UEFI| | OK |

This approach takes a kali linux NetInstaller, modifies it s.t. during install it loads a preseed.cfg and postinstall.sh from a public site (no authentication) to fully automate installation. The modified iso is then used to create a bootable usb stick. NetInstaller is chosen because it downloads current packet versions during installation. The boot medium (usb stick) however, has to be recreated if a newer version of the NetInstaller is desired.

## Install required tools

```console
sudo apt install wget xorriso
```

## Download and modify Kali netinstaller iso

Start from the git repo directory (```[...]/linux-provisioning/A-simple-modified-netinstaller```) and copy our custom ```.cfg``` files to ```/tmp```.

```console
cp menu.cfg /tmp # BIOS mode menu
cp txt.cfg /tmp # BIOS mode menu
cp grub.cfg /tmp # UEFI mode menu
```

Now update download and updated a netinstaller iso and replace the ```.cfg``` files.

```
cd /tmp
LATEST=$(curl https://cdimage.kali.org/current/ | grep -Eio 'kali-linux-.{6,7}-installer-netinst-amd64.iso' | uniq)
wget -O kali-linux-netinst.iso https://cdimage.kali.org/current/$LATEST
rm -f kali-custom.iso    # cleanup first
xorriso -indev kali-linux-netinst.iso \
        -outdev kali-custom.iso \
        -boot_image any replay \
        -update txt.cfg /isolinux/txt.cfg \
        -update menu.cfg /isolinux/menu.cfg \
        -update grub.cfg /boot/grub/grub.cfg \
        -commit
```

The final set of boot parameters inside the modified ```.cfg``` files is

```console
/install.amd/vmliuz initrd=/install.amd/initrd.gz auto=true priority=critical ipv6.disable=1 url=https://path.to/preeseed.cfg netcfg/choose_interface=auto --- quiet
```

Some of the parameters of the custom bootparameters explained:

- ```auto=true``` enables automatic installation mode. This tells the Debian installer to expect a preseed configuration and skip most interactive prompts.
- ```priority=critical``` limits installer prompts to critical questions only.
- ```---``` This separator tells the Debian installer: everything after this is passed to the installer environment, not the kernel itself. It separates kernel arguments from installer arguments.
- ```netcfg/choose_interface=auto``` selects the first network interface where a carrier is detected (link is up). This prevents a user prompt if more than one interface is up (e.g. eth and wlan).
- ```quiet``` reduces boot verbosity. Instead of printing lots of kernel messages, the installer displays a cleaner screen.

## Verification

If desired, the content of the new custom kali iso can be inspected by unpacking it completely and then navigating to the files we want to check.

```console
cd /tmp
sudo mount -o loop kali-custom.iso /mnt
sudo rm -rf kali-custom # cleanup
mkdir kali-custom
cp -r /mnt/* kali-custom/
sudo umount /mnt
```

## Write the iso to usb

The resulting ```kali-custom.iso``` from above can be used in a vm by mounting it to a virtual optical drive. To have a USB installer, the iso has to be written to a usb stick first.

Identify usb drive with ```lsblk```. Assume the usb drive is ```sdg```:

```console
cd /tmp
sudo dd if=kali-custom.iso of=/dev/sdg bs=4M status=progress oflag=sync
```

## Cleanup

```console
cd /tmp
rm -f menu.cfg txt.cfg grub.cfg
rm -f kali-linux-netinst.iso
rm -f kali-custom.iso
sudo rm -rf kali-custom
```
