#!/bin/bash

. ./vm-configurations.sh
. ./project_config.sh

KICKSTART_DIR=/tmp/openstack-scripts

IFS=

function initialKickstartSetup {
  vm=$1
  printf -v vm_type_n '%s\n' "${vm//[[:digit:]]/}"
  vm_type=$(tr -dc '[:print:]' <<< "$vm_type_n")
  rm -rf ${KICKSTART_DIR}/centos-8-kickstart-"$vm".cfg
  if [ "$vm_type" == "kolla" ]; then
    cp ${KICKSTART_DIR}/centos-8-kickstart-kolla.cfg ${KICKSTART_DIR}/centos-8-kickstart-"$vm".cfg
  else
    cp ${KICKSTART_DIR}/centos-8-kickstart-cloud_common.cfg ${KICKSTART_DIR}/centos-8-kickstart-"$vm".cfg
  fi
  kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-${vm}.cfg
  sed -i "s/{HOST}/$vm/g" "$kickstart_file"
  sed -i "s/{TYPE}/$vm_type/g" "$kickstart_file"
  networkInformation "$kickstart_file" "$vm_type" "$vm"
}

function closeOutAndBuildKickstartAndISO {
  kickstart_file=$1
  vm_name=$2
  working_dir=$(pwd)
  IFS=' ' read -r -a embedded_files <<< "$3"
  #### to allow certs to print right
  IFS=
  #######

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
  if [[ $vm_name == "openstack" ]]; then
    cp ${KICKSTART_DIR}/isolinux-openstack.cfg /var/tmp/"${vm_name}"/isolinux/isolinux.cfg
  else
    cp ${KICKSTART_DIR}/isolinux.cfg /var/tmp/"${vm_name}"/isolinux/isolinux.cfg
  fi

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
  sudo rm -rf /var/tmp/"${vm_name}"
  sudo rm -rf "${kickstart_file}"
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
                '/tmp/docker-repo.tar'
                "/tmp/openstack-scripts/$vm_type.sh"
                '/tmp/openstack-setup/openstack-env.sh')

  printf -v embed_files_string '%s ' "${embed_files[@]}"
  closeOutAndBuildKickstartAndISO "$kickstart_file" "$vm_name" "$embed_files_string"
}

function buildAndPushOpenstackSetupISO {

  ############### kickstart init
  initialKickstartSetup "kolla"
  ###########################

  ########## add host trust script
  touch /tmp/host-trust.sh
  { cat /tmp/dns_hosts; cat /tmp/additional_hosts; } >> /tmp/host-trust.sh
  echo  "$1" >> /tmp/host-trust.sh
  #####################

  ############ control hack script
  touch /tmp/control-trust.sh
  echo  "$2" >> /tmp/control-trust.sh
  #################################

  ############## host count
  touch /tmp/host_count
  echo  "$3" >> /tmp/host_count
  #########################

  #####################################
  embed_files=("/tmp/magnum-$MAGNUM_IMAGE_VERSION.qcow2"
                '/tmp/host-trust.sh'
                '/tmp/control-trust.sh'
                '/tmp/host_count'
                "/tmp/trove_instance-$UBUNTU_VERSION.img"
                "/tmp/trove_db-$TROVE_DB_VERSION.img"
                "/tmp/terraform_cf-$CF_ATTIC_TERRAFORM_VERSION.zip"
                '/tmp/host_list'
                '/tmp/storage_hosts'
                '/tmp/cirros-0.5.1-x86_64-disk.img'
                "/tmp/amphora-x64-haproxy-$OPENSTACK_VERSION-$AMPHORA_VERSION.qcow2"
                '/tmp/openstack-scripts/kolla.sh'
                "/tmp/harbor/$OPENSTACK_VERSION/globals.yml"
                '/tmp/openstack-scripts/vm_functions.sh'
                '/tmp/openstack-setup/openstack-env.sh'
                '/tmp/cf-templates.zip'
                "/tmp/cf_deployment-$CF_DEPLOY_VERSION.zip"
                '/tmp/openstack-scripts/project_config.sh'
                "/tmp/bosh-$STEMCELL_STAMP.tgz")

  IFS=$'\n'
  for stemcell in /tmp/stemcell-*-"$STEMCELL_STAMP".tgz;
  do
    embed_files+=("$stemcell")
  done
  ####

  ##### if homebrew cache is available
  if [ -f "/tmp/homebrew-$CF_BBL_INSTALL_TERRAFORM_VERSION.tar" ]; then
    embed_files+=("/tmp/homebrew-$CF_BBL_INSTALL_TERRAFORM_VERSION.tar")
  fi
  #####

  printf -v embed_files_string '%s ' "${embed_files[@]}"
  closeOutAndBuildKickstartAndISO "${kickstart_file}" "kolla" "$embed_files_string"

  rm -rf /tmp/host_count
  rm -rf /tmp/control-trust.sh
  rm -rf /tmp/host-trust.sh
  rm -rf /tmp/host_list
  rm -rf /tmp/storage_hosts
}

function networkInformation {
  kickstart_file=$1
  vm_type=$2
  host=$3

  if [[ "kolla" != "$vm_type" ]]; then
    echo "$host" >> /tmp/host_list
  else
    echo "" >> /tmp/host_list
  fi

  vmstr=$(vm_definitions "$vm_type")
  vm_str=${vmstr//[$'\t\r\n ']}

  network_string=$(parse_json "$vm_str" "network_string")

  IFS=',' read -r -a net_array <<< "$network_string"
  network_lines=()
  ct=1
  addresses=()
  default_flag="0"
  for element in "${net_array[@]}"
  do
#    default_set="--nodefroute"
    default_set=""
    if [[ "${element}" =~ .*"static".* ]]; then
      ##check if internal or external network and set ip/gateway accordingly
      ip_addr="${NETWORK_PREFIX}.${CORE_VM_START_IP}"

      if ! grep -q "$host" "/tmp/dns_hosts"; then
          #add localhost entry
        echo "runuser -l root -c  'echo "$ip_addr $host" >> /etc/hosts;'" >> /tmp/dns_hosts
        addresses+=("$ip_addr")
      fi

        # If storage address, add to array to build rings later
      if [[ "$vm_type" == "storage" ]]; then
          echo "$ip_addr" >> /tmp/storage_hosts
      fi

      if [[ $default_flag == "0" ]]; then
        default_set=""
        network_lines+=("network  --device=enp${ct}s0 --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$GATEWAY_ROUTER_IP --netmask=$NETMASK --nameserver=$IDENTITY_VIP ${default_set}\n")
        default_flag="1"
      else
        network_lines+=("network  --device=enp${ct}s0 --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$GATEWAY_ROUTER_IP --netmask=$NETMASK --nameserver=$IDENTITY_VIP ${default_set}\n")
      fi

      ((CORE_VM_START_IP++))

    #not static, do DHCP
    else
      network_lines+=("network  --device=enp${ct}s0 --bootproto=dhcp --noipv6 --onboot=yes --activate --nodefroute\n")
    fi
    ((ct++))
  done

  for ip in "${addresses[@]}"
  do
    echo "runuser -l root -c  'ssh-keyscan -H $ip >> ~/.ssh/known_hosts';" >> /tmp/additional_hosts
  done

  printf -v net_line_string '%s ' "${network_lines[@]}"
  sed -i "s/{NETWORK}/$net_line_string/g" "${kickstart_file}"
}