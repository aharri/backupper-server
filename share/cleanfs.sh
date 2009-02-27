#!/bin/sh
#
# $Id: cleanfs,v 1.3 2009/02/25 09:55:00 iku Exp $
#
# Copyright (c) 2007 Antti Harri <iku@openbsd.fi>
#

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

# Call function to parse command line arguments.
parse_arguments $@

clean_fs # function call