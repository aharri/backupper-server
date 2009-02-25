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

		;;
		Linux)
			HAVE_MLOCATE=Yes
			HAVE_GNU_DATE=Yes
			HAVE_GNU_DF=Yes
		;;
		*)
			printf '%s\n' "Unknown OS, check opsys.sh and adjust if appropriate." | log
			HAVE_BSD_LOCATE=Yes
			HAVE_BSD_DATE=Yes
			HAVE_BSD_DF=Yes
		;;
	esac
}

configure_envs
