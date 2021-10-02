#!/bin/bash

source /tmp/project_config.sh
source /tmp/openstack-scripts/vm_functions.sh

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

function getVMVolSize() {
      disk_type="${1}"
      vm_count=$2
      DISK_COUNT=`lshw -json -class disk | grep -o -i disk: | wc -l`
      if [[ $DISK_COUNT -lt 2 ]]; then
        size_avail=`df /VM-VOL-ALL | awk '{print $4}' | sed 1d`
        case $disk_type in
          "control")
            echo $(($((size_avail * 15/100)) / 1024 / 1024 / vm_count))
          ;;
          "network")
            echo $(($((size_avail * 10/100)) / 1024 / 1024 / vm_count))
          ;;
          "compute")
            echo $(($((size_avail * 25/100)) / 1024 / 1024))
          ;;
          "monitoring")
            echo $(($((size_avail * 5/100)) / 1024 / 1024))
          ;;
          "cinder")
            echo $(($((size_avail * 20/100)) / 1024 / 1024))
          ;;
          "swift")
            echo $(($((size_avail * 20/100)) / 1024 / 1024))
          ;;
          "kolla")
            echo $(($((size_avail * 5/100)) / 1024 / 1024))
          ;;
        esac
      else
         case $disk_type in
            "control")
              size_avail=`df /VM-VOL-CONTROL | awk '{print $2}' | sed 1d`
              echo $(($((size_avail / vm_count)) / 1024 / 1024))
            ;;
            "network")
              size_avail=`df /VM-VOL-NETWORK | awk '{print $2}' | sed 1d`
              echo $(($((size_avail / vm_count)) / 1024 / 1024))
            ;;
            "compute")
              size_avail=`df /VM-VOL-COMPUTE | awk '{print $4}' | sed 1d`
              echo $((size_avail / 1024 / 1024))
            ;;
            "monitoring")
              size_avail=`df /VM-VOL-MONITORING | awk '{print $4}' | sed 1d`
              echo $((size_avail / 1024 / 1024))
            ;;
            "cinder")
              size_avail=`df /VM-VOL-CINDER | awk '{print $4}' | sed 1d`
              echo $(($((size_avail / 1024 / 1024)) - 100))
            ;;
            "swift")
              size_avail=`df /VM-VOL-SWIFT | awk '{print $2}' | sed 1d`
              echo $(($((size_avail / vm_count)) / 1024 / 1024))
            ;;
            "kolla")
              size_avail=`df /VM-VOL-KOLLA | awk '{print $4}' | sed 1d`
              echo $((size_avail / 1024 / 1024))
            ;;
          esac
      fi
}

function getDiskMapping() {
  vm_type=$1
  vm_count=$2
  ### this is the drive request from below config, REG for regular speed drive, HIGH for high speed drive
  DISK_COUNT=`lshw -json -class disk | grep -o -i disk: | wc -l`
  if [[ $DISK_COUNT -lt 2 ]]; then
    ## only 1 disk, return only storage pool
    option="${1}"
    case $option in
      "misc")
          echo "VM-VOL-ALL"
        ;;
      *)
        echo "VM-VOL-ALL:$(getVMVolSize $vm_type $vm_count)"
      ;;
    esac
  else
    vm_count=$2
      case $vm_type in
        "control")
          echo "VM-VOL-CONTROL:$(getVMVolSize $vm_type $vm_count)"
        ;;
        "network")
          echo "VM-VOL-NETWORK:$(getVMVolSize $vm_type $vm_count)"
        ;;
        "compute")
          echo "VM-VOL-COMPUTE:$(getVMVolSize $vm_type $vm_count)"
        ;;
        "monitoring")
          echo "VM-VOL-MONITORING:$(getVMVolSize $vm_type $vm_count)"
        ;;
        "storage")
          #Disk:300,Disk:300,SSD:175,SSD:175,SSD:175
          echo "VM-VOL-CINDER:100,VM-VOL-CINDER:$(getVMVolSize "cinder" $vm_count),VM-VOL-SWIFT:$(getVMVolSize "swift" 3),VM-VOL-SWIFT:$(getVMVolSize "swift" 3),VM-VOL-SWIFT:$(getVMVolSize "swift" 3)"
        ;;
        "kolla")
          echo "VM-VOL-KOLLA:$(getVMVolSize $vm_type 1)"
        ;;
        "misc")
          echo "VM-VOL-MISC"
        ;;
        esac
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
  COMPUTE_COUNT=1
  ######

  case $option in
    "control")
        STRING='{
            "count":"$CONTROL_COUNT",
            "cpu":"2",
            "memory":"$CONTROL_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$CONTROL_RAM/'$CONTROL_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'$(getDiskMapping "control" "$CONTROL_COUNT")'/g')"
        STRING="$(echo $STRING | sed 's/$CONTROL_COUNT/'$CONTROL_COUNT'/g')"
        echo $STRING
    ;;
    "network")
        STRING='{
            "count":"$NETWORK_COUNT",
            "cpu":"2",
            "memory":"$NETWORK_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$NETWORK_RAM/'$NETWORK_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'$(getDiskMapping "network" "$NETWORK_COUNT")'/g')"
        STRING="$(echo $STRING | sed 's/$NETWORK_COUNT/'$NETWORK_COUNT'/g')"
        echo $STRING
    ;;
    "compute")
        CPU_COUNT=`lscpu | awk -F':' '$1 == "CPU(s)" {print $2}' | awk '{ gsub(/ /,""); print }'`
        INSTALLED_RAM=`runuser -l root -c  'dmidecode -t memory | grep  Size: | grep -v "No Module Installed"' | awk '{sum+=$2}END{print sum}'`
        RESERVED_RAM=$(( $INSTALLED_RAM * $RAM_PCT_AVAIL_CLOUD/100 ))
        COMPUTE_RAM=$((RESERVED_RAM - (CONTROL_RAM * CONTROL_COUNT) - (NETWORK_RAM * NETWORK_COUNT) - (MONITORING_RAM * MONITORING_COUNT) - (STORAGE_RAM * STORAGE_COUNT) - KOLLA_RAM))
        STRING='{
            "count":"$COMPUTE_COUNT",
            "cpu":"$CPU_COUNT",
            "memory":$COMPUTE_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'$(getDiskMapping "compute" "1")'/g')"
        STRING="$(echo $STRING | sed 's/$CPU_COUNT/'$CPU_COUNT'/g')"
        STRING="$(echo $STRING | sed 's/$COMPUTE_RAM/'$COMPUTE_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$COMPUTE_COUNT/'$COMPUTE_COUNT'/g')"
        echo $STRING
    ;;
    "monitoring")
        STRING='{
            "count":"$MONITORING_COUNT",
            "cpu":"2",
            "memory":"$MONITORING_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$MONITORING_RAM/'$MONITORING_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'$(getDiskMapping "monitoring" "$MONITORING_COUNT")'/g')"
        STRING="$(echo $STRING | sed 's/$MONITORING_COUNT/'$MONITORING_COUNT'/g')"
        echo $STRING
    ;;
    "storage")
        STRING='{
            "count":"$STORAGE_COUNT",
            "cpu":"2",
            "memory":"$STORAGE_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$STORAGE_RAM/'$STORAGE_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'$(getDiskMapping "storage" "$STORAGE_COUNT")'/g')"
        STRING="$(echo $STRING | sed 's/$STORAGE_COUNT/'$STORAGE_COUNT'/g')"
        echo $STRING
    ;;
    "kolla")
        STRING='{
            "count":"1",
            "cpu":"4",
            "memory":"$KOLLA_RAM",
            "drive_string":"$DRIVE_MAPPING",
            "network_string":"amp-net,loc-static"
          }'
        STRING="$(echo $STRING | sed 's/$KOLLA_RAM/'$KOLLA_RAM'/g')"
        STRING="$(echo $STRING | sed 's/$DRIVE_MAPPING/'$(getDiskMapping "kolla" "1")'/g')"
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
  printf -v vm_type_n '%s\n' "${vm_name//[[:digit:]]/}"
  vm_type=$(tr -dc '[[:print:]]' <<< "$vm_type_n")
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
  if [[ $DISK_COUNT -lt 2 ]]; then
    VM_TYPE="ALL"
    deleteVMVol $vm_name "ALL"
  else
    case $vm_type in
      "control")
        deleteVMVol $vm_name "CONTROL"
      ;;
      "network")
        deleteVMVol $vm_name "NETWORK"
      ;;
      "compute")
        deleteVMVol $vm_name "COMPUTE"
      ;;
      "monitoring")
        deleteVMVol $vm_name "MONITORING"
      ;;
      "storage")
        deleteVMVol $vm_name "CINDER"
        deleteVMVol $vm_name "SWIFT"
      ;;
      "kolla")
        deleteVMVol $vm_name "KOLLA"
      ;;
      "misc")
        deleteVMVol $vm_name "MISC"
      ;;
    esac
  fi


  ##########################
}

function deleteVMVol() {
  vm_name=$1
  VM_TYPE=$2
  virsh vol-list VM-VOL-$VM_TYPE | awk 'NR > 2 && !/^+--/ { print $1 }' | while read line; do
    if [[ ! -z $line ]]; then
      if [[ "$line" =~ .*"$vm_name".* ]]; then
        virsh vol-delete --pool VM-VOL-$VM_TYPE $line
      fi
    fi
  done
}
