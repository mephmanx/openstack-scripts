source ./vm-configurations.sh

function installESXiTools {
  alternatives --set python /usr/bin/python2
  python -m ensurepip --default-pip
  pip2 install six enum34 bcrypt PyAML

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

function removeVM {
  ESXI_HOSTNAME=$1
  VM_NAME=$2
  ESXI_PASSWORD=$3
  DRIVE_LOCATION=$4

  echo "Hostname -> " $ESXI_HOSTNAME
  echo "VM_NAME -> " $VM_NAME
  echo "ESXI_PWD -> " $ESXI_PASSWORD
  echo "DRIVE_LOCATION -> " $DRIVE_LOCATION

  rm -rf ~/.esxi-vm.yml
  #update ESXi defaults for ESXi library
  esxi-vm-create -H $ESXI_HOSTNAME -P $ESXI_PASSWORD -u
  #remove VM from esxi
  esxi-vm-destroy -n $VM_NAME
  sleep 15
  #remove iso from ESXI datastore
  esxi-scp-remove -H $ESXI_HOSTNAME -n $VM_NAME-iso.iso -l "$DRIVE_LOCATION/isos"
  #remove VM directory
  esxi-scp-remove -H $ESXI_HOSTNAME -n $VM_NAME -l "$DRIVE_LOCATION"
}

function pushISO {
  HOSTNAME=$1
  ESXI_HOST=$2
  printf -v vm_type_n '%s\n' "${1//[[:digit:]]/}"
  VM_TYPE=$(tr -dc '[[:print:]]' <<< "$vm_type_n")
  echo "Pushing ISO to ESXi host -> " $ESXI_HOST
  esxi-scp -H $ESXI_HOST -n /var/tmp/$HOSTNAME-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos
}

function create_vm_esxi {
  ESXI_HOSTNAME=$1
  VM_NAME=$2
  ESXI_PASSWORD=$3
  DRIVE_LOCATION=$4
  VM_TYPE=$5
  VM_DISK_NAME=$6
  ISO_DISK_NAME=$7

  echo "Hostname -> " $ESXI_HOSTNAME
  echo "VM_NAME -> " $VM_NAME
  echo "ESXI_PWD -> " $ESXI_PASSWORD
  echo "DRIVE_LOCATION -> " $DRIVE_LOCATION
  echo "VM_TYPE -> " $VM_TYPE
  echo "VM_DISK_NAME -> " $VM_DISK_NAME
  echo "ISO_DISK_NAME -> " $ISO_DISK_NAME

  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_str=${vmstr//[$'\t\r\n ']}
  cpu_ct=$(parse_json "$vm_str" "cpu")
  memory_ct=$(parse_json "$vm_str" "memory")
  drive_string=$(parse_json "$vm_str" "drive_string")
  network_string=$(parse_json "$vm_str" "network_string")

  echo "creating VM name -> $VM_NAME type -> $VM_TYPE"
  echo "command -> esxi-vm-create -n $VM_NAME --summary --iso $DRIVE_LOCATION/$VM_NAME-iso.iso -c $cpu_ct -m $memory_ct -S $VM_DISK_NAME -v $drive_string -V -N $network_string -o 'options_list'"
  esxi-vm-create -n $VM_NAME --summary --iso $DRIVE_LOCATION/$VM_NAME-iso.iso \
          -c $cpu_ct -m $memory_ct -S $VM_DISK_NAME -v $drive_string -V \
          -N $network_string -o 'cpuid.coresPerSocket = "2",
              vhv.enable = "TRUE",
              vvtd.enable = "TRUE",
              guestOS="centos8-64",
              virtualHW.version = "17",
              tools.upgrade.policy = "upgradeAtPowerCycle",
              autostart = "TRUE",
              tools.syncTime = "TRUE"' &
}