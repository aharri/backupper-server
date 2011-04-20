#!/bin/sh
#
# Copyright (c) 2007 Antti Harri <iku@openbsd.fi>
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

# Paths where to look for installed utilities.
PATH=/root/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
BASE=$(cd -- "$(dirname -- "$0")"; pwd)/..

if [ ! -e "$BASE/config/backup.conf" ]; then
    echo "Edit configuration: $BASE/config/backup.conf"
    exit 1
fi

# Pick up functions & defaults.
. "$BASE/share/functions.sh"
. "$BASE/share/opsys.sh"
. "$BASE/config/backup.conf"
. "$BASE/share/helpers.sh"

clean_fs()
{
	local _INTERVAL; _INTERVAL=10
	local dir; dir=
	local dirs; dirs=
	local size; size=$(printf '%s\n' "$minimum_space * 1048576" | bc)
	local num; num=
	local dir_to_remove; dir_to_remove=
	local elements; elements=
	local _megs; _megs=

	printf '%s\n' "Keeping $minimum_space GB and $minimum_inodes inodes available" | debuglog

	while : ; do 

		# build directory variable
		dirs=
		local job
		for backup_job in $backup_jobs; do
			# Get _target, _user, _host and _login
			parse_target "$backup_job"
			for dir in "${backups}/${_login}"/*; do
				num=$(ls -1d "${dir}"/* 2>/dev/null | wc -l)
				if [ "$num" -gt "$min_backups" ]; then
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
			elements=$(find $dirs -maxdepth 1 -type d -name "????-??-??-??" | tail -n 1)
#			printf '[DEBUG_FS] dir_to_remove=%s\n' "$dir_to_remove " | debuglog
			elements=$(printf '%s\n' "$dir_to_remove" | \
				sed 's,/\+,/,g;s,$,/,' | \
				tr -dc '/' | \
				wc -c)
			printf '[DEBUG_FS] elements=%s\n' "$elements " | debuglog
			dir_to_remove=$(find $dirs -maxdepth 1 -type d -name "????-??-??-??" | \
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

# Call function to parse command line arguments.
parse_arguments $@

clean_fs # function call
