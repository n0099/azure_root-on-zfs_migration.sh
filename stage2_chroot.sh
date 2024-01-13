#!/bin/bash
set -x
set -e # https://mywiki.wooledge.org/BashFAQ/105
# AUTO stage2_chroot.sh START
rm -r /boot/efi
mkdir /boot/efi
mount /boot/efi

rm -r /boot/grub
mkdir /boot/efi/grub /boot/grub
echo /boot/efi/grub /boot/grub none defaults,bind 0 0 >> /etc/fstab
mount /boot/grub

apt install --yes grub-efi-amd64 grub-efi-amd64-signed shim-signed zfs-initramfs
apt purge --yes os-prober

# hwe6.5.0 vs linux-image-azure6.2.0 vs linux-image-gernic@5.15.0 https://www.omgubuntu.co.uk/2024/01/ubuntu-2204-linux-6-5-kernel-update
# https://askubuntu.com/questions/266772/why-are-there-so-many-linux-kernel-packages-on-my-machine-and-what-do-they-a
apt install --yes linux-generic-hwe-22.04
# if installing linux-generic-hwe-22.04 didn't trigger update-initramfs:
# update-initramfs -c -k all -v # unexpecting `Nothing to do, exiting.`

grub-probe /boot # expecting `zfs`

cat <<"EOT" > /etc/default/grub.d/99-zfs.cfg
GRUB_CMDLINE_LINUX="$GRUB_CMDLINE_LINUX init_on_alloc=0"
# below is optional
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=5
GRUB_RECORDFAIL_TIMEOUT=5
EOT
# FROM openzfs-docs:
# Add init_on_alloc=0 to: GRUB_CMDLINE_LINUX_DEFAULT
# Optional (but highly recommended): Make debugging GRUB easier:
# Comment out: GRUB_TIMEOUT_STYLE=hidden
# Set: GRUB_TIMEOUT=5
# Below GRUB_TIMEOUT, add: GRUB_RECORDFAIL_TIMEOUT=5
# Remove quiet and splash from: GRUB_CMDLINE_LINUX_DEFAULT
# Uncomment: GRUB_TERMINAL=console
# Save and quit.
# Later, once the system has rebooted twice and you are sure everything is working, you can undo these changes, if desired.

# update the GRUB_FORCE_PARTUUID by `blkid | grep /dev/sdc4` https://askubuntu.com/questions/1375589/what-are-the-different-versions-available-as-ubuntu-cloud-images-general-guid
echo GRUB_FORCE_PARTUUID="$(blkid -s PARTUUID -o value ${DISK}-part4)" > /etc/default/grub.d/40-force-partuuid.cfg

update-grub
grub-install $DISK # bios MBR
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck --no-floppy # uefi ESP

mkdir /etc/zfs/zfs-list.cache
touch /etc/zfs/zfs-list.cache/bpool
touch /etc/zfs/zfs-list.cache/rpool
# AUTO stage2_chroot.sh END
