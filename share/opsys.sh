#!/bin/sh

# Configure script to be compatible across different 
# operating systems.
configure_envs()
{
	local OPSYS; OPSYS=$(uname)

	case "$OPSYS" in
		OpenBSD)
			HAVE_BSD_LOCATE=Yes
			HAVE_BSD_DATE=Yes
			HAVE_BSD_DF=Yes

			HAVE_MLOCATE=No
			HAVE_GNU_DATE=No
			HAVE_GNU_DF=No
		;;
		Linux)
			HAVE_BSD_LOCATE=No
			HAVE_BSD_DATE=No
			HAVE_BSD_DF=No

			HAVE_MLOCATE=Yes
			HAVE_GNU_DATE=Yes
			HAVE_GNU_DF=Yes
		;;
		*)
			printf '%s\n' "Unknown OS, check opsys.sh and adjust if appropriate." | log
			HAVE_BSD_LOCATE=Yes
			HAVE_BSD_DATE=Yes
			HAVE_BSD_DF=Yes

			HAVE_MLOCATE=No
			HAVE_GNU_DATE=No
			HAVE_GNU_DF=No
		;;
	esac
}

configure_envs

# Linux and OpenBSD have different df -i syntaxes.
my_df_i()
{
	if [ "$HAVE_BSD_DF" = "Yes" ]; then
		echo $(df -i "$1" | tail -1 | awk '{ print $7 }')
	elif [ "$HAVE_GNU_DF" = "Yes" ]; then
		echo $(df -i "$1" | tail -1 | awk '{ print $4 }')
	else
		printf "ERROR: No df type defined, check opsys.sh!" >&2
		exit 1
	fi
}

# Linux and OpenBSD have different date time parsing syntaxes.
my_date_parse()
{
	if [ "$HAVE_BSD_DATE" = "Yes" ]; then
		echo $(date -j $(echo "$1" | sed -e 's/-//g')00 "+%s")
	elif [ "$HAVE_GNU_DATE" = "Yes" ]; then
		echo $(date -d "$(echo "$1" | sed -r 's/^([0-9]{4})-([0-9]{2})-([0-9]{2})-([0-9]{2})$/\1\2\3 \4/')00" "+%s")
	else
		printf "ERROR: No date type defined, check opsys.sh!" >&2
		exit 1
	fi
}
