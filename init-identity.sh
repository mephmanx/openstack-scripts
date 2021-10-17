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

#IPA vars

### gen pwd's
HOWLONG=30 ## the number of characters
DIR_PWD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
echo $DIR_PWD > /root/directory_pwd

ADMIN_PWD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
echo $ADMIN_PWD > /root/admin_pwd
##############

DIRECTORY_MANAGER_PASSWORD=$DIR_PWD
ADMIN_PASSWORD=$ADMIN_PWD
REALM_NAME=$(echo "$DOMAIN_NAME" | tr '[:lower:]' '[:upper:]')
HOSTNAME=identity.$DOMAIN_NAME

/usr/bin/hostnamectl set-hostname $HOSTNAME

dnf module enable idm:DL1 -y

dnf distro-sync -y

dnf update -y

dnf install -y cyrus-sasl-devel make libtool autoconf libtool-ltdl-devel openssl-devel libdb-devel tar gcc perl perl-devel wget vim rsyslog ipa-server ipa-server-dns

#Disable root login in ssh and disable password login
sed -i 's/\(PermitRootLogin\).*/\1 no/' /etc/ssh/sshd_config
sed -i 's/\(PasswordAuthentication\).*/\1 no/' /etc/ssh/sshd_config
/usr/sbin/service sshd restart

runuser -l root -c 'cp /tmp/id_rsa.crt /etc/ipa/ca.crt'
# Configure freeipa
ipa-server-install -p $DIRECTORY_MANAGER_PASSWORD -a $ADMIN_PASSWORD -n $DOMAIN_NAME -r $REALM_NAME --hostname $HOSTNAME --ip-address $IDENTITY_VIP --mkhomedir --setup-dns --auto-reverse --auto-forwarders --no-dnssec-validation --ntp-server=$NTP_SERVER -U -q
#Create user on ipa WITHOUT A PASSWORD - we don't need one since we'll be using ssh key
/usr/bin/ipa user-add --first=Firstname --last=Lastname ipauser
SSH_KEY=`cat /root/.ssh/id_rsa.pub`
/usr/bin/ipa user-mod ipauser --sshpubkey="$SSH_KEY"

#Add sudo rules
/usr/bin/ipa sudorule-add su
/usr/bin/ipa sudocmd-add /usr/bin/su
/usr/bin/ipa sudorule-add-allow-command su --sudocmds /usr/bin/su
/usr/bin/ipa sudorule-add-host su --hosts pfsense.$DOMAIN_NAME
/usr/bin/ipa sudorule-add-host su --hosts harbor.$DOMAIN_NAME
/usr/bin/ipa sudorule-add-user su --users ipauser
/usr/bin/ipa sudorule-add defaults
/usr/bin/ipa sudorule-add-option defaults --sudooption '!authenticate'

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
