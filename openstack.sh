#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/openstack-scripts/vm_functions.sh
. /tmp/openstack-scripts/vm-configurations.sh
. /tmp/openstack-env.sh
. /tmp/project_config.sh

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

## trust generated ca
cp /root/.ssh/id_rsa.crt /etc/pki/ca-trust/source/anchors
runuser -l root -c  'update-ca-trust extract'
#########

## Send System info
load_system_info
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Openstack Cloud System: $SYSTEM_INFO"

################# setup KVM and kick off openstack cloud create
dnf module install -y virt
dnf install -y cockpit-machines virt-install virt-viewer bridge-utils swtpm libtpms telnet bridge-utils
systemctl restart libvirtd
############################

### system profile
tuned-adm profile virtual-host
#############

########## configure and start networks
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Configuring networks on hypervisor...."
#### private net 1
ip link add dev vm1 type veth peer name vm2
ip link set dev vm1 up
ip tuntap add tapm mode tap
ip link set dev tapm up
ip link add loc-static type bridge

ip link set tapm master loc-static
ip link set vm1 master loc-static

ip addr add ${LAN_CENTOS_IP}/24 dev loc-static
ip addr add ${LAN_BRIDGE_IP}/24 dev vm2

ip link set loc-static up
ip link set vm2 up

nmcli connection modify loc-static ipv4.addresses ${LAN_CENTOS_IP}/24 ipv4.method manual connection.autoconnect yes ipv6.method "disabled"

### amp-net
ip link add dev vm3 type veth peer name vm4
ip link set dev vm3 up
ip tuntap add tapm1 mode tap
ip link set dev tapm1 up
ip link add amp-net type bridge

ip link set tapm1 master amp-net
ip link set vm3 master amp-net

ip addr add  10.1.0.1/24 dev amp-net
ip addr add  10.1.0.2/24 dev vm4

ip link set amp-net up
ip link set vm4 up

nmcli connection modify amp-net ipv4.addresses 10.1.0.1/24 ipv4.method manual connection.autoconnect yes ipv6.method "disabled"

## build vif devices and pair them for the bridge, 10 for each network created above
node_ct=20
while [ $node_ct -gt 0 ]; do
  ip link add dev Node${node_ct}s type veth peer name Node${node_ct}
  ((node_ct--))
done

node_ct=20
while [ $node_ct -gt 0 ]; do
  ip link set Node${node_ct} up
  ((node_ct--))
done

node_ct=20
while [ $node_ct -gt 0 ]; do
  ip link set Node${node_ct}s up
  ((node_ct--))
done

node_ct=10
while [ $node_ct -gt 0 ]; do
  brctl addif loc-static Node${node_ct}s
  ((node_ct--))
done

node_ct=10
while [ $node_ct -gt 0 ]; do
  brctl addif amp-net Node${node_ct}s
  ((node_ct--))
done
#############

virsh net-undefine default
###########################

#### vtpm
vtpm
######

############ Create and init storage pools
for part in `df | grep "VM-VOL" | awk '{print $6, " " }' | tr -d '/' | tr -d '\n'`; do
  virsh pool-define-as "$part" dir - - - - "/$part"
  virsh pool-build "$part"
  virsh pool-autostart "$part"
  virsh pool-start "$part"
done
############################

### start image hosting
pwd=`pwd`
mkdir /tmp/pftransfer
cp /tmp/linux.iso /tmp/pftransfer
### copy pfsense files to folder for host
cp /root/.ssh/id_rsa.pub /tmp/pftransfer
cp /root/.ssh/id_rsa /tmp/pftransfer
cp /tmp/openstack-env.sh /tmp/pftransfer
cp /tmp/openstack-scripts/pf_functions.sh /tmp/pftransfer
cp /tmp/project_config.sh /tmp/pftransfer
cp /tmp/openstack-scripts/pfsense-init.sh /tmp/pftransfer
cd /tmp/pftransfer
python3 -m http.server &
web_pid=$!
echo $web_pid > /tmp/web_pid
cd $pwd

runuser -l root -c  'cd /tmp/openstack-scripts; ./create-identity-kvm.sh'

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

restrict_to_root

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
