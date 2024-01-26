#!/bin/bash
set -x
set -e # https://mywiki.wooledge.org/BashFAQ/105
# AUTO stage1.sh START
[[ $DISK ]] || ( echo 'plz set and pass $DISK like `DISK=...; ./stageX.sh`' && exit 1)

apt install --yes gdisk zfsutils-linux
systemctl stop zed
blkdiscard -f $DISK
sgdisk --zap-all $DISK

sgdisk     -n1:1M:+512M   -t1:EF00 $DISK # uefi esp
sgdisk -a1 -n5:24K:+1000K -t5:EF02 $DISK # bios mbr
sgdisk     -n3:0:+1G      -t3:BE00 $DISK # /boot
sgdisk     -n4:0:0        -t4:BF00 $DISK # /
udevadm trigger -s block # /etc/udev/rules.d/66-azure-storage.rules

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

# not setting zsys props due to https://github.com/openzfs/openzfs-docs/commit/8105d010fed0da7a59a02a2cc89e06f8c05e398a
# and https://github.com/ubuntu/zsys/issues/230
# so these datasets are more similar to https://openzfs.github.io/openzfs-docs/Getting%20Started/ubuntu/ubuntu%20Bookworm%20Root%20on%20ZFS.html#step-3-system-installation
# another dataset layout ref: https://github.com/djacu/nixos-on-zfs/blob/main/blog/2022-03-24.md
zfs create -o mountpoint=/boot bpool/BOOT
zfs create -o canmount=noauto -o mountpoint=/ rpool/ROOT
zfs mount rpool/ROOT

zfs create -o canmount=off rpool/usr
zfs create -o canmount=off rpool/var
zfs create rpool/var/cache
zfs create rpool/var/log
zfs create -o canmount=off rpool/var/lib
# it's recommend to rebuild docker image layers with zfs storage driver https://docs.docker.com/storage/storagedriver/zfs-driver/
# to prevent running another COWfs(overlayfs) over zfs: https://anarc.at/blog/2022-11-17-zfs-migration/#docker-performance
# https://gdevillele.github.io/engine/userguide/storagedriver/zfs-driver/
# https://www.reddit.com/r/docker/comments/my6p90/comment/gvv3bej/?context=3
# https://www.reddit.com/r/docker/comments/smtzho/docker_and_zfs_looks_like_a_mess/
# https://github.com/docker/for-linux/issues/1410
zfs create -o com.sun:auto-snapshot=false rpool/var/lib/docker
# https://planet.mysql.com/entry/?id=19489
# https://www.percona.com/blog/mysql-zfs-performance-update/
# https://www.reddit.com/r/zfs/comments/u1xklc/mariadbmysql_database_settings_for_zfs/
zfs create -o recordsize=16k -o primarycache=metadata -o atime=off rpool/var/lib/mysql
# https://dev.mysql.com/doc/dev/mysql-server/latest/PAGE_INNODB_REDO_LOG_FORMAT.html
# https://stackoverflow.com/questions/70637782/why-doesnt-mysql-innodb-redo-log-block-writing-need-double-write
zfs create -o recordsize=128k -o primarycache=metadata -o atime=off rpool/var/lib/mysql/#innodb_redo
# https://www.reddit.com/r/zfs/comments/3mvv8e/does_anyone_run_mysql_or_postgresql_on_zfs/
# https://news.ycombinator.com/item?id=29647645
zfs create -o recordsize=8k -o primarycache=metadata -o atime=off rpool/var/lib/postgresql

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
# https://stackoverflow.com/questions/51305706/shell-script-that-does-chroot-and-execute-commands-in-chroot/51312156#51312156
chroot /mnt /usr/bin/env DISK=$DISK bash --login <<"EOT"
[[ $DISK ]] || ( echo 'plz set and pass $DISK like `DISK=...; ./stageX.sh`' && exit 1)

rm /etc/resolv.conf # symlink to systemd-resolved
echo 'nameserver 1.1.1.1' > /etc/resolv.conf
echo 127.0.0.1 $(hostname) >> /etc/hosts

apt install --yes dosfstools
mkdosfs -F 32 -s 1 -n EFI ${DISK}-part1
EOT
# AUTO stage1.sh END
