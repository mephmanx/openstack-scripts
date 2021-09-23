#!/bin/bash

source /tmp/project_config.sh
source /tmp/openstack-scripts/vm_functions.sh
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

round() {
    printf "%.${2:-0}f" "$1"
}

function getDriveRatings() {
  drive_ratings=()
  LSHW_OUT=`lshw -json -class disk`
  jq_out=`echo "[$LSHW_OUT]" | jq .`
  for disk in `echo $jq_out | jq .[].logicalname`; do
    drive=`echo $disk | rev | cut -d'/' -f 1 | rev | tr -d '"'`
    speed=`hdparm -tv /dev/$drive | awk '/Timing buffered disk reads/ {print $11}'`
    speed=$(round $(cut -d':' -f2 <<<$speed) 0)
    drive_ratings+=("$drive:$speed")
  done
  printf -v drive_speed_string '%s ' "${drive_ratings[@]}"
  echo $drive_speed_string
}

function getFastestDrive() {
  drive_speed_string=$1
  IFS=' ' read -r -a drive_ratings_fst <<< "$drive_speed_string"
  fastest_drive_speed=0
  for entry in "${drive_ratings_fst[@]}"; do
    if [[ $(round $(cut -d':' -f2 <<<$entry) 0) -gt $fastest_drive_speed ]]; then
      fastest_drive=`cut -d':' -f1 <<<$entry`
      fastest_drive_speed=$(round $(cut -d':' -f2 <<<$entry) 0)
    fi
  done
  echo "$fastest_drive"
}

function getSecondFastestDrive() {
  drive_speed_string=$1
  ## remove fastest drive info
  fDr="$(getFastestDrive $drive_speed_string)"
  IFS=' ' read -r -a drive_ratings_reg <<< "$drive_speed_string"
  new_arr=()
  echo $drive_ratings_reg
  for ele in "${drive_ratings_reg[@]}"; do
    if [ -n "$(sed -n "/$fDr/p" <<< "$ele")" ]; then
      ##do nothing as it matches
      echo "$ele not being added to test array"
      x=1
    else
      echo "$ele being added to test array"
      new_arr+=("$ele")
    fi
  done
  fastest_drive_speed=0
  fastest_drive=""
  for entry in "${new_arr[@]}"; do
    if [[ $(round $(cut -d':' -f2 <<<$entry) 0) -gt $fastest_drive_speed ]]; then
      fastest_drive=`cut -d':' -f1 <<<$entry`
      fastest_drive_speed=$(round $(cut -d':' -f2 <<<$entry) 0)
    fi
  done
  echo "$fastest_drive"
}

function getDiskMapping() {
  ### this is the drive request from below config, REG for regular speed drive, HIGH for high speed drive
  DISK_COUNT=`lshw -json -class disk | grep -o -i disk: | wc -l`
  if [[ $DISK_COUNT -lt 2 ]]; then
    ## only 1 disk, return only storage pool
    echo "VM-VOL1"
  else
    ## multiple disks, find which one corresponds to "high speed" and "regular speed"
    drive_speed_request=$1
    drive_ratings=$(getDriveRatings)
    if [[ "HIGH" == $drive_speed_request ]]; then
      volume=`lsblk -o MOUNTPOINT -nr /dev/"$(getFastestDrive $drive_ratings)" | grep "VM-VOL" | tr -d '/'`
      echo $volume
    else
      volume=`lsblk -o MOUNTPOINT -nr /dev/"$(getSecondFastestDrive $drive_ratings)" | grep "VM-VOL" | tr -d '/'`
      echo $volume
    fi
  fi
}

function vm_definitions {
  option="${1}"

  ### these counts can be adjusted if larger than 1 server
  ### below counts are based on single server
  CONTROL_RAM=34
  NETWORK_RAM=12
  MONITORING_RAM=16
  STORAGE_RAM=22
  KOLLA_RAM=4

  CONTROL_COUNT=3
  NETWORK_COUNT=2
  MONITORING_COUNT=1
  STORAGE_COUNT=1
  KOLLA_COUNT=1
  ######

  case $option in
    "control")
        STRING='{
            "count":"$CONTROL_COUNT",
            "cpu":"2",
            "memory":"$CONTROL_RAM",
            "drive_string":"REG:100",
            "network_string":"amp-net,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$CONTROL_RAM/'$CONTROL_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$CONTROL_COUNT/'$CONTROL_COUNT'/g')"
        echo $STRING
    ;;
    "network")
        STRING='{
            "count":"$NETWORK_COUNT",
            "cpu":"2",
            "memory":"$NETWORK_RAM",
            "drive_string":"REG:100",
            "network_string":"amp-net,loc-static,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$NETWORK_RAM/'$NETWORK_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$NETWORK_COUNT/'$NETWORK_COUNT'/g')"
        echo $STRING
    ;;
    "compute")
        CPU_COUNT=`lscpu | awk -F':' '$1 == "CPU(s)" {print $2}' | awk '{ gsub(/ /,""); print }'`
        INSTALLED_RAM=`runuser -l root -c  'dmidecode -t memory | grep  Size: | grep -v "No Module Installed"' | awk '{sum+=$2}END{print sum}'`
        RESERVED_RAM=$(( $INSTALLED_RAM * $RAM_PCT_AVAIL_CLOUD/100 ))
        COMPUTE_RAM=$((RESERVED_RAM - (CONTROL_RAM * CONTROL_COUNT) - (NETWORK_RAM * NETWORK_COUNT) - (MONITORING_RAM * MONITORING_COUNT) - (STORAGE_RAM * STORAGE_COUNT) - KOLLA_RAM))
        STRING='{
            "count":"1",
            "cpu":"$CPU_COUNT",
            "memory":$COMPUTE_RAM",
            "drive_string":"HIGH:700",
            "network_string":"amp-net,loc-static,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$CPU_COUNT/'$CPU_COUNT'/g')"
        STRING="$(echo $STRING | sed 's/$COMPUTE_RAM/'$COMPUTE_RAM'/g')"
        echo $STRING
    ;;
    "monitoring")
        STRING='{
            "count":"$MONITORING_COUNT",
            "cpu":"2",
            "memory":"$MONITORING_RAM",
            "drive_string":"REG:350",
            "network_string":"amp-net,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$MONITORING_RAM/'$MONITORING_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$MONITORING_COUNT/'$MONITORING_COUNT'/g')"
        echo $STRING
    ;;
    "storage")
        STRING='{
            "count":"$STORAGE_COUNT",
            "cpu":"2",
            "memory":"$STORAGE_RAM",
            "drive_string":"REG:300,REG:300,HIGH:175,HIGH:175,HIGH:175",
            "network_string":"amp-net,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$STORAGE_RAM/'$STORAGE_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$STORAGE_COUNT/'$STORAGE_COUNT'/g')"
        echo $STRING
    ;;
    "kolla")
        STRING='{
            "count":"$KOLLA_COUNT",
            "cpu":"4",
            "memory":"$KOLLA_RAM",
            "drive_string":"REG:60",
            "network_string":"loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$KOLLA_RAM/'$KOLLA_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$KOLLA_COUNT/'$KOLLA_COUNT'/g')"
        echo $STRING
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
      ### use above function to match speed (REG, HIGH) with the volume name to put the disk on
      pool=$((getDiskMapping ${drive_info[0]}))
      virt_disk_list+=("--disk pool=$pool,size=${drive_info[1]},bus=virtio,sparse=no ")
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
  DISK_COUNT=`lshw -json -class disk | grep -o -i disk: | wc -l`

  while [ $DISK_COUNT -gt 0 ]; do
    virsh vol-list VM-VOL$DISK_COUNT | awk 'NR > 2 && !/^+--/ { print $1 }' | while read line; do
        if [[ ! -z $line ]]; then
          if [[ "$line" =~ .*"$vm_name".* ]]; then
            virsh vol-delete --pool VM-VOL$DISK_COUNT $line
          fi
        fi
      done
  done
  ##########################
}
