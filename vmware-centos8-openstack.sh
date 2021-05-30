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

for FILE in /etc/sysconfig/network-scripts/*; do
    echo $FILE | sed "s:/etc/sysconfig/network-scripts/ifcfg-::g" | xargs ifup;
done

#########load secrets into env
chmod 777 /tmp/openstack-env.sh
source ./tmp/openstack-env.sh
############################

systemctl start cockpit.socket
systemctl enable --now cockpit.socket

  ## Prep OpenStack install
rm -rf /etc/rc.d/rc.local
curl -o /etc/rc.d/rc.local https://mephmanx:$GITHUB_TOKEN@raw.githubusercontent.com/mephmanx/openstack-scripts/master/openstack.sh
chmod +x /etc/rc.d/rc.local

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
