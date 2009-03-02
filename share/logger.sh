#!/bin/sh
#
# $Id: logger,v 1.3 2008/03/12 17:15:02 iku Exp $
#
# Copyright (c) 2007 Antti Harri <iku@openbsd.fi>
#

BASE=$(cd -- "$(dirname -- "$0")"; pwd)/..
lockdir="${BASE}/.logger.lock"
logfile="${BASE}/logs/system.log"

if [ -n "$1" ]; then
	logfile=$1
fi

# Prevent race condition. Code from Lasse Collin.
while ! mkdir "$lockdir" 2> /dev/null ; do 
	sleep 1
done
trap "rmdir \"$lockdir\"" 0 1 2 13 15

# Log parameters
cat >> "$logfile"
