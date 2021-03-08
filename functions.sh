IFS=

function setupENV {
  export HOSTNAME=$1
  export ISO_DISK_NAME=HP-Disk
  export DISK_NAME=HP-Disk
  rm -rf /var/tmp/*.*

  sudo yum install epel-release -y
  sudo yum install -y rsync genisoimage pykickstart isomd5sum make python2 gcc yum-utils createrepo syslinux bzip2 curl file sshpass

  if [ -f "/tmp/centos8.iso" ]; then
      echo "$FILE exists."
  else
    curl -o /tmp/centos8.iso http://mirrors.oit.uci.edu/centos/8.2.2004/isos/x86_64/CentOS-8.2.2004-x86_64-minimal.iso
  fi

  sudo rm -rf /centos
  sudo mkdir -p /centos
}

function cockpitCerts {
  ###  Prepare certs
  echo 'cat > /etc/cockpit/ws-certs.d/certificate.cert <<EOF' >> ./$1
  cat ./certs/lyonsgroup-wildcard.fullchain >> ./$1
  echo 'EOF' >> ./$1
  echo 'cat > /etc/cockpit/ws-certs.d/certificate.key <<EOF' >> ./$1
  cat ./certs/lyonsgroup-wildcard.key >> ./$1
  echo 'EOF' >> ./$1
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

function closeOutAndBuildKickstartAndISO {
  working_dir=`pwd`
  #### to allow certs to print right
  IFS=
  ########

  ###Close out cfg file
  echo '%end' >> ./$1
  echo 'eula --agreed' >> ./$1
  echo 'reboot --eject' >> ./$1
  #########

  sudo rm -rf /var/tmp/$2
  sudo mount -t iso9660 -o loop /tmp/centos8.iso /centos
  sudo mkdir -p /var/tmp/$2
  sudo rsync -a /centos/ /var/tmp/$2
  sudo umount /centos

  cp ./$1 /var/tmp/$2/ks.cfg
  cp ./isolinux-centos8.cfg /var/tmp/$2/isolinux/isolinux.cfg

  sudo ksvalidator /var/tmp/$2/ks.cfg

  cd /var/tmp/$2
  sudo genisoimage -o ../$2-iso.iso \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e images/efiboot.img \
    -no-emul-boot -J -R -v -T -V 'CentOS 8 x86_64' .

  cd /var/tmp/
  sudo implantisomd5 $2-iso.iso
  sudo rm -rf /var/tmp/$2
  cd $working_dir
}