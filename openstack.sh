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
  <name>os-loc-static</name>
  <bridge name='virbr0' stp='on' delay='0'/>
  <ip address='10.0.20.1' netmask='255.255.255.0'>

  </ip>
</network>
EOF

cat > /tmp/openstack-internal.xml <<EOF
<network>
  <name>os-int-static</name>
  <bridge name='virbr1' stp='on' delay='0'/>
  <forward mode='passthrough'>
    <pf dev='eth0'/>
  </forward>
  <ip address='192.168.1.1' netmask='255.255.255.0'>

  </ip>
</network>
EOF

cat > /tmp/openstack-external.xml <<EOF
<network>
  <name>os-ext-static</name>
  <bridge name='virbr2' stp='on' delay='0'/>
  <forward mode='passthrough'>
    <pf dev='eth0'/>
  </forward>
  <ip address='10.0.10.1' netmask='255.255.255.0'>

  </ip>
</network>
EOF

virsh net-define /tmp/openstack-local.xml
virsh net-define /tmp/openstack-internal.xml
virsh net-define /tmp/openstack-external.xml

virsh net-autostart Openstack-Local-Static
virsh net-autostart Openstack-Internal-Static
virsh net-autostart Openstack-External-Static
################################

################ Prep and run cloud script
cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;

runuser -l root -c 'cd /tmp/openstack-setup; ./create-cloud.sh;'
################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local