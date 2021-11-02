#!/bin/bash
#can ONLY be run as root!  sudo to root

source ./vm_functions.sh
source ./iso-functions.sh
### openstack-env needs to be in same directory as this script
rm -rf /tmp/openstack-env.sh
cp $1 /tmp/openstack-env.sh
source /tmp/openstack-env.sh

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

#### generate random password and reload env
export RANDOM_PWD=`date +%s | sha256sum | base64 | head -c 32 ; echo`
######

########### replace variables in project_config
sed -i 's/{CENTOS_ADMIN_PWD}/'$RANDOM_PWD'/g' ${kickstart_file}
sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' ${kickstart_file}
###########################

## download files to be embedded
if [ ! -f "/tmp/amphora-x64-haproxy.qcow2" ]; then
  ############# build octavia image
  yum install -y debootstrap qemu-img git e2fsprogs policycoreutils-python-utils
  git clone https://opendev.org/openstack/octavia -b master /tmp/octavia
  pip3 install  --trusted-host pypi.org --trusted-host files.pythonhosted.org diskimage-builder
  chmod +x /tmp/octavia/diskimage-create/diskimage-create.sh
  chown -R stack /tmp/octavia/diskimage-create/diskimage-create.sh
  pwd=`pwd`
  cd /tmp/octavia/diskimage-create;
  ./diskimage-create.sh;
  cd $pwd
  cp /tmp/octavia/diskimage-create/amphora-x64-haproxy.qcow2 /tmp/amphora-x64-haproxy.qcow2
fi

if [ ! -f "/tmp/pfSense.gz" ]; then
  wget -O /tmp/pfSense.gz ${PFSENSE}
fi
cp /tmp/pfSense.gz /tmp/pfSense-CE-memstick-ADI.img.gz
gunzip -f /tmp/pfSense-CE-memstick-ADI.img.gz

if [ ! -f "/tmp/harbor.tgz" ]; then
  wget -O /tmp/harbor.tgz ${HARBOR}
fi

if [ ! -f "/tmp/magnum.qcow2" ]; then
  wget -O /tmp/magnum.qcow2 ${MAGNUM_IMAGE}
fi

if [ ! -f "/tmp/terraform_cf.zip" ]; then
  wget -O /tmp/terraform_cf.zip ${CF_ATTIC_TERRAFORM}
fi

if [ ! -f "/tmp/trove_instance.img" ]; then
  wget -O /tmp/trove_instance.img ${TROVE_INSTANCE_IMAGE}
fi

if [ ! -f "/tmp/trove_db.img" ]; then
  wget -O /tmp/trove_db.img ${TROVE_DB_IMAGE}
fi

if [ ! -f "/tmp/libtpms.zip" ]; then
  wget -O /tmp/libtpms.zip ${LIBTPMS_GIT}
fi

if [ ! -f "/tmp/swtpm.zip" ]; then
  wget -O /tmp/swtpm.zip ${SWTPM_GIT}
fi

if [ ! -f "/tmp/cf-templates.zip" ]; then
  wget -O /tmp/cf-templates.zip ${BOSH_OPENSTACK_ENVIRONMENT_TEMPLATES}
fi

if [ ! -f "/tmp/cf_deployment.zip" ]; then
  wget -O /tmp/cf_deployment.zip ${CF_DEPLOYMENT}
fi
####
rm -rf /tmp/repo.zip
zip -r /tmp/repo.zip ./* -x "*.git" -x "tmp/*"

embed_files=('/tmp/magnum.qcow2'
              '/tmp/pfSense-CE-memstick-ADI.img'
              '/tmp/harbor.tgz'
              '/tmp/amphora-x64-haproxy.qcow2'
              '/tmp/terraform_cf.zip'
              '/tmp/repo.zip'
              '/tmp/openstack-env.sh'
              '/tmp/linux.iso'
              '/tmp/trove_instance.img'
              '/tmp/trove_db.img'
              '/tmp/libtpms.zip'
              '/tmp/swtpm.zip'
              '/tmp/cf-templates.zip'
              '/tmp/cf_deployment.zip'
              '/tmp/project_config.sh')

printf -v embed_files_string '%s ' "${embed_files[@]}"
closeOutAndBuildKickstartAndISO "${kickstart_file}" "openstack" $embed_files_string

## cleanup work dir
rm -rf ./tmp