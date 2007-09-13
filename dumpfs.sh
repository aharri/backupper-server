#!/bin/sh
#
# $Id: dumpfs.sh,v 1.7 2007/09/13 12:10:04 iku Exp $
#
# Copyright (c) 2006,2007 Antti Harri <iku@openbsd.fi>
#

####################################
# do not edit unless you know what
# you're actually doing.
#
# for configuration check
# config/dump.conf{,.sample}
####################################

# defaults
opts="-a -0 -u"
source=wd0
target=wd1
target_dir=/mnt
partitions_to_dump="a d e f"
mailto="root"
halt="/sbin/halt -p"

hostname=$(hostname)
PATH=/root/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
BASE=$(cd -- "$(dirname -- "$0")"; pwd)

if [ ! -e "$BASE/config/dump.conf" ]; then
	echo "Edit configuration: $BASE/config/dump.conf"
	exit 1
fi

# pick up functions & defaults
. "$BASE/libexec/functions.sh"
. "$BASE/config/dump.conf"

# sanity check: see if the disks are there, otherwise we quit
source_found=0
target_found=0
count=$(sysctl hw.diskcount | cut -f 2 -d '=')
for num in $(jot "$count"); do
	disks=$(sysctl hw.disknames | cut -f 2 -d '=')
	disk=$(echo "$disks" | cut -f "$num" -d ',')
	if [ "$disk" = "$target" ]; then
		target_found=1
	fi
	if [ "$disk" = "$source" ]; then
		source_found=1
	fi
done

if [ "$source_found" -ne 1 ] || [ "$target_found" -ne 1 ]; then
	exit 0
fi

log 'Starting dump to a removable drive'

# mount the target directory, this should be listed in fstab
mount -fw "$target_dir"

for partition in $partitions_to_dump; do
	# dump
	output=$(dump $opts -f ${target_dir}/${hostname}_${source}${partition} /dev/${source}${partition} 2>&1)
	log "$output"
	# dd
	#log "# /bin/dd if=/dev/r${source}${partition} of=/dev/r${target}${partition} $opts"
	#output=$(/bin/dd if=/dev/r${source}${partition} of=/dev/r${target}${partition} $opts 2>&1)
	#log "\n$output"
	#log "# /sbin/fsck -y /dev/${target}${partition}"
	#output=$(/sbin/fsck -y /dev/${target}${partition} 2>&1)
	#log "\n$output"
done

# finally log the disklabel outputs (in case we need to restore them too)
output=$(/sbin/disklabel $source 2>&1)
log "$output"

echo "$debug_str" | mail -s "Dump log" $mailto

exit 0
