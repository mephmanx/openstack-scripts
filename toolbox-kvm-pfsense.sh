#!/bin/bash
#can ONLY be run as root!  sudo to root
rm -rf /tmp/pfsense-install.log
exec 1>/root/pfsense-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x

source /tmp/openstack-env.sh
source ./vm_functions.sh
## prep project config by replacing nested vars
prep_project_config
#########

./create-pfsense-kvm.sh &
