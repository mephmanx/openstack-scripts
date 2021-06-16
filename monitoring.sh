#!/bin/bash

chmod 777 /tmp/openstack-env.sh
cd /tmp
. ./openstack-env.sh

. /tmp/vm_functions.sh

common_second_boot_setup

######## Put type specific code

############################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

#########  Spot for anything that needs to be run on every reboot from here on out
cat > /etc/rc.d/rc.local <<EOF

EOF

chmod a+x /etc/rc.d/rc.local