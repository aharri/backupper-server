#!/bin/sh

# dump options
opts="-a -0 -u"
# dd options
#opts="bs=16b seek=1 skip=1 conv=noerror"
source=wd0
target=wd1
target_dir=/mnt
partitions_to_dump="a d e f"

# who to mail
mailto="iku@openbsd.fi"

# power off when finished?
halt=NO

# command to run when halt=YES
halt_cmd="halt"
halt_opt="-p"


####################################
# do not edit below
####################################
debug_str=
source_found=0
target_found=0
hostname=$(hostname)

# 1st param: a string to be logged
log()
{
	local stamp=$(/bin/date "+%h %e %H:%M:%S")
#	local foo=$(echo $1 | sed "s|^|$stamp|")
	debug_str="${debug_str}\n${stamp} ${1}"
}

# sanity check: see if the disks are there, otherwise we quit
count=$(/sbin/sysctl hw.diskcount | /usr/bin/cut -f 2 -d '=')
for num in $(jot "$count"); do
	disks=$(/sbin/sysctl hw.disknames | /usr/bin/cut -f 2 -d '=')
	disk=$(echo "$disks" | /usr/bin/cut -f "$num" -d ',')
	if [ "$disk" = "$target" ]; then
		target_found=1
	fi
	if [ "$disk" = "$source" ]; then
		source_found=1
	fi
done

if [ "$source_found" -ne 1 ] || [ "$target_found" -ne 1 ]; then
	if [ "$halt" = "YES" ]; then
		$halt_cmd $halt_opt
	fi

	# sleep a while in case backupper mailed and didn't sleep
	sleep 10
	exit 1
fi

log 'Source and target devices found! good'
log 'Starting dump to a removable drive'

# mount the target directory, this should be listed in fstab
mount "$target_dir"

for partition in $partitions_to_dump; do
	# dump
	output=$(/sbin/dump $opts -f ${target_dir}/${hostname}_${source}${partition} /dev/${source}${partition} 2>&1)
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

echo "$debug_str" | /usr/bin/mail -s "Dump log" $mailto

# allow the mail to be delivered if halt specified
if [ "$halt" = "YES" ]; then
	sleep 180
	$halt_cmd $halt_opt
fi
