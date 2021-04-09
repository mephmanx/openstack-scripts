#!/bin/bash

chmod 777 /tmp/openstack-env.sh
cd /tmp
. ./openstack-env.sh

source /tmp/vm_functions.sh

common_second_boot_setup

cd /etc/init.d
./vmware-tools restart

#remove so as to not run again
rm -rf /etc/rc.d/rc.local