#!/bin/bash
#can ONLY be run as root!  sudo to root

source ./iso-functions.sh
source ./openstack-env.sh

rm -rf /tmp/openstack-setup;
rm -rf /tmp/openstack-scripts;

git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git /tmp/openstack-setup;
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git /tmp/openstack-scripts;

cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;

rm -rf /var/tmp/openstack-iso.iso
cd /tmp/openstack-setup

IFS=
kickstart_file=centos-8-kickstart-openstack.cfg
####initial certs###############
letsEncryptAndCockpitCerts ${kickstart_file}
###############################

########### add passwords in
sed -i 's/{GITHUB_TOKEN}/'$GITHUB_TOKEN'/g' ${kickstart_file}
sed -i 's/{CENTOS_ROOT_PWD}/'$CENTOS_ROOT_PWD'/g' ${kickstart_file}
###########################

############### Secrets file ################
echo 'cat > /tmp/openstack-env.sh <<EOF' >> ${kickstart_file}
cat ./openstack-env.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

############### Global Addresses ################
echo 'cat > /tmp/global_addresses.sh <<EOF' >> ${kickstart_file}
cat ./global_addresses.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

closeOutAndBuildKickstartAndISO "${kickstart_file}" "openstack"


