#!/bin/bash

source /tmp/project_config.sh
source ./vm_functions.sh
####  Functions in this file should be used AFTER ISO's are created and pushed to esxi

function parse_json()
{
    echo $1 | \
    sed -e 's/[{}]/''/g' | \
    sed -e 's/", "/'\",\"'/g' | \
    sed -e 's/" ,"/'\",\"'/g' | \
    sed -e 's/" , "/'\",\"'/g' | \
    sed -e 's/","/'\"---SEPERATOR---\"'/g' | \
    awk -F=':' -v RS='---SEPERATOR---' "\$1~/\"$2\"/ {print}" | \
    sed -e "s/\"$2\"://" | \
    tr -d "\n\t" | \
    sed -e 's/\\"/"/g' | \
    sed -e 's/\\\\/\\/g' | \
    sed -e 's/^[ \t]*//g' | \
    sed -e 's/^"//'  -e 's/"$//'
}

function getVMCount {
  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_str=${vmstr//[$'\t\r\n ']}
  vm_ct=$(parse_json "$vm_str" "count")
  echo $vm_ct
}

### Need to add methods for calculating memory, disk, and cpu for each VM by detecting whats available in env, not hardcoding.
function calculate_mem() {
  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_count=$(getVMCount "$option")
  memory_ct=$(parse_json "$vm_str" "memory")

}

function calculate_disk() {
  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_count=$(getVMCount "$option")
  drive_string=$(parse_json "$vm_str" "drive_string")

}

function calculate_cpu() {
  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_count=$(getVMCount "$option")
  cpu=$(parse_json "$vm_str" "cpu")

}
##############

function vm_definitions {
  option="${1}"
  case $option in
    "control")
        echo '{
            "count":"3",
            "cpu":"2",
            "memory":"34",
            "drive_string":"Disk:100",
            "network_string":"amp-net,loc-static"
          }'
    ;;
    "network")
        echo '{
            "count":"2",
            "cpu":"2",
            "memory":"12",
            "drive_string":"Disk:100",
            "network_string":"amp-net,loc-static,loc-static"
          }'
    ;;
    "compute")
        echo '{
            "count":"1",
            "cpu":"24",
            "memory":178",
            "drive_string":"SSD:700",
            "network_string":"amp-net,loc-static,loc-static"
          }'
    ;;
    "monitoring")
        echo '{
            "count":"1",
            "cpu":"2",
            "memory":"16",
            "drive_string":"Disk:350",
            "network_string":"amp-net,loc-static"
          }'
    ;;
    "storage")
        echo '{
            "count":"1",
            "cpu":"2",
            "memory":"22",
            "drive_string":"Disk:300,Disk:300,SSD:175,SSD:175,SSD:175",
            "network_string":"amp-net,loc-static"
          }'
    ;;
    "kolla")
        echo '{
            "count":"1",
            "cpu":"4",
            "memory":"4",
            "drive_string":"Disk:60",
            "network_string":"loc-static"
          }'
    ;;
  esac
}

function create_vm_kvm {
  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_str=${vmstr//[$'\t\r\n ']}

  ## CPU ct per VM needs to be computed based on how much load a VM of this type handles and total number of physical CPU's on hypervisor
  cpu_ct=$(parse_json "$vm_str" "cpu")

  ## Memory needs to be computed using the same method as above
  memory_ct=$(parse_json "$vm_str" "memory")

  ### Drives should be computed based on a) if there is more than 1 drive in the system a speed test will be done to figure out what drive is "fast" vs "slow"
  ##  (SSD vs platter).  VM's that need "fast" storage will place themselves there.
  drive_string=$(parse_json "$vm_str" "drive_string")

  ## networks can remain hardcoded as cloud infra contains entire network.
  network_string=$(parse_json "$vm_str" "network_string")

  #### build disk info for kvm.  iterate over drive string and get kvm storage path.
  virt_disk_list=()
  IFS=',' read -r -a disk_array <<< "$drive_string"
  for element in "${disk_array[@]}"
    do
      IFS=':' read -ra drive_info <<< "$element"
      virt_disk_list+=("--disk pool=${drive_info[0]},size=${drive_info[1]},bus=virtio,sparse=no ")
  done
  #####################

  ##########  build network info for kvm
  virt_network_list=()
  IFS=',' read -r -a net_array <<< "$network_string"
  for net_element in "${net_array[@]}"
    do
      virt_network_list+=("--network type=bridge,source=$net_element,model=virtio ")
  done
  #########################

  printf -v virt_disk_string '%s ' "${virt_disk_list[@]}"
  printf -v virt_network_string '%s ' "${virt_network_list[@]}"

  autostart=""
  if [[ $option != "kolla" ]]; then
    autostart=" --autostart"
  fi

  #### kvm cpu topology
  threads=2
  if [[ $cpu_ct > 4 ]]; then
    sockets=$((cpu_ct / 4))
    cores=2
  else
    if [[ $((cpu_ct % 2)) == 0 ]]; then
      sockets=$((cpu_ct / 2))
      cores=2
    else
      sockets=2
      cores=2
    fi
  fi
  cpu_topology="vcpus=$((sockets * cores * threads)),maxvcpus=$((sockets * cores * threads)),sockets=$sockets,cores=$cores,threads=$threads"
  ###############

  create_line="virt-install "
  create_line+="--hvm "
  create_line+="--virt-type=kvm "
  create_line+="--name=$2 "
  create_line+="--memory=${memory_ct}000 "
  create_line+="--cpu=host-passthrough,cache.mode=passthrough "
  create_line+="--cpuset=auto "
  create_line+="--vcpus=$cpu_topology "
  create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
  create_line+="--memorybacking hugepages=yes "
  create_line+="--controller type=scsi,model=virtio-scsi "
  create_line+="$virt_disk_string"
  create_line+="--cdrom=/var/tmp/$2-iso.iso "
  create_line+="$virt_network_string"
  create_line+="--os-variant=centos8 "
  create_line+="--graphics=vnc "
  create_line+="$autostart"

  echo $create_line
  eval $create_line &
}

function removeVM_kvm {
  vm_name=$1

  #### test if vm exists
  if (virsh list --name | grep -q $vm_name)
  then
    echo "Destroying vm $vm_name"
  else
   return
  fi

  virsh destroy "$vm_name"
  virsh undefine "$vm_name"

  ########### Delete volumes in storage pools
  virsh vol-list Disk | awk 'NR > 2 && !/^+--/ { print $1 }' | while read line; do
    if [[ ! -z $line ]]; then
      if [[ "$line" =~ .*"$vm_name".* ]]; then
        virsh vol-delete --pool Disk $line
      fi
    fi
  done

  virsh vol-list SSD | awk 'NR > 2 && !/^+--/ { print $1 }' | while read line; do
    if [[ ! -z $line ]]; then
      if [[ "$line" =~ .*"$vm_name".* ]]; then
        virsh vol-delete --pool SSD $line
      fi
    fi
  done
  ##########################
}
