#!/bin/sh
#
# Copyright (c) 2006,2007,2008,2011 Antti Harri <iku@openbsd.fi>
#
# Permission to use, copy, modify, and distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
# OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

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
	if [ "$debug" = "YES" ]; then log; else exec > /dev/null; fi
}

get_space_left()
{
	space_left=`df -k "${backups}" | tail -1 | awk '{ print $4 }'`
}
get_inodes_left()
{
	inodes_left=$(my_df_i "${backups}")
}

#
# Check config/backup.conf.sample for details on the 
# backup job syntax.
#
parse_jobs()
{
	local backup_job
	local parsed_jobs2; parsed_jobs2=
	parsed_jobs=

	# First parser.
	for backup_job in $backup_jobs; do
		# Explode job into parts.
		parse_target "$backup_job"

		case "$backup_mode" in
		filecopy|pull)
			if [ ! -d "$_dst_dir" ]; then
				mkdir -p "$_dst_dir"
				if [ "$?" -ne 0 ]; then
					printf '%s\n' "[QUITING] could not create ${_dst_dir}" | log
					# FIXME: use clean up routine & exit
					return 1
				fi
				printf '%s\n' "created ${_dst_dir}" | debuglog
				printf '%s\n' "${_src_login}/${_filter} expired and added to job queue (filter's destination was not found)" | debuglog
				parsed_jobs2=$(openbsd_addel "$parsed_jobs2" "$backup_job")
				continue
			fi

			local last_backup_dir; last_backup_dir=$(\
				find "$_dst_dir" -maxdepth 1 | \
				egrep -e '/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}/?$' | \
				sort -n | tail -1)
			;;
		push)
			pingtest "$_dst_host"
			check_ssh_keyfile "$_dst_host" || continue
			setup_socket "$_dst_login"
			ssh \
				-S "$socket" \
				-o PasswordAuthentication=no \
				-o BatchMode=yes \
				"$_dst_login" \
				"test -d '${_dst_dir}'"
			if [ "$?" -ne "0" ]; then
				ssh \
					-S "$socket" \
					-o PasswordAuthentication=no \
					-o BatchMode=yes \
					"$_dst_login" \
					"mkdir -p '${_dst_dir}'"
				if [ "$?" -ne 0 ]; then
					printf '%s\n' "[QUITING] could not create ${_dst_dir}" | log
					# FIXME: use clean up routine & exit
					return 1
				fi
				printf '%s\n' "created ${_dst_login}:${_dst_dir}" | debuglog
				printf '%s\n' "${_src_login}/${_filter} expired and added to job queue (filter's destination was not found)" | debuglog
				parsed_jobs2=$(openbsd_addel "$parsed_jobs2" "$backup_job")
				continue
			fi

			local last_backup_dir=$(
				ssh \
				-S "$socket" \
				-o PasswordAuthentication=no \
				-o BatchMode=yes \
				"$_dst_login" \
				"find '${_dst_dir}' -type d -maxdepth 1 | \
				egrep -e '/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}$' | \
				sort -n | tail -n 1")
			;;
		esac
		if [ -z "$last_backup_dir" ]; then
			continue
		fi
		# compare expiration times
		printf '%s\n' "Checking if expired: $last_backup_dir" | debuglog
		local last_backup_time; last_backup_time=$(my_date_parse $(basename "$last_backup_dir"))
		local _now; _now=$(date "+%s")

		local expiration
		expiration=$((_exp * 3600))

		# finally compare!
		if [ "$((last_backup_time + expiration))" -gt "$_now" ] || [ $(basename "$last_backup_dir") = "$date" ]; then
			local _valid; _valid=$(((last_backup_time + expiration - _now) / 3600))
			printf '%s\n' "${_src_login}/${_filter} is valid ($_valid h) and therefore skipped" | debuglog
			continue
		fi
		printf '%s\n' "[EXPIRED] \"${_src_login}\": ${_filter}" | log
		parsed_jobs2=$(openbsd_addel "$parsed_jobs2" "$backup_job")
	done

	# Second parser.
	local login=
	local logins=$(printf '%s\n' "$parsed_jobs2" | cut -f 1,2,3,4 -d ':' | sort -u)
	# Traverse logins.
	for login in $logins; do
		# Select only jobs with highest priority (= lowest number).
		local backup_job; backup_job=$(printf '%s\n' "$parsed_jobs2" | grep "^[[:space:]]*${login}:" | sort -n -k 5 -t ':' | head -n 1)
		local filter_name; filter_name=$(printf '%s\n' "$backup_job" | cut -f 7 -d ':')
		parsed_jobs=$(openbsd_addel "$parsed_jobs" "$backup_job")
		printf '%s\n' "[ADDED] \"${login}\": ${filter_name}" | log
	done
	printf '%s\n' "Parsed jobs2 looks like this: $parsed_jobs2" | debuglog
	printf '%s\n' "Parsed jobs looks like this: $parsed_jobs" | debuglog
}


# $1 = remote host
check_ssh_keyfile()
{
	local file

	file=${HOME}/.ssh/known_hosts

	if [ ! -f "$file" ]; then
		printf '%s\n' "[SKIPPING] '${HOME}/.ssh/known_hosts' missing." | log
		return 1
	fi

	awk '{ print $1 }' "$file" | fgrep -q -w -e "$1"
	if [ "$?" -ne 0 ]; then
		printf '%s\n' "[SKIPPING] Host key not set. \"ssh $1\" and accept signature." | log
		return 1
	fi
	return 0
}

pingtest()
{
	ping -w 1 -c 1 "$1" 1>/dev/null 2>&1
	if [ "$?" -ne 0 ]; then
		printf '%s\n' "[SKIPPING] \"$1\" is currently unavailable" | log
		continue 1
	fi
	printf '%s\n' "\"$1\" is alive" | log
}

# $1 = login
sockets=
setup_socket()
{
	# Check for existing socket
	socket="${TMPDIR}/sockets/$1"
	printf '%s\n' "$sockets" | fgrep -q -w -e "$1"
	if [ "$?" -ne 0 ]; then
		# Open a connection to the remote host and
		# create a control socket
		# ssh -S /tmp/ssh_socket -M -N -f host.example.com
		ssh \
			-q $ssh_verbose \
			-S "$socket" \
			-M \
			-N \
			-o PasswordAuthentication=no \
			-o BatchMode=yes \
			-i "$ssh_key" \
			-f "$1" >> ${BASE}/logs/auth.log 2>&1
		if [ "$?" -ne 0 ]; then
			printf '%s\n' "[SKIPPING] failed to create ssh master socket for $_src_login" | log
			return 1
		fi
		sockets=$(openbsd_addel "$sockets" "$1")
		printf '%s\n' "Created socket for \"$1\"" | debuglog
	fi
	return 0
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
