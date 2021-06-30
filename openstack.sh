#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/openstack-env.sh
. /tmp/global_addresses.sh

start() {

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

### system profile
tuned-adm profile virtual-host
#############

########## configure and start networks
ip link add dev Node1s type veth peer name Node1
ip link add dev Node2s type veth peer name Node2
ip link add dev Node3s type veth peer name Node3
ip link add dev Node4s type veth peer name Node4
ip link add dev Node5s type veth peer name Node5
ip link add dev Node6s type veth peer name Node6
ip link add dev Node7s type veth peer name Node7
ip link add dev Node8s type veth peer name Node8

ip link set Node1 up
ip link set Node2 up
ip link set Node3 up
ip link set Node4 up
ip link set Node5 up
ip link set Node6 up
ip link set Node7 up
ip link set Node8 up

ip link set Node1s up
ip link set Node2s up
ip link set Node3s up
ip link set Node4s up
ip link set Node5s up
ip link set Node6s up
ip link set Node7s up
ip link set Node8s up

brctl addbr loc-static
ifconfig loc-static up

brctl addif loc-static Node1s
brctl addif loc-static Node2s
brctl addif loc-static Node3s
brctl addif loc-static Node4s
brctl addif loc-static Node5s
brctl addif loc-static Node6s
brctl addif loc-static Node7s
brctl addif loc-static Node8s

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

}

stop() {
    # code to stop app comes here
    # example: killproc program_name
    /bin/true
}

case "$1" in
    start)
       start
       ;;
    stop)
        /bin/true
       stop
       ;;
    restart)
       stop
       start
       ;;
    status)
        /bin/true
       # code to check status of app comes here
       # example: status program_name
       ;;
    *)
       echo "Usage: $0 {start|stop|status|restart}"
esac

exit 0
