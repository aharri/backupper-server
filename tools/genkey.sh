#!/bin/sh

BASE=$(cd -- "$(dirname -- "$0")"; pwd)

ssh-keygen -N '' -t rsa -f "$BASE/../config/ssh_key"

if [ "$?" -eq 0 ]; then
	echo "You should now place the public key into clients' authorized_keys"
fi
