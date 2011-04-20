#!/bin/sh
#
# Copyright (c) 2011 Antti Harri <iku@openbsd.fi>
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

# Walks through $required_tools and checks that
# they are all in $PATH.
check_required_tools()
{
	local util
	local foo

	for util in $required_tools; do
		foo=$(which "$util")
		if [ "$?" = 0 ]; then
			printf '%s\n' "found util: $foo" | debuglog
		elif [ "$util" = "sudo-backup-wrapper" ]; then
			printf '%s\n' "sudo-backup-wrapper is included with this software package." | log
			printf '%s\n' "Refer to the documentation how to install it approriately." | log
			exit 1
		else
			printf '%s\n' "You are missing $util, please install it" | log
			exit 1
		fi
	done
	printf '%s\n' "Found all required tools" | log
}

# Check all configured backup jobs.
check_configured_jobs()
{
	if [ -z "$backup_jobs" ]; then 
		printf '%s\n' "[QUITING] No backup jobs defined!" | log
		exit 1
	fi
	parse_jobs
	if [ -z "$parsed_jobs" ]; then 
		printf '%s\n' "[QUITING] Nothing to do!" | log
		# Dump to an external hard drive.
		if [ "$exec_dump" = "YES" ]; then
			$BASE/dumpfs
		fi
	fi
}

# Backup process checking.
check_backup_process()
{
	if [ -d "${BASE}/.backup.lock" ]; then
		printf '%s\n' "[QUITING] Process is already running" | log
		exit 1
	fi
}

# Show usage options.
show_usage()
{
	echo "$0 [-v|-h|-n]"
	exit 1
}

# Parse command line arguments.
parse_arguments()
{
	args=$(getopt vhn $*)
	if [ $? -ne 0 ]; then
		show_usage
	fi
	set -- $args
	while [ $# -ge 0 ]; do
		case "$1" in
				-v)
					if [ "$debug" = "YES" ]; then set -x; fi; shift;;
				-h)
					show_usage; shift;;
				-n)
					rsync_opts="$rsync_opts -n"; shift;;
				--)
			shift; break;;
		esac
	done

}

# Prevent shutdown before mail is delivered
quit_handler()
{

	# Close sockets.
	if [ $(ls -1 "$TMPDIR/sockets/"|wc -l) -gt 0 ]; then
		for socket in "$TMPDIR/sockets/"*; do
			# Get _target, _user, _host and _login
			parse_target "$(basename $socket)"
			ssh -S "$socket" -O exit "$_login" 2>&1 | debuglog
			test -e "$socket" && printf 'Socket did not seem to close: %s\n' "$socket" | debuglog
		done
	fi

	# Mail the results.
	if [ -n "$mailto" ]; then
		mail -s "[$(hostname)] Backup log $task_successes/$task_count" "$mailto" < "${BASE}/logs/system.log" && (: > "${BASE}/logs/system.log")
	fi
	rm -rf "$TMPDIR"
	rmdir "${BASE}/.backup.lock"
}

# Install signal traps and run initialization stuff.
run_init()
{
	TMPDIR=$(mktemp -d /tmp/backup.XXXXXXXXX) || exit 1
	trap : 2
	trap 'quit_handler' 0 1 13 15
	mkdir "$TMPDIR/tempfiles"
	mkdir "$TMPDIR/sockets"
	mkdir "${BASE}/.backup.lock"
	printf '%s\n' "Installed signal traps and set up tmp environment" | log
}

# Parse target
# Returns _target, _user, _host, _login and _cmd
parse_target()
{
	_target=$(echo "$1" | cut -f 1 -d ':')
	_cmd=$(echo "$1" | cut -f 5 -d ':')
	_host=$(echo "$_target" | cut -f 2 -d '@')
	echo "$_target" | fgrep -q '@'
	if [ "$?" -eq 0 ]; then
		_user=$(echo "$_target" | cut -f 1 -d '@')
	else
		_user=$(whoami)
	fi
	_login="${_user}@${_host}"
}
