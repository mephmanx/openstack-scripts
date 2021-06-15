#!/bin/bash

chmod 777 /tmp/openstack-env.sh
cd /tmp
. ./openstack-env.sh

. /tmp/vm_functions.sh

common_second_boot_setup

######## Put type specific code

#runuser -l root -c  '/sbin/ip link set eth2 promisc on'
#runuser -l root -c  '/sbin/ip link set eth0 promisc on'

#sed '/^IPADDR/d' -i /tmp/eth2
#sed '/^GATEWAY/d' -i /tmp/eth2
#sed '/^DNS1/d' -i /tmp/eth2
#sed '/^NETMASK/d' -i /tmp/eth2
#
#runuser -l root -c  "rm -rf /etc/sysconfig/network-scripts/ifcfg-eth2"
#runuser -l root -c  "cat /tmp/eth2 > /etc/sysconfig/network-scripts/ifcfg-eth2"
############################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

cat > /etc/rc.d/rc.local <<EOF

EOF

chmod a+x /etc/rc.d/rc.local

reboot