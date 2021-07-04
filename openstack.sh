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
dnf install -y cockpit-machines virt-install virt-viewer dhcp-server bridge-utils swtpm libtpms
systemctl restart libvirtd
############################

### system profile
tuned-adm profile virtual-host
#############

########## configure and start networks
ip link add dev vm1 type veth peer name vm2
ip link set dev vm1 up
ip tuntap add tapm mode tap
ip link set dev tapm up
ip link add loc-static type bridge

ip link set tapm master loc-static
ip link set vm1 master loc-static

ip addr add 10.0.20.1/24 dev loc-static
ip addr add 10.0.20.2/24 dev vm2

ip link set loc-static up
ip link set vm2 up

nmcli connection modify loc-static ipv4.addresses 10.0.20.1/24 ipv4.gateway 192.168.1.50 ipv4.method manual ipv4.dns 8.8.8.8 connection.autoconnect yes ipv6.method "disabled"

ip link add dev Node1s type veth peer name Node1
ip link add dev Node2s type veth peer name Node2
ip link add dev Node3s type veth peer name Node3
ip link add dev Node4s type veth peer name Node4
ip link add dev Node5s type veth peer name Node5
ip link add dev Node6s type veth peer name Node6
ip link add dev Node7s type veth peer name Node7
ip link add dev Node8s type veth peer name Node8
ip link add dev Node9s type veth peer name Node9
ip link add dev Node10s type veth peer name Node10

ip link set Node1 up
ip link set Node2 up
ip link set Node3 up
ip link set Node4 up
ip link set Node5 up
ip link set Node6 up
ip link set Node7 up
ip link set Node8 up
ip link set Node9 up
ip link set Node10 up

ip link set Node1s up
ip link set Node2s up
ip link set Node3s up
ip link set Node4s up
ip link set Node5s up
ip link set Node6s up
ip link set Node7s up
ip link set Node8s up
ip link set Node9s up
ip link set Node10s up

brctl addif loc-static Node1s
brctl addif loc-static Node2s
brctl addif loc-static Node3s
brctl addif loc-static Node4s
brctl addif loc-static Node5s
brctl addif loc-static Node6s
brctl addif loc-static Node7s
brctl addif loc-static Node8s
brctl addif loc-static Node9s
brctl addif loc-static Node10s

runuser -l root -c  'echo "net.ipv4.ip_forward = 1" > /etc/sysctl.conf'

sysctl -w net.ipv4.ip_forward=1

runuser -l root -c 'cat << EOF > /etc/dhcp/dhcpd.conf
default-lease-time 600;
max-lease-time 7200;
ddns-update-style none;
authoritative;

subnet 10.0.20.0 netmask 255.255.255.0 {
        range 10.0.20.50 10.0.20.100;
        option routers 10.0.20.1;
        option subnet-mask 255.255.255.0;
        option domain-name-servers 8.8.8.8;
}
EOF'

systemctl start dhcpd
systemctl enable dhcpd

iptables --table nat --append POSTROUTING --out-interface int-static -j MASQUERADE
iptables --append FORWARD --in-interface loc-static -j ACCEPT

virsh net-undefine default
###########################

###### vTPM setup #####
cd /root
dnf -y update \
 && dnf -y install diffutils make file automake autoconf libtool gcc gcc-c++ openssl-devel gawk git \
 && git clone https://github.com/stefanberger/libtpms.git \
 && dnf -y install which python3 python3-cryptography python3-pip python3-setuptools expect libtasn1-devel \
    socat trousers tpm-tools gnutls-devel gnutls-utils net-tools libseccomp-devel json-glib-devel \
 && pip3 install twisted \
 && git clone https://github.com/stefanberger/swtpm.git

LIBTPMS_BRANCH=master

cd libtpms \
 && runuser -l root -c  'echo ${date} > /.date' \
 && git pull \
 && git checkout ${LIBTPMS_BRANCH} \
 && runuser -l root -c  'cd libtpms; ./autogen.sh --prefix=/usr --libdir=/usr/lib64 --with-openssl --with-tpm2;' \
 && make -j$(nproc) V=1 \
 && make -j$(nproc) V=1 check \
 && make install

SWTPM_BRANCH=master
cd ../swtpm \
 && git pull \
 && git checkout ${SWTPM_BRANCH} \
 && runuser -l root -c  'cd /root/swtpm; ./autogen.sh --prefix=/usr --libdir=/usr/lib/x86_64-linux-gnu --with-openssl;' \
 && make -j$(nproc) V=1 \
 && make -j$(nproc) V=1 VERBOSE=1 check \
 && make -j$(nproc) install

runuser -l root -c  'cd /usr/share/swtpm; ./swtpm-create-user-config-files --overwrite --root;'
runuser -l root -c  'chown tss:tss /root/.config/*'
#runuser -l root -c  'chown tss:tss /var/lib/swtpm-localca/*'
#####################

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
