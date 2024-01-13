#!/bin/bash
set -x
set -e # http://mywiki.wooledge.org/BashFAQ/105
# AUTO stage2_chroot.sh START
mount /boot/efi

mkdir /boot/efi/grub /boot/grub
echo /boot/efi/grub /boot/grub none defaults,bind 0 0 >> /etc/fstab
mount /boot/grub

apt install --yes grub-pc # bios
apt install --yes grub-efi-amd64 grub-efi-amd64-signed shim-signed # uefi
apt purge --yes os-prober
apt install zfs-initramfs linux-image-generic
# https://askubuntu.com/questions/266772/why-are-there-so-many-linux-kernel-packages-on-my-machine-and-what-do-they-a
# apt reinstall linux-image-azure # cannot trigger update-initramfs
apt install linux-generic-hwe-22.04 # hwe6.5.0 vs azure6.2.0 vs gernic5.15.0 https://www.omgubuntu.co.uk/2024/01/ubuntu-2204-linux-6-5-kernel-update
grub-probe /boot
update-initramfs -c -k all -v # unexpecting Nothing to do, exiting.
# AUTO stage2_chroot.sh END