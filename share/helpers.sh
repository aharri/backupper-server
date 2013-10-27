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

	for util; do
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
		# Broken currently.
# 		if [ "$exec_dump" = "YES" ]; then
# 			$BASE/dumpfs
# 		fi
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
			# Exit can be sent as any user.
			ssh -S "$socket" -O exit "foo@bar.com" 2>&1 | debuglog
			test -e "$socket" && printf 'Socket did not seem to close: %s\n' "$socket" | debuglog
		done
	fi

	cat "${BASE}/logs/auth.log" | debuglog

	# Mail the results.
	if [ -n "$mailto" ]; then
		mail -s "[$(hostname)] Backup log $task_successes/$task_count" "$mailto" \
			< "${BASE}/logs/system.log" && \
			(: > "${BASE}/logs/system.log")
	fi
	rm -rf "$TMPDIR"
}

# Install signal traps and run initialization stuff.
run_init()
{
	TMPDIR=$(mktemp -d /tmp/backup.XXXXXXXXX) || exit 1
	trap : 2
	trap 'quit_handler' 0 1 13 15
	mkdir "$TMPDIR/tempfiles"
	mkdir "$TMPDIR/sockets"
	:> "${BASE}/logs/auth.log"
	printf '%s\n' "Installed signal traps and set up tmp environment" | log
	ssh_verbose=
	if [ "$debug" = 'YES' ]; then
		ssh_verbose='-vv'
		echo "SSH debug log will be output last." | log
	fi
}

# Example:
# IFS=: assign_vars "foo:bar" foo bar
# foo="foo"
# bar="bar"
assign_vars()
{
	for i in $1; do
		eval "$2=\$i"
		shift
	done
}

# Parse target: src:src_dir:dst:dst_dir:pri:exp:filter:command
# Returns
#  _src
#  _src_dir
#  _src_user
#  _src_host
#  _src_login
#  _dst
#  _dst_dir
#  _dst_user
#  _dst_host
#  _dst_login
#  _pri
#  _exp
#  _filter
#  _cmd
#
# This expands following variables: %origin% %filter%
# Note: newlines are not supported when defining jobs.
parse_target()
{
	local NONE
	_src= _src_dir= _src_user= _src_host= _src_login=
	_dst= _dst_dir= _dst_user= _dst_host= _dst_login=
	_pri= _exp= _filter= _cmd=

	IFS=: assign_vars "$1" _src _src_dir _dst _dst_dir _pri _exp _filter _cmd
	IFS=@ assign_vars "$_src" _src_user _src_host
	IFS=@ assign_vars "$_dst" _dst_user _dst_host
	unset IFS

	if [ -z "$_src_host" ]; then
		_src_host=$_src
		_src_user=$(whoami)
	fi
	_src_login="${_src_user}@${_src_host}"

	if [ -z "$_dst_host" ]; then
		_dst_host=$_dst
		_dst_user=$(whoami)
	fi
	_dst_login="${_dst_user}@${_dst_host}"

	# Both are remote
	if [ "$_src_host" != "localhost" ] && [ "$_dst_host" != "localhost" ]; then
		#backup_mode=relay
		echo "Error in configuration: rsync doesn't support relay." | log
		exit 1
	# Neither is remote
	elif [ "$_src_host" = "localhost" ] && [ "$_dst_host" = "localhost" ]; then
		backup_mode=filecopy
	# Source is local: push to remote
	elif [ "$_src_host" = "localhost" ]; then
		backup_mode=push
	# Destination is local: pull from source
	else
		backup_mode=pull
	fi
	_dst_dir=$(printf "%s\n" "$_dst_dir" | sed -e "s/%origin%/${_src_login}/g")
	_dst_dir=$(printf "%s\n" "$_dst_dir" | sed -e "s/%filter%/${_filter}/g")
}

seq()
{	local N; N=$1
	local N2; N2=$2
	while [ $N -le $N2 ]
	do
		echo $N
		N=$(expr $N + 1)
	done
}
