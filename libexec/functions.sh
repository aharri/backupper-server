#!/bin/sh
#
# $Id: functions.sh,v 1.11 2009/02/25 09:55:00 iku Exp $
#
# Copyright (c) 2006,2007,2008 Antti Harri <iku@openbsd.fi>
#

log()
{
	local stamp=$(date "+%h %e %H:%M:%S")

	test -t 1 # test for stdout
	if [ "$?" -eq 0 ] || [ -z "$mailto" ]; then
		local TMP=$(mktemp) || exit 1
		sed "s|^|$stamp |" > "$TMP"
		cat "$TMP"
		"${BASE}/logger" < "$TMP"
		rm -f "$TMP"
	else
		sed "s|^|$stamp |" | "${BASE}/logger"
	fi
}

# debug logging
debuglog()
{
	if [ "$debug" = "YES" ]; then
		cat | log
	fi
}

clean_fs()
{
	local _INTERVAL=10
	local dir=
	local dirs=
	local size=$(printf '%s\n' "$minimum_space * 1048576" | bc)
	local host=
	local hosts=$(printf '%s\n' "$backup_jobs" | cut -f 1 -d ':' | sort -u)
	local num=
	local dir_to_remove=
	local elements=
	local _megs=
	#global machines backups keep_backups space_left minimum_inodes

	printf '%s\n' "Keeping $minimum_space GB and $minimum_inodes inodes available" | debuglog

	while : ; do 

		# build directory variable
		dirs=
		for host in $hosts; do
			for dir in "${backups}"/"${host}"/*; do
				num=$(ls -1d "${dir}"/* 2>/dev/null | wc -l)
				if [ "$num" -gt "$keep_backups" ]; then
					dirs="$dirs $dir"
				fi
			done
		done

		if [ -z "$dirs" ]; then
			printf '%s\n' "[ERROR] configuration error. FS cleaner cannot continue" | log
			exit 1
		fi

		while :; do
			# don't clean the disc if there is enough space & inodes left
			get_space_left
			get_inodes_left

			if [ "$space_left" -gt "$size" ] && \
			   [ "$inodes_left" -gt "$minimum_inodes" ]; then break; fi
			printf '[DEBUG_FS] dirs=%s\n' "$dirs" | debuglog
			elements=$(find $dirs -type d -maxdepth 1 -name "????-??-??-??" | tail -n 1)
#			printf '[DEBUG_FS] dir_to_remove=%s\n' "$dir_to_remove " | debuglog
			elements=$(printf '%s\n' "$dir_to_remove" | \
				sed 's,/\+,/,g;s,$,/,' | \
				tr -dc '/' | \
				wc -c)
			printf '[DEBUG_FS] elements=%s\n' "$elements " | debuglog
			dir_to_remove=$(find $dirs -type d -maxdepth 1 -name "????-??-??-??" | \
				sort -t '/' -k $elements | \
				head -n 1)
			printf '[DEBUG_FS] dir_to_remove=%s\n' "$dir_to_remove " | debuglog
			_megs=$((space_left / 1024))
			# Print status only before and after operation to prevent log flooding
			if [ -n "$dir_to_remove" ]; then
				printf '%s\n' "[STATUS1] left: ${_megs} MiB / ${inodes_left} inodes" | log
				printf '%s\n' "removing old backup: $dir_to_remove" | log
				rm -rf "$dir_to_remove"
				printf '%s\n' "[STATUS2] left: ${_megs} MiB / ${inodes_left} inodes" | log
			fi
			sleep 2
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
	if [ "$HAVE_BSD_DF" = "Yes" ]; then
		inodes_left=`df -i "${backups}" | tail -1 | awk '{ print $7 }'`
	elif [ "$HAVE_GNU_DF" = "Yes" ]; then
		inodes_left=`df -i "${backups}" | tail -1 | awk '{ print $4 }'`
	else
		echo "ERROR NO DF TYPE DEFINED! CHECK opsys.sh!"
		exit
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
		printf '%s\n' "[PREV. RUN] Quiting without waiting" | debuglog
		exit "$retval"
	fi

	# allow mail to BECOME VISIBLE!
	sleep 5

	# Wait for mail queue to become empty
	while : ; do 
		mailq | grep -q empty && break
		sleep "$_INTERVAL"
		# Log is not visible in mail, because it has been sent already!
		# It should show up in the next session though.
		printf '%s\n' "[PREV. RUN] Slept $_INTERVAL seconds, mail queue was not empty" | debuglog
		if [ "$count" -ge "$maxtries" ]; then
			temp=$((count * _INTERVAL))
			printf '%s\n' "[PREV. RUN] Max tries reached, mail was not delivered in $temp seconds, quiting anyway" | log
			break
		fi
		count=$((count + 1))
	done

	# Halt the machine and exit with the correct return value!
	$halt
	exit "$retval"
}

# host:priority:expiration:filter_name
#
# host: IP or resolvable hostname
# priority: priority when same host has multiple jobs
#           (0 or higher number. Lowest "wins")
# expiration: how many hours will the snapshot be valid
# filter_name: filter file name under config/filters/
#

parse_jobs()
{
	local backup_job=
	local parsed_jobs2=
	local date=$(date +%Y-%m-%d-%H)
	parsed_jobs=

	# First parser.
	for backup_job in $backup_jobs; do
		# get vars
		local machine=$(printf '%s\n' "$backup_job" | cut -f 1 -d ':')
		local priority=$(printf '%s\n' "$backup_job" | cut -f 2 -d ':')
		local expiration=$(printf '%s\n' "$backup_job" | cut -f 3 -d ':')
		local filter_name=$(printf '%s\n' "$backup_job" | cut -f 4 -d ':')

		if [ ! -d "${backups}/${machine}/${filter_name}/" ]; then
			mkdir -p "${backups}/${machine}/${filter_name}/"
			if [ "$?" -ne 0 ]; then
				printf '%s\n' "[QUITING] could not create ${backups}/${machine}/${filter_name}/" | log
				# FIXME: use clean up routine & exit
				return 1
			fi
			printf '%s\n' "created ${backups}/${machine}/${filter_name}/" | debuglog
			printf '%s\n' "${machine}/${filter_name} expired and added to jobs (filter's destination was not found)" | debuglog
		else 
			# compare expiration times
			local last_backup_dir=$(\
				find "${backups}/${machine}/${filter_name}/" \
				-maxdepth 1 \
				-name "????-??-??-??" | sort -n | tail -1)

			if [ -n "$last_backup_dir" ]; then
				printf '%s\n' "Checking if expired: $last_backup_dir" | debuglog
				if [ "$HAVE_BSD_DATE" = "Yes" ]; then
					local last_backup_time=$(date -j "+%s" $(basename "$last_backup_dir" | sed -e 's/-//g')00)
				elif [ "$HAVE_GNU_DATE" = "Yes" ]; then
					local last_backup_time=$(date -d "$(basename "$last_backup_dir" | sed -r 's/^([0-9]{4})-([0-9]{2})-([0-9]{2})-([0-9]{2})$/\1\2\3 \4/')00" "+%s")
				else
					echo "ERROR NO DATE TYPE DEFINED! CHECK opsys.sh!"
					exit
				fi
				local _now=$(date "+%s")

				expiration=$((expiration * 3600))

				# finally compare!
				if [ "$((last_backup_time + expiration))" -gt "$_now" ] || [ $(basename "$last_backup_dir") = "$date" ]; then
					local _valid=$(((last_backup_time + expiration - _now) / 3600))
					printf '%s\n' "${machine}/${filter_name} is valid ($_valid h) and therefore skipped" | debuglog
					continue
				fi
				printf '%s\n' "[EXPIRED] \"${machine}\": ${filter_name}" | log
			fi
		fi
		parsed_jobs2="$parsed_jobs2
			$backup_job"

	done

	# Second parser.
	local host=
	local hosts=$(printf '%s\n' "$parsed_jobs2" | cut -f 1 -d ':' | sort -u)
	# Traverse hosts.
	for host in $hosts; do
		# Select only jobs with highest priority (= lowest number).
		local hipri=$(printf '%s\n' "$parsed_jobs2" | grep "^[[:space:]]*${host}:" | cut -f 2 -d ':' | sort -n | head -n 1)
		local backup_job=$(printf '%s\n' "$parsed_jobs2" | grep "^[[:space:]]*${host}:${hipri}:")
		local filter_name=$(printf '%s\n' "$backup_job" | cut -f 4 -d ':' | perl -pe 's/\s+/ /g')
		parsed_jobs="$parsed_jobs
			$backup_job"
		printf '%s\n' "[ADDED] \"${host}\": ${filter_name}" | log
	done
	printf '%s\n' "Parsed jobs2 looks like this: $parsed_jobs2" | debuglog
	printf '%s\n' "Parsed jobs looks like this: $parsed_jobs" | debuglog
}

check_ssh_keyfile()
{
	local file=/root/.ssh/known_hosts

	if [ "$1" = "localhost" ]; then
		return 0
	fi

	if [ ! -f "$file" ]; then
		return 1
	fi

	awk '{ print $1 }' "$file" | fgrep -q -w -e "$1"
	return $?
}

create_db()
{
	# OpenBSD's Locate can be very slow when indexing (<= 4.5-release at least)
	if [ "$HAVE_BSD_LOCATE" = "Yes" ]; then
		# Index only regular files for now.
		find "$1" -type f -print0 | \
			xargs -0r md5 -r | \
			sed -e 's/ /:/' | \
			/usr/libexec/locate.mklocatedb > "$2"
	elif [ "$HAVE_MLOCATE" = "Yes" ]; then
		updatedb --prunepaths "" -l 0 -o "$2" -U "$1"
	else
		echo "ERROR NO LOCATE TYPE CONFIGURED! CHECK OPSYS.SH"
	fi
}
