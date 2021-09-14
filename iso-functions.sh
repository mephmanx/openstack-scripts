#!/bin/bash

source ./network-functions.sh
source /tmp/openstack-env.sh
source /tmp/project_config.sh

LINUX_OS="https://$GATEWAY_ROUTER_IP/isos/linux.iso"
KICKSTART_DIR=/tmp/openstack-scripts

IFS=

function cockpitCerts {
  kickstart_file=$1
  ###  Prepare certs
  echo 'cat > /etc/cockpit/ws-certs.d/certificate.cert <<EOF' >> ${kickstart_file}
  cat /root/.ssh/id_rsa.crt >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  echo 'cat > /etc/cockpit/ws-certs.d/certificate.key <<EOF' >> ${kickstart_file}
  cat /root/.ssh/id_rsa.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
}

function commonItems {
  kickstart_file=$1

  UNIQUE_SUFFIX=`cat /tmp/suffix`
  ############## passwordless ssh
  echo 'cat > /tmp/openstack-setup.key.pub <<EOF' >> ${kickstart_file}
  cat /tmp/openstack-setup-$UNIQUE_SUFFIX.key.pub >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/openstack-setup.key <<EOF' >> ${kickstart_file}
  cat /tmp/openstack-setup-$UNIQUE_SUFFIX.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  ###### hypervisor key
  echo 'cat > /tmp/hypervisor.key <<EOF' >> ${kickstart_file}
  cat ~/.ssh/id_rsa.pub >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  #####
  ###############################

  ############### External Project Configs ################
  echo 'cat > /tmp/project_config.sh <<EOF' >> ${kickstart_file}
  cat /tmp/project_config.sh >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  ###############################

  ##########
  # Maybe decrpyt this file or values with a TPM pk or password
  #########

  ############### Secrets File ################
  echo 'cat > /tmp/openstack-env.sh <<EOF' >> ${kickstart_file}
  cat /tmp/openstack-env.sh >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  ###############################
}

function initialKickstartSetup {
  vm=$1
  printf -v vm_type_n '%s\n' "${vm//[[:digit:]]/}"
  vm_type=$(tr -dc '[[:print:]]' <<< "$vm_type_n")

  if [[ $HYPERVISOR_DEBUG == 1 ]]; then
    #### use random root password from install
    rootpwd=`cat /home/admin/rootpw`
    ######
  else
    #### Use autogen password
    HOWLONG=15 ## the number of characters
    rootpwd=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
  fi

  ADMIN_PWD=`cat /root/env_admin_pwd`

  ### load file contents
  PROJECT_CONFIG_FILE=`cat /tmp/project_config.sh`
  INIT_SCRIPT_FILE=`cat /tmp/init-cloud_common.sh`
  VM_FUNCTIONS_FILE=`cat /tmp/vm_functions.sh`
  ###

  rm -rf ${KICKSTART_DIR}/centos-8-kickstart-$vm.cfg
  cp ${KICKSTART_DIR}/centos-8-kickstart-cloud_common.cfg ${KICKSTART_DIR}/centos-8-kickstart-$vm.cfg
  echo "copied kickstart -> ${KICKSTART_DIR}/centos-8-kickstart-cloud_common.cfg to -> ${KICKSTART_DIR}/centos-8-kickstart-$vm.cfg"
  kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-${vm}.cfg
  echo "kickstart file -> ${kickstart_file}"
  sed -i 's/{HOST}/'$vm'/g' ${kickstart_file}
  sed -i 's/{TYPE}/'$vm_type'/g' ${kickstart_file}
  sed -i 's/{PROJECT_CONFIG_FILE}/'$PROJECT_CONFIG_FILE'/g' ${kickstart_file}
  sed -i 's/{INIT_SCRIPT_FILE}/'$INIT_SCRIPT_FILE'/g' ${kickstart_file}
  sed -i 's/{VM_FUNCTIONS_FILE}/'$VM_FUNCTIONS_FILE'/g' ${kickstart_file}
#  sed -i 's/{GITHUB_TOKEN}/'$GITHUB_TOKEN'/g' ${kickstart_file}
  sed -i 's/{GITHUB_USER}/'$GITHUB_USER'/g' ${kickstart_file}
  sed -i 's/{GENERATED_PWD}/'$rootpwd'/g' ${kickstart_file}
  sed -i 's/{CENTOS_ADMIN_PWD}/'$ADMIN_PWD'/g' ${kickstart_file}
  sed -i 's/{NTP_SERVER}/'$GATEWAY_ROUTER_IP'/g' ${kickstart_file}
  sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' ${kickstart_file}
  networkInformation ${kickstart_file} ${vm_type} ${vm}
}

function prepareEnv {

  dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
  sudo yum install epel-release -y
  sudo yum install -y rsync genisoimage pykickstart isomd5sum make python2 gcc yum-utils createrepo syslinux bzip2 curl file sshpass

  if [ -f "/tmp/centos8.iso" ]; then
    return;
  fi

  echo "Using CentOS 8"
  curl -o /tmp/centos8.iso $LINUX_OS -k -s
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
  echo '%end' >> ${kickstart_file}
  echo 'eula --agreed' >> ${kickstart_file}
  echo 'reboot --eject' >> ${kickstart_file}
  #########

  sudo rm -rf /var/tmp/${vm_name}
  mkdir /centos
  sudo mount -t iso9660 -o loop /tmp/centos8.iso /centos
  sudo mkdir -p /var/tmp/${vm_name}
  sudo rsync -q -a /centos/ /var/tmp/${vm_name}
  sudo umount /centos
  rm -rf /centos

  cp ${kickstart_file} /var/tmp/${vm_name}/ks.cfg
  cp ${KICKSTART_DIR}/isolinux-centos8.cfg /var/tmp/${vm_name}/isolinux/isolinux.cfg

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
    -quiet \
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
  cockpitCerts ${kickstart_file}
  ##########################

  ############## common misc items
  commonItems ${kickstart_file}
  ##########################

  #####################################
  closeOutAndBuildKickstartAndISO ${kickstart_file} ${vm_name}
}

function buildAndPushOpenstackSetupISO {

  ############### kickstart init
  initialKickstartSetup "kolla"
  ###########################

  ########### common certs
  cockpitCerts ${kickstart_file}
  ##########################

  ############## common misc items
  commonItems ${kickstart_file}
  ##########################

  ############ certs to enable SSL on VNC
  echo 'cat > /tmp/haproxy.pem <<EOF' >> ${kickstart_file}
  cat /root/.ssh/id_rsa.crt >> ${kickstart_file}
  cat /root/.ssh/id_rsa.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/haproxy-internal.pem <<EOF' >> ${kickstart_file}
  cat /root/.ssh/id_rsa.crt >> ${kickstart_file}
  cat /root/.ssh/id_rsa.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/internal-ca.pem <<EOF' >> ${kickstart_file}
  cat /root/.ssh/id_rsa.crt >> ${kickstart_file}
  cat /root/.ssh/id_rsa.key >> ${kickstart_file}
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
}
