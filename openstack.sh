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
export IP=`hostname -I | awk '{print $1}'`
export IP+="/24"
export eth0UUID=`nmcli connection show | awk '$1 == "eth0" { print $2 }'`
export eth1UUID=`nmcli connection show | awk '$1 == "eth1" { print $2 }'`
export eth2UUID=`nmcli connection show | awk '$1 == "eth2" { print $2 }'`
export eth3UUID=`nmcli connection show | awk '$1 == "eth3" { print $2 }'`

nmcli connection delete $eth0UUID
nmcli connection delete $eth1UUID
nmcli connection delete $eth2UUID
nmcli connection delete $eth3UUID

nmcli connection add type team con-name os-int-static ifname os-int-static config '{"runner": {"name": "activebackup"}}'

nmcli con mod os-int-static ipv4.method auto
nmcli con mod os-int-static ipv4.dhcp-fqdn `hostname`
nmcli con mod os-int-static connection.autoconnect yes

nmcli con add type team-slave con-name os-int-static-slave0 ifname eth0 master os-int-static
nmcli con add type team-slave con-name os-int-static-slave1 ifname eth1 master os-int-static
nmcli con add type team-slave con-name os-int-static-slave2 ifname eth2 master os-int-static
nmcli con add type team-slave con-name os-int-static-slave3 ifname eth3 master os-int-static

nmcli connection down os-int-static && nmcli connection up os-int-static
##########################################

################# Add bridge
#ip link add os-int-static type bridge
#ip address add dev os-int-static $IP
#ip link set bond0 master os-int-static
#
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
dnf install -y cockpit-machines virt-install virt-viewer
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

## HP-SSD pool
virsh pool-define-as HP-EXT dir - - - - "/HP-EXT"
virsh pool-build HP-EXT
virsh pool-autostart HP-EXT
virsh pool-start HP-EXT
############################

############### configure networks

rm -rf /tmp/openstack-local.xml

cat > /tmp/openstack-local.xml <<EOF
<network>
  <name>os-loc-static</name>
  <bridge name="os-loc-static" />
</network>
EOF

virsh net-define /tmp/openstack-local.xml

virsh net-autostart os-loc-static

virsh net-start os-loc-static

################################

################ Prep and run cloud script
################### Load cloud create
cd /tmp
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git

cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;

######remove existing isos
rm -rf /var/tmp/*.*;
#############

####################
runuser -l root -c 'cd /tmp/openstack-setup; ./create-cloudsupport-centos8-kvm.sh;'
runuser -l root -c 'cd /tmp/openstack-setup; ./create-cloud.sh;'
################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local