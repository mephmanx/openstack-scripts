#!/bin/bash
#can ONLY be run as root!  sudo to root
rm -rf /tmp/cloud-install.log
exec 1>/root/cloud-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x

source /tmp/openstack-env.sh

rm -rf /tmp/openstack-setup;
rm -rf /tmp/openstack-scripts;

git clone https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/openstack-setup.git /tmp/openstack-setup;
git clone https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/openstack-scripts.git /tmp/openstack-scripts;

cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;

## prep project config by replacing nested vars
cp /tmp/openstack-setup/vm_functions.sh /tmp/vm_functions.sh
source /tmp/openstack-setup/vm_functions.sh
prep_project_config
#########

cd /tmp/openstack-setup
/tmp/openstack-setup/create-cloud-kvm.sh &
