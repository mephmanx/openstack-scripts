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

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Beginning hypervisor cloud setup, core network setup in progress....."



# set up net script to be called after reboot
cp /tmp/openstack-scripts/openstack.sh /tmp
prep_next_script "openstack"

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
