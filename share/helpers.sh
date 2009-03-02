#!/bin/sh

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
# FIXME: exiting here will not mail the logs: create clean up routine
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
		quit_handler
	fi
}

# Backup process checking.
check_backup_process()
{
	local lockdir
	lockdir="${BASE}/.backup.lock"
	if [ -d "$lockdir" ]; then
		printf '%s\n' "[QUITING] Process is already running (lock: $lockdir)" | log
		exit 1
	fi
	trap "rmdir \"$lockdir\"" 0 1 2 13 15
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

# Install signal traps.
trap_signals()
{
	trap : INT
	trap "rmdir \"$TMPDIR\"" EXIT
	printf '%s\n' "Installed signal traps: INT EXIT" | log
}

# Parse target
# Returns _target, _user, _host and _login
parse_target()
{
	_target=$(echo "$1" | cut -f 1 -d ':')
	_host=$(echo "$_target" | cut -f 2 -d '@')
	echo "$_target" | fgrep -q '@'
	if [ "$?" -eq 0 ]; then
		_user=$(echo "$_target" | cut -f 1 -d '@')
	else
		_user=$(whoami)
	fi
	_login="${_user}@${_host}"
}
