#!/bin/bash
#can ONLY be run as root!  sudo to root

### openstack-env needs to be in same directory as this script
rm -rf /tmp/openstack-env.sh
cp $1 /tmp/openstack-env.sh
source /tmp/openstack-env.sh
cp project_config.sh /tmp
cp vm_functions.sh /tmp
source vm_functions.sh
## prep project config by replacing nested vars
prep_project_config
source /tmp/project_config.sh
#########
source iso-functions.sh

rm -rf /var/tmp/*

## make sure libs are installed
yum install -y wget zip

rm -rf /tmp/linux.iso
docker pull $DOCKER_LINUX_BUILD_IMAGE
docker run -v /tmp:/opt/mount --rm -ti $DOCKER_LINUX_BUILD_IMAGE bash -c "mv CentOS-x86_64-minimal.iso linux.iso; cp linux.iso /opt/mount"

rm -rf ./tmp
mkdir ./tmp
cp centos-8-kickstart-openstack.cfg ./tmp

IFS=
kickstart_file=./tmp/centos-8-kickstart-openstack.cfg
NEWPWD=$(generate_random_pwd 31)
echo $NEWPWD > /tmp/current_pwd
########### replace variables in project_config
## generate random hostname suffix
HOWLONG=5 ## the number of characters
HOSTNAME_SUFFIX=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
sed -i 's/{HOSTNAME_SUFFIX}/'$HOSTNAME_SUFFIX'/g' ${kickstart_file}
###
sed -i 's/{CENTOS_ADMIN_PWD_123456789012}/'$NEWPWD'/g' ${kickstart_file}
###########################

## download files to be embedded
if [ ! -f "/tmp/amphora-x64-haproxy-$AMPHORA_VERSION.qcow2" ]; then
  ############# build octavia image
  yum -y install epel-release
  yum install -y debootstrap qemu-img git e2fsprogs policycoreutils-python-utils
  git clone https://opendev.org/openstack/octavia -b master /tmp/octavia
  pip3 install  --trusted-host pypi.org --trusted-host files.pythonhosted.org diskimage-builder
  chmod +x /tmp/octavia/diskimage-create/diskimage-create.sh
  pwd=`pwd`
  cd /tmp/octavia/diskimage-create;
  ./diskimage-create.sh;
  cd $pwd
  cp /tmp/octavia/diskimage-create/amphora-x64-haproxy.qcow2 /tmp/amphora-x64-haproxy-$AMPHORA_VERSION.qcow2
  rm -rf /tmp/octavia
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
NEWPW=$(generate_random_pwd 31)
###

#### generate ssh keys
# create CA cert before the network goes down to add ip to SAN
create_ca_cert $NEWPW $CERT_DIR

### initial wildcard cert
create_server_cert $NEWPW $CERT_DIR "wildcard" "*"
#############

if [ ! -f "/tmp/homebrew-$CF_BBL_INSTALL_TERRAFORM_VERSION.tar" ]; then
  docker pull mephmanx/homebrew-cache:latest
  docker run --rm -v /tmp:/tmp/export mephmanx/homebrew-cache $CF_BBL_INSTALL_TERRAFORM_VERSION
fi

IFS=' ' read -r -a stemcell_array <<< "$CF_STEMCELLS"
for stemcell in "${stemcell_array[@]}";
do
  if [ ! -f "/tmp/stemcell-$stemcell-$STEMCELL_STAMP.tgz" ]; then
    curl -L https://bosh.io/d/stemcells/bosh-openstack-kvm-$stemcell-go_agent --output /tmp/stemcell-$stemcell-$STEMCELL_STAMP.tgz > /dev/null
  fi
done
####

if [ ! -f "/tmp/harbor/centos-binary-base-${OPENSTACK_VERSION}.tar" ] && [ ! -f "/tmp/harbor/kolla_${OPENSTACK_VERSION}_rpm_repo.tar.gz" ]; then
    rm -rf /tmp/harbor
    mkdir /tmp/harbor
    rm -rf /out
    mkdir /out
    docker pull mephmanx/os-airgap:latest
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v /out:/out mephmanx/os-airgap:latest
    #### add build images
    mv /out/centos-binary-base-${OPENSTACK_VERSION}.tar /tmp/harbor
    mv /out/kolla_${OPENSTACK_VERSION}_rpm_repo.tar.gz /tmp/harbor
    rm -rf /out
    ### add copied images
    docker pull kolla/centos-source-kuryr-libnetwork:wallaby && docker save kolla/centos-source-kuryr-libnetwork:wallaby >/tmp/harbor/centos-source-kuryr-libnetwork.tar
    docker pull kolla/centos-source-kolla-toolbox:wallaby && docker save kolla/centos-source-kolla-toolbox:wallaby >/tmp/harbor/centos-source-kolla-toolbox.tar
    docker pull kolla/centos-source-zun-compute:wallaby && docker save kolla/centos-source-zun-compute:wallaby >/tmp/harbor/centos-source-zun-compute.tar
    docker pull kolla/centos-source-zun-wsproxy:wallaby && docker save kolla/centos-source-zun-wsproxy:wallaby >/tmp/harbor/centos-source-zun-wsproxy.tar
    docker pull kolla/centos-source-zun-api:wallaby && docker save kolla/centos-source-zun-api:wallaby >/tmp/harbor/centos-source-zun-api.tar
    docker pull kolla/centos-source-zun-cni-daemon:wallaby && docker save kolla/centos-source-zun-cni-daemon:wallaby >/tmp/harbor/centos-source-zun-cni-daemon.tar
    docker pull kolla/centos-binary-fluentd:wallaby && docker save kolla/centos-binary-fluentd:wallaby >/tmp/harbor/centos-binary-fluentd.tar
    docker pull kolla/centos-binary-grafana:wallaby && docker save kolla/centos-binary-grafana:wallaby >/tmp/harbor/centos-binary-grafana.tar
    docker pull kolla/centos-binary-elasticsearch-curator:wallaby && docker save kolla/centos-binary-elasticsearch-curator:wallaby >/tmp/harbor/centos-binary-elasticsearch-curator.tar
fi


./create-pfsense-kvm-iso.sh
./create-cloudsupport-kvm-iso.sh
./create-identity-kvm-iso.sh
./create-cloud-kvm-iso.sh

embed_files=('/tmp/openstack-env.sh'
              '/tmp/project_config.sh'
              '/tmp/openstack-setup.key'
              '/tmp/openstack-setup.key.pub'
              '/tmp/id_rsa.pub'
              '/tmp/id_rsa.key'
              '/tmp/id_rsa.crt'
              '/tmp/id_rsa'
              '/tmp/wildcard.crt'
              '/tmp/wildcard.key'
              "/tmp/libtpms-$SWTPM_VERSION.zip"
              "/tmp/swtpm-$SWTPM_VERSION.zip"
              '/tmp/openstack-scripts/init-openstack.sh'
              '/tmp/openstack-scripts/pf_functions.sh'
              '/tmp/openstack-scripts/pfsense-init.sh'
              '/tmp/openstack-scripts/openstack.sh'
              '/tmp/openstack-scripts/vm_functions.sh'
              '/tmp/openstack-scripts/vm-configurations.sh'
              '/tmp/openstack-scripts/create-cloud-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-cloudsupport-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-identity-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-pfsense-kvm-deploy.sh'
              "/var/tmp/pfSense-CE-memstick-ADI.img")

iso_images="/var/tmp/*.iso"
for img in $iso_images; do
  embed_files+=($img)
done

printf -v embed_files_string '%s ' "${embed_files[@]}"
closeOutAndBuildKickstartAndISO "${kickstart_file}" "openstack" $embed_files_string

isohybrid /var/tmp/openstack-iso.iso
## cleanup work dir
rm -rf ./tmp