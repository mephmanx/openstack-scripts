CENTOS_STREAM=http://centos.host-engine.com/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-20210421-boot.iso
CENTOS_8=http://mirrors.oit.uci.edu/centos/8.2.2004/isos/x86_64/CentOS-8.2.2004-x86_64-minimal.iso
ALMA_LINUX=http://mirror.vtti.vt.edu/almalinux/8.3/isos/x86_64/AlmaLinux-8.3-x86_64-minimal.iso

# versions supported 1 - CentOS 8, 2 - CentOS 8 Stream, 3 - Alma Linux 8
LINUX_VERSION=2

function setupENV {
  export HOSTNAME=$1
  export ISO_DISK_NAME=HP-Disk
  export DISK_NAME=HP-Disk
  rm -rf /var/tmp/*.*

  sudo yum install epel-release -y
  sudo yum install -y rsync genisoimage pykickstart isomd5sum make python2 gcc yum-utils createrepo syslinux bzip2 curl file sshpass

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
      ./bootstrap.sh run

      mv /tmp/CentOS-Stream-Minimal.iso /tmp/centos8.iso
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
  rm -rf ~/.esxi-vm.yml
  esxi-vm-create -H $HOSTNAME -P $1 -u
  esxi-vm-destroy -n $2
  sleep 15
  esxi-scp-remove -H $HOSTNAME -n $2-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos
  esxi-scp-remove -H $HOSTNAME -n $2 -l /vmfs/volumes/$DISK_NAME
}
