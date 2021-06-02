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