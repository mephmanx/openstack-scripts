#!/bin/bash

exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
runuser -l root -c  'yum install -y https://raw.githubusercontent.com/mephmanx/cloud-libs/master/docker-ce-cli-18.09.9-3.el7.x86_64.rpm'
sleep 5
runuser -l root -c  'yum install -y https://raw.githubusercontent.com/mephmanx/cloud-libs/master/docker-ce-18.09.9-3.el7.x86_64.rpm'
sleep 5

chmod 777 /tmp/portus-env.sh
cd /tmp
. ./portus-env.sh

systemctl restart docker
docker login -u $PORTUS_USERNAME -p $PORTUS_PASSWORD $MACHINE_FQDN:$REGISTRY_PORT

mkdir /root/.ssh
cp /tmp/openstack-setup.key.pub /root/.ssh/authorized_keys
mv /tmp/openstack-setup.key.pub /root/.ssh/id_rsa.pub
mv /tmp/openstack-setup.key /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa
chmod 600 /root/.ssh/authorized_keys

systemctl stop firewalld
systemctl mask firewalld


pip3 install --upgrade pip
cd /etc/init.d
./vmware-tools restart

#remove so as to not run again
rm -rf /etc/rc.d/rc.local