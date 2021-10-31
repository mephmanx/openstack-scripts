#!/bin/bash

source /tmp/openstack-scripts/network-functions.sh
source /tmp/project_config.sh

LINUX_OS="https://$GATEWAY_ROUTER_IP/isos/linux.iso"
KICKSTART_DIR=/tmp/openstack-scripts

IFS=

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
}

function initialKickstartSetup {
  vm=$1
  printf -v vm_type_n '%s\n' "${vm//[[:digit:]]/}"
  vm_type=$(tr -dc '[[:print:]]' <<< "$vm_type_n")
  rootpwd=`cat /root/env_admin_pwd`
  ADMIN_PWD=`cat /home/admin/env_osuser_pwd`

  rm -rf ${KICKSTART_DIR}/centos-8-kickstart-$vm.cfg
  cp ${KICKSTART_DIR}/centos-8-kickstart-cloud_common.cfg ${KICKSTART_DIR}/centos-8-kickstart-$vm.cfg
  echo "copied kickstart -> ${KICKSTART_DIR}/centos-8-kickstart-cloud_common.cfg to -> ${KICKSTART_DIR}/centos-8-kickstart-$vm.cfg"
  kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-${vm}.cfg
  echo "kickstart file -> ${kickstart_file}"
  sed -i 's/{HOST}/'$vm'/g' ${kickstart_file}
  sed -i 's/{TYPE}/'$vm_type'/g' ${kickstart_file}
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

  if [ -f "/tmp/linux.iso" ]; then
    return;
  fi

  echo "Linux ISO not found, downloading..."
  curl -o /tmp/linux.iso $LINUX_OS -k -s
}

function closeOutAndBuildKickstartAndISO {
  kickstart_file=$1
  vm_name=$2
  working_dir=`pwd`
  IFS=' ' read -r -a embedded_files <<< "$3"
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
  sudo mount -t iso9660 -o loop /tmp/linux.iso /centos
  sudo mkdir -p /var/tmp/${vm_name}
  sudo rsync -q -a /centos/ /var/tmp/${vm_name}
  sudo umount /centos
  rm -rf /centos

  cp ${kickstart_file} /var/tmp/${vm_name}/ks.cfg
  cp ${KICKSTART_DIR}/isolinux.cfg /var/tmp/${vm_name}/isolinux/isolinux.cfg

  #### add embedded files to iso
  ## file must exist on filesystem
  ##  It will be added to a /embedded directory.
  ##  Contents of this directory will be copied to the /tmp directory during install
  mkdir /var/tmp/${vm_name}/embedded
  for embed_file in "${embedded_files[@]}";
  do
    if [ -f "$embed_file" ]; then
      IFS='/' read -ra file_parts <<< "$embed_file"
      length=${#file_parts[@]}
      echo "copying file -> $embed_file to /var/tmp/${vm_name}/embedded/${file_parts[length - 1]}"
      cp $embed_file /var/tmp/${vm_name}/embedded/${file_parts[length - 1]}
    fi
  done
  #####

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

  ############## common misc items
  commonItems ${kickstart_file}
  ##########################

  #####################################
  embed_files=('/tmp/openstack-scripts/vm_functions.sh'
                '/tmp/project_config.sh'
                '/root/.ssh/id_rsa.crt'
                '/root/.ssh/id_rsa.key'
                '/root/.ssh/wildcard.crt'
                '/root/.ssh/wildcard.key'
                "/tmp/openstack-scripts/$vm_type.sh"
                '/tmp/openstack-scripts/init-cloud_common.sh'
                '/tmp/openstack-env.sh')

  printf -v embed_files_string '%s ' "${embed_files[@]}"
  closeOutAndBuildKickstartAndISO ${kickstart_file} ${vm_name} $embed_files_string
}

function buildAndPushOpenstackSetupISO {

  ############### kickstart init
  initialKickstartSetup "kolla"
  ###########################

  ############## common misc items
  commonItems ${kickstart_file}
  ##########################

  ############ certs to enable SSL on VNC
  echo 'cat > /tmp/haproxy.pem <<EOF' >> ${kickstart_file}
  cat /root/.ssh/wildcard.crt >> ${kickstart_file}
  cat /root/.ssh/wildcard.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/haproxy-internal.pem <<EOF' >> ${kickstart_file}
  cat /root/.ssh/wildcard.crt >> ${kickstart_file}
  cat /root/.ssh/wildcard.key >> ${kickstart_file}
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

  #####################################
  embed_files=('/tmp/magnum.qcow2'
                '/tmp/trove_instance.img'
                '/tmp/trove_db.img'
                '/tmp/terraform_cf.zip'
                '/tmp/host_list'
                '/root/.ssh/id_rsa.crt'
                '/root/.ssh/id_rsa.key'
                '/root/.ssh/wildcard.crt'
                '/root/.ssh/wildcard.key'
                '/tmp/storage_hosts'
                '/tmp/openstack-scripts/kolla.sh'
                '/tmp/openstack-scripts/globals.yml'
                '/tmp/openstack-scripts/vm_functions.sh'
                '/tmp/openstack-env.sh'
                '/tmp/openstack-scripts/init-cloud_common.sh'
                '/tmp/project_config.sh')

  printf -v embed_files_string '%s ' "${embed_files[@]}"
  closeOutAndBuildKickstartAndISO ${kickstart_file} "kolla" $embed_files_string
}
