#!/bin/sh
#
# $Id: functions.sh,v 1.11 2009/02/25 09:55:00 iku Exp $
#
# Copyright (c) 2006,2007,2008 Antti Harri <iku@openbsd.fi>
#

log()
{
	local stamp; stamp=$(date "+%h %e %H:%M:%S")

	test -t 1 # test for stdout
	if [ "$?" -eq 0 ] || [ -z "$mailto" ]; then
		local TMP; TMP=$(mktemp) || exit 1
		sed "s|^|$stamp |" > "$TMP"
		cat "$TMP"
		"${BASE}/share/logger.sh" < "$TMP"
		rm -f "$TMP"
	else
		sed "s|^|$stamp |" | "${BASE}/share/logger.sh"
	fi
}

# debug logging
debuglog()
{
	if [ "$debug" = "YES" ]; then
		cat | log
	fi
}

get_space_left()
{
	space_left=`df -k "${backups}" | tail -1 | awk '{ print $4 }'`
}
get_inodes_left()
{
	inodes_left=$(my_df_i "${backups}")
}

# login:priority:expiration:filter_name
#
# login:    [username@] + IP or resolvable hostname
# priority: priority when same login has multiple jobs
#           (0 or higher number. Lowest "wins")
# expiration: how many hours will the snapshot be valid
# filter_name: filter file name under config/filters/
#

parse_jobs()
{
	local backup_job; backup_job=
	local parsed_jobs2; parsed_jobs2=
	local date; date=$(date +%Y-%m-%d-%H)
	parsed_jobs=

	# First parser.
	for backup_job in $backup_jobs; do
		# get vars
		local priority; priority=$(printf '%s\n' "$backup_job" | cut -f 2 -d ':')
		local expiration; expiration=$(printf '%s\n' "$backup_job" | cut -f 3 -d ':')
		local filter_name; filter_name=$(printf '%s\n' "$backup_job" | cut -f 4 -d ':')
		# Get _target, _user, _host and _login
		parse_target "$backup_job"

		if [ ! -d "${backups}/${_login}/${filter_name}/" ]; then
			mkdir -p "${backups}/${_login}/${filter_name}/"
			if [ "$?" -ne 0 ]; then
				printf '%s\n' "[QUITING] could not create ${backups}/${_login}/${filter_name}/" | log
				# FIXME: use clean up routine & exit
				return 1
			fi
			printf '%s\n' "created ${backups}/${_login}/${filter_name}/" | debuglog
			printf '%s\n' "${_login}/${filter_name} expired and added to jobs (filter's destination was not found)" | debuglog
		else 
			# compare expiration times
			local last_backup_dir; last_backup_dir=$(\
				find "${backups}/${_login}/${filter_name}/" \
				-maxdepth 1 \
				-name "????-??-??-??" | sort -n | tail -1)

			if [ -n "$last_backup_dir" ]; then
				printf '%s\n' "Checking if expired: $last_backup_dir" | debuglog
				local last_backup_time; last_backup_time=$(my_date_parse $(basename "$last_backup_dir"))
				local _now; _now=$(date "+%s")

				expiration=$((expiration * 3600))

				# finally compare!
				if [ "$((last_backup_time + expiration))" -gt "$_now" ] || [ $(basename "$last_backup_dir") = "$date" ]; then
					local _valid; _valid=$(((last_backup_time + expiration - _now) / 3600))
					printf '%s\n' "${_login}/${filter_name} is valid ($_valid h) and therefore skipped" | debuglog
					continue
				fi
				printf '%s\n' "[EXPIRED] \"${_login}\": ${filter_name}" | log
			fi
		fi
		parsed_jobs2="$parsed_jobs2
			$backup_job"

	done

	# Second parser.
	local login; login=
	local logins; logins=$(printf '%s\n' "$parsed_jobs2" | cut -f 1 -d ':' | sort -u)
	# Traverse logins.
	for login in $logins; do
		# Select only jobs with highest priority (= lowest number).
		local hipri; hipri=$(printf '%s\n' "$parsed_jobs2" | grep "^[[:space:]]*${login}:" | cut -f 2 -d ':' | sort -n | head -n 1)
		local backup_job; backup_job=$(printf '%s\n' "$parsed_jobs2" | grep "^[[:space:]]*${login}:${hipri}:")
		local filter_name; filter_name=$(printf '%s\n' "$backup_job" | cut -f 4 -d ':' | perl -pe 's/\s+/ /g')
		parsed_jobs="$parsed_jobs
			$backup_job"
		printf '%s\n' "[ADDED] \"${login}\": ${filter_name}" | log
	done
	printf '%s\n' "Parsed jobs2 looks like this: $parsed_jobs2" | debuglog
	printf '%s\n' "Parsed jobs looks like this: $parsed_jobs" | debuglog
}

check_ssh_keyfile()
{
	local file; file=/root/.ssh/known_hosts

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
