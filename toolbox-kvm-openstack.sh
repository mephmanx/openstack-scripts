#!/bin/bash
#can ONLY be run as root!  sudo to root
source ./openstack-setup/openstack-env.sh

rm -rf /tmp/openstack-setup;
rm -rf /tmp/openstack-scripts;

git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git /tmp/openstack-setup;
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git /tmp/openstack-scripts;

cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;

rm -rf /var/tmp/openstack-iso.iso
cd /tmp/openstack-setup
/tmp/openstack-setup/create-openstack-kvm.sh &
