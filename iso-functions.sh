#!/bin/bash

. ./vm-configurations.sh
. ./project_config.sh

KICKSTART_DIR=/tmp/openstack-scripts

IFS=

function initialKickstartSetup {
  vm=$1
  printf -v vm_type_n '%s\n' "${vm//[[:digit:]]/}"
  vm_type=$(tr -dc '[:print:]' <<< "$vm_type_n")
  if [ "$vm_type" != "kolla" ]; then
    rm -rf ${KICKSTART_DIR}/centos-8-kickstart-"$vm".cfg
    cp ${KICKSTART_DIR}/centos-8-kickstart-cloud_common.cfg ${KICKSTART_DIR}/centos-8-kickstart-"$vm".cfg
    kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-${vm}.cfg
  else
    rm -rf ${KICKSTART_DIR}/centos-8-kickstart-jumpserver-ks.cfg
    cp ${KICKSTART_DIR}/centos-8-kickstart-jumpserver.cfg ${KICKSTART_DIR}/centos-8-kickstart-jumpserver-ks.cfg
    kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-jumpserver-ks.cfg
  fi
  echo "$kickstart_file"
  sed -i "s/{HOST}/$vm/g" "$kickstart_file"
}

function closeOutAndBuildKickstartAndISO {
  kickstart_file=$1
  vm_name=$2
  working_dir=$(pwd)
  IFS=' ' read -r -a embedded_files <<< "$3"

  sudo rm -rf /var/tmp/"${vm_name}"
  mkdir /centos
  sudo mount -t iso9660 -o loop /tmp/linux.iso /centos
  sudo mkdir -p /var/tmp/"${vm_name}"
  sudo mkdir -p /var/tmp/"${vm_name}"/ks_configs
  sudo rsync -q -a /centos/ /var/tmp/"${vm_name}"
  sudo umount /centos
  rm -rf /centos

  cp "${kickstart_file}" /var/tmp/"${vm_name}"/ks.cfg
  cp /tmp/configs/*.cfg /var/tmp/"${vm_name}"/ks_configs
  if [[ "$vm_name" == "openstack" ]]; then
    cp ${KICKSTART_DIR}/isolinux-openstack.cfg /var/tmp/"${vm_name}"/isolinux/isolinux.cfg
  else
    cp ${KICKSTART_DIR}/isolinux.cfg /var/tmp/"${vm_name}"/isolinux/isolinux.cfg
  fi
  rm -rf /var/tmp/"$vm_name"/embedded/embedded_files

  #### add embedded files to iso
  ## file must exist on filesystem
  ##  It will be added to a /embedded directory.
  ##  Contents of this directory will be copied to the /tmp directory during install
  for embed_file in "${embedded_files[@]}";
  do
    if [ -f "$embed_file" ]; then
      IFS='/' read -ra file_parts <<< "$embed_file"
      length=${#file_parts[@]}
      echo "copying file -> $embed_file to /var/tmp/${vm_name}/embedded/${file_parts[length - 1]}"
      cp "$embed_file" /var/tmp/"${vm_name}"/embedded/"${file_parts[length - 1]}"
    fi
  done
  #####

  if [[ $vm_name == "kolla" ]]; then
  ### add appropriate openstack ansible lib
    \cp -r /tmp/harbor/"$OPENSTACK_VERSION"/pyclient/* /var/tmp/"${vm_name}"/PyRepo
    echo "kolla-ansible==$OPENSTACK_KOLLA_PYLIB_VERSION" >> /var/tmp/"${vm_name}"/ks_configs/python.modules
  #####
  fi

  sudo ksvalidator /var/tmp/"${vm_name}"/ks.cfg
  cd /var/tmp/"${vm_name}" || exit
  rm -rf "${vm_name}"-iso.iso
  sudo mkisofs -o ../"${vm_name}"-iso.iso \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -quiet \
    -iso-level 3 \
    -J -R -V 'CentOS-8-x86_64' .

  cd /var/tmp/ || exit
  sudo implantisomd5 "${vm_name}"-iso.iso
  if [[ "$vm_name" != "kolla" ]]; then
    sudo rm -rf "${kickstart_file}"
  fi
  if [[ "$vm_name" != "openstack" ]]; then
    sudo rm -rf /var/tmp/"${vm_name}"
  fi
  cd "$working_dir" || exit
}

function buildAndPushVMTypeISO {
  vm_name=$1
  ############### kickstart init
  initialKickstartSetup "${vm_name}"
  ###########################

  #####################################
  embed_files=('/tmp/openstack-scripts/vm_functions.sh'
                '/tmp/openstack-scripts/project_config.sh'
                '/tmp/docker-repo.tar')

  printf -v embed_files_string '%s ' "${embed_files[@]}"
  closeOutAndBuildKickstartAndISO "$kickstart_file" "$vm_name" "$embed_files_string"
}

function buildAndPushOpenstackSetupISO {

  ############### kickstart init
  initialKickstartSetup "kolla"
  ###########################

  #####################################
  embed_files=("/tmp/magnum-$MAGNUM_IMAGE_VERSION.qcow2"
                "/tmp/trove_instance-$UBUNTU_VERSION.img"
                "/tmp/trove_db-$TROVE_OPENSTACK_VERSION.img"
                "/tmp/terraform_cf-$CF_ATTIC_TERRAFORM_VERSION.zip"
                '/tmp/cirros-0.5.1-x86_64-disk.img'
                "/tmp/amphora-x64-haproxy-$OPENSTACK_VERSION.qcow2"
                '/tmp/openstack-scripts/init-jumpserver.sh'
                "/tmp/harbor/$OPENSTACK_VERSION/globals.yml"
                '/tmp/openstack-scripts/vm_functions.sh'
                '/tmp/cf-templates.zip'
                '/tmp/stratos-console.zip'
                "/tmp/homebrew-$CF_BBL_INSTALL_TERRAFORM_VERSION.tar"
                "/tmp/cf_deployment-$CF_DEPLOY_VERSION.zip"
                '/tmp/openstack-scripts/project_config.sh'
                "/tmp/bosh-$STEMCELL_STAMP.tgz")

  IFS=$'\n'
  for stemcell in /tmp/stemcell-*-"$STEMCELL_STAMP".tgz;
  do
    embed_files+=("$stemcell")
  done
  ####

  printf -v embed_files_string '%s ' "${embed_files[@]}"
  closeOutAndBuildKickstartAndISO "${kickstart_file}" "kolla" "$embed_files_string"
}
