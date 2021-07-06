#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /cloudprep/vm_functions.sh
. /cloudprep/openstack-env.sh
. /cloudprep/global_addresses.sh

start() {

common_second_boot_setup

######## Put type specific code
sed -i '/^IPADDR/d' /etc/sysconfig/network-scripts/ifcfg-eth1
sed -i '/^DNS1/d' /etc/sysconfig/network-scripts/ifcfg-eth1
sed -i '/^NETMASK/d' /etc/sysconfig/network-scripts/ifcfg-eth1
sed -i '/^GATEWAY/d' /etc/sysconfig/network-scripts/ifcfg-eth1
############################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

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
