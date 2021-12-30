#!/bin/bash
#can ONLY be run as root!  sudo to root

### openstack-env needs to be in same directory as this script
rm -rf /tmp/openstack-env.sh
cp $1 /tmp/openstack-env.sh
source /tmp/openstack-env.sh
source vm_functions.sh
source iso-functions.sh

rm -rf /var/tmp/openstack-iso.iso

## make sure libs are installed
yum install -y wget zip

## prep project config by replacing nested vars
prep_project_config
source /tmp/project_config.sh
#########

### build centos iso if not exist
#if [ ! -f "/tmp/linux.iso" ]; then
#  pwd=`pwd`
#  git clone https://github.com/mephmanx/centos-8-minimal.git /tmp/centos-8-minimal
#  if [ ! -f "/tmp/CentOS-Stream.iso" ]; then
#    curl -o /tmp/CentOS-Stream.iso $CENTOS_BASE -L
#  fi
#  cd /tmp/centos-8-minimal
#  ./create_iso_in_container.sh "/tmp/CentOS-Stream.iso"
#  mv /tmp/centos-8-minimal/CentOS-x86_64-minimal.iso /tmp/linux.iso
#  cd $pwd
#fi

mkdir ./tmp
cp centos-8-kickstart-openstack.cfg ./tmp

IFS=
kickstart_file=./tmp/centos-8-kickstart-openstack.cfg
NEWPWD=$(generate_random_pwd)
echo $NEWPWD > /tmp/current_pwd
########### replace variables in project_config
## generate random hostname suffix
HOWLONG=5 ## the number of characters
HOSTNAME_SUFFIX=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
sed -i 's/{HOSTNAME_SUFFIX}/'$HOSTNAME_SUFFIX'/g' ${kickstart_file}
###
sed -i 's/{CENTOS_ADMIN_PWD}/'$NEWPWD'/g' ${kickstart_file}
###########################

## download files to be embedded
if [ ! -f "/tmp/amphora-x64-haproxy-$AMPHORA_VERSION.qcow2" ]; then
  ############# build octavia image
  yum install -y debootstrap qemu-img git e2fsprogs policycoreutils-python-utils
  git clone https://opendev.org/openstack/octavia -b master /tmp/octavia
  pip3 install  --trusted-host pypi.org --trusted-host files.pythonhosted.org diskimage-builder
  chmod +x /tmp/octavia/diskimage-create/diskimage-create.sh
  pwd=`pwd`
  cd /tmp/octavia/diskimage-create;
  ./diskimage-create.sh;
  cd $pwd
  cp /tmp/octavia/diskimage-create/amphora-x64-haproxy.qcow2 /tmp/amphora-x64-haproxy-$AMPHORA_VERSION.qcow2
fi

if [ ! -f "/tmp/pfSense-$PFSENSE_VERSION.gz" ]; then
  wget -O /tmp/pfSense-$PFSENSE_VERSION.gz ${PFSENSE}
fi
cp /tmp/pfSense-$PFSENSE_VERSION.gz /tmp/pfSense-CE-memstick-ADI.img.gz
rm -rf /tmp/pfSense-CE-memstick-ADI.img
gunzip -f /tmp/pfSense-CE-memstick-ADI.img.gz

if [ ! -f "/tmp/harbor-$HARBOR_VERSION.tgz" ]; then
  wget -O /tmp/harbor-$HARBOR_VERSION.tgz ${HARBOR}
fi

if [ ! -f "/tmp/magnum-$MAGNUM_IMAGE_VERSION.qcow2" ]; then
  wget -O /tmp/magnum-$MAGNUM_IMAGE_VERSION.qcow2 ${MAGNUM_IMAGE}
fi

if [ ! -f "/tmp/terraform_cf-$CF_ATTIC_TERRAFORM_VERSION.zip" ]; then
  wget -O /tmp/terraform_cf-$CF_ATTIC_TERRAFORM_VERSION.zip ${CF_ATTIC_TERRAFORM}
fi

if [ ! -f "/tmp/trove_instance-$UBUNTU_VERSION.img" ]; then
  wget -O /tmp/trove_instance-$UBUNTU_VERSION.img ${TROVE_INSTANCE_IMAGE}
fi

if [ ! -f "/tmp/trove_db-$TROVE_DB_VERSION.img" ]; then
  wget -O /tmp/trove_db-$TROVE_DB_VERSION.img ${TROVE_DB_IMAGE}
fi

if [ ! -f "/tmp/libtpms-$SWTPM_VERSION.zip" ]; then
  wget -O /tmp/libtpms-$SWTPM_VERSION.zip ${LIBTPMS_GIT}
fi

if [ ! -f "/tmp/swtpm-$SWTPM_VERSION.zip" ]; then
  wget -O /tmp/swtpm-$SWTPM_VERSION.zip ${SWTPM_GIT}
fi

if [ ! -f "/tmp/cf-templates.zip" ]; then
  wget -O /tmp/cf-templates.zip ${BOSH_OPENSTACK_ENVIRONMENT_TEMPLATES}
fi

if [ ! -f "/tmp/cf_deployment-$CF_DEPLOY_VERSION.zip" ]; then
  wget -O /tmp/cf_deployment-$CF_DEPLOY_VERSION.zip ${CF_DEPLOYMENT}
fi

if [ ! -f "/tmp/docker-compose-$DOCKER_COMPOSE_VERSION" ]; then
  wget -O /tmp/docker-compose-$DOCKER_COMPOSE_VERSION ${DOCKER_COMPOSE}
fi

rm -rf /tmp/repo.zip
zip -r /tmp/repo.zip ./* -x "*.git" -x "tmp/*" -x "build*" -x "*openstack.cfg"

### download director & jumpbox stemcell
if [ ! -f "/tmp/bosh-$STEMCELL_STAMP.tgz" ]; then
  curl -L https://bosh.io/d/stemcells/bosh-openstack-kvm-$BOSH_STEMCELL-go_agent --output /tmp/bosh-$STEMCELL_STAMP.tgz > /dev/null
fi

##### build openstack vm keys
ssh-keygen -t rsa -b 4096 -C "openstack-setup" -N "" -f /tmp/openstack-setup.key <<<y 2>&1 >/dev/null
###########

## setup cert directory
rm -rf /tmp/id_rsa*
rm -rf /tmp/wildcard.*
CERT_DIR="/tmp"

### CA key pass
NEWPW=$(generate_random_pwd)
###

#### generate ssh keys
# create CA cert before the network goes down to add ip to SAN
create_ca_cert $NEWPW $CERT_DIR

### initial wildcard cert
create_server_cert $NEWPW $CERT_DIR "wildcard" "*"
#############

embed_files=("/tmp/magnum-$MAGNUM_IMAGE_VERSION.qcow2"
              '/tmp/pfSense-CE-memstick-ADI.img'
              "/tmp/harbor-$HARBOR_VERSION.tgz"
              "/tmp/amphora-x64-haproxy-$AMPHORA_VERSION.qcow2"
              "/tmp/terraform_cf-$CF_ATTIC_TERRAFORM_VERSION.zip"
              '/tmp/openstack-setup.key'
              '/tmp/openstack-setup.key.pub'
              '/tmp/id_rsa.pub'
              '/tmp/id_rsa.key'
              '/tmp/id_rsa.crt'
              '/tmp/id_rsa'
              '/tmp/wildcard.crt'
              '/tmp/wildcard.key'
              '/tmp/repo.zip'
              '/tmp/openstack-env.sh'
              '/tmp/linux.iso'
              "/tmp/trove_instance-$UBUNTU_VERSION.img"
              "/tmp/trove_db-$TROVE_DB_VERSION.img"
              "/tmp/libtpms-$SWTPM_VERSION.zip"
              "/tmp/swtpm-$SWTPM_VERSION.zip"
              '/tmp/cf-templates.zip'
              "/tmp/cf_deployment-$CF_DEPLOY_VERSION.zip"
              "/tmp/docker-compose-$DOCKER_COMPOSE_VERSION"
              '/tmp/project_config.sh'
              "/tmp/bosh-$STEMCELL_STAMP.tgz")

IFS=' ' read -r -a stemcell_array <<< "$CF_STEMCELLS"
for stemcell in "${stemcell_array[@]}";
do
  if [ ! -f "/tmp/stemcell-$stemcell-$STEMCELL_STAMP.tgz" ]; then
    curl -L https://bosh.io/d/stemcells/bosh-openstack-kvm-$stemcell-go_agent --output /tmp/stemcell-$stemcell-$STEMCELL_STAMP.tgz > /dev/null
  fi
  embed_files+=("/tmp/stemcell-$stemcell-$STEMCELL_STAMP.tgz")
done
####

#### if homebrew cache is available
if [ ! -f "/tmp/homebrew-$CF_BBL_INSTALL_TERRAFORM_VERSION.tar" ]; then
  docker pull mephmanx/homebrew-cache:latest
  docker run --rm -v /tmp:/tmp/export mephmanx/homebrew-cache $CF_BBL_INSTALL_TERRAFORM_VERSION
fi
embed_files+=("/tmp/homebrew-$CF_BBL_INSTALL_TERRAFORM_VERSION.tar")
####

printf -v embed_files_string '%s ' "${embed_files[@]}"
closeOutAndBuildKickstartAndISO "${kickstart_file}" "openstack" $embed_files_string

## cleanup work dir
rm -rf ./tmp