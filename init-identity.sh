#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/project_config.sh
. /tmp/openstack-env.sh

start() {
# code to start app comes here
# example: daemon program_name &
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
  systemctl enable --now dnf-automatic.timer
fi

#### add hypervisor host key to authorized keys
## this allows the hypervisor to ssh without password to openstack vms
runuser -l root -c 'cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys'
######

runuser -l root -c 'cp /tmp/id_rsa.key /root/.ssh/id_rsa'
runuser -l root -c 'cp /tmp/id_rsa.pub /root/.ssh/id_rsa.pub'

runuser -l root -c 'chmod 600 /root/.ssh/id_rsa'
runuser -l root -c 'chmod 600 /root/.ssh/id_rsa.pub'
runuser -l root -c 'chmod 600 /root/.ssh/authorized_keys'

yum -y install @idm:DL1
yum -y install freeipa-server ipa-server-dns bind-dyndb-ldap
ipa-server-install --setup-dns

ssh-keyscan -H $LAN_CENTOS_IP >> ~/.ssh/known_hosts;
ssh root@$LAN_CENTOS_IP 'cd /tmp/openstack-scripts; ./create-pfsense-kvm.sh;' &

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Identity VM ready for use"
##########################
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
