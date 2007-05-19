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
machines=
#notify_common="admin@host"
backups=/backups
keep_backups=5
mailto="root@localhost"
debug=NO
io_timeout=21600
minimum_space=3
minimum_inodes=10000

#
# below this you shouldn't modify
#

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
. "$BASE/templates/notify_tpl.sh"

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

rsync_filter_common=
if [ -n "$filter_common" ]; then
	TMPFILE1=$(mktemp)
	if [ "$?" -ne 0 ]; then
		log "Could not create tempfile"
		exit 1
	fi
	echo "$filter_common" > "$TMPFILE1"
	rsync_filter_common=--filter=". $TMPFILE1"
fi
# We probably will need this so create it
TMPFILE2=$(mktemp)
if [ "$?" -ne 0 ]; then
	log "Could not create tempfile"
	exit 1
fi

date=$(date +%Y-%m-%d-%H)

# if machines is defined on the parameter line, use it
if [ -n "$1" ]; then
	machines=$1
fi

clean_fs &
clean_fs_pid=$!
log "Launched filesystem cleaner into bg, pid: $clean_fs_pid"
debuglog "Keeping $minimum_space GB and $minimum_inodes inodes"

for machine in $machines; do
	ping -w 1 -c 1 "${machine}" 1>/dev/null 2>/dev/null
	if [ "$?" -eq 0 ]; then
		log "machine $machine is alive"

		if [ ! -e "${backups}/${machine}/" ]; then
			install -d -m 0700 -o 0 -g 0 "${backups}/${machine}/"
			if [ "$?" -ne 0 ]; then 
				log "[SKIPPING] could not create ${backups}/${machine}/" 
				break
			fi
			log "created ${backups}/${machine}/"
		fi

		last_backup_dir=$(find "${backups}/${machine}/" -maxdepth 1 -name "????-??-??-??" | sort -nr | head -1)
		if [ -n "$last_backup_dir" ]; then
			log "latest backup seems to be in directory: $last_backup_dir"
			local last_backup_time=$(date -j "+%s" $(basename "$last_backup_dir" | sed -e 's/-//g')00)
			local _now=$(date "+%s")
			
			# get and prepare expiration
			local _expir=$(echo "$machine" | sed 's/\./_/g')
			eval _expir=$(echo '$'expiration_${_expir})
			if [ -z "$_expir" ] || [ "$_expir" -lt 0 ]; then
				_expir=0
			fi
			_expir=$((_expir * 3600))

			# finally compare!
			if [ "$((last_backup_time + _expir))" -gt "$_now" ] || [ $(basename "$last_backup_dir") = "$date" ]; then
				local _valid=$(((last_backup_time + _expir - _now) / 3600))
				log "[SKIPPING] snapshot exists that is valid for $_valid hours"
				continue
			fi
		fi

		new_dir="${backups}/${machine}/${date}"

		# create empty dir
		debuglog "about to create: $new_dir"
		install -d -m 0700 -o 0 -g 0 "$new_dir"
		if [ ! -e "$new_dir" ]; then
			log "[SKIPPING] failed to create ${new_dir}"
			continue
		fi

		# previous backup found -> copy it to be as base
		if [ -n "$last_backup_dir" ]; then
			cd "${last_backup_dir}"
			pax -r -w -l -p e * "${new_dir}"
		fi

		local rsync_filter_machine=
		local _test=$(echo "$machine" | sed 's/\./_/g')
		eval _test=$(echo '$'filter_${_test})

		if [ -n "$_test" ]; then
			echo "$_test" > $TMPFILE2			
			rsync_filter_machine=--filter=". $TMPFILE2"
		fi

		notify "$machine" "$backup_started"

		# directory setup complete
		# the following -e specification needs to be indented with spaces!
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
			"$rsync_filter_common" \
			"$rsync_filter_machine" \
			"${machine}:/" \
			"${new_dir}/" 2>&1)

		if [ "$?" -eq 0 ]; then
			log "[SUCCESSFUL] rsync was successful"
		else
			log "[FAILED] rsync failed, exit code was ${?}, output was:"
		fi
		log "$output"
		notify "$machine" "$backup_finished"
	else
		log "[SKIPPING] machine $machine is currently unavailable"
	fi
done

if [ -n "$TMPFILE1" ]; then
	rm -f "$TMPFILE1"
fi
rm -f "$TMPFILE2"

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
