source ./functions.sh
source ./iso-functions.sh
source ./vm-configurations.sh
source ./openstack-env.sh

ESXI_HOST=$1
ESXI_PASSWORD=$2
#### ESXi hostname #1 VM Name arg #2
setupENV ${ESXI_HOST}
########  ESXi password arg #2
installESXiTools

IFS=


########## remove openstack
removeVM ${ESXI_PASSWORD} "openstack"
####################

####################### create openstack vm
create_vm_esxi "openstack" "openstack"
##################################
