#!/bin/bash

chmod 777 /tmp/openstack-env.sh
cd /tmp
. ./openstack-env.sh

. /tmp/vm_functions.sh

common_second_boot_setup

######## Put type specific code

cat > /etc/init.d/rc.local <<EOF
/sbin/ip link set eth2 promisc on
/sbin/ip link set eth1 promisc on
EOF
chmod 777 /etc/init.d/rc.local
runuser -l root -c  '/sbin/ip link set eth2 promisc on'
runuser -l root -c  '/sbin/ip link set eth1 promisc on'
############################

cd /etc/init.d
./vmware-tools restart

#remove so as to not run again
rm -rf /etc/rc.d/rc.local