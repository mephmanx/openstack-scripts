#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/project_config.sh
. /tmp/openstack-env.sh
. /etc/os-release

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

# set VM type for future use
TYPE=`cat /tmp/type`

# adjust main volumes to allocate most size to root volume
grow_fs

## enable auto updates if selected
if [[ $LINUX_AUTOUPDATE == 1 ]]; then
  systemctl enable --now dnf-automatic.timer
fi

# load libraries for this VM "type"
load_libs "${TYPE}"

#### Centos8 to Centos 8 Stream
if [[ $NAME == "CentOS Linux" ]]; then
  dnf swap centos-linux-repos centos-stream-repos -y
  dnf distro-sync -y
fi

# add stack user with passwordless sudo privs
add_stack_user

# set up net script to be called after reboot
prep_next_script "${TYPE}"

## join to domain
ADMIN_PWD=`cat /root/env_admin_pwd`
join_machine_to_domain $ADMIN_PWD

host=`hostname`
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Cloud VM $host starting second reboot..."

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
