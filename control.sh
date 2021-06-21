#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/openstack-env.sh

start() {

common_second_boot_setup

######## Put type specific code
#runuser -l root -c  '/sbin/ip link set eth2 promisc on'
#runuser -l root -c  '/sbin/ip link set eth0 promisc on'

#sed '/^IPADDR/d' -i /tmp/eth2
#sed '/^GATEWAY/d' -i /tmp/eth2
#sed '/^DNS1/d' -i /tmp/eth2
#sed '/^NETMASK/d' -i /tmp/eth2
#
#runuser -l root -c  "rm -rf /etc/sysconfig/network-scripts/ifcfg-eth2"
#runuser -l root -c  "cat /tmp/eth2 > /etc/sysconfig/network-scripts/ifcfg-eth2"
############################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

#########  Spot for anything that needs to be run on every reboot from here on out
cat > /etc/rc.d/rc.local <<EOF

EOF

chmod a+x /etc/rc.d/rc.local

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
