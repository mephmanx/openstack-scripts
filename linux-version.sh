
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