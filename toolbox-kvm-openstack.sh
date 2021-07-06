#!/bin/bash
#can ONLY be run as root!  sudo to root
source ./openstack-setup/openstack-env.sh

rm -rf /cloudprep/openstack-setup;
rm -rf /cloudprep/openstack-scripts;

git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git /cloudprep/openstack-setup;
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git /cloudprep/openstack-scripts;

cp /cloudprep/openstack-scripts/*.sh /cloudprep/openstack-setup;
cp /cloudprep/openstack-scripts/*.cfg /cloudprep/openstack-setup;

rm -rf /var/cloudprep/openstack-iso.iso
cd /cloudprep/openstack-setup
/cloudprep/openstack-setup/create-openstack-kvm.sh &
