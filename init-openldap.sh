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

mkdir /root/.ssh

#### add hypervisor host key to authorized keys
## this allows the hypervisor to ssh without password to openstack vms
runuser -l root -c 'cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys'
######

chmod 600 /root/.ssh/id_rsa
chmod 600 /root/.ssh/authorized_keys

dnf update -y

dnf install -y cyrus-sasl-devel make libtool autoconf libtool-ltdl-devel openssl-devel libdb-devel tar gcc perl perl-devel wget vim

useradd -r -M -d /var/lib/openldap -u 55 -s /usr/sbin/nologin ldap

tar xzf /tmp/openldap.tgz

cd /tmp/openldap



telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Openldap VM ready for use"
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
