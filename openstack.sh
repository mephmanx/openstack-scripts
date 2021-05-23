#!/bin/bash

chmod 777 /tmp/openstack-env.sh
cd /tmp
. ./openstack-env.sh

. /tmp/vm_functions.sh

######## Openstack main server install

exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

yum clean all && yum update -y  #this is only to make the next call work, DONT remove!

systemctl stop firewalld
systemctl mask firewalld

################# setup KVM and kick off openstack cloud create
dnf install -y cockpit-machines virt virt-install
############################

################### Load cloud create
wget -O /tmp/create-cloud.sh -d https://mephmanx:{GITHUB_TOKEN}@raw.githubusercontent.com/mephmanx/openstack-scripts/master/create-cloud.sh
chmod 777 /tmp/create-cloud.sh
####################
cd /tmp
./create-cloud.sh
################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local