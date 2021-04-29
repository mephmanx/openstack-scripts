#!/bin/bash

exec 1>/tmp/cloudsupport-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
pip3 install --upgrade pip

working_dir=`pwd`
chmod 777 /tmp/openstack-env.sh
source ./tmp/openstack-env.sh
cd $working_dir

runuser -l root -c  "yum install -y https://$GITHUB_TOKEN@raw.githubusercontent.com/mephmanx/cloud-libs/master/containerd.io-1.2.6-3.3.el7.x86_64.rpm"
sleep 5
runuser -l root -c  "yum install -y https://$GITHUB_TOKEN@raw.githubusercontent.com/mephmanx/cloud-libs/master/docker-ce-cli-18.09.9-3.el7.x86_64.rpm"
sleep 5
runuser -l root -c  "yum install -y https://$GITHUB_TOKEN@raw.githubusercontent.com/mephmanx/cloud-libs/master/docker-ce-18.09.9-3.el7.x86_64.rpm"
sleep 5

systemctl start docker
systemctl enable docker
chkconfig docker on

systemctl restart docker
docker login -u $DOCKER_HUB_USER -p $DOCKER_HUB_PWD

pip3 install docker-compose
curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

cd /root
yum install -y tar

wget -O /tmp/harbor.tgz https://github.com/goharbor/harbor/releases/download/v2.1.5/harbor-offline-installer-v2.1.5.tgz
tar xzvf /tmp/harbor.tgz

wget -O /root/harbor/harbor.yml -d --header="Authorization: Bearer $GITHUB_TOKEN" https://raw.githubusercontent.com/mephmanx/openstack-scripts/master/harbor.yml
sed -i "s/{MACHINE_FQDN}/${MACHINE_FQDN}/g" /root/harbor/harbor.yml
sed -i "s/{PORTUS_PASSWORD}/${PORTUS_PASSWORD}/g" /root/harbor/harbor.yml
sed -i "s/{DATABASE_PASSWORD}/${DATABASE_PASSWORD}/g" /root/harbor/harbor.yml

./install.sh --with-notary --with-trivy --with-chartmuseum

#remove so as to not run again
rm -rf /etc/rc.d/rc.local
