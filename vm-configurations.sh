#!/bin/bash

source /tmp/openstack-scripts/project_config.sh
source /tmp/vm_functions.sh

function getVMCount {
  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_str=${vmstr//[$'\t\r\n ']}
  vm_ct=$(parse_json "$vm_str" "count")
  echo "$vm_ct"
}

function getVMVolSize() {
  disk_type="${1}"
  vm_count=$2
  case $disk_type in
  "control")
    size_avail=$(df /VM-VOL-CONTROL | awk '{print $2}' | sed 1d)
    echo $(($((size_avail / vm_count)) / 1024 / 1024))
    ;;
  "network")
    size_avail=$(df /VM-VOL-NETWORK | awk '{print $2}' | sed 1d)
    echo $(($((size_avail / vm_count)) / 1024 / 1024))
    ;;
  "compute")
    size_avail=$(df /VM-VOL-COMPUTE | awk '{print $4}' | sed 1d)
    echo $((size_avail / 1024 / 1024))
    ;;
  "monitoring")
    size_avail=$(df /VM-VOL-MONITORING | awk '{print $4}' | sed 1d)
    echo $((size_avail / 1024 / 1024))
    ;;
  "cinder")
    size_avail=$(df /VM-VOL-CINDER | awk '{print $4}' | sed 1d)
    echo $(($((size_avail / 1024 / 1024)) - 100))
    ;;
  "swift")
    size_avail=$(df /VM-VOL-SWIFT | awk '{print $2}' | sed 1d)
    echo $(($((size_avail / vm_count)) / 1024 / 1024))
    ;;
  "kolla")
    size_avail=$(df /VM-VOL-KOLLA | awk '{print $4}' | sed 1d)
    echo $((size_avail / 1024 / 1024))
    ;;
  esac
}

function getDiskMapping() {
  vm_type=$1
  vm_count=$2
  case $vm_type in
  "control")
    echo "VM-VOL-CONTROL:$(getVMVolSize "$vm_type" "$vm_count")"
    ;;
  "network")
    echo "VM-VOL-NETWORK:$(getVMVolSize "$vm_type" "$vm_count")"
    ;;
  "compute")
    echo "VM-VOL-COMPUTE:$(getVMVolSize "$vm_type" "$vm_count")"
    ;;
  "monitoring")
    echo "VM-VOL-MONITORING:$(getVMVolSize "$vm_type" "$vm_count")"
    ;;
  "storage")
    echo "VM-VOL-CINDER:100,VM-VOL-CINDER:$(getVMVolSize "cinder" "$vm_count"),VM-VOL-SWIFT:$(getVMVolSize "swift" 3),VM-VOL-SWIFT:$(getVMVolSize "swift" 3),VM-VOL-SWIFT:$(getVMVolSize "swift" 3)"
    ;;
  "kolla")
    echo "VM-VOL-KOLLA:$(getVMVolSize "$vm_type" 1)"
    ;;
  "misc")
    echo "VM-VOL-MISC"
    ;;
  esac
}

function vm_definitions {
  option="${1}"

  case $option in
  "control")
    STRING='{
            "count":"$CONTROL_COUNT",
            "cpu":"2",
            "memory":"$CONTROL_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static"
          }'
    STRING="$(echo $STRING | sed 's/$CONTROL_RAM/'"$CONTROL_RAM"'/g')"
    STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'"$(getDiskMapping "control" "$CONTROL_COUNT")"'/g')"
    STRING="$(echo $STRING | sed 's/$CONTROL_COUNT/'"$CONTROL_COUNT"'/g')"
    echo "$STRING"
    ;;
  "network")
    STRING='{
            "count":"$NETWORK_COUNT",
            "cpu":"2",
            "memory":"$NETWORK_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static,loc-static"
          }'
    STRING="$(echo $STRING | sed 's/$NETWORK_RAM/'"$NETWORK_RAM"'/g')"
    STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'"$(getDiskMapping "network" "$NETWORK_COUNT")"'/g')"
    STRING="$(echo $STRING | sed 's/$NETWORK_COUNT/'"$NETWORK_COUNT"'/g')"
    echo "$STRING"
    ;;
  "compute")
    CPU_COUNT=$(lscpu | awk -F':' '$1 == "CPU(s)" {print $2}' | awk '{ gsub(/ /,""); print }')
    INSTALLED_RAM=$(runuser -l root -c 'dmidecode -t memory | grep  Size: | grep -v "No Module Installed"' | awk '{sum+=$2}END{print sum}')
    ## the subtraction at the end is for pfsense & cloudsupport & identity allocation from available memory
    RESERVED_RAM=$(($(($INSTALLED_RAM * $RAM_PCT_AVAIL_CLOUD / 100)) - PFSENSE_RAM - IDENTITY_RAM - CLOUDSUPPORT_RAM))
    COMPUTE_RAM=$((RESERVED_RAM - (CONTROL_RAM * CONTROL_COUNT) - (NETWORK_RAM * NETWORK_COUNT) - (MONITORING_RAM * MONITORING_COUNT) - (STORAGE_RAM * STORAGE_COUNT) - KOLLA_RAM))
    STRING='{
            "count":"$COMPUTE_COUNT",
            "cpu":"$CPU_COUNT",
            "memory":$COMPUTE_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static,loc-static"
          }'
    STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'"$(getDiskMapping "compute" "1")"'/g')"
    STRING="$(echo $STRING | sed 's/$CPU_COUNT/'"$CPU_COUNT"'/g')"
    STRING="$(echo $STRING | sed 's/$COMPUTE_RAM/'"$COMPUTE_RAM"'/g')"
    STRING="$(echo $STRING | sed 's/$COMPUTE_COUNT/'"$COMPUTE_COUNT"'/g')"
    echo "$STRING"
    ;;
  "monitoring")
    STRING='{
            "count":"$MONITORING_COUNT",
            "cpu":"2",
            "memory":"$MONITORING_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static"
          }'
    STRING="$(echo $STRING | sed 's/$MONITORING_RAM/'"$MONITORING_RAM"'/g')"
    STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'"$(getDiskMapping "monitoring" "$MONITORING_COUNT")"'/g')"
    STRING="$(echo $STRING | sed 's/$MONITORING_COUNT/'"$MONITORING_COUNT"'/g')"
    echo "$STRING"
    ;;
  "storage")
    STRING='{
            "count":"$STORAGE_COUNT",
            "cpu":"2",
            "memory":"$STORAGE_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static"
          }'
    STRING="$(echo $STRING | sed 's/$STORAGE_RAM/'"$STORAGE_RAM"'/g')"
    STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'"$(getDiskMapping "storage" "$STORAGE_COUNT")"'/g')"
    STRING="$(echo $STRING | sed 's/$STORAGE_COUNT/'"$STORAGE_COUNT"'/g')"
    echo "$STRING"
    ;;
  "kolla")
    STRING='{
            "count":"1",
            "cpu":"4",
            "memory":"$KOLLA_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static"
          }'
    STRING="$(echo $STRING | sed 's/$KOLLA_RAM/'"$KOLLA_RAM"'/g')"
    STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'"$(getDiskMapping "kolla" "1")"'/g')"
    echo "$STRING"
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
  IFS=',' read -r -a disk_array <<<"$drive_string"
  for element in "${disk_array[@]}"; do
    IFS=':' read -ra drive_info <<<"$element"
    virt_disk_list+=("--disk pool=${drive_info[0]},size=${drive_info[1]},bus=virtio,sparse=no ")
  done
  #####################

  ##########  build network info for kvm
  virt_network_list=()
  IFS=',' read -r -a net_array <<<"$network_string"
  for net_element in "${net_array[@]}"; do
    virt_network_list+=("--network type=bridge,source=$net_element,model=virtio ")
  done
  #########################

  printf -v virt_disk_string '%s ' "${virt_disk_list[@]}"
  printf -v virt_network_string '%s ' "${virt_network_list[@]}"

  #### kvm cpu topology
  threads=2
  if [[ $cpu_ct -gt 4 ]]; then
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
  create_line+="--vcpus=$cpu_topology "
  create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
  create_line+="--memorybacking hugepages=yes "
  create_line+="--controller type=scsi,model=virtio-scsi "
  create_line+="$virt_disk_string"
  create_line+="--cdrom=/tmp/$2-iso.iso "
  create_line+="$virt_network_string"
  create_line+="--os-variant=centos8 "
  create_line+="--graphics=vnc "

  create_line+="--channel unix,target.type=virtio,target.name='org.qemu.guest_agent.0' "

  create_line+=" --autostart --wait -1; rm -rf /tmp/$2-iso.iso"

  echo "$create_line"
  eval "$create_line" &
}