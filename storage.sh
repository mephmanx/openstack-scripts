#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/openstack-env.sh
. /tmp/project_config.sh

start() {

common_second_boot_setup

######## Put type specific code

wipefs -a /dev/vdb
sleep 3
pvcreate /dev/vdb
sleep 3
vgcreate -v cinder-volumes /dev/vdb
sleep 3

index=0
for d in vdc vdd vde; do
  wipefs -a /dev/${d}
  pvcreate /dev/${d}
  parted /dev/${d} -s -- mklabel gpt mkpart KOLLA_SWIFT_DATA 1 -1
  sleep 5
  mkfs.xfs -f -L d${index} /dev/${d}1
  ((index++))
done

############################

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

restrict_to_root

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
