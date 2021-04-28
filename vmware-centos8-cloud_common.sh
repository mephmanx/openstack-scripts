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
# set VM type for future use
TYPE=`cat /tmp/type`

#########load secrets into env
working_dir=`pwd`
chmod 777 /tmp/openstack-env.sh
source ./tmp/openstack-env.sh
cd $working_dir
############################

#########load global addresses into env
working_dir=`pwd`
chmod 777 /tmp/global_addresses.sh
source ./tmp/global_addresses.sh
cd $working_dir
############################

# adjust main volumes to allocate most size to root volume
grow_fs

# load libraries for this VM "type"
load_libs "${TYPE}"

#####  Docker prep #########
runuser -l root -c  "yum install -y https://$GITHUB_TOKEN@raw.githubusercontent.com/mephmanx/cloud-libs/master/containerd.io-1.2.6-3.3.el7.x86_64.rpm"
sleep 5
#####################

#################use old net names
use_old_net_names

# add stack user with passwordless sudo privs
add_stack_user

# set up net script to be called after reboot
prep_next_script "${TYPE}"

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
