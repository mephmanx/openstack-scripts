#!/bin/bash

exec 1>/tmp/cloudsupport-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
pip3 install --upgrade pip

yum-config-manager \
--add-repo \
https://download.docker.com/linux/centos/docker-ce.repo

yum install -y docker-ce docker-ce-cli containerd.io --nobest

systemctl start docker
systemctl enable docker
chkconfig docker on

systemctl restart docker
docker login -u $DOCKER_HUB_USER -p $DOCKER_HUB_PWD

pip3 install docker-compose
curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

cd /root
git clone https://github.com/mephmanx/Portus.git

working_dir=`pwd`
chmod 777 /tmp/openstack-env.sh
source ./tmp/openstack-env.sh
cd $working_dir

wget -O /root/Portus/docker-compose.yml -d --header="Authorization: Bearer $GITHUB_TOKEN" https://raw.githubusercontent.com/mephmanx/openstack-scripts/master/portus-compose.yml

chmod 777 /tmp/portus-env.sh
cd /tmp
. ./portus-env.sh

cd /root/Portus
sed -i "s/password=portus/password=${PORTUS_PASSWORD}/g" /root/Portus/examples/compose/clair/clair.yml

docker-compose up -d
sleep 90
##### Set up cloud accounts
jq --version || apt-get install -y jq || yum install -y jq || zypper install -y jq

export PORTUS_HOST=$MACHINE_FQDN:$MACHINE_PORT
# -- bootstrap (no one has opened the web ui and auto-registered as first super admin)
# first, we need the secret (the token) to authenticate to Portus API
# - The [/bootstrap] Endpoints, POST, to crate users, and PUT to modify permissions
# http://port.us.org/docs/API.html#spec-method-post-api-v1-users-bootstrap

# => With this first Portus API call, you retrieve in the response the token you are going to use to
#     authenticate to the Portus REST API in all the next Portus API calls below
export FIRST_SUPER_ADMIN_USERNAME=$PORTUS_USERNAME
export FIRST_SUPER_ADMIN_PASSWORD=$PORTUS_PASSWORD
export FIRST_SUPER_ADMIN_EMAIL=$ADMIN_EMAIL
# We don't need the role, cause bootstraping implicitly means
# giving admin role to bootstraped first user.
# export FIRST_SUPER_ADMIN_ROLE=admin

export PAYLOAD="{\"user\": {\"username\": \"$FIRST_SUPER_ADMIN_USERNAME\", \"email\": \"$FIRST_SUPER_ADMIN_EMAIL\", \"password\": \"$FIRST_SUPER_ADMIN_PASSWORD\", \"display_name\": \"$FIRST_SUPER_ADMIN_EMAIL\"}}"

curl -H 'Content-type: application/json' -H 'Accept: application/json' -X POST --data "$PAYLOAD" https://$PORTUS_HOST/api/v1/users/bootstrap > /tmp/portus.bootstrap.json

export  PORTUS_API_BOOT_TOKEN=$(cat /tmp/portus.bootstrap.json | jq '.plain_token' | awk -F '"' '{print $2}')
# And this one guy , $PORTUS_API_BOOT_TOKEN , it's your most critical portus secret, so you immediately secrue it into a secret manager like ansible secret manager, kubernetes / openshift secret manager, personally I prefer hashicorp vault.
# Then you'll use a credential helper, configured with your secret manager, to resolve your Portus API auth secret, for all subsequent Portus API calls.
# Or best: you revoke it once bootstrap process completed
#
# Now we can authenticate to portus api using the token :
# --- #
curl -X GET --header 'Accept: application/json' --header "Portus-Auth: $FIRST_SUPER_ADMIN_USERNAME:$PORTUS_API_BOOT_TOKEN" https://${PORTUS_HOST}/api/v1/_ping | jq '.'
curl -X GET --header 'Accept: application/json' --header "Portus-Auth: $FIRST_SUPER_ADMIN_USERNAME:$PORTUS_API_BOOT_TOKEN" https://${PORTUS_HOST}/api/v1/health | jq '.'
curl -X GET --header 'Accept: application/json' --header "Portus-Auth: $FIRST_SUPER_ADMIN_USERNAME:$PORTUS_API_BOOT_TOKEN" https://${PORTUS_HOST}/api/v1/users | jq '.[]'

# --->> REGISTRY CONFIG
# ok, so now let's configure the OCI image regsitry in portus :
#
# 1./ Configuring the registry, so portus knows how to reach it, onthe network.
# [POST /api/v1/registries]
export PORTUS_REGISTRY_NAME=$FIRST_SUPER_ADMIN_USERNAME
export PORTUS_REGISTRY_HOSTNAME=$MACHINE_FQDN:$REGISTRY_PORT
export PORTUS_REGISTRY_USE_SSL=true
export PORTUS_REGISTRY_EXTERNAL_HOSTNAME=$MACHINE_FQDN
export PAYLOAD="{\"registry\": {\"name\": \"$PORTUS_REGISTRY_NAME\", \"hostname\": \"$PORTUS_REGISTRY_HOSTNAME\", \"use_ssl\": \"$PORTUS_REGISTRY_USE_SSL\", \"external_hostname\": \"$PORTUS_REGISTRY_EXTERNAL_HOSTNAME\"}}"

curl --header 'Content-type: application/json' --header 'Accept: application/json' --header "Portus-Auth: $FIRST_SUPER_ADMIN_USERNAME:$PORTUS_API_BOOT_TOKEN" -X POST --data "$PAYLOAD" https://${PORTUS_HOST}/api/v1/registries | jq '.'

#remove so as to not run again
rm -rf /etc/rc.d/rc.local
