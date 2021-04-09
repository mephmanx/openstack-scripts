#!/bin/bash

common_second_boot_setup

cd /etc/init.d
./vmware-tools restart

##update ip of network card 2 so that it is static in the 192.168.0.XXX range
#IP=(`awk -F'=' '$1 == "IPADDR" {print $2}' /etc/sysconfig/network-scripts/ifcfg-eth1`)
#octet=`echo "$IP" | cut -d . -f 4 | tr -d '"'`
#cn=`echo $octet + 5 | bc`
#sed -i "s/IPADDR=$IP/IPADDR=192.168.0.$cn/g" /etc/sysconfig/network-scripts/ifcfg-eth1
#ifdown eth1 && ifup eth1

#### create bond for eth1/2
#IP=(`awk -F'=' '$1 == "IPADDR" {print $2}' /etc/sysconfig/network-scripts/ifcfg-eth1`)
#IP+="/24"
#eth1UUID=`nmcli connection show | awk '$1 == "eth1" { print $2 }'`
#eth2UUID=`nmcli connection show | awk '$1 == "eth2" { print $2 }'`
#
#nmcli connection delete $eth1UUID
#nmcli connection delete $eth2UUID
#
#nmcli connection add type team con-name bond0 ifname bond0 config '{"runner": {"name": "activebackup"}}'
#
#nmcli con mod bond0  ipv4.addresses '$IP'
#nmcli con mod bond0  ipv4.gateway 192.168.0.1
#nmcli con mod bond0  ipv4.dns 192.168.0.1
#nmcli con mod bond0  ipv4.method manual
#nmcli con mod bond0  connection.autoconnect yes
#
#nmcli con add type team-slave con-name bond0-slave0 ifname eth1 master bond0
#nmcli con add type team-slave con-name bond0-slave1 ifname eth2 master bond0
#
#nmcli connection down bond0 && nmcli connection up bond0

#remove so as to not run again
rm -rf /etc/rc.d/rc.local