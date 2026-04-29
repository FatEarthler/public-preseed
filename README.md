# Linux Provisioning

## File overview

| file | purpose | status |
| ---- | ------- | ------ |
| preseedminiBIOS.cfg | testfile for BIOS boot | working |
| preseedminiUEFI.cfg | testfile for UEFI boot | work in progress |
| select-disk.sh | script to identify target disk for installation | working |

### Notes

If possible, BIOS and UEFI files should be unified into one, as there is a lot of duplication between the two.


This repository holds several methods how to provision a (my) custom linux, mostly kali.

## Provisioning Variants

### A) Simple modified NetInstaller iso

This approach takes a kali linux NetInstaller, modifies it s.t. during install it loads a preseed.cfg and postinstall.sh from a public site (no authentication) to fully automate installation. The modified iso is then used to create a bootable usb stick. NetInstaller is chosen because it downloads current packet versions during installation. The boot medium (usb stick) however, has to be recreated if a newer version of the NetInstaller is desired.

