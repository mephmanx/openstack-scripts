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
dnf module install -y virt
dnf install -y cockpit-machines virt-install
############################
systemctl restart libvirtd
################### Load cloud create
cd /tmp
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git
####################
runuser -l root -c 'cd /tmp/openstack-scripts; ./create-cloud.sh;'
################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local