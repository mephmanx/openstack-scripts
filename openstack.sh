#!/bin/bash

chmod 777 /tmp/openstack-env.sh
. /tmp/openstack-env.sh

. /tmp/vm_functions.sh

######## Openstack main server install

exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

yum clean all && yum update -y  #this is only to make the next call work, DONT remove!

systemctl stop firewalld
systemctl disable firewalld
systemctl mask firewalld

################# setup KVM and kick off openstack cloud create
dnf module install -y virt
dnf install -y cockpit-machines virt-install virt-viewer bridge-utils
systemctl restart libvirtd
############################

### enable nested virtualization
sed -i "s/#options kvm_intel nested=1/options kvm_intel nested=1/g" /etc/modprobe.d/kvm.conf
runuser -l root -c  'echo "options kvm-intel enable_shadow_vmcs=1" >> /etc/modprobe.d/kvm.conf;'
runuser -l root -c  'echo "options kvm-intel enable_apicv=1" >> /etc/modprobe.d/kvm.conf;'
runuser -l root -c  'echo "options kvm-intel ept=1" >> /etc/modprobe.d/kvm.conf;'
modprobe kvm_intel nested=1
modprobe kvm_intel enable_shadow_vmcs=1
modprobe kvm_intel enable_apicv=1
modprobe kvm_intel ept=1
##############

################# Add bridge
#cat > /etc/sysctl.d/99-netfilter-bridge.conf <<EOF
#net.bridge.bridge-nf-call-ip6tables = 0
#net.bridge.bridge-nf-call-iptables = 0
#net.bridge.bridge-nf-call-arptables = 0
#EOF
#
#modprobe br_netfilter
#
#cat > /etc/modules-load.d/br_netfilter.conf <<EOF
#br_netfilter
#EOF
#
#sysctl -p /etc/sysctl.d/99-netfilter-bridge.conf

cat > /tmp/openstack-local.xml <<EOF
<network>
  <name>loc-static</name>
  <bridge name='loc-static' stp='on' delay='0'/>
  <ip address='10.0.20.1' netmask='255.255.255.0'>

  </ip>
</network>
EOF

virsh net-define /tmp/openstack-local.xml

virsh net-autostart loc-static

virsh net-start loc-static

virsh net-destroy default
virsh net-undefine default
###########################

############ Create and init storage pools

## HP-Disk pool
virsh pool-define-as HP-Disk dir - - - - "/HP-Disk"
virsh pool-build HP-Disk
virsh pool-autostart HP-Disk
virsh pool-start HP-Disk

## HP-SSD pool
virsh pool-define-as HP-SSD dir - - - - "/HP-SSD"
virsh pool-build HP-SSD
virsh pool-autostart HP-SSD
virsh pool-start HP-SSD

## HP-SSD pool
virsh pool-define-as HP-EXT dir - - - - "/HP-EXT"
virsh pool-build HP-EXT
virsh pool-autostart HP-EXT
virsh pool-start HP-EXT
############################

################ Prep and run cloud script
################### Load cloud create
cd /tmp
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git

cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;
####################
runuser -l root -c 'cd /tmp/openstack-setup; ./create-cloudsupport-kvm.sh;'
runuser -l root -c 'cd /tmp/openstack-setup; ./create-cloud-kvm.sh;'
################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local