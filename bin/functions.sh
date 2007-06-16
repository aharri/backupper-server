#!/bin/sh

# 1st param: what client are we working on
# 2nd param: what template to use for email body
notify()
{
	local _test=$(echo "$1" | sed 's/\./_/g')

	eval _test=$(echo '$'notify_${_test})
	if [ -n "$_test" ]; then
		echo "$2" | mail -s "Backup process of ${1}" "$_test"
	fi
	if [ -n "$notify_common" ]; then
		echo "$2" | mail -s "Backup process of ${1}" "$notify_common"
	fi
}

debug_str=
log()
{
	local stamp=$(date "+%h %e %H:%M:%S")
	#global mailto debug_str

	debug_str="${debug_str}\n$stamp ${1}"
	test -t 1 # test for stdout
	if [ "$?" -eq 0 ] || [ -z "$mailto" ]; then
		echo "$stamp ${1}"
	fi
}

# debug logging
debuglog()
{
	#global debug

	if [ "$debug" = "YES" ]; then
		log "$1"
	fi
}

clean_fs()
{
	local _INTERVAL=10
	local dirs=
	local size=$(echo "$minimum_space * 1048576" | bc)
	local _machine
	local num
	local dir_to_remove
	local elements
	local _megs
	#global machines backups keep_backups space_left minimum_inodes

	while : ; do 
		# build directory variable
		for _machine in $machines; do
			num=$(find "${backups}/$_machine/" -type d -maxdepth 1 | wc -l)
			if [ "$num" -gt "$keep_backups" ]; then
				dirs="$dirs ${backups}/$_machine/"
			fi
		done

		while :; do
			# don't clean the disc if there is enough space & inodes left
			get_space_left
			get_inodes_left
			if [ "$space_left" -gt "$size" ] && \
			   [ "$inodes_left" -gt "$minimum_inodes" ]; then break; fi
			dir_to_remove=$(find $dirs -type d -maxdepth 1 -name "????-??-??-??")
			elements=$(echo "$dir_to_remove" | tail -n 1 | sed 's,/\+,/,g')
			elements=$(echo "$elements"/ | tr -dc '/' | wc -c)
			dir_to_remove=$(echo "$dir_to_remove" | sort -t '/' -k $elements | head -n 1)
			_megs=$((space_left / 1024))
			log "[STATUS] space left ${_megs} MiB / inodes left ${inodes_left}"
			log "removing old backup: $dir_to_remove"
			rm -rf "$dir_to_remove"
		done
		sleep $_INTERVAL
	done
}

get_space_left()
{
	#global space_left
	space_left=`df -k "${backups}" | tail -1 | awk '{ print $4 }'`
}
get_inodes_left()
{
	#global inodes_left
	inodes_left=`df -i "${backups}" | tail -1 | awk '{ print $7 }'`
}

kill_bg_jobs()
{
	#global clean_fs_pid
	if [ -n "$clean_fs_pid" ]; then
		kill -KILL "$clean_fs_pid"
		clean_fs_pid=
		log "Killed fs cleaner"
	fi
}

# Prevent shutdown before mail is delivered
quit_handler()
{
	local retval=0
	local count=1
	local maxtries=5
	local _INTERVAL=60
	local temp

	# Get return value, if defined
	if [ -n "$1" ]; then
		retval=$1
	fi

	# If we aren't suppose to shutdown machine, we can exit right away
	if [ -z "$halt" ]; then
		debuglog "Quiting without waiting"
		exit "$retval"
	fi

	# allow mail to BECOME VISIBLE!
	sleep 5

	# Wait for mail queue to become empty
	while : ; do 
		mailq | grep -q empty && break
		sleep "$_INTERVAL"
		# log is not visible in mail, because it has been sent already!
		# it should show up when running interactively though
		debuglog "Slept $_INTERVAL seconds, mail queue was not empty"
		if [ "$count" -ge "$maxtries" ]; then
			temp=$((count * _INTERVAL))
			log "Max tries reached, mail was not delivered in $temp seconds, quiting anyway"
			break
		fi
		count=$((count + 1))
	done

	# Halt the machine and exit with the correct return value!
	$halt
	exit "$retval"
}
