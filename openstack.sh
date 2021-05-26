#!/bin/bash

chmod 777 /tmp/openstack-env.sh
cd /tmp
. ./openstack-env.sh

. /tmp/vm_functions.sh

######## Openstack main server install

exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

yum clean all && yum update -y  #this is only to make the next call work, DONT remove!

systemctl stop firewalld
systemctl mask firewalld

################# Bond all NIC's together
IP=(`hostname -I | awk '{print $1}'`)
IP+="/24"
eth1UUID=`nmcli connection show | awk '$1 == "eth0" { print $2 }'`
eth2UUID=`nmcli connection show | awk '$1 == "eth1" { print $2 }'`
eth3UUID=`nmcli connection show | awk '$1 == "eth2" { print $2 }'`

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

################# setup KVM and kick off openstack cloud create
dnf module install -y virt
dnf install -y cockpit-machines virt-install
############################
systemctl restart libvirtd
################### Load cloud create
cd /tmp
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git
####################

############ Create and init storage pools

## HP-Disk pool
virsh pool-define-as HP-Disk logical - - /dev/sdb libvirt_lvm_hpdisk  /dev/libvirt_lvm_hpdisk
virsh pool-build HP-Disk
virsh pool-autostart HP-Disk
virsh pool-start HP-Disk

## HP-SSD pool
virsh pool-define-as HP-SSD logical - - /dev/sdc libvirt_lvm_hpssd  /dev/libvirt_lvm_hpssd
virsh pool-build HP-SSD
virsh pool-autostart HP-SSD
virsh pool-start HP-SSD

## SSD Pool for non openstack VM's
virsh pool-define-as SSD-EXT logical - - /dev/sdd libvirt_lvm_ssdext  /dev/libvirt_lvm_ssdext
virsh pool-build SSD-EXT
virsh pool-autostart SSD-EXT
virsh pool-start SSD-EXT
############################

############### configure networks
virsh net-destroy default
virsh net-undefine default

cat > /tmp/openstack-local.xml <<EOF
<network>
  <name>os-loc</name>
  <bridge name='os-loc' stp='on' delay='0'/>
  <ip address='10.0.20.1' netmask='255.255.255.0'>

  </ip>
</network>
EOF

cat > /tmp/openstack-internal.xml <<EOF
<network>
  <name>os-int</name>
  <bridge name='os-int' stp='on' delay='0'/>
  <forward mode='passthrough'>
    <pf dev='bond0'/>
  </forward>
  <ip address='192.168.1.1' netmask='255.255.255.0'>

  </ip>
</network>
EOF

cat > /tmp/openstack-external.xml <<EOF
<network>
  <name>os-ext</name>
  <bridge name='os-ext' stp='on' delay='0'/>
  <forward mode='passthrough'>
    <pf dev='bond0'/>
  </forward>
  <ip address='10.0.10.1' netmask='255.255.255.0'>

  </ip>
</network>
EOF

virsh net-define /tmp/openstack-local.xml
virsh net-define /tmp/openstack-internal.xml
virsh net-define /tmp/openstack-external.xml

virsh net-autostart os-loc
virsh net-autostart os-int
virsh net-autostart os-ext

virsh net-start os-loc
virsh net-start os-int
virsh net-start os-ext
################################

################ Prep and run cloud script
cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;

runuser -l root -c 'cd /tmp/openstack-setup; ./create-cloud.sh;'
################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local