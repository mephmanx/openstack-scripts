#!/bin/bash
#can ONLY be run as root!  sudo to root

source /tmp/openstack-setup/openstack-env.sh

rm -rf /tmp/openstack-setup;
rm -rf /tmp/openstack-scripts;

git clone https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/openstack-setup.git /tmp/openstack-setup;
git clone https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/openstack-scripts.git /tmp/openstack-scripts;

cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;

rm -rf /tmp/vm_functions.sh
rm -rf /tmp/openstack-env.sh
cp /tmp/openstack-scripts/vm_functions.sh /tmp
cp /tmp/openstack-setup/openstack-env.sh /tmp

rm -rf /var/tmp/openstack-iso.iso
cd /tmp/openstack-setup

## prep project config by replacing nested vars
source /tmp/vm_functions.sh
prep_project_config
#########

source /tmp/openstack-setup/iso-functions.sh
source /tmp/project_config.sh

IFS=
kickstart_file=centos-8-kickstart-openstack.cfg

#### generate random password and reload env
export RANDOM_PWD=`date +%s | sha256sum | base64 | head -c 32 ; echo`
sed -i 's/{RANDOM_PWD}/'$RANDOM_PWD'/g' /tmp/openstack-setup/openstack-env.sh
source /tmp/openstack-setup/openstack-env.sh
######

########### add passwords in
sed -i 's/{GITHUB_TOKEN}/'$GITHUB_TOKEN'/g' ${kickstart_file}
sed -i 's/{GITHUB_USER}/'$GITHUB_USER'/g' ${kickstart_file}
sed -i 's/{CENTOS_ADMIN_PWD}/'$CENTOS_ADMIN_PWD'/g' ${kickstart_file}
sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' ${kickstart_file}
###########################

############### Secrets file ################
echo 'cat > /tmp/openstack-env.sh <<EOF' >> ${kickstart_file}
cat /tmp/openstack-setup/openstack-env.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

closeOutAndBuildKickstartAndISO "${kickstart_file}" "openstack"