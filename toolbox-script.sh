#!/bin/bash
#can ONLY be run as root!  sudo to root
rm -rf /tmp/$1-install.log
exec 1>/root/$1-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x

source /tmp/openstack-env.sh
source ./vm_functions.sh

./create-$1-kvm.sh &
