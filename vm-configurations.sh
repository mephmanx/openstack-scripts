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

function vm_definitions {
  option="${1}"
  case $option in
    "control")
        echo '{
            "count":"3",
            "cpu":"2",
            "memory":"40",
            "drive_string":"HP-Disk:100",
            "network_string":"loc-static,int-static"
          }'
    ;;
    "network")
        echo '{
            "count":"2",
            "cpu":"2",
            "memory":"16",
            "drive_string":"HP-Disk:100",
            "network_string":"loc-static,int-static,int-static"
          }'
    ;;
    "compute")
        echo '{
            "count":"1",
            "cpu":"24",
            "memory":200",
            "drive_string":"HP-SSD:800",
            "network_string":"loc-static,int-static,int-static"
          }'
    ;;
    "monitoring")
        echo '{
            "count":"1",
            "cpu":"2",
            "memory":"24",
            "drive_string":"HP-Disk:300",
            "network_string":"loc-static,int-static"
          }'
    ;;
    "storage")
        echo '{
            "count":"1",
            "cpu":"2",
            "memory":"24",
            "drive_string":"HP-Disk:300,HP-Disk:300,HP-SSD:250,HP-SSD:250,HP-SSD:250",
            "network_string":"loc-static,int-static"
          }'
    ;;
    "kolla")
        echo '{
            "count":"1",
            "cpu":"4",
            "memory":"16",
            "drive_string":"HP-Disk:100",
            "network_string":"loc-static,int-static"
          }'
    ;;
  esac
}

function create_vm_esxi {
  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_str=${vmstr//[$'\t\r\n ']}
  cpu_ct=$(parse_json "$vm_str" "cpu")
  memory_ct=$(parse_json "$vm_str" "memory")
  drive_string=$(parse_json "$vm_str" "drive_string")
  network_string=$(parse_json "$vm_str" "network_string")

  echo "creating VM name -> $2 type -> $1"
  esxi-vm-create -n ${2} --summary --iso /vmfs/volumes/$ISO_DISK_NAME/isos/$2-iso.iso \
          -c $cpu_ct -m $memory_ct -S $DISK_NAME -v $drive_string -V \
          -N $network_string -o 'cpuid.coresPerSocket = "2",
              vhv.enable = "TRUE",
              vvtd.enable = "TRUE",
              guestOS="centos8-64",
              virtualHW.version = "17",
              tools.upgrade.policy = "upgradeAtPowerCycle",
              autostart = "TRUE",
              tools.syncTime = "TRUE"' &
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
      virt_disk_list+=("--disk pool=${drive_info[0]},size=${drive_info[1]},bus=scsi,sparse=no ")
  done
  #####################

  ##########  build network info for kvm
  virt_network_list=()
  IFS=',' read -r -a net_array <<< "$network_string"
  for net_element in "${net_array[@]}"
    do
      if [[ "${net_element}" =~ .*"loc".* ]]; then
        virt_network_list+=("--network type=network,source=$net_element,model=virtio ")
      else
        virt_network_list+=("--network type=direct,source=$net_element,model=virtio,source_mode=bridge ")
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
  create_line+="--virt-type kvm "
  create_line+="--name $2 "
  create_line+="--memory ${memory_ct}000 "
  create_line+="--cpu host-passthrough,cache.mode=passthrough "
  create_line+="--cpuset=auto "
  create_line+="--vcpus=$cpu_topology "
  create_line+="--cpuset=auto "
  create_line+="$virt_disk_string"
  create_line+="--cdrom /var/tmp/$2-iso.iso "
  create_line+="$virt_network_string"
  create_line+="--os-variant centos8 "
  create_line+="--graphics vnc $autostart"

  echo $create_line
  eval $create_line &
  #"virt-install --virt-type kvm --name $2 --memory ${memory_ct}000 --cpu host-passthrough,cache.mode=passthrough --hvm --vcpus=$cpu_ct,$cpu_topology $virt_disk_string--cdrom /var/tmp/$2-iso.iso $virt_network_string--os-variant centos8 --graphics vnc $autostart" &
}

function installESXiTools {
  alternatives --set python /usr/bin/python3
  pip3 install --upgrade pip
  pip3 install six enum34 bcrypt PyAML setuptools_rust setuptools rust wheel cryptography

  cd /root
  rm -rf /root/esxi-vm-create
  git clone https://github.com/mephmanx/esxi-vm-create.git
  cd /root/esxi-vm-create
  make install

  cd /root
  rm -rf /root/scp.py
  git clone https://github.com/jbardin/scp.py.git
  cd /root/scp.py
  python setup.py install

  cd /root/openstack-setup
}

function removeVM_esxi {
  rm -rf ~/.esxi-vm.yml
  esxi-vm-create -H $HOSTNAME -P $1 -u
  esxi-vm-destroy -n $2
  sleep 15
  esxi-scp-remove -H $HOSTNAME -n $2-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos
  esxi-scp-remove -H $HOSTNAME -n $2 -l /vmfs/volumes/$DISK_NAME
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