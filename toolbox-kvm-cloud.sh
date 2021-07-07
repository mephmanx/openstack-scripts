#!/bin/bash
#can ONLY be run as root!  sudo to root
source ./openstack-setup/openstack-env.sh

rm -rf /root/openstack-setup;
rm -rf /root/openstack-scripts;

git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git /root/openstack-setup;
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git /root/openstack-scripts;

cp /root/openstack-scripts/*.sh /root/openstack-setup;
cp /root/openstack-scripts/*.cfg /root/openstack-setup;

cd /root/openstack-setup
/root/openstack-setup/create-cloud-kvm.sh &
