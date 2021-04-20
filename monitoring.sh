#!/bin/bash

chmod 777 /tmp/openstack-env.sh
cd /tmp
. ./openstack-env.sh

. /tmp/vm_functions.sh

common_second_boot_setup

######## Put type specific code

############################

cd /etc/init.d
./vmware-tools restart

#remove so as to not run again
rm -rf /etc/rc.d/rc.local