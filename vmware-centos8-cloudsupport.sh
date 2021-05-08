#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh

start() {
# code to start app comes here
# example: daemon program_name &
exec 1>/tmp/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

#########load secrets into env
working_dir=`pwd`
chmod 777 /tmp/openstack-env.sh
source ./tmp/openstack-env.sh
cd $working_dir
############################

#########load global addresses into env
working_dir=`pwd`
chmod 777 /tmp/global_addresses.sh
source /tmp/global_addresses.sh
cd $working_dir
############################

#################use old net names
use_old_net_names

# set up net script to be called after reboot
prep_next_script "cloudsupport"

########################
#remove this script so it only runs once on machine start
rm -rf /etc/init.d/vmware-centos8.sh
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
