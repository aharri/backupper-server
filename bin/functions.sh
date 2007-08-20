#!/bin/sh

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
	local dir=
	local dirs=
	local size=$(echo "$minimum_space * 1048576" | bc)
	local host=
	local hosts=$(echo "$backup_jobs" | cut -f 1 -d ':' | sort -u)
	local num=
	local dir_to_remove=
	local elements=
	local _megs=
	#global machines backups keep_backups space_left minimum_inodes

	while : ; do 
		# build directory variable
		for host in $hosts; do
			for dir in "${backups}"/"${host}"/*; do
				num=$(ls -1d "${dir}"/* 2>/dev/null | wc -l)
				if [ "$num" -gt "$keep_backups" ]; then
					dirs="$dirs $dir"
				fi
			done
		done

		if [ -z "$dirs" ]; then
			log "[ERROR] configuration error. FS cleaner cannot continue"
			exit 1
		fi

		while :; do
			# don't clean the disc if there is enough space & inodes left
			get_space_left
			get_inodes_left
			if [ "$space_left" -gt "$size" ] && \
			   [ "$inodes_left" -gt "$minimum_inodes" ]; then break; fi
			dir_to_remove=$(find $dirs -type d -maxdepth 2 -name "????-??-??-??")
			elements=$(echo "$dir_to_remove" | tail -n 1 | sed 's,/\+,/,g')
			elements=$(echo "$elements"/ | tr -dc '/' | wc -c)
			dir_to_remove=$(echo "$dir_to_remove" | sort -t '/' -k $elements | head -n 1)
			_megs=$((space_left / 1024))
			log "[STATUS] space left ${_megs} MiB / inodes left ${inodes_left}"
			log "removing old backup: $dir_to_remove"
			rm -rf "$dir_to_remove"
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
		local machine=$(echo "$backup_job" | cut -f 1 -d ':')
		local priority=$(echo "$backup_job" | cut -f 2 -d ':')
		local expiration=$(echo "$backup_job" | cut -f 3 -d ':')
		local filter_name=$(echo "$backup_job" | cut -f 4 -d ':')

		if [ ! -d "${backups}/${machine}/${filter_name}/" ]; then
			mkdir -p "${backups}/${machine}/${filter_name}/"
			if [ "$?" -ne 0 ]; then
				log "[QUITING] could not create ${backups}/${machine}/${filter_name}/"
				# FIXME: use clean up routine & exit
				return 1
			fi
			debuglog "created ${backups}/${machine}/${filter_name}/"
			debuglog "${machine}/${filter_name} expired and added to jobs (filter was not found)"
		else 
			# compare expiration times
			local last_backup_dir=$(\
				find "${backups}/${machine}/${filter_name}/" \
				-maxdepth 1 \
				-name "????-??-??-??" | sort -n | tail -1)

			if [ -n "$last_backup_dir" ]; then
				debuglog "Checking if expired: $last_backup_dir"
				local last_backup_time=$(date -j "+%s" $(basename "$last_backup_dir" | sed -e 's/-//g')00)
				local _now=$(date "+%s")
				
				expiration=$((expiration * 3600))

				# finally compare!
				if [ "$((last_backup_time + expiration))" -gt "$_now" ] || [ $(basename "$last_backup_dir") = "$date" ]; then
					local _valid=$(((last_backup_time + expiration - _now) / 3600))
					debuglog "${machine}/${filter_name} is valid ($_valid h) and therefore skipped"
					continue
				fi
				log "[EXPIRED] ${machine}/${filter_name}"
			fi
		fi
		parsed_jobs2="$parsed_jobs2
			$backup_job"

	done

	# Second parser.
	local host=
	local hosts=$(echo "$parsed_jobs2" | cut -f 1 -d ':' | sort -u)
	# Traverse hosts.
	for host in $hosts; do
		# Select only jobs with highest priority (= lowest number).
		local hipri=$(echo "$parsed_jobs2" | grep "^[[:space:]]*${host}:" | cut -f 2 -d ':' | sort -n | head -n 1)
		local backup_job=$(echo "$parsed_jobs2" | grep "^[[:space:]]*${host}:${hipri}:")
		local filter_name=$(echo "$backup_job" | cut -f 4 -d ':' | perl -pe 's/\s+/ /g')
		parsed_jobs="$parsed_jobs
			$backup_job"
		log "[ADDED] ${host}: ${filter_name}"
	done
	debuglog "Parsed jobs2 looks like this: $parsed_jobs2"
	debuglog "Parsed jobs looks like this: $parsed_jobs"
}

check_ssh_keyfile()
{
	local file=$HOME/.ssh/known_hosts
	
	if [ ! -f "$file" ]; then
		return 1
	fi

	awk '{ print $1 }' "$file" | fgrep -q -w -e "$1"
	return $?
}
