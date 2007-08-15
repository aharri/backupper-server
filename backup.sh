#!/bin/sh

# Copyright (c) 2006,2007 Antti Harri <iku@openbsd.fi>
# All rights reserved

####################################
# do not edit unless you know what
# you're actually doing.
#
# for configuration check
# config/backup.conf{,.sample}
####################################

# defaults
backup_jobs=
backups=/backups
keep_backups=5
mailto="root"
debug=NO
io_timeout=600
minimum_space=3
minimum_inodes=10000

#
# below this you shouldn't modify
#

filter_generic=

# default umask
umask 077

# paths where to look for installed utilities
PATH=/root/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
BASE=$(cd -- "$(dirname -- "$0")"; pwd)

if [ ! -e "$BASE/config/backup.conf" ]; then
	echo "Edit configuration: $BASE/config/backup.conf"
	exit 1
fi

# pick up functions & defaults
. "$BASE/bin/functions.sh"
. "$BASE/config/backup.conf"

# install signal traps
trap : INT
log "Installed signal traps"

# where is ssh pubkey for root user in remote clients
ssh_key="$BASE/config/ssh_key"

# section: check for missing programs
required="
	rm ls date pax df kill
	ping
	mail tr ssh find dirname basename tail sort head install wc du bc cut awk
	rsync"

for util in $required; do
	foo=$(which $util)
	if [ "$?" = 0 ]; then
		debuglog "found util: $foo"
	else
		log "You are missing $util, please install it"
		exit 1
	fi
done
log "Found all required tools"

if [ -f "$BASE/config/filters/generic" ]; then
	filter_generic=--filter=". $BASE/config/filters/generic"
fi

# Check jobs
# FIXME: exiting here will not mail the logs: create clean up routine
if [ -z "$backup_jobs" ]; then log "[QUITING] No backup jobs defined!"; exit 1; fi
parse_jobs
if [ -z "$parsed_jobs" ]; then log "[QUITING] Nothing to do!"; exit 0; fi

clean_fs &
clean_fs_pid=$!
log "Launched filesystem cleaner into bg, pid: $clean_fs_pid"
debuglog "Keeping $minimum_space GB and $minimum_inodes inodes"

sleep 20
exit
for backup_job in $parsed_jobs; do
	machine=$(echo "$backup_job" | cut -f 1 -d ':')
	filter_name=$(echo "$backup_job" | cut -f 4 -d ':')

	ping -w 1 -c 1 "${machine}" 1>/dev/null 2>/dev/null
	if [ "$?" -eq 0 ]; then
		log "machine $machine is alive"

		last_backup_dir=$(find "${backups}/${machine}/${filter_name}/" \
			-maxdepth 1 \
			-name "????-??-??-??" | sort -n | tail -n 1)

		date=$(date +%Y-%m-%d-%H)
		new_dir="${backups}/${machine}/${filter_name}/${date}"

		# create empty dir
		debuglog "about to create: $new_dir"
		mkdir "$new_dir"
		if [ ! -d "$new_dir" ]; then
			log "[QUITING] failed to create ${new_dir}"
			# FIXME: quit handler
			break
		fi

		# Previous backup found -> copy it to be as base.
		if [ -n "$last_backup_dir" ]; then
			(cd "${last_backup_dir}" && pax -r -w -l -p e * "${new_dir}")
			if [ "$?" -ne 0 ]; then
				rm -rf "$new_dir"
				log "[QUITING] Failed to copy."
				# FIXME: quit handler
				break
			fi
		fi

		local filter_machine=
		local filter_machine_generic=

		if [ -f "${BASE}/config/filters/generic_${machine}" ]; then
			filter_generic_machine=--filter=". ${BASE}/config/filters/generic_${machine}"
		fi
		if [ -f "${BASE}/config/filters/${filter_name}" ]; then
			filter_machine=--filter=". ${BASE}/config/filters/${filter_name}"
		else
			# Non-fatal, continue.
			log "[SKIPPING] Filter not found. Please check configuration."
			continue
		fi

		# Everything ready and initialized!
		# The following -e specification needs to be indented with spaces
		# because rsync is crappy!
		output=$(rsync \
			-a \
			-e "ssh \
                -o PasswordAuthentication=no \
                -o BatchMode=yes \
                -l _backup \
                -i ${ssh_key}" \
			--rsync-path=/home/_backup/backup_wrapper.sh \
			--delete-after \
			--delete-excluded \
			--numeric-ids \
			--timeout $io_timeout \
			"$filter_generic" \
			"$filter_generic_machine" \
			"$filter_machine" \
			"${machine}:/" \
			"${new_dir}/" 2>&1)

		if [ "$?" -eq 0 ]; then
			log "[SUCCESSFUL] rsync was successful"
		else
			log "[FAILED] exit code was ${?}, output was:"
			log "$output"
			rm -rf "$new_dir"
		fi
	else
		log "[SKIPPING] machine $machine is currently unavailable"
	fi
done

# mail the results
if [ -n "$mailto" ]; then
	echo "$debug_str" | mail -s "Backup log" "$mailto"
fi

# Remove fs cleaner
kill_bg_jobs

# Run dump
$BASE/dumpfs.sh

if [ "$?" -gt 0 ]; then
	debuglog "Dump was not succesful"
fi

quit_handler
