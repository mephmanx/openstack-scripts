source ./vm-configurations.sh

CENTOS_STREAM=http://centos.host-engine.com/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-20210421-boot.iso
CENTOS_8=http://mirrors.oit.uci.edu/centos/8.2.2004/isos/x86_64/CentOS-8.2.2004-x86_64-minimal.iso
ALMA_LINUX=https://repo.almalinux.org/almalinux/8.3/isos/x86_64/AlmaLinux-8.3-x86_64-minimal.iso

# versions supported 1 - CentOS 8, 2 - CentOS 8 Stream, 3 - Alma Linux 8
LINUX_VERSION=1

# What disk to store ISO's on
ISO_DISK_NAME=HP-Disk

function setupENV {
  rm -rf /var/tmp/*.*

  if [ -f "/tmp/centos8.iso" ]; then
    return;
  fi

  case ${LINUX_VERSION} in
    1)
      echo "Using CentOS 8"
      curl -o /tmp/centos8.iso $CENTOS_8
    ;;
    2)
      echo "Using CentOS 8 Stream"
      cd /root
      rm -rf /root/centos-8-minimal
      git clone https://github.com/mephmanx/centos-8-minimal.git
      cd /root/centos-8-minimal

      if [ -f "/tmp/centos8-stream-base.iso" ]; then
        echo "CentOS 8 Stream Base exists"
      else
        wget -O /tmp/centos8-stream-base.iso $CENTOS_STREAM
      fi

      export CMISO='/tmp/centos8-stream-base.iso'
      export CMOUT='CentOS-Stream-Minimal.iso'
      ./bootstrap.sh run

      mv /root/centos-8-minimal/CentOS-Stream-Minimal.iso /tmp/centos8.iso
    ;;
    3)
      echo "Using Alma Linux 8"
      curl -o /tmp/centos8.iso $ALMA_LINUX
    ;;
  esac

  sudo rm -rf /centos
  sudo mkdir -p /centos
}

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

  printf -v vm_type_n '%s\n' "${1//[[:digit:]]/}"
  VM_TYPE=$(tr -dc '[[:print:]]' <<< "$vm_type_n")

  esxi-scp -H $HOSTNAME -n /var/tmp/$HOSTNAME-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos
}

function create_vm_esxi {
  ESXI_HOSTNAME=$1
  VM_NAME=$2
  ESXI_PASSWORD=$3
  DRIVE_LOCATION=$4
  VM_TYPE=$5
  VM_DISK_NAME=$6
  ISO_DISK_NAME=$7

  option="${1}"

  vmstr=$(vm_definitions "$option")
  vm_str=${vmstr//[$'\t\r\n ']}
  cpu_ct=$(parse_json "$vm_str" "cpu")
  memory_ct=$(parse_json "$vm_str" "memory")
  drive_string=$(parse_json "$vm_str" "drive_string")
  network_string=$(parse_json "$vm_str" "network_string")

  echo "creating VM name -> $VM_NAME type -> $VM_TYPE"
  esxi-vm-create -n $VM_NAME --summary --iso /vmfs/volumes/$ISO_DISK_NAME/isos/$VM_NAME-iso.iso \
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