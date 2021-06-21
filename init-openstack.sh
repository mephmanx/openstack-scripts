#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh

start() {

exec 1>/tmp/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

##### load secrets
load_secrets

chmod 777 /tmp/global_addresses.sh

# set up net script to be called after reboot
prep_next_script "openstack"

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

#####  Make this call last as this takes down the network connection for a period of time and download in previous call fails
################# Bond all NIC's together
nmcli connection add type bond con-name int-static ifname int-static mode 802.3ad
nmcli con mod id int-static bond.options mode=802.3ad,miimon=100,lacp_rate=fast,xmit_hash_policy=layer2+3

nmcli con mod int-static ipv4.method auto
nmcli con mod int-static ipv6.method auto
nmcli con mod int-static connection.autoconnect yes

ct=0
for DEVICE in `nmcli device | awk '$1 != "DEVICE" && $3 == "connected" && $2 == "ethernet" { print $1 }'`; do
    echo "$DEVICE"
    nmcli connection delete $DEVICE
    nmcli con add type bond-slave con-name int-static-slave$ct ifname $DEVICE master int-static
    ((ct++))
done

nmcli connection down int-static && nmcli connection up int-static
##########################################

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
