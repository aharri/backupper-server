#!/bin/sh

# From baseup
function touch_file
{
	if [ ! -e "$1" ]; then
		touch "$1"
		if [ "$?" -ne 0 ]; then
			echo "Failed to create configuration file $1"
			exit 1
		fi
	fi
}
# From baseup
function get_config
{
	# If configuration does not exist, create it
	touch_file "$CONFIG"

	_VAL=$(egrep "^$1=" "$CONFIG")
	ret=$?
	if [ "$ret" -ne "0" ]; then
		return $ret
	fi
	_VAL=$(echo "$_VAL"	| cut -f 2 -d '=' | tail -n 1)
	
}
# From baseup
function set_config
{
	# If configuration does not exist, create it
	touch_file "$CONFIG"
	get_config $1
	if [ "$?" -ne "0" ]; then
		echo "$1=$2" >> "$CONFIG"
		return 0
	fi
	TMPFILE=`mktemp -t baseup.XXXXXXXXXX` || return 1
	sed "s,^$1=.*$,$1=$2," "$CONFIG" > "$TMPFILE"
	cp -f "$TMPFILE" "$CONFIG"
	rm -f "$TMPFILE"
	return 0
}

# 1st param: what client are we working on
# 2nd param: what template to use for email body
notify()
{
	_test=$(echo "$1" | sed 's/\./_/g')
	eval _test=$(echo '$'notify_${_test})
	#eval _test='$'notify_$1
	if [ -n "$_test" ]; then
		echo "$2" | mail -s "Backup process of ${1}" "$_test"
	fi
	if [ -n "$notify_common" ]; then
		echo "$2" | mail -s "Backup process of ${1}" "$notify_common"
	fi
}

# init
debug_str=
# 1st param: a string to be logged
log()
{
	local stamp=$(date "+%h %e %H:%M:%S")
	debug_str="${debug_str}\n$stamp ${1}"
	test -t 1 # test for stdout
	ret=$?
	if [ -z "$send_logs_to" ] || [ $ret -eq 0 ]; then
		echo "$stamp ${1}"
	fi
}

clean_fs()
{
	dirs=
	size=$(echo "$minimum_space * 1048576" | bc)

	# build directory variable
	for _machine in $machines; do
		num=$(find ${backups}/$_machine/ -type d -maxdepth 1 | wc -l)
		if [ "$num" -gt "$keep_backups" ]; then
			dirs="$dirs ${backups}/$_machine/"
		fi
	done

	while :; do
		# don't clean the disc if there is enough space & inodes left
		get_space_left
		get_inodes_left
		if [ "$space_left" -gt "$size" ] && \
		   [ "$inodes_left" -gt "$minimum_inodes" ]; then break; fi
		dir_to_remove=$(find $dirs -type d -maxdepth 1 -name "????-??-??")
		elements=$(echo "$dir_to_remove" | tail -n 1 | sed 's,/\+,/,g')
		elements=$(echo "$elements"/ | tr -dc '/' | wc -c)
		dir_to_remove=$(echo "$dir_to_remove" | sort -t '/' -k $elements | head -n 1)
		log "removing old backup: $dir_to_remove"
		rm -rf "$dir_to_remove"
	done
}

get_space_left()
{
	space_left=`df -k "${backups}" | tail -1 | awk '{ print $4 }'`
}
get_inodes_left()
{
	inodes_left=`df -i "${backups}" | tail -1 | awk '{ print $7 }'`
}
