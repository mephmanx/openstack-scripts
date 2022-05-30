#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh

start() {

exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

### system profile
tuned-adm profile virtual-guest
#############

# add stack user with passwordless sudo privs
add_stack_user

### module recommended on openstack.org
modprobe vhost_net

######## Put type specific code
systemctl stop libvirtd
systemctl disable libvirtd

rm -rf /var/run/libvirt/*sock
rm -rf /var/run/libvirt/*sock*

##eth0 is octavia mgmt net
remove_ip_from_adapter "eth0"

### eth2 is neutron external net
remove_ip_from_adapter "eth2"
############################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

restrict_to_root

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
