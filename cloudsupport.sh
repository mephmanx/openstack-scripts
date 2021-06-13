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
runuser -l root -c  'echo "10.0.20.200 cloudsupport.lyonsgroup.family" >> /etc/hosts;'
########### set up registry connection to docker hub
export etext=`echo -n "$SUPPORT_USERNAME:$SUPPORT_PASSWORD" | base64`
curl --location --request POST "https://${SUPPORT_HOST}/api/v2.0/registries" \
  --header "authorization: Basic $etext" \
  --header 'content-type: application/json' \
  --data-raw "{ \
    'name': 'docker-hub', \
    'url': 'https://hub.docker.com', \
    'insecure': false, \
    'type': 'docker-hub', \
    'description': 'docker hub', \
    'access_key':'$DOCKER_HUB_PWD', \
    'access_secret':'$DOCKER_HUB_USER' \
  }"
###########################

###########  remove default "library" project and create new proxy-cache library project
curl --location --request DELETE "https://${SUPPORT_HOST}/api/v2.0/projects/1" \
  --header "authorization: Basic $etext"

curl --location --request POST "https://${SUPPORT_HOST}/api/v2.0/projects" \
  --header "authorization: Basic $etext" \
  --header 'content-type: application/json' \
  --data-raw '{ \
      "project_name": "library", \
      "cve_allowlist": { \
          "items": [ \
              { \
                  "cve_id": "string" \
              } \
          ], \
          "project_id": 0, \
          "id": 0, \
          "expires_at": 0, \
          "update_time": "2021-06-12T15:44:26.510Z", \
          "creation_time": "2021-06-12T15:44:26.510Z" \
      }, \
      "count_limit": 0, \
      "registry_id": 1, \
      "storage_limit": 0, \
      "metadata": { \
          "enable_content_trust": "string", \
          "auto_scan": "string", \
          "severity": "string", \
          "public": "string", \
          "reuse_sys_cve_allowlist": "string", \
          "prevent_vul": "string", \
          "retention_id": "string" \
      }, \
      "public": true, \
      "proxy_cache": true \
  }'
##########################
#remove so as to not run again
rm -rf /etc/rc.d/rc.local
