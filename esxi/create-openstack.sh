source ./config/vm-configurations.sh
source ./esxi/esxi-functions.sh
source ./lib/iso-functions.sh
source ./openstack-env.sh
source ./lib/linux-version.sh

ESXI_HOSTNAME=$1
ESXI_PASSWORD=$2
VM_NAME=$3
ESXI_DRIVE_LOCATION=$4

echo "Hostname -> " $ESXI_HOSTNAME
echo "VM_NAME -> " $VM_NAME
echo "ESXI_PWD -> " $ESXI_PASSWORD
echo "DRIVE_LOCATION -> " $ESXI_DRIVE_LOCATION


########### create vm's
index=0
for d in "${vms[@]}"; do
  printf -v vm_type_n '%s\n' "${d//[[:digit:]]/}"
  vm_type=$(tr -dc '[[:print:]]' <<< "$vm_type_n")
  echo "creating vm of type -> $vm_type"
  create_vm_esxi "$ESXI_HOSTNAME" "$d" "$ESXI_PASSWORD" "/vmfs/volumes/$ESXI_DRIVE_LOCATION/isos" "$vm_type" "HP-Disk" "HP-Disk"
  sleep 30
  ((index++))
done

