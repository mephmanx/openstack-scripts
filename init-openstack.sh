#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/openstack-scripts/vm_functions.sh
. /tmp/openstack-env.sh
. /tmp/project_config.sh

start() {

exec 1>/root/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

### cleanup from previous boot
rm -rf /tmp/eth*
########

## enable auto updates if selected
if [[ $LINUX_AUTOUPDATE == 1 ]]; then
  dnf install -y dnf-automatic

  cat > /etc/dnf/automatic.conf <<EOF
[commands]
upgrade_type = default
random_sleep = 0
network_online_timeout = 60
download_updates = yes
apply_updates = yes
EOF

  systemctl enable --now dnf-automatic.timer
fi

# set up net script to be called after reboot
cp /tmp/openstack-scripts/openstack.sh /tmp
prep_next_script "openstack"

### enable nested virtualization
touch /etc/modprobe.d/kvm.conf
runuser -l root -c  'echo "options kvm_intel nested=1" >> /etc/modprobe.d/kvm.conf;'
runuser -l root -c  'echo "options kvm-intel enable_shadow_vmcs=1" >> /etc/modprobe.d/kvm.conf;'
runuser -l root -c  'echo "options kvm-intel enable_apicv=1" >> /etc/modprobe.d/kvm.conf;'
runuser -l root -c  'echo "options kvm-intel ept=1" >> /etc/modprobe.d/kvm.conf;'
modprobe kvm_intel nested=1
modprobe kvm_intel enable_shadow_vmcs=1
modprobe kvm_intel enable_apicv=1
modprobe kvm_intel ept=1
##############

## do not perform anything that would need internet access after the below command is executed.
##  the network is being reconfigured, the call will fail, and it might kill all future scripts
##### create bond ext-con
nmcli connection add type bond con-name ext-con ifname ext-con mode 802.3ad
nmcli con mod id ext-con bond.options mode=802.3ad,miimon=100,lacp_rate=fast,xmit_hash_policy=layer2+3

nmcli con mod ext-con ipv4.method auto
nmcli con mod ext-con ipv6.method auto
nmcli con mod ext-con connection.autoconnect yes

ct=0
for DEVICE in `nmcli device | awk '$1 != "DEVICE" && $3 == "connected" && $2 == "ethernet" { print $1 }'`; do
    echo "$DEVICE"
    nmcli connection delete $DEVICE
    nmcli con add type bond-slave con-name ext-con-slave$ct ifname $DEVICE master ext-con
    ((ct++))
done

nmcli connection down ext-con && nmcli connection up ext-con
#########################

#### generate ssh keys
## setup cert directory
CERT_DIR="/root/.ssh"

runuser -l root -c  "mkdir $CERT_DIR"

### CA key pass
NEWPW=$(generate_random_pwd)
echo $NEWPW > $CERT_DIR/ca_pwd
###

# create CA
create_ca_cert $NEWPW $CERT_DIR

# create vpn server key and cert
create_server_cert $NEWPW $CERT_DIR "cloud-vpn"

### initial wildcard cert
create_server_cert $NEWPW $CERT_DIR "wildcard" "*"

### generate osuser cert and key
create_user_cert $NEWPW $CERT_DIR "osuser"
##########

## setup public key as other systems use it for cross system passwordless ssh
runuser -l root -c 'cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys'

### use CA cert for cockpit
cp $CERT_DIR/wildcard.crt /etc/cockpit/ws-certs.d/certificate.cert
cp $CERT_DIR/wildcard.key /etc/cockpit/ws-certs.d/certificate.key

### adjust key permissions.  Important! cockpit wolnt work without correct permissions
chmod 755 /etc/cockpit/ws-certs.d/*
chmod 600 /root/.ssh/*

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
