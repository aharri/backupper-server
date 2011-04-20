#!/bin/sh
#
# Copyright (c) 2007 Antti Harri <iku@openbsd.fi>
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
