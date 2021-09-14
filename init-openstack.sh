#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/openstack-env.sh

start() {

exec 1>/root/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Beginning hypervisor cloud setup. Pulling git repos...."

#### prepare git repos
git clone https://github.com/$GITHUB_USER/openstack-scripts.git /tmp/openstack-scripts;
chmod 700 /tmp/openstack-scripts
#########

### load project config
prep_project_config
source /tmp/openstack-scripts/project_config.sh
#######

##### test to make sure checkout was good and internet was reachable
SCRIPTS_FILE_COUNT=`ls /tmp/openstack-scripts | wc -l`
if [[ $SCRIPTS_FILE_COUNT -gt 0 ]]; then
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Checkout successful, pulled $SCRIPTS_FILE_COUNT from scripts folder"
else
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Checkout failed!  Possible network config issue or internet unreachable!  Install exiting."
  exit -1
fi
##########

### cleanup from previous boot
rm -rf /tmp/eth*
########

# set up net script to be called after reboot
prep_next_script "openstack"

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Hypervisor core network setup in progress....."

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
HOWLONG=15 ## the number of characters
NEWPW=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
echo $NEWPW > $CERT_DIR/ca_pwd
###

# create CA
create_ca_cert $NEWPW $CERT_DIR

# create vpn server key and cert
create_server_cert $NEWPW $CERT_DIR "cloud-vpn"

### initial wildcard cert
## this will be replaced through letsencrypt process later.  should never be used
create_server_cert $NEWPW $CERT_DIR "placeholder"

### generate osuser cert and key
create_user_cert $NEWPW $CERT_DIR "osuser"
##########

### use CA cert for cockpit
cp $CERT_DIR/id_rsa.crt /etc/cockpit/ws-certs.d/certificate.cert
cp $CERT_DIR/id_rsa.key /etc/cockpit/ws-certs.d/certificate.key

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
