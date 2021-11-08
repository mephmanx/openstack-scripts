#!/bin/bash

source /tmp/openstack-scripts/network-functions.sh
source /tmp/openstack-scripts/vm-configurations.sh
source /tmp/openstack-scripts/vm_functions.sh
source /tmp/project_config.sh

NETMASK="255.255.255.0"
LINUX_OS="https://$GATEWAY_ROUTER_IP/isos/linux.iso"
KICKSTART_DIR=/tmp/openstack-scripts

IFS=

function initialKickstartSetup {
  vm=$1
  printf -v vm_type_n '%s\n' "${vm//[[:digit:]]/}"
  vm_type=$(tr -dc '[[:print:]]' <<< "$vm_type_n")
  ADMIN_PWD=`cat /root/env_admin_pwd`

  rm -rf ${KICKSTART_DIR}/centos-8-kickstart-$vm.cfg
  cp ${KICKSTART_DIR}/centos-8-kickstart-cloud_common.cfg ${KICKSTART_DIR}/centos-8-kickstart-$vm.cfg
  echo "copied kickstart -> ${KICKSTART_DIR}/centos-8-kickstart-cloud_common.cfg to -> ${KICKSTART_DIR}/centos-8-kickstart-$vm.cfg"
  kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-${vm}.cfg
  echo "kickstart file -> ${kickstart_file}"
  sed -i 's/{HOST}/'$vm'/g' ${kickstart_file}
  sed -i 's/{TYPE}/'$vm_type'/g' ${kickstart_file}
  sed -i 's/{GENERATED_PWD}/'$(generate_random_pwd)'/g' ${kickstart_file}
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

  sudo rm -rf /var/tmp/${vm_name}
  mkdir /centos
  sudo mount -t iso9660 -o loop /tmp/linux.iso /centos
  sudo mkdir -p /var/tmp/${vm_name}
  sudo rsync -q -a /centos/ /var/tmp/${vm_name}
  sudo umount /centos
  rm -rf /centos

  cp ${kickstart_file} /var/tmp/${vm_name}/ks.cfg
  if [[ $vm_name == "openstack" ]]; then
    cp ${KICKSTART_DIR}/isolinux-openstack.cfg /var/tmp/${vm_name}/isolinux/isolinux.cfg
  else
    cp ${KICKSTART_DIR}/isolinux.cfg /var/tmp/${vm_name}/isolinux/isolinux.cfg
  fi

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
  pwd2=`pwd`
  if [[ "openstack" == $vm_name ]]; then
    if [[ -z `which convert` ]]; then
      git clone https://github.com/ImageMagick/ImageMagick.git /tmp/ImageMagick-7.1.0
      cd /tmp/ImageMagick-7.1.0
      ./configure
      make
    fi
    convert splash.png +dither -colors 16 -depth 4 -resize 640x480\! /var/tmp/${vm_name}/isolinux/splash.png
  fi
  cd $pwd2
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

  #####################################
  embed_files=('/tmp/openstack-scripts/vm_functions.sh'
                '/tmp/project_config.sh'
                '/root/.ssh/id_rsa.crt'
                '/root/.ssh/id_rsa.pub'
                '/tmp/openstack-setup.key'
                '/tmp/openstack-setup.key.pub'
                '/tmp/libtpms.zip'
                '/tmp/swtpm.zip'
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

  ############ certs to enable SSL on VNC
  touch  /tmp/haproxy.pem
  cat /root/.ssh/wildcard.key >> /tmp/haproxy.pem
  cat /root/.ssh/wildcard.crt >> /tmp/haproxy.pem
  cat /root/.ssh/id_rsa.crt >> /tmp/haproxy.pem

  touch /tmp/haproxy-internal.pem
  cat /root/.ssh/wildcard.key >> /tmp/haproxy-internal.pem
  cat /root/.ssh/wildcard.crt >> /tmp/haproxy-internal.pem
  cat /root/.ssh/id_rsa.crt >> /tmp/haproxy-internal.pem

  touch /tmp/internal-ca.pem
  cat /root/.ssh/wildcard.key >> /tmp/internal-ca.pem
  cat /root/.ssh/wildcard.crt >> /tmp/internal-ca.pem
  cat /root/.ssh/id_rsa.crt >> /tmp/internal-ca.pem
  #################################

  ########## add host trust script
  touch /tmp/host-trust.sh
  cat /tmp/dns_hosts >> /tmp/host-trust.sh
  echo  $1 >> /tmp/host-trust.sh
  cat /tmp/additional_hosts >> /tmp/host-trust.sh
  #####################

  ############ control hack script
  touch /tmp/control-trust.sh
  echo  $2 >> /tmp/control-trust.sh
  #################################

  ############## host count
  touch /tmp/host_count
  echo  $3 >> /tmp/host_count
  #########################

  #####################################
  embed_files=('/tmp/magnum.qcow2'
                '/tmp/haproxy.pem'
                '/tmp/haproxy-internal.pem'
                '/tmp/internal-ca.pem'
                '/tmp/host-trust.sh'
                '/tmp/control-trust.sh'
                '/tmp/host_count'
                '/tmp/trove_instance.img'
                '/tmp/trove_db.img'
                '/tmp/terraform_cf.zip'
                '/tmp/host_list'
                '/root/.ssh/id_rsa.crt'
                '/root/.ssh/id_rsa.pub'
                '/tmp/openstack-setup.key'
                '/tmp/openstack-setup.key.pub'
                '/tmp/storage_hosts'
                '/tmp/amphora-x64-haproxy.qcow2'
                '/tmp/openstack-scripts/kolla.sh'
                '/tmp/openstack-scripts/globals.yml'
                '/tmp/openstack-scripts/vm_functions.sh'
                '/tmp/openstack-env.sh'
                '/tmp/openstack-scripts/init-cloud_common.sh'
                '/tmp/libtpms.zip'
                '/tmp/swtpm.zip'
                '/tmp/cf-templates.zip'
                '/tmp/cf_deployment.zip'
                '/tmp/project_config.sh')

  printf -v embed_files_string '%s ' "${embed_files[@]}"
  closeOutAndBuildKickstartAndISO ${kickstart_file} "kolla" $embed_files_string

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

      if ! grep -q $host "/tmp/dns_hosts"; then
          #add localhost entry
        echo "runuser -l root -c  'echo "$ip_addr $host" >> /etc/hosts;'" >> /tmp/dns_hosts
        addresses+=($ip_addr)
      fi

        # If storage address, add to array to build rings later
      if [[ "$vm_type" == "storage" ]]; then
          echo "$ip_addr" >> /tmp/storage_hosts
      fi

      if [[ $default_flag == "0" ]]; then
        default_set=""
        network_lines+=("network  --device=enp${ct}s0 --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$GATEWAY_ROUTER_IP --netmask=$NETMASK --nameserver=$GATEWAY_ROUTER_IP ${default_set}\n")
        default_flag="1"
      else
        network_lines+=("network  --device=enp${ct}s0 --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$GATEWAY_ROUTER_IP --netmask=$NETMASK --nameserver=$GATEWAY_ROUTER_IP ${default_set}\n")
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
  sed -i 's/{NETWORK}/'$net_line_string'/g' ${kickstart_file}
}