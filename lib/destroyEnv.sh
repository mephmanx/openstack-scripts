source ./config/vm-configurations.sh
source ./esxi/esxi-functions.sh

#Storing all isos on HP-Disk for ESXI
ESXI_DRIVE_LOCATION=HP-Disk

function destroy {
  case $hypervisor in
    "esxi") destroyESXi;;
    "kvm") destroyKVM;;
    *) die "Invalid Hypervisor, only esxi and kvm are supported";;
  esac
}

function destroyESXi {
  control_count=$(getVMCount "control")
  network_count=$(getVMCount "network")
  compute_count=$(getVMCount "compute")
  monitoring_count=$(getVMCount "monitoring")
  storage_count=$(getVMCount "storage")


  ### add vm's to array
  vms=()
  while [ $control_count -gt 0 ]; do
    printf -v control_count_format "%02d" $control_count
    echo "Adding control$control_count_format to destroy list"
    vms+=("control$control_count_format")
    control_count=$[$control_count - 1]
  done

  while [ $network_count -gt 0 ]; do
    printf -v network_count_format "%02d" $network_count
    echo "Adding network$network_count_format to destroy list"
    vms+=("network$network_count_format")
    network_count=$[$network_count - 1]
  done

  while [ $compute_count -gt 0 ]; do
    printf -v compute_count_format "%02d" $compute_count
    echo "Adding compute$compute_count_format to destroy list"
    vms+=("compute$compute_count_format")
    compute_count=$[$compute_count - 1]
  done

  while [ $monitoring_count -gt 0 ]; do
    printf -v monitoring_count_format "%02d" $monitoring_count
    echo "Adding monitoring$monitoring_count_format to destroy list"
    vms+=("monitoring$monitoring_count_format")
    monitoring_count=$[$monitoring_count - 1]
  done

  while [ $storage_count -gt 0 ]; do
    printf -v storage_count_format "%02d" $storage_count
    echo "Adding storage$storage_count_format to destroy list"
    vms+=("storage$storage_count_format")
    storage_count=$[$storage_count - 1]
  done

  ############## remove vm's
  for d in "${vms[@]}"; do
    echo "removing vm -> $d"
    printf -v vm_type_n '%s\n' "${d//[[:digit:]]/}"
    vm_type=$(tr -dc '[[:print:]]' <<< "$vm_type_n")
    removeVM $hypervisor_host ${d} $PASS "/vmfs/volumes/$ESXI_DRIVE_LOCATION"
    sleep 15
  done

  ########## remove kolla
  removeVM $hypervisor_host "kolla" $PASS "/vmfs/volumes/$ESXI_DRIVE_LOCATION"
  ####################
}

function destroyKVM {
  echo "destroy kvm"
}