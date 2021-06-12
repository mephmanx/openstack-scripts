#!/bin/bash

exec 1>/tmp/cloudsupport-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
pip3 install --upgrade pip

chmod 777 /tmp/openstack-env.sh
source ./tmp/openstack-env.sh

yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce docker-ce-cli containerd.io

systemctl start docker
systemctl enable docker
chkconfig docker on

systemctl restart docker
docker login -u $DOCKER_HUB_USER -p $DOCKER_HUB_PWD

curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

cd /root
yum install -y tar

wget -O /tmp/harbor.tgz https://github.com/goharbor/harbor/releases/download/v2.2.2/harbor-offline-installer-v2.2.2.tgz
tar xzvf /tmp/harbor.tgz

wget -O /root/harbor/harbor.yml -d https://mephmanx:$GITHUB_TOKEN@raw.githubusercontent.com/mephmanx/openstack-scripts/master/harbor.yml
sed -i "s/{SUPPORT_HOST}/${SUPPORT_HOST}/g" /root/harbor/harbor.yml
sed -i "s/{SUPPORT_PASSWORD}/${SUPPORT_PASSWORD}/g" /root/harbor/harbor.yml
sed -i "s/{DATABASE_PASSWORD}/${DATABASE_PASSWORD}/g" /root/harbor/harbor.yml
cd /root/harbor
chmod 777 *.sh
runuser -l root -c  "cd /root/harbor; ./install.sh --with-notary --with-trivy --with-chartmuseum"

########### set up registry connection to docker hub

###########################

###########  remove default "library" project and create new proxy-cache library project

##########################
#remove so as to not run again
rm -rf /etc/rc.d/rc.local
