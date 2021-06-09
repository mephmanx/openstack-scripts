source ./network-functions.sh
source ./openstack-env.sh

CENTOS_STREAM=http://centos.host-engine.com/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-20210421-boot.iso
CENTOS_8=https://pfsense.lyonsgroup.family/isos/CentOS-8.3.2011-x86_64-minimal.iso
ALMA_LINUX=https://repo.almalinux.org/almalinux/8.3/isos/x86_64/AlmaLinux-8.3-x86_64-minimal.iso
# versions supported 1 - CentOS 8, 2 - CentOS 8 Stream, 3 - Alma Linux 8
LINUX_VERSION=1

IFS=

function cockpitCerts {
  ###  Prepare certs
  echo 'cat > /etc/cockpit/ws-certs.d/certificate.cert <<EOF' >> ./$1
  cat ./certs/lyonsgroup-wildcard.fullchain >> ./$1
  echo 'EOF' >> ./$1
  echo 'cat > /etc/cockpit/ws-certs.d/certificate.key <<EOF' >> ./$1
  cat ./certs/lyonsgroup-wildcard.key >> ./$1
  echo 'EOF' >> ./$1
}

function letsEncryptAndCockpitCerts {
  kickstart_file=$1
  ####initial certs###############
  cockpitCerts ${kickstart_file}

  echo 'mkdir -p /etc/letsencrypt/live/lyonsgroup.family' >> ${kickstart_file}

  echo 'cat > /etc/letsencrypt/live/lyonsgroup.family/cert.pem   <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.all.pem >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  echo 'cat > /etc/letsencrypt/live/lyonsgroup.family/chain.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.fullchain >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /etc/letsencrypt/live/lyonsgroup.family/fullchain.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.fullchain >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  echo 'cat > /etc/letsencrypt/live/lyonsgroup.family/privkey.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  ###############################
}

function commonItems {
  kickstart_file=$1

  ############## passwordless ssh
  echo 'cat > /tmp/openstack-setup.key.pub <<EOF' >> ${kickstart_file}
  cat /tmp/openstack-setup.key.pub >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/openstack-setup.key <<EOF' >> ${kickstart_file}
  cat /tmp/openstack-setup.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  ###############################

  ############### Global Addresses ################
  echo 'cat > /tmp/global_addresses.sh <<EOF' >> ${kickstart_file}
  cat /tmp/global_addresses.sh >> ${kickstart_file}
  cat /tmp/dns_hosts >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  ###############################

  ############### Secrets File ################
  echo 'cat > /tmp/openstack-env.sh <<EOF' >> ${kickstart_file}
  cat ./openstack-env.sh >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  ###############################

  ############ add SSL proxy cert
  echo 'cat > /tmp/proxy.crt <<EOF' >> ${kickstart_file}
  cat ./certs/Lyonsgroup+VPN.crt >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  ########################
}

function initialKickstartSetup {
  printf -v vm_type_n '%s\n' "${1//[[:digit:]]/}"
  vm_type=$(tr -dc '[[:print:]]' <<< "$vm_type_n")

  rm -rf centos-8-kickstart-$1.cfg
  cp centos-8-kickstart-cloud_common.cfg centos-8-kickstart-$1.cfg
  echo "copied kickstart -> centos-8-kickstart-$vm_type.cfg to -> centos-8-kickstart-$1.cfg"
  kickstart_file=centos-8-kickstart-${1}.cfg
  sed -i 's/{HOST}/'$1'/g' ${kickstart_file}
  sed -i 's/{TYPE}/'$vm_type'/g' ${kickstart_file}
  sed -i 's/{GITHUB_TOKEN}/'$GITHUB_TOKEN'/g' ${kickstart_file}
  sed -i 's/{CENTOS_ROOT_PWD}/'$CENTOS_ROOT_PWD'/g' ${kickstart_file}
  networkInformation ${kickstart_file} ${vm_type} ${1}
  echo ${kickstart_file}
}

function prepareEnv {

  if [ -f "/tmp/centos8.iso" ]; then
    return;
  fi

  sudo yum install epel-release -y
  sudo yum install -y rsync genisoimage pykickstart isomd5sum make python2 gcc yum-utils createrepo syslinux bzip2 curl file sshpass

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

function closeOutAndBuildKickstartAndISO {
  kickstart_file=$1
  vm_name=$2
  working_dir=`pwd`
  #### to allow certs to print right
  IFS=
  ########
  prepareEnv
  ###Close out cfg file
  echo '%end' >> ./${kickstart_file}
  echo 'eula --agreed' >> ./${kickstart_file}
  echo 'reboot --eject' >> ./${kickstart_file}
  #########

  sudo rm -rf /var/tmp/${vm_name}
  sudo mount -t iso9660 -o loop /tmp/centos8.iso /centos
  sudo mkdir -p /var/tmp/${vm_name}
  sudo rsync -a /centos/ /var/tmp/${vm_name}
  sudo umount /centos

  cp ./${kickstart_file} /var/tmp/${vm_name}/ks.cfg
  cp ./isolinux-centos8.cfg /var/tmp/${vm_name}/isolinux/isolinux.cfg

  sudo ksvalidator /var/tmp/${vm_name}/ks.cfg

  cd /var/tmp/${vm_name}
  sudo genisoimage -o ../${vm_name}-iso.iso \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e images/efiboot.img \
    -no-emul-boot -J -R -v -T -V 'CentOS 8 x86_64' .

  cd /var/tmp/
  sudo implantisomd5 ${vm_name}-iso.iso
  sudo rm -rf /var/tmp/${vm_name}
  cd $working_dir
}

function buildAndPushVMTypeISO {
  vm_name=$1
  ############### kickstart init
  initialKickstartSetup ${vm_name}
  ###########################

  ########### common certs
  letsEncryptAndCockpitCerts ${kickstart_file}
  ##########################

  ############## common misc items
  commonItems ${kickstart_file}
  ##########################

  #####################################
  closeOutAndBuildKickstartAndISO ${kickstart_file} ${vm_name}
  esxi_transfer ${vm_name}
}

function buildAndPushOpenstackSetupISO {

  ############### kickstart init
  initialKickstartSetup "kolla"
  ###########################

  ########### common certs
  letsEncryptAndCockpitCerts ${kickstart_file}
  ##########################

  #############  Octavia Keys
  echo 'cat > /tmp/client.cert-and-key.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.fullchain >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/client_ca.cert.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.fullchain >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/server_ca.cert.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.fullchain >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/server_ca.key.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  #################################

  ############## common misc items
  commonItems ${kickstart_file}
  ##########################

  ############ certs to enable SSL on VNC
  echo 'cat > /tmp/haproxy.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.fullchain >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  #################################

  ########## add host trust script
  echo 'cat > /tmp/host-trust.sh <<EOF' >> ${kickstart_file}
  cat /tmp/dns_hosts >> ${kickstart_file}
  echo  $1 >> ${kickstart_file}
  cat /tmp/additional_hosts >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  #####################

  ############ control hack script
  echo 'cat > /tmp/control-trust.sh <<EOF' >> ${kickstart_file}
  echo  $2 >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  #################################

  ############## host count
  echo 'cat > /tmp/host_count <<EOF' >> ${kickstart_file}
  echo  $3 >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  #########################

  ############## storage internal host ip
  echo 'cat > /tmp/storage_hosts <<EOF' >> ${kickstart_file}
  cat /tmp/storage_hosts >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  #########################

  ############## host list
  echo 'cat > /tmp/host_list <<EOF' >> ${kickstart_file}
  cat /tmp/host_list >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  #########################

  #####################################
  closeOutAndBuildKickstartAndISO ${kickstart_file} "kolla"
  esxi_transfer "kolla"
}

function esxi_transfer {
  vm_name=$1
  if [[ $TRANSFER > 0 ]]; then
    esxi-scp -H $HOSTNAME -n /var/tmp/${vm_name}-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos
  fi
}