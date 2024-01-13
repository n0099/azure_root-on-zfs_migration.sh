# mainly based on https://openzfs.github.io/openzfs-docs/Getting%20Started/Ubuntu/Ubuntu%2022.04%20Root%20on%20ZFS.html
# see also https://anarc.at/blog/2022-11-17-zfs-migration/

# /dev/sdb refers to the original disk
# and the target disk is /dev/sdc
fdisk -l
ls -la /dev/disk/by-id # figure out SCSI id of /dev/sdc
DISK=/dev/disk/by-id/scsi-...

#!/bin/bash
set -x
set -e # http://mywiki.wooledge.org/BashFAQ/105
[[ ! $DISK ]] || ( echo 'plz set and pass $DISK like `DISK=...; ./stageX.sh`' && exit 1)
# AUTO stage1.sh START
apt install --yes gdisk zfsutils-linux
systemctl stop zed
blkdiscard -f $DISK
sgdisk --zap-all $DISK
sgdisk     -n1:1M:+512M   -t1:EF00 $DISK # uefi esp
sgdisk -a1 -n5:24K:+1000K -t5:EF02 $DISK # bios mbr
sgdisk     -n3:0:+1G      -t3:BE00 $DISK # /boot
sgdisk     -n4:0:0        -t4:BF00 $DISK # /
partprobe /dev/sdc # or `zpool create` may `cannot resolve path '{DISK}-partX'` that just created

zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -o cachefile=/etc/zfs/zpool.cache \
    -o compatibility=grub2 \
    -o feature@livelist=enabled \
    -o feature@zpool_checkpoint=enabled \
    -O devices=off \
    -O acltype=posixacl -O xattr=sa \
    -O compression=lz4 \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off -O mountpoint=/boot -R /mnt \
    bpool ${DISK}-part3
zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl -O xattr=sa -O dnodesize=auto \
    -O compression=zstd \
    -O normalization=formD \
    -O relatime=on \
    -O canmount=off -O mountpoint=/ -R /mnt \
    rpool ${DISK}-part4

# not setting zsys props due to https://github.com/openzfs/openzfs-docs/commit/8105d010fed0da7a59a02a2cc89e06f8c05e398a https://github.com/ubuntu/zsys/issues/230
# so these datasets are more similar to https://openzfs.github.io/openzfs-docs/Getting%20Started/ubuntu/ubuntu%20Bookworm%20Root%20on%20ZFS.html#step-3-system-installation
# another dataset layout ref: https://github.com/djacu/nixos-on-zfs/blob/main/blog/2022-03-24.md
zfs create -o canmount=off -o mountpoint=none rpool/ROOT
zfs create -o canmount=off -o mountpoint=none bpool/BOOT
zfs create -o canmount=noauto -o mountpoint=/ rpool/ROOT/ubuntu
zfs mount rpool/ROOT/ubuntu
zfs create -o mountpoint=/boot bpool/BOOT/ubuntu

zfs create -o canmount=off rpool/usr
zfs create -o canmount=off rpool/var
zfs create rpool/var/cache
zfs create rpool/var/log
zfs create -o canmount=off rpool/var/lib
zfs create rpool/var/lib/docker
zfs create rpool/var/lib/mysql
zfs create rpool/var/lib/postgresql
zfs create rpool/home
zfs create rpool/home/www
zfs create rpool/home/www/log

mkdir /mnt/run
mount -t tmpfs tmpfs /mnt/run
mkdir /mnt/run/lock

mkdir -p /mnt/etc/zfs
cp /etc/zfs/zpool.cache /mnt/etc/zfs/

fdisk -l /dev/sdb /dev/sdc
mkdir /null
mount /dev/sdb1 /null # /dev/sdb1 refers to the largest main partition in /dev/sdb

rsync --stats --info progress2 --no-inc-recursive -aHAXh /null/ /mnt

mount --make-private --rbind /dev  /mnt/dev
mount --make-private --rbind /proc /mnt/proc
mount --make-private --rbind /sys  /mnt/sys
chroot /mnt /usr/bin/env DISK=$DISK bash --login <<"EOT" # https://stackoverflow.com/questions/51305706/shell-script-that-does-chroot-and-execute-commands-in-chroot/51312156#51312156

[[ ! $DISK ]] || ( echo 'plz set and pass $DISK like `DISK=...; ./stageX.sh`' && exit 1)
rm /etc/resolv.conf # symlink to systemd-resolved
echo 'nameserver 1.1.1.1' > /etc/resolv.conf
echo 127.0.0.1 $(hostname) >> /etc/hosts

apt install --yes dosfstools
mkdosfs -F 32 -s 1 -n EFI ${DISK}-part1
mkdir /boot/efi
EOT
# AUTO stage1.sh END

# MANUALL STAGE START
chroot /mnt /usr/bin/env DISK=$DISK bash --login
[[ ! $DISK ]] || ( echo 'plz set and pass $DISK like `DISK=...; ./stageX.sh`' && exit 1)
vim /etc/fstab # replace LABEL=UUID with LABEL=EFI for /boot/efi and UUID=... with LABEL=rpool for /

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

vim /etc/default/grub
# Add init_on_alloc=0 to: GRUB_CMDLINE_LINUX_DEFAULT
# Comment out: GRUB_TIMEOUT_STYLE=hidden
# Set: GRUB_TIMEOUT=5
# Below GRUB_TIMEOUT, add: GRUB_RECORDFAIL_TIMEOUT=5
# Remove quiet and splash from: GRUB_CMDLINE_LINUX_DEFAULT
# Uncomment: GRUB_TERMINAL=console
# Save and quit.

#!/bin/bash
set -x
set -e # http://mywiki.wooledge.org/BashFAQ/105
[[ ! $DISK ]] || ( echo 'plz set and pass $DISK like `DISK=...; ./stageX.sh`' && exit 1)
# AUTO stage3_chroot.sh START
update-grub # try umount && mount /boot/grub
grub-install $DISK # bios
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck --no-floppy # uefi

mkdir /etc/zfs/zfs-list.cache
touch /etc/zfs/zfs-list.cache/bpool
touch /etc/zfs/zfs-list.cache/rpool
# AUTO stage3_chroot.sh END

zed -F &

# Verify that zed updated the cache by making sure these are not empty:
cat /etc/zfs/zfs-list.cache/bpool
echo
cat /etc/zfs/zfs-list.cache/rpool

fg # Press Ctrl-C.
sed -Ei "s|/mnt/?|/|" /etc/zfs/zfs-list.cache/*
# exit && exit && exit # nesting chroot and bash --login and zsh

mount | grep -v zfs | tac | awk '/\/mnt/ {print $3}' | xargs -I{} umount -lf {}
umount /mnt
rm -r /mnt # to prevent `cannot export 'rpool': pool is busy`
zpool export -a
reboot

# /dev/sdb -> /dev/sdc finished and the current OS disk that being referred to /dev/sda somehow will be broken
# unattch /dev/sdb in portal.azure.com but keeps the broken /dev/sda and target /dev/sdc disks
# reboot should be boot from /dev/sdc since /dev/sda is unbootable
# dmesg will stuck at `Begin: Sleeping for ...` after spamming `sr 0:0:0:2: [sr0] tag#40 unaligned transfer` for a few minutes
# remove `rootwait=300` kernel param in /etc/default/grub https://unix.stackexchange.com/questions/67199/whats-the-point-of-rootwait-rootdelay won't help

apt remove --yes linux-image-generic # select [No] for the ncurses popup about `You are running a kernel (version ...) and attempting to remove the same version. It is highly recommended to abort the kernel removal unless you are prepared to fix the system after removal. Abort kernel removal?`
apt reinstall linux-azure
shutdown

# obtain an SAS url of `exported.vhd` in portal.azure.com for /dev/sdc
# create a VM with sufficient disk spaces or memory `/dev/shm tmpfs` to wget the `exported.vhd`
# azcopy copy `exported.vhd` https://storage-account.blob.windows.net/SASurl
# create a managed disk based on the `exported.vhd` in the storage account in portal.azure.com
# create the VM with the custom image based on the managed disk as OS disk
# custom image may disable the AccelNet NIC https://learn.microsoft.com/en-us/azure/virtual-network/accelerated-networking-mana-linux try manually enable it for the NIC then checkout does ifconfig contains NIC with name prefix `enP`

# the approach below is not working due to swapping the OS disk will wipe its ESP partition
# create an new VM in portal.azure.com with arbitrary size of OS disk
# then delete itself and all its related resources except the OS disk and refer to /dev/sdd
# create another new VM with an OS disk as /dev/sde and share the SAME size with the target /dev/sdc
# swap the OS disk /dev/sde with /dev/sdd, attach /dev/sdc and reboot into /dev/sdd
dd if=/dev/sdc of=/dev/sde bs=1M status=progress
zpool import -f rpool
zpool import -f bpool
vim /mnt/etc/fstab # repeat changes made on /etc/fstab previously
zpool export -a
shutdown
# swap the OS disk /dev/sdd with /dev/sde and delete /dev/sd{a,b,c,e}
