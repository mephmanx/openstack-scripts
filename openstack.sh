#!/bin/bash

chmod 777 /tmp/openstack-env.sh
. /tmp/openstack-env.sh

. /tmp/vm_functions.sh

######## Openstack main server install

exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

for FILE in /etc/sysconfig/network-scripts/*; do
    echo $FILE | sed "s:/etc/sysconfig/network-scripts/ifcfg-::g" | xargs ifup;
done

yum clean all && yum update -y  #this is only to make the next call work, DONT remove!

systemctl stop firewalld
systemctl mask firewalld

################# Bond all NIC's together
IP=`hostname -I | awk '{print $1}'`
IP+="/24"
eth0UUID=`nmcli connection show | awk '$1 == "eth0" { print $2 }'`
eth1UUID=`nmcli connection show | awk '$1 == "eth1" { print $2 }'`
eth2UUID=`nmcli connection show | awk '$1 == "eth2" { print $2 }'`

nmcli connection delete $eth0UUID
nmcli connection delete $eth1UUID
nmcli connection delete $eth2UUID

nmcli connection add type team con-name bond0 ifname bond0 config '{"runner": {"name": "activebackup"}}'

nmcli con mod bond0  ipv4.addresses '$IP'
nmcli con mod bond0  ipv4.gateway 192.168.1.1
nmcli con mod bond0  ipv4.dns 192.168.1.1
nmcli con mod bond0  ipv4.method manual
nmcli con mod bond0  connection.autoconnect yes

nmcli con add type team-slave con-name bond0-slave0 ifname eth0 master bond0
nmcli con add type team-slave con-name bond0-slave1 ifname eth1 master bond0
nmcli con add type team-slave con-name bond0-slave2 ifname eth2 master bond0

nmcli connection down bond0 && nmcli connection up bond0
##########################################

################# Add bridge
ip link add os-int-static type bridge
ip address add dev bond0 $IP
ip link set bond0 master os-int-static

cat > /etc/sysctl.d/99-netfilter-bridge.conf <<EOF
net.bridge.bridge-nf-call-ip6tables = 0
net.bridge.bridge-nf-call-iptables = 0
net.bridge.bridge-nf-call-arptables = 0
EOF

modprobe br_netfilter

cat > /etc/modules-load.d/br_netfilter.conf <<EOF
br_netfilter
EOF

sysctl -p /etc/sysctl.d/99-netfilter-bridge.conf
###########################

################# setup KVM and kick off openstack cloud create
dnf module install -y virt
dnf install -y cockpit-machines virt-install
############################
systemctl restart libvirtd


############ Create and init storage pools

## HP-Disk pool
virsh pool-define-as HP-Disk dir - - - - "/HP-Disk"
virsh pool-build HP-Disk
virsh pool-autostart HP-Disk
virsh pool-start HP-Disk

## HP-SSD pool
virsh pool-define-as HP-SSD logical - - /dev/sdb libvirt_lvm_hpssd  /dev/libvirt_lvm_hpssd
virsh pool-build HP-SSD
virsh pool-autostart HP-SSD
virsh pool-start HP-SSD
############################

############### configure networks
virsh net-destroy default
virsh net-undefine default

rm -rf /tmp/openstack-local.xml
rm -rf /tmp/openstack-internal.xml

cat > /tmp/openstack-local.xml <<EOF
<network>
  <name>os-loc-static</name>
  <ip address='10.0.20.1' netmask='255.255.255.0' />
</network>
EOF

cat > /tmp/openstack-internal.xml <<EOF
<network>
  <name>os-int-static</name>
  <bridge name='os-int-static'/>
  <forward mode='bridge' />
</network>
EOF

virsh net-define /tmp/openstack-local.xml
virsh net-define /tmp/openstack-internal.xml

virsh net-autostart os-loc-static
virsh net-autostart os-int-static

virsh net-start os-loc-static
virsh net-start os-int-static
################################

################ Prep and run cloud script
################### Load cloud create
cd /tmp
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git

cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;
####################

runuser -l root -c 'cd /tmp/openstack-setup; ./create-cloud.sh;'
################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local