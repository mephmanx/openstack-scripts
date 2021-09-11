#!/bin/bash
#can ONLY be run as root!  sudo to root
rm -rf /tmp/cloudsupport-install.log
exec 1>/root/cloudsupport-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x

source /tmp/openstack-env.sh

rm -rf /tmp/openstack-scripts;
git clone https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/openstack-scripts.git /tmp/openstack-scripts;

## prep project config by replacing nested vars
cp /tmp/openstack-scripts/vm_functions.sh /tmp/vm_functions.sh
source /tmp/vm_functions.sh
prep_project_config
#########

cd /tmp/openstack-scripts
./create-cloudsupport-kvm.sh &
