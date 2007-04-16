#!/bin/sh

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
send_logs_to="root@localhost"
debug=YES
halt="/sbin/halt -p"
dump=YES
kill_timer=NO
minimum_space=3
minimum_inodes=350000

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
if [ "$kill_timer" = "YES" ]; then
	trap "pkill -f '/bin/sh $BASE/bin/shnuke'": 3
	trap "pkill -f '/bin/sh $BASE/bin/shnuke'": 15
fi

# where is ssh pubkey for root user in remote clients
ssh_key="$BASE/config/ssh_key"

# section: check for missing programs
required="
rm ls date pax df
ping
mail tr ssh find dirname basename tail sort head install wc du bc cut awk
rsync"

for util in $required; do
	foo=`which $util`
	if [ "$?" = 0 ]; then
		log "found util: $foo"
	else
		log "You are missing $util, please install it"
		exit
	fi
done

date=`date +%Y-%m-%d`

# if machines is defined on the parameter line, use it
if [ -n "$1" ]; then
	machines=$1
fi

for machine in $machines; do
	ping -w 1 -c 1 "${machine}" 1>/dev/null 2>/dev/null
	if [ "$?" -eq "0" ]; then
		clean_fs

		# install timer for dead processes
		if [ "$kill_timer" = "YES" ]; then
			shnuke &
			foopid=$!
		fi
		log "machine $machine is alive"

		if [ ! -e "${backups}/${machine}/" ]; then
			install -d -m 0700 -o 0 -g 0 "${backups}/${machine}/"
			if [ "$?" -ne "0" ]; then 
				log "could not create ${backups}/${machine}/: skipping" 
				break
			fi
			log "created ${backups}/${machine}/"
		fi

		last_backup_dir=`find "${backups}/${machine}/" -maxdepth 1 -name "????-??-??" | sort -nr | head -1`
		last_backup_time=`basename ${last_backup_dir} 2>/dev/null`
		log "latest backup seems to be in directory: ${last_backup_dir} (${last_backup_time})"
		if [ "$last_backup_time" = "$date" ]; then
			log "you already seem to have backups for today: skipping"
			continue
		fi

		new_dir="${backups}/${machine}/${date}"

		# create empty dir
		install -d -m 0700 -o 0 -g 0 "$new_dir"
		if [ -e "$new_dir" ]; then
			log "created: $new_dir"
		else
			log "failed to create ${new_dir}: skipping to the next"
			continue
		fi
		# previous backup found -> copy it to be as base
		if [ "$last_backup_time" != "" ]; then
			# check for hd space
			get_space_left
			get_inodes_left
			_space_left=$(echo "$space_left / 1024" | bc)
			log "status: ${_space_left} MiB (space left) / ${inodes_left} (inodes left)"

			cd "${last_backup_dir}"
			pax -r -w -l -p e * "${new_dir}"
		fi

		if [ -e "$BASE/config/filter_${machine}" ]; then
			IFS=:
			excludes="--filter:. $BASE/config/filter_${machine}"
		else
			excludes=
		fi
	
		notify "$machine" "$backup_started"

		# directory setup complete
		output=$(rsync															\
			-a																	\
			-e "ssh -o PasswordAuthentication=no -l _backup -i ${ssh_key}"	\
			--rsync-path=/home/_backup/backup_wrapper.sh						\
			--delete-after														\
			--delete-excluded													\
			--numeric-ids														\
			--filter ". $BASE/config/filter_common"								\
			$excludes															\
			"${machine}:/"														\
			"${new_dir}/" 2>&1)

		if [ "$?" -eq 0 ]; then
			log "rsync was succesful"
		else
			log "rsync failed with exit code ${?}"
			log "output of rsync follows:"
		fi
		unset IFS
		if [ "$kill_timer" = "YES" ]; then
			kill -9 $foopid
		fi
		log "$output"
		notify "$machine" "$backup_finished"
	else
		log "machine $machine is currently unavailable"
	fi
done

if [ "$debug" = "YES" ]; then
	# mail the results, else print them
	if [ -n "$send_logs_to" ]; then
		echo "$debug_str" | mail -s "Backup log" "$send_logs_to"
	fi
fi

if [ "$dump" = "YES" ]; then
	$BASE/dumpfs.sh
elif [ -n "$halt" ]; then
	$halt
fi
