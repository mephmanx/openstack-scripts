#!/bin/bash

chmod 777 /tmp/openstack-env.sh
cd /tmp
. ./openstack-env.sh

. /tmp/vm_functions.sh

common_second_boot_setup

######## Put type specific code

cat > /usr/lib/systemd/system/netcfg@.service <<EOF
[Unit]
Description=Control promiscuous mode for interface %i
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/ip link set %i promisc on
ExecStop=/sbin/ip link set %i promisc off
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
runuser -l root -c  'systemctl enable netcfg@eth2'
############################

cd /etc/init.d
./vmware-tools restart

#remove so as to not run again
rm -rf /etc/rc.d/rc.local