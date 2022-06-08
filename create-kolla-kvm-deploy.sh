#!/bin/bash

rm -rf /root/kolla-install.log
exec 1>/root/kolla-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x

source /tmp/vm_functions.sh
source /tmp/vm-configurations.sh

telegram_notify  "Creating cloud vm: kolla"
create_vm_kvm "kolla" "kolla"
###wait until jobs complete and servers come up
wait

telegram_notify  "Kolla VM installed.  Openstack install will begin if VM's came up correctly."
##########