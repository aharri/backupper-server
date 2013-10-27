#!/bin/sh
#
# Copyright (c) 2007,2013 Antti Harri <iku@openbsd.fi>
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

set -eu

# Pick up functions & defaults.
. "$BASE/share/opsys.sh"
. "$BASE/share/functions.sh"
. "$BASE/config/backup.conf"
. "$BASE/share/helpers.sh"

rm_last_directory()
{
	dir_to_remove=$(find "$@" -maxdepth 1 -type d -name "????-??-??-??" | \
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
}

clean_fs()
{
	local _INTERVAL; _INTERVAL=10
	local _LONG_INTERVAL; _LONG_INTERVAL=1000
	local dir; dir=
	local dirs; dirs=
	local size; size=$(printf '%s\n' "$minimum_space * 1048576" | bc)
	local num; num=
	local num_to_remove; num_to_remove=
	local dir_to_remove; dir_to_remove=
	local _megs; _megs=

	printf '%s\n' "Keeping $minimum_space GB and $minimum_inodes inodes available" | debuglog

	# Count the number of path names in $backups and add our hierarchy which
	# is login@hostname/filter/date == 3
	# Make this available globally.
	elements=$(printf '%s\n' "$backups" | \
		sed 's,$,/,;s,/\+,/,g' | \
		tr -dc '/' | \
		wc -c)
	elements=$((elements + 3))
	printf '[DEBUG_FS] elements=%s\n' "$elements " | debuglog

	while : ; do 

		# build directory variable
		dirs=
		local job
		for backup_job in $backup_jobs; do
			# Get _src, _src_user, _src_host and _src_login
			parse_target "$backup_job"
			for dir in "${backups}/${_src_login}"/*; do
				num=$(ls -1d "${dir}"/* 2>/dev/null | wc -l)
				if [ "$num" -gt "$max_backups" ]; then
					get_space_left
					get_inodes_left
					num_to_remove=$(($num - $max_backups))
					for i in $(seq 1 "$num_to_remove"); do
						rm_last_directory "$dir"
						sleep 5
					done
					# Now force the next if-statement, because this dir
					# may qualify for more cleaning
					dirs="$dirs $dir"
					continue
				fi
				if [ "$num" -gt "$min_backups" ]; then
					dirs="$dirs $dir"
				fi
			done
		done

		if [ -z "$dirs" ]; then
			# Don't error out at this point. There might not be enough of backups
			# synced yet to have $dirs variable.
			sleep $_LONG_INTERVAL
			continue
		fi

		while :; do
			# don't clean the disc if there is enough space & inodes left
			get_space_left
			get_inodes_left

			if [ "$space_left" -gt "$size" ] && \
			   [ "$inodes_left" -gt "$minimum_inodes" ]; then break; fi

			printf '[DEBUG_FS] dirs=%s\n' "$dirs" | debuglog

			rm_last_directory "$dirs"

			sleep 5
		done
		sleep $_INTERVAL
	done
}

# Call function to parse command line arguments.
parse_arguments $@

clean_fs # function call
