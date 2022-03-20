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

### initial libs
yum update -y
yum -y install epel-release
yum update -y

yum install -y perl \
              yum-utils \
              python3-devel \
              python38 \
              make \
              ruby \
              ruby-devel \
              gcc-c++ \
              mysql-devel \
              nodejs \
              mysql-server
#########

## enable auto updates if selected
if [[ $LINUX_AUTOUPDATE == 1 ]]; then
  systemctl enable --now dnf-automatic.timer
fi

### gen pwd's
DIR_PWD={DIRECTORY_MGR_PWD_12345678901}
ADMIN_PWD={CENTOS_ADMIN_PWD_123456789012}
##############

DIRECTORY_MANAGER_PASSWORD=$DIR_PWD
REALM_NAME=$(echo "$INTERNAL_DOMAIN_NAME" | tr '[:lower:]' '[:upper:]')
HOSTNAME=identity.$INTERNAL_DOMAIN_NAME

runuser -l root -c "echo '$IDENTITY_VIP $HOSTNAME' >> /etc/hosts"
runuser -l root -c "echo $HOSTNAME > /etc/hostname"
runuser -l root -c "sysctl kernel.hostname=$HOSTNAME"

dnf module enable idm:DL1 -y
dnf distro-sync -y
dnf update -y

dnf install -y cyrus-sasl-devel \
                make \
                libtool \
                autoconf \
                libtool-ltdl-devel \
                openssl-devel \
                libdb-devel \
                tar \
                gcc \
                perl \
                perl-devel \
                vim \
                rsyslog \
                ipa-server \
                ipa-server-dns

runuser -l root -c 'cp /tmp/id_rsa.crt /etc/ipa/ca.crt'
runuser -l root -c 'chown -R pkiuser /etc/ipa/ca.crt'
# Configure freeipa
runuser -l root -c "ipa-server-install -p $DIRECTORY_MANAGER_PASSWORD \
                                        -a $ADMIN_PWD \
                                        -n $INTERNAL_DOMAIN_NAME \
                                        -r $REALM_NAME \
                                        --ip-address $IDENTITY_VIP \
                                        --mkhomedir \
                                        --setup-dns \
                                        --auto-reverse \
                                        --auto-forwarders \
                                        --no-dnssec-validation \
                                        --ntp-server=$GATEWAY_ROUTER_IP -U -q"

runuser -l root -c "ipa-dns-install --auto-forwarders --auto-reverse --no-dnssec-validation -U"
#Create user on ipa WITHOUT A PASSWORD - we don't need one since we'll be using ssh key
#Kinit session
echo $ADMIN_PWD | kinit admin

## run record adds here after kinint for auth
runuser -l root -c "ipa dnszone-mod $INTERNAL_DOMAIN_NAME. --allow-sync-ptr=TRUE"
runuser -l root -c "ipa dnsrecord-add $INTERNAL_DOMAIN_NAME. '*' --a-ip-address=$LB_ROUTER_IP"
runuser -l root -c "ipa dnsrecord-add $INTERNAL_DOMAIN_NAME. '$APP_INTERNAL_HOSTNAME' --a-ip-address=$INTERNAL_VIP"
runuser -l root -c "ipa dnsrecord-add $INTERNAL_DOMAIN_NAME. '$APP_EXTERNAL_HOSTNAME' --a-ip-address=$EXTERNAL_VIP"
runuser -l root -c "ipa dnsrecord-add $INTERNAL_DOMAIN_NAME. '$SUPPORT_HOST' --a-ip-address=$SUPPORT_VIP"

#### groups
/usr/bin/ipa group-add cloud-admins
/usr/bin/ipa group-add openstack-admins
/usr/bin/ipa group-add vpn-users

#### users
/usr/bin/ipa user-add --first=Firstname --last=Lastname ipauser --random

####  send random pwd over telegram
RANDOM_PWD=`cat /root/start-install.log | grep 'Random password' | awk -F': ' '{print $2}'`
telegram_debug_msg $TELEGRAM_API $TELEGRAM_CHAT_ID "ipauser random password is $RANDOM_PWD"

SSH_KEY=`cat /root/.ssh/id_rsa.pub`
/usr/bin/ipa user-mod ipauser --sshpubkey="$SSH_KEY"

#Add sudo rules
/usr/bin/ipa sudorule-add sysadmin_sudo --hostcat=all --runasusercat=all --runasgroupcat=all --cmdcat=all
/usr/bin/ipa sudorule-add-user sysadmin_sudo --group cloud-admins

##### group memberships
/usr/bin/ipa group-add-member openstack-admins --users=ipauser
/usr/bin/ipa group-add-member vpn-users --users=ipauser
/usr/bin/ipa group-add-member cloud-admins --users=ipauser

#### Continue cloud init
ssh-keyscan -H $LAN_CENTOS_IP >> ~/.ssh/known_hosts;
ssh root@$LAN_CENTOS_IP 'cd /tmp; ./create-cloudsupport-kvm.sh;' &
ssh root@$LAN_CENTOS_IP 'cd /tmp; ./create-cloud-kvm.sh;' &

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
