#!/bin/bash

chmod 777 /tmp/openstack-env.sh
cd /tmp
. ./openstack-env.sh

source /tmp/vm_functions.sh

common_second_boot_setup

wipefs -a /dev/sdb
sleep 3
pvcreate /dev/sdb
sleep 3
vgcreate -v cinder-volumes /dev/sdb
sleep 3

index=0
for d in sdc sdd sde; do
  wipefs -a /dev/${d}
  pvcreate /dev/${d}
  parted /dev/${d} -s -- mklabel gpt mkpart KOLLA_SWIFT_DATA 1 -1
  sleep 5
  mkfs.xfs -f -L d${index} /dev/${d}1
  ((index++))
done

cd /etc/init.d
./vmware-tools restart

#remove so as to not run again
rm -rf /etc/rc.d/rc.local