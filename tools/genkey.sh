#!/bin/sh
#
# $Id: genkey.sh,v 1.3 2007/09/05 22:20:01 iku Exp $
#
# Copyright (c) 2007 Antti Harri <iku@openbsd.fi>
#

BASE=$(cd -- "$(dirname -- "$0")"; pwd)

ssh-keygen -N '' -t rsa -f "$BASE/../config/ssh_key"

if [ "$?" -eq 0 ]; then
	echo "You should now place the public key into clients' authorized_keys"
	echo "See the contents of .pub and paste it for example"
fi
