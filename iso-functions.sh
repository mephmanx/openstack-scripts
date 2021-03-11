source ./network-functions.sh
source ./portus-env.sh

IFS=
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

function initialKickstartSetup {
  printf -v vm_type_n '%s\n' "${1//[[:digit:]]/}"
  vm_type=$(tr -dc '[[:print:]]' <<< "$vm_type_n")

  rm -rf centos-8-kickstart-$1.cfg
  cp centos-8-kickstart-cloud_common.cfg centos-8-kickstart-$1.cfg
  echo "copied kickstart -> centos-8-kickstart-$vm_type.cfg to -> centos-8-kickstart-$1.cfg"
  kickstart_file=centos-8-kickstart-${1}.cfg
  sed -i 's/{HOST}/'$1'/g' ${kickstart_file}
  sed -i 's/{TYPE}/'$vm_type'/g' ${kickstart_file}
  networkInformation ${kickstart_file} ${vm_type} ${1}
  echo ${kickstart_file}
}

function buildAndPushVMTypeISO {
  ############### kickstart init
  initialKickstartSetup $1
  ###########################

  ########### common certs
  letsEncryptAndCockpitCerts ${kickstart_file}
  ##########################

  #######godaddy settings###############
  echo 'cat > /tmp/api-settings.sh <<EOF' >> ${kickstart_file}
  cat ./api-settings.sh >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  ############# Docker account
  echo 'cat > /tmp/docker.pass <<EOF' >> ${kickstart_file}
  echo ${PORTUS_PASSWORD} >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  ############## passwordless ssh
  echo 'cat > /tmp/openstack-setup.key.pub <<EOF' >> ${kickstart_file}
  cat /tmp/openstack-setup.key.pub >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/openstack-setup.key <<EOF' >> ${kickstart_file}
  cat /tmp/openstack-setup.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  ###############################

  #########portus env##############

  echo 'cat > /tmp/portus-env.sh <<EOF' >> ${kickstart_file}
  cat ./portus-env.sh >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  #######################

  #####################################
  closeOutAndBuildKickstartAndISO ${kickstart_file} ${1}
  esxi-scp -H $HOSTNAME -n /var/tmp/${1}-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos
}

function buildAndPushOpenstackSetupISO {

  ############### kickstart init
  initialKickstartSetup "kolla"
  ###########################

  ########### common certs
  letsEncryptAndCockpitCerts ${kickstart_file}
  ##########################

  echo 'cat > /tmp/backend-cert.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.fullchain >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  echo 'cat > /tmp/backend-key.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/haproxy.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.fullchain >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}
  echo 'cat > /tmp/haproxy-internal.pem <<EOF' >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.fullchain >> ${kickstart_file}
  cat ./certs/lyonsgroup-wildcard.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  #########################################################
  SERVICE_LIST=('Barbican' 'Glance' 'Heat' 'Horizon' 'Keystone' 'Nova' 'Placement' 'Cinder')
  for service in "${SERVICE_LIST[@]}"
  do
    lower_service=${service,,}
    echo "cat > /tmp/${lower_service}-cert.pem <<EOF" >> ${kickstart_file}
    cat ./certs/lyonsgroup-wildcard.fullchain >> ${kickstart_file}
    echo 'EOF' >> ${kickstart_file}
    echo "cat > /tmp/${lower_service}-key.pem <<EOF" >> ${kickstart_file}
    cat ./certs/lyonsgroup-wildcard.key >> ${kickstart_file}
    echo 'EOF' >> ${kickstart_file}
  done
  ############################################

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

  #######godaddy settings###############
  echo 'cat > /tmp/api-settings.sh <<EOF' >> ${kickstart_file}
  cat ./api-settings.sh >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  ############# Docker account
  echo 'cat > /tmp/docker.pass <<EOF' >> ${kickstart_file}
  echo ${PORTUS_PASSWORD} >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  ############## passwordless ssh
  echo 'cat > /tmp/openstack-setup.key.pub <<EOF' >> ${kickstart_file}
  cat /tmp/openstack-setup.key.pub >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  echo 'cat > /tmp/openstack-setup.key <<EOF' >> ${kickstart_file}
  cat /tmp/openstack-setup.key >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  ###############################

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

  #########portus env##############

  echo 'cat > /tmp/portus-env.sh <<EOF' >> ${kickstart_file}
  cat ./portus-env.sh >> ${kickstart_file}
  echo 'EOF' >> ${kickstart_file}

  #######################

  #####################################
  closeOutAndBuildKickstartAndISO ${kickstart_file} "kolla"
  esxi-scp -H $HOSTNAME -n /var/tmp/kolla-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos
}