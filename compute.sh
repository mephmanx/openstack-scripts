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

common_second_boot_setup

######## Put type specific code
systemctl stop libvirtd
systemctl disable libvirtd

#sed -i '/^IPADDR/d' /etc/sysconfig/network-scripts/ifcfg-eth1
#sed -i '/^DNS1/d' /etc/sysconfig/network-scripts/ifcfg-eth1
#sed -i '/^NETMASK/d' /etc/sysconfig/network-scripts/ifcfg-eth1
#sed -i '/^GATEWAY/d' /etc/sysconfig/network-scripts/ifcfg-eth1
############################

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
#####################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

restrict_to_root

reboot

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
