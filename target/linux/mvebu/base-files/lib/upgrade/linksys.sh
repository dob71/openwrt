#
# Copyright (C) 2014-2015 OpenWrt.org
#

linksys_get_target_firmware() {

	local cur_boot_part mtd_ubi0

	cur_boot_part=`/usr/sbin/fw_printenv -n boot_part`
	if [ -z "${cur_boot_part}" ] ; then
		mtd_ubi0=$(cat /sys/devices/virtual/ubi/ubi0/mtd_num)
		case $(egrep ^mtd${mtd_ubi0}: /proc/mtd | cut -d '"' -f 2) in
		kernel1|rootfs1)
			cur_boot_part=1
			;;
		kernel2|rootfs2)
			cur_boot_part=2
			;;
		esac
		>&2 printf "Current boot_part='%s' selected from ubi0/mtd_num='%s'" \
			"${cur_boot_part}" "${mtd_ubi0}"
	fi

	case $cur_boot_part in
	1)
		fw_setenv -s - <<-EOF
			boot_part 2
			bootcmd "run altnandboot"
		EOF
		printf "kernel2"
		return
		;;
	2)
		fw_setenv -s - <<-EOF
			boot_part 1
			bootcmd "run nandboot"
		EOF
		printf "kernel1"
		return
		;;
	*)
		return
		;;
	esac
}

linksys_get_root_magic() {
	(get_image "$@" | dd skip=786432 bs=4 count=1 | hexdump -v -n 4 -e '1/1 "%02x"') 2>/dev/null
}

platform_do_upgrade_linksys() {
	local magic_long="$(get_magic_long "$1")"

	mkdir -p /var/lock
	local part_label="$(linksys_get_target_firmware)"
	touch /var/lock/fw_printenv.lock

	if [ ! -n "$part_label" ]
	then
		echo "cannot find target partition"
		exit 1
	fi

	local target_mtd=$(find_mtd_part $part_label)

	[ "$magic_long" = "73797375" ] && {
		CI_KERNPART="$part_label"
		if [ "$part_label" = "kernel1" ]
		then
			CI_UBIPART="rootfs1"
		else
			CI_UBIPART="rootfs2"
		fi

		nand_upgrade_tar "$1"
	}
	[ "$magic_long" = "27051956" -o "$magic_long" = "0000a0e1" ] && {
		# check firmwares' rootfs types
		local target_mtd=$(find_mtd_part $part_label)
		local oldroot="$(linksys_get_root_magic $target_mtd)"
		local newroot="$(linksys_get_root_magic "$1")"

		if [ "$newroot" = "55424923" -a "$oldroot" = "55424923" ]
		# we're upgrading from a firmware with UBI to one with UBI
		then
			# erase everything to be safe
			mtd erase $part_label
			get_image "$1" | mtd -n write - $part_label
		else
			get_image "$1" | mtd write - $part_label
		fi
	}
}

platform_copy_config_linksys() {
	cp -f "$CONF_TAR" "/tmp/syscfg/$BACKUP_FILE"
	sync
}
