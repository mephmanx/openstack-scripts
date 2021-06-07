#!/bin/bash

# Source function library.
. /tmp/vm_functions.sh


exec 1>/tmp/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

for FILE in /etc/sysconfig/network-scripts/*; do
    echo $FILE | sed "s:/etc/sysconfig/network-scripts/ifcfg-::g" | xargs ifup;
done

#########load secrets into env
chmod 777 /tmp/openstack-env.sh
source ./tmp/openstack-env.sh
############################

systemctl start cockpit.socket
systemctl enable --now cockpit.socket

############## Prep OpenStack install
rm -rf /etc/rc.d/rc.local
curl -o /etc/rc.d/rc.local https://mephmanx:$GITHUB_TOKEN@raw.githubusercontent.com/mephmanx/openstack-scripts/master/openstack.sh
chmod +x /etc/rc.d/rc.local

########################

################# Bond all NIC's together
#export IP=`hostname -I | awk '{print $1}'`
#export IP+="/24"
nmcli connection add type bond con-name os-int-static ifname os-int-static mode 802.3ad
nmcli con mod id os-int-static bond.options mode=802.3ad,miimon=100,lacp_rate=fast,xmit_hash_policy=layer2+3

nmcli con mod os-int-static ipv4.method auto
nmcli con mod os-int-static ipv6.method auto
nmcli con mod os-int-static connection.autoconnect yes

ct=0
for DEVICE in `nmcli device | awk '$1 != "DEVICE" && $3 == "connected" && $2 == "ethernet" { print $1 }'`; do
    echo "$DEVICE"
    nmcli connection delete $DEVICE
    nmcli con add type bond-slave con-name os-int-static-slave$ct ifname $DEVICE master os-int-static
    ((ct++))
done

nmcli connection down os-int-static && nmcli connection up os-int-static
##########################################

reboot
