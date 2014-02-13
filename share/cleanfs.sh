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

clean_fs()
{
	local space_to_keep; space_to_keep=$(printf '%s\n' "$minimum_space * 1048576" | bc)

	printf '%s\n' "[DEBUG_FS] Keeping $minimum_space GB and $minimum_inodes inodes available" | debuglog

	local backup_job
	for backup_job in $backup_jobs; do
		# Get type, destination dir, etc.
		parse_target "$backup_job"

		# Skip remote targets
		test "$backup_mode" = push && continue

		if [ ! -d "$_dst_dir" ]; then
			continue
		fi

		local cur_date
		cur_date=$(date +%s)

		# 1st:0:3:-1
		# ci_minrate [h/job] ci_maxrate [h/job]
		local ci_name ci_start ci_stop ci_minrate ci_maxrate ci_minjobs ci_maxjobs
		local count cleaning_interval
		count=0; for cleaning_interval in $cleaning_intervals; do
			count=$((count + 1))

			IFS=: assign_vars "$cleaning_interval" ci_name ci_start ci_stop ci_maxrate
			unset IFS

			# Keep all
			test "$ci_maxrate" = "-1" && continue

			# Lets first calculate the maximum number of jobs allowed.
			# (stop[d] - start[d]) * 24h / rate[h/job] = max jobs
			if [ "$ci_maxrate" = "0" ]; then
				ci_maxjobs=0 # prevent division by zero
				ci_minjobs=0
			else
				ci_maxjobs=$(printf '(%s - %s) * 24 / %s\n' "$ci_stop" "$ci_start" "$ci_maxrate" | bc)
				if [ "$ci_maxjobs" -lt "0" ]; then
					printf '[WARNING] Could not calculate max jobs for "%s", exiting\n' "$ci_name" | log
					break 2
				fi
				ci_minjobs=$(printf '%s\n' "$_minjobs" | cut -f "$count" -d ',')
			fi
# 			ci_maxjobs=2
# 			ci_minjobs=0
			printf '[DEBUG_FS] Maximum jobs for %s is %s (ci:%s)\n' "$_dst_dir" "$ci_maxjobs" "$ci_name" | debuglog

			ci_start=$(printf '%s - (3600 * 24 * %s)\n' "$cur_date" "$ci_start" | bc)
			ci_stop=$(printf '%s - (3600 * 24 * %s)\n' "$cur_date" "$ci_stop" | bc)

			local dir dirs interval_dirs count2
			dirs=$(find "$_dst_dir" -maxdepth 1 -type d -name "????-??-??-??" | \
				sed -E 's,(.*/)(.*),\2/\1\2,' | \
				sort -t '/' -k 1 | \
				cut -c 15-)
			interval_dirs=''; count2=0; for dir in $dirs; do
				# 2013-08-17-07 -> %Y-%m-%dT%H:%M:%S so GNU date can grok it.
				# XXX: Use my_date_parse()
				local snap_date
				snap_date=$(date --date="$(basename "$dir" | sed -E 's,(.*)-(..)$,\1T\2:00:00,')" +%s)
				# Out-of-range check
				if [ "$snap_date" -lt "$ci_stop" ] || \
				   [ "$snap_date" -gt "$ci_start" ]; then
					continue
				fi
				count2=$((count2 + 1))
				interval_dirs=$(openbsd_addel "$interval_dirs" "$dir")
			done

			# XXX: -lt -1 ?
			if [ -z "$ci_minjobs" ] || [ "$ci_minjobs" -lt "-1" ]; then
				printf '[WARNING] Could not get minimum jobs for "%s", exiting.\n' "$_dst_dir" | log
				break 2
			fi
			printf '[DEBUG_FS] Minimum jobs for %s is %s (ci:%s)\n' "$_dst_dir" "$ci_minjobs" "$ci_name" | debuglog
			if [ "$count2" -le "$ci_minjobs" ]; then
				printf '[DEBUG_FS] Backups low in "%s":"%s", lagging? -> skipping job\n' \
					"$_dst_dir" "$ci_name" | log
				continue 2
			fi

			if [ "$count2" -gt "$ci_maxjobs" ]; then
				printf '[DEBUG_FS] more than %s backups in %s -> cleaning\n' \
					"$ci_maxjobs" "$_dst_dir" | debuglog
				# Loop through available snapshots,
				# if there are more than rate allows, delete them.
				local suspended_snap_date # Suspended from deletion
				suspended_snap_date=''; for dir in $interval_dirs; do
					# 2013-08-17-07 -> %Y-%m-%dT%H:%M:%S so GNU date can grok it.
					# XXX: Use my_date_parse()
					snap_date=$(date --date="$(basename "$dir" | sed -E 's,(.*)-(..)$,\1T\2:00:00,')" +%s)
					# Initialize the variable
					if [ -z "$suspended_snap_date" ]; then
						suspended_snap_date=$snap_date
						printf '[DEBUG_FS] Suspended:      "%s"\n' "$(date --date="@$snap_date" +%Y-%m-%d-%H)" | debuglog
						test "$ci_maxrate" != "0" && continue
					fi
					local temp1
					temp1=$(printf '%s - (%s * 3600)\n' "$suspended_snap_date" "$ci_maxrate" | bc)
					printf '[DEBUG_FS] Time threshold: "%s"\n' "$(date --date="@$temp1" +%Y-%m-%d-%H)" | debuglog
					printf '[DEBUG_FS] Snapshot date:  "%s"\n' "$(basename "$dir")" | debuglog
					if [ "$snap_date" -gt "$temp1" ] || [ "$ci_maxrate" = "0" ]; then
						printf 'Removing: %s\n' "$dir" | log
						rm -rf "$dir"
					else
						suspended_snap_date=$snap_date
						printf '[DEBUG_FS] Suspended:      "%s"\n' "$(date --date="@$snap_date" +%Y-%m-%d-%H)" | debuglog
					fi
				done
			fi
			test "X$ci_minjobs" = "X-1" && continue

			# Reverse the list so the oldest is first
			temp1=''; for dir in $interval_dirs; do temp1=$(openbsd_addel "$temp1" "$dir"); done
			for dir in $temp1; do
				get_disc_stats "$_dst_dir"
				test "$space_left" -gt "$space_to_keep" && break
				test "$inodes_left" -gt "$minimum_inodes" && break
				test "$count2" -le "$ci_minjobs" && break

				printf '[DEBUG_FS] Not enough space/inodes in %s -> cleaning\n' \
					"$_dst_dir" | debuglog
				printf 'Removing: %s\n' "$dir" | log
				rm -rf "$dir"
				count2=$((count2 - 1))
			done
		done
	done
}

