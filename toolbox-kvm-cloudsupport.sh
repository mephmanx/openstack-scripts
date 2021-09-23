#!/bin/bash
#can ONLY be run as root!  sudo to root
rm -rf /tmp/cloudsupport-install.log
exec 1>/root/cloudsupport-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x

source /tmp/openstack-env.sh

## prep project config by replacing nested vars
source ./vm_functions.sh
prep_project_config
#########

./create-cloudsupport-kvm.sh &
