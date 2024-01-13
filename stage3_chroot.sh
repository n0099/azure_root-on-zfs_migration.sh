#!/bin/bash
set -x
set -e # http://mywiki.wooledge.org/BashFAQ/105
# AUTO stage3_chroot.sh START
[[ $DISK ]] || ( echo 'plz set and pass $DISK like `DISK=...; ./stageX.sh`' && exit 1)
update-grub # try umount && mount /boot/grub
grub-install $DISK # bios
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck --no-floppy # uefi

mkdir /etc/zfs/zfs-list.cache
touch /etc/zfs/zfs-list.cache/bpool
touch /etc/zfs/zfs-list.cache/rpool
# AUTO stage3_chroot.sh END
