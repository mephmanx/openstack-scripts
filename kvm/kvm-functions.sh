source ./vm-configurations.sh

CENTOS_STREAM=http://centos.host-engine.com/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-20210421-boot.iso
CENTOS_8=http://mirrors.oit.uci.edu/centos/8.2.2004/isos/x86_64/CentOS-8.2.2004-x86_64-minimal.iso
ALMA_LINUX=https://repo.almalinux.org/almalinux/8.3/isos/x86_64/AlmaLinux-8.3-x86_64-minimal.iso

# versions supported 1 - CentOS 8, 2 - CentOS 8 Stream, 3 - Alma Linux 8
LINUX_VERSION=1

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

function removeVM {
  rm -rf ~/.esxi-vm.yml
  #update ESXi defaults for ESXi library
  esxi-vm-create -H $HOSTNAME -P $1 -u
  #remove VM from esxi
  esxi-vm-destroy -n $2
  sleep 15
  #remove iso from ESXI datastore
  esxi-scp-remove -H $HOSTNAME -n $2-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos
  #remove VM directory
  esxi-scp-remove -H $HOSTNAME -n $2 -l /vmfs/volumes/$DISK_NAME
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
