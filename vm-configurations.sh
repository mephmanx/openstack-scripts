#!/bin/bash
####  Functions in this file should be used AFTER ISO's are created and pushed to esxi

function parse_json()
{
    echo $1 | \
    sed -e 's/[{}]/''/g' | \
    sed -e 's/", "/'\",\"'/g' | \
    sed -e 's/" ,"/'\",\"'/g' | \
    sed -e 's/" , "/'\",\"'/g' | \
    sed -e 's/","/'\"---SEPERATOR---\"'/g' | \
    awk -F=':' -v RS='---SEPERATOR---' "\$1/root/\"$2\"/ {print}" | \
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

function vm_definitions {
  option="${1}"
  case $option in
    "control")
        echo '{
            "count":"3",
            "cpu":"2",
            "memory":"34",
            "drive_string":"HP-Disk:100",
            "network_string":"loc-static,int-static"
          }'
    ;;
    "network")
        echo '{
            "count":"2",
            "cpu":"2",
            "memory":"12",
            "drive_string":"HP-Disk:100",
            "network_string":"loc-static,int-static,int-static"
          }'
    ;;
    "compute")
        echo '{
            "count":"1",
            "cpu":"24",
            "memory":180",
            "drive_string":"HP-SSD:800",
            "network_string":"loc-static,int-static,int-static"
          }'
    ;;
    "monitoring")
        echo '{
            "count":"1",
            "cpu":"2",
            "memory":"20",
            "drive_string":"HP-Disk:300",
            "network_string":"loc-static,int-static"
          }'
    ;;
    "storage")
        echo '{
            "count":"1",
            "cpu":"2",
            "memory":"22",
            "drive_string":"HP-Disk:300,HP-Disk:300,HP-SSD:250,HP-SSD:250,HP-SSD:250",
            "network_string":"loc-static,int-static"
          }'
    ;;
    "kolla")
        echo '{
            "count":"1",
            "cpu":"4",
            "memory":"8",
            "drive_string":"HP-Disk:100",
            "network_string":"loc-static,int-static"
          }'
    ;;
  esac
}

function create_vm_kvm {
  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_str=${vmstr//[$'\t\r\n ']}
  cpu_ct=$(parse_json "$vm_str" "cpu")
  memory_ct=$(parse_json "$vm_str" "memory")
  drive_string=$(parse_json "$vm_str" "drive_string")
  network_string=$(parse_json "$vm_str" "network_string")

  #### build disk info for centos.  iterate over drive string and get centos storage path.
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
      if [[ "${net_element}" =~ .*"int".* ]]; then
        virt_network_list+=("--network type=direct,source=$net_element,model=virtio,source_mode=bridge ")
      else
        virt_network_list+=("--network type=bridge,source=$net_element,model=virtio ")
      fi
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
  create_line+="--cpuset=auto "
  create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
  create_line+="--memorybacking hugepages=yes "
  create_line+="--controller type=scsi,model=virtio-scsi "
  create_line+="$virt_disk_string"
  create_line+="--cdrom=/var/root/$2-iso.iso "
  create_line+="$virt_network_string"
  create_line+="--os-variant=centos8 "
  create_line+="--graphics=vnc "
  create_line+="$autostart"

  echo $create_line
  eval $create_line &
}

function removeVM_kvm {
  vm_name=$1
  virsh destroy "$vm_name"
  virsh undefine "$vm_name"

  ########### Delete volumes in storage pools
  virsh vol-list HP-Disk | awk 'NR > 2 && !/^+--/ { print $1 }' | while read line; do
    if [[ ! -z $line ]]; then
      if [[ "$line" =~ .*"$vm_name".* ]]; then
        virsh vol-delete --pool HP-Disk $line
      fi
    fi
  done

  virsh vol-list HP-SSD | awk 'NR > 2 && !/^+--/ { print $1 }' | while read line; do
    if [[ ! -z $line ]]; then
      if [[ "$line" =~ .*"$vm_name".* ]]; then
        virsh vol-delete --pool HP-SSD $line
      fi
    fi
  done
  ##########################
}
