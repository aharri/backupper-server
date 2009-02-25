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

# Show usage options.
show_usage()
{
	echo "$0 [-v|-h]"
	exit 1
}

# Parse command line arguments.
parse_arguments()
{
	args=$(getopt vh $*)
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