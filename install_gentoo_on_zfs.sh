#!/usr/bin/env bash
source "lib/functions.sh"

### README
### For temporary installation run like that:
### ```
### RPOOL=rpooltmp BPOOL=bpooltmp DISK=/dev/disk/by-id/ata-INTEL_SSDSCKGF180A4L_CVDA342501A4180W ./install_gentoo_on_zfs.sh
### ```

DEFAULT_SWAPSIZE=40G
RPOOL=${RPOOL:=rpool}
BPOOL=${BPOOL:=bpool}

POSITIONAL=()
for i in "$@"; do
	case $i in
		-d=*|--disk=*)
			DISK="${i#*=}"
			shift # past argument=value
			;;
		-n=*|--name=*)
			MACHINENAME="${i#*=}"
			shift # past argument=value
			;;
		-s=*|--swap=*)
			SWAPSIZE="${i#*=}"
			shift # past argument=value
			;;
		-h|--help)
			show_usage
			exit 0
			;;
		*)
			echo "ERROR: Unknown option $i"
			echo
			show_usage
			exit 1
			;;
	esac
done

## CHECK INPUT PARAMETERS
if [ -z "$DISK" ]; then
	show_usage
	exit 1
fi

if [ -z "$MACHINENAME" ]; then
	show_usage
	exit 1
fi

if [[ -z "${SWAPSIZE}" ]]; then
	SWAPSIZE=${DEFAULT_SWAPSIZE}
fi

if [[ ! "${SWAPSIZE}" =~ [0-9]+[K|M|G|T]$ ]]; then
	echo "Swapsize incorrectly specified: ${SWAPSIZE}"
	echo "Example: 512K, 32G, 1T"
	echo "Default: ${DEFAULT_SWAPSIZE}"
	exit 1
fi

echo "DISK=${DISK} MACHINE_NAME=${MACHINENAME} SWAPSIZE=${SWAPSIZE}"

## INITIALIZE DISK LAYOUT
source ./lib/partiotion_all_disk_for_installation.sh "${MACHINENAME}" "${DISK}" "${SWAPSIZE}" 1>/dev/null 2>&1
if [[ $? -eq 0 ]]; then
	echo "SUCCESS: disk layout for ZFS instalaltion is written to ${DISK}"
else
	echo "Error: cannot create disk layout for ZFS installation. Output of 'partprobe' command:"
	part_probe_result=$(partprobe -d -s "${DISK}")
	echo "${part_probe_result}"
	exit 1
fi

exit 1

# echo ${DISK}
# echo ${RPOOL}
# echo ${BPOOL}
# exit 1

cwd=$(pwd)

# apt update
# apt install -y curl

mkdir /mnt/gentoo

mkfs.fat -F 32 ${DISK}-part1
mkswap ${DISK}-part2


#zpool create \
#    -o ashift=12 \
#    -o cachefile=/etc/zfs/zpool.cache \
#    -O acltype=posixacl -O canmount=off -O compression=lz4 \
#    -O dnodesize=auto -O normalization=formD -O relatime=on \
#    -O xattr=sa -O mountpoint=/ -R /mnt/gentoo \
#    ${RPOOL} ${DISK}-part3

# * Messages for package sys-fs/zfs-kmod-2.0.4-r1:
#
# * This version of OpenZFS includes support for new feature flags
# * that are incompatible with previous versions. GRUB2 support for
# * /boot with the new feature flags is not yet available.
# * Do *NOT* upgrade root pools to use the new feature flags.
# * Any new pools will be created with the new feature flags by default
# * and will not be compatible with older versions of ZFSOnLinux. To
# * create a newpool that is backward compatible wih GRUB2, use 
# * 
# * zpool create -d -o feature@async_destroy=enabled 
# * 	-o feature@empty_bpobj=enabled -o feature@lz4_compress=enabled
# * 	-o feature@spacemap_histogram=enabled
# * 	-o feature@enabled_txg=enabled 
# * 	-o feature@extensible_dataset=enabled -o feature@bookmarks=enabled
# * 	...
# * 
# * GRUB2 support will be updated as soon as either the GRUB2
# * developers do a tag or the Gentoo developers find time to backport
# * support from GRUB2 HEAD.
	
	
## BPOOL - boot pool
zpool create -d -o feature@allocation_classes=enabled \
					  -o feature@async_destroy=enabled      \
					  -o feature@bookmarks=enabled          \
					  -o feature@embedded_data=enabled      \
					  -o feature@empty_bpobj=enabled        \
					  -o feature@enabled_txg=enabled        \
					  -o feature@extensible_dataset=enabled \
					  -o feature@filesystem_limits=enabled  \
					  -o feature@hole_birth=enabled         \
					  -o feature@large_blocks=enabled       \
					  -o feature@lz4_compress=enabled       \
					  -o feature@project_quota=enabled      \
					  -o feature@resilver_defer=enabled     \
					  -o feature@spacemap_histogram=enabled \
					  -o feature@spacemap_v2=enabled        \
					  -o feature@userobj_accounting=enabled \
					  -o feature@zpool_checkpoint=enabled   \
					  -f -o ashift=12                       \
					  -o autotrim=on                        \
					  -o cachefile=/tmp/zpool.cache         \
					  -O aclinherit=passthrough             \
					  -O acltype=posixacl                   \
					  -O atime=off                          \
					  -O canmount=off                       \
					  -O devices=off                        \
					  -O mountpoint=/                       \
					  -O normalization=formD                \
					  -O xattr=sa                           \
					  -R /mnt/gentoo                        \
					  ${BPOOL} ${DISK}-part3
## RPOOL - root pool
zpool create -f -o ashift=12 \
					  -o autotrim=on                        \
					  -o cachefile=/tmp/zpool.cache         \
					  -O acltype=posixacl                   \
					  -O aclinherit=passthrough             \
					  -O atime=off                          \
					  -O canmount=off                       \
					  -O devices=off                        \
					  -O dnodesize=auto                     \
					  -O compression=lz4                    \
					  -O mountpoint=/                       \
					  -O normalization=formD                \
					  -O xattr=sa                           \
					  -R /mnt/gentoo                        \
					  ${RPOOL} ${DISK}-part4


### BOOT
zfs create -o canmount=off -o mountpoint=none ${BPOOL}/BOOT
zfs create -o canmount=noauto -o dnodesize=legacy -o mountpoint=/boot ${BPOOL}/BOOT/gentoo

### ROOT
zfs create -o canmount=off -o mountpoint=none ${RPOOL}/ROOT
zfs create -o canmount=noauto -o mountpoint=/ ${RPOOL}/ROOT/gentoo



zfs mount ${RPOOL}/ROOT/gentoo
zfs mount ${BPOOL}/BOOT/gentoo





zfs create                                 ${RPOOL}/home
zfs create -o mountpoint=/root             ${RPOOL}/home/root
chmod 700 /mnt/gentoo/root
zfs create -o canmount=off                 ${RPOOL}/var
zfs create -o canmount=off                 ${RPOOL}/var/lib
zfs create                                 ${RPOOL}/var/log
zfs create                                 ${RPOOL}/var/spool
zfs create -o com.sun:auto-snapshot=false  ${RPOOL}/var/cache
zfs create -o com.sun:auto-snapshot=false  ${RPOOL}/var/tmp
chmod 1777 /mnt/gentoo/var/tmp
zfs create                                 ${RPOOL}/opt
zfs create                                 ${RPOOL}/srv
zfs create -o canmount=off                 ${RPOOL}/usr
zfs create                                 ${RPOOL}/usr/local
zfs create                                 ${RPOOL}/var/games
# TODO: WARNING: net-mail/mailbase prevents mounting /var/mail as filesystem
# so if you want to claws-mail and its dependencies, then do not create
# /var/mail as separate filesystem
zfs create                                 ${RPOOL}/var/spool/mail
zfs create                                 ${RPOOL}/var/snap
zfs create                                 ${RPOOL}/var/www
zfs create                                 ${RPOOL}/var/lib/AccountsService
zfs create -o com.sun:auto-snapshot=false  ${RPOOL}/var/lib/docker
zfs create -o com.sun:auto-snapshot=false  ${RPOOL}/var/lib/nfs
zfs create -o com.sun:auto-snapshot=false -o compression=off -o relatime=off -o atime=off ${RPOOL}/chiatmp
zfs create -o com.sun:auto-snapshot=false -o relatime=off -o atime=off ${RPOOL}/tmp


cd /mnt/gentoo
latest_stage3=$(curl http://distfiles.gentoo.org/releases/amd64/autobuilds/latest-stage3-amd64-systemd.txt 2>/dev/null | awk '$0 !~ /^#/ { print $1; exit; };')
wget http://distfiles.gentoo.org/releases/amd64/autobuilds/$latest_stage3
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
cd ${cwd}
cp configs/make.conf /mnt/gentoo/etc/portage/make.conf
mkdir --parents /mnt/gentoo/etc/portage/repos.conf
cp /mnt/gentoo/usr/share/portage/config/repos.conf /mnt/gentoo/etc/portage/repos.conf/gentoo.conf
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
test -L /dev/shm && rm /dev/shm && mkdir /dev/shm
mount --types tmpfs --options nosuid,nodev,noexec shm /dev/shm
chmod 1777 /dev/shm

mkdir /mnt/gentoo/etc/zfs
mkdir /mnt/gentoo/install
cp -R configs/systemd /mnt/gentoo/installation_files/
cp -R configs/portage/* /mnt/gentoo/etc/portage/
cp /tmp/zpool.cache /mnt/gentoo/etc/zfs/
cp configs/locale.gen /mnt/gentoo/etc/locale.gen
cp configs/fstab /mnt/gentoo/etc/
cp configs/kernel/.config /mnt/gentoo/
cp configs/grub /mnt/gentoo/


mkdir /mnt/gentoo/boot/efi
mount ${DISK}-part1 /mnt/gentoo/boot/efi


cp ./in_chroot.sh /mnt/gentoo
chroot /mnt/gentoo /in_chroot.sh


umount /mnt/gentoo/boot/efi
umount -l /mnt/gentoo/{dev,sys,proc}
zfs umount /mnt/gentoo/boot
zfs umount /mnt/gentoo
zfs set mountpoint=legacy ${BPOOL}/BOOT/gentoo
rm -R /mnt/gentoo
zpool export ${BPOOL}
zpool export ${RPOOL}


