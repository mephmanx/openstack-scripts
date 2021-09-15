#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/openstack-env.sh
. /tmp/project_config.sh

start() {

#### Common setup
common_second_boot_setup
#################

#####  setup global VIPs
SUPPORT_VIP_DNS="$SUPPORT_HOST.$DOMAIN_NAME"
INTERNAL_VIP_DNS="$APP_INTERNAL_HOSTNAME.$DOMAIN_NAME"
EXTERNAL_VIP_DNS="$APP_EXTERNAL_HOSTNAME.$DOMAIN_NAME"
###################

############ add keys
working_dir=`pwd`
chmod 700 /tmp/host-trust.sh
runuser -l root -c  'cd /tmp; ./host-trust.sh'
cd $working_dir

ADMIN_PWD=`cat /root/env_admin_pwd`

########### set up registry connection to docker hub
export etext=`echo -n "$SUPPORT_USERNAME:$ADMIN_PWD" | base64`
curl -k --location --request POST "https://$SUPPORT_VIP_DNS/api/v2.0/registries" \
  --header "authorization: Basic $etext" \
  --header 'content-type: application/json' \
  --header "host: $SUPPORT_VIP_DNS" \
  -H 'Accept-Language: en-us' \
  -H 'Accept-Encoding: gzip, deflate, br' \
  -H "Referer: https://$SUPPORT_VIP_DNS/harbor/registries" \
  -H "Origin: https://$SUPPORT_VIP_DNS" \
  -H 'Connection: keep-alive' \
  --data-binary "{\"credential\":{\"access_key\":\"$DOCKER_HUB_USER\",\"access_secret\":\"$DOCKER_HUB_PWD\",\"type\":\"basic\"},\"description\":\"\",\"insecure\":false,\"name\":\"docker-hub\",\"type\":\"docker-hub\",\"url\":\"https://hub.docker.com\"}"

###########################

###########  remove default "library" project and create new proxy-cache library project
curl -k --location --request DELETE "https://$SUPPORT_VIP_DNS/api/v2.0/projects/1" \
  --header "authorization: Basic $etext"

curl -k --location --request POST "https://$SUPPORT_VIP_DNS/api/v2.0/projects" \
  --header "authorization: Basic $etext" \
  --header 'content-type: application/json' \
  --header "host: $SUPPORT_VIP_DNS" \
  --data-binary "{\"project_name\":\"library\",\"registry_id\":1,\"metadata\":{\"public\":\"true\"},\"storage_limit\":-1}"

status_code=$(curl https://$SUPPORT_VIP_DNS/api/v2.0/registries --write-out %{http_code} -k --silent --output /dev/null -H "authorization: Basic $etext" )

if [[ "$status_code" -ne 200 ]] ; then
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Harbor install failed!"
  exit -1
else
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Harbor install successful. Hypervisor SSH keys added to VM's. continuing install..."
fi

unset HOME

###  Make sure noting goes into the /home/stack folder
mkdir /home/stack
#chown /home/stack stack
chmod 777 /home/stack
#change to stack user
runuser -l root -c  'su - stack'
########################

pip3 install --upgrade pip
pip3 install 'ansible==2.9.10' --ignore-installed
pip3 install kolla-ansible --ignore-installed

export PATH="/usr/local/bin:$PATH"

mkdir -p /etc/kolla

cp -r /usr/local/share/kolla-ansible/etc_examples/kolla/* /etc/kolla
cp /usr/local/share/kolla-ansible/ansible/inventory/* /etc/kolla

mkdir -p /var/lib/kolla/config_files
mkdir /etc/kolla/certificates
cp /tmp/*.pem /etc/kolla/certificates
cp /tmp/internal-ca.pem /etc/kolla/certificates/ca

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Downloading Openstack Kolla deployment playbook and performing env customization...."
curl -s -o /etc/kolla/globals.yml https://raw.githubusercontent.com/$GITHUB_USER/openstack-scripts/master/globals.yml > /dev/null

sed -i "s/{INTERNAL_VIP}/${INTERNAL_VIP}/g" /etc/kolla/globals.yml
sed -i "s/{INTERNAL_VIP_DNS}/${INTERNAL_VIP_DNS}/g" /etc/kolla/globals.yml
sed -i "s/{EXTERNAL_VIP}/${EXTERNAL_VIP}/g" /etc/kolla/globals.yml
sed -i "s/{EXTERNAL_VIP_DNS}/${EXTERNAL_VIP_DNS}/g" /etc/kolla/globals.yml
sed -i "s/{SUPPORT_HOST}/${SUPPORT_VIP_DNS}/g" /etc/kolla/globals.yml
sed -i "s/{DESIGNATE_RECORD}/${DOMAIN_NAME}/g" /etc/kolla/globals.yml
sed -i "s/{SUPPORT_USERNAME}/${SUPPORT_USERNAME}/g" /etc/kolla/globals.yml

kolla-genpwd

#### Replace passwords
sed -i "s/docker_registry_password: null/docker_registry_password: ${ADMIN_PWD}/g" /etc/kolla/passwords.yml
sed -i "s/keystone_admin_password: .*/keystone_admin_password: ${ADMIN_PWD}/g" /etc/kolla/passwords.yml
sed -i "s/kibana_password: .*/kibana_password: ${ADMIN_PWD}/g" /etc/kolla/passwords.yml
sed -i "s/grafana_admin_password: .*/grafana_admin_password: ${ADMIN_PWD}/g" /etc/kolla/passwords.yml
#####

######  prepare storage rings
export KOLLA_SWIFT_BASE_IMAGE="kolla/centos-source-swift-base:4.0.0"
mkdir -p /etc/kolla/config/swift
# 0 based (ie 0=1, so 1=2)
drive_count=0

while IFS="" read -r p || [ -n "$p" ]
do
  printf 'storage host -> %s\n' "$p"
  export KOLLA_INTERNAL_ADDRESS=$p
  # Object ring
  docker run \
    --rm \
    -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
    $KOLLA_SWIFT_BASE_IMAGE \
    swift-ring-builder \
      /etc/kolla/config/swift/object.builder create 10 1 1
  for i in $(seq 0 $drive_count); do
    docker run \
      --rm \
      -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
      $KOLLA_SWIFT_BASE_IMAGE \
      swift-ring-builder \
        /etc/kolla/config/swift/object.builder add r1z1-${KOLLA_INTERNAL_ADDRESS}:6000/d${i} 1;
  done
  # Account ring
  docker run \
    --rm \
    -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
    $KOLLA_SWIFT_BASE_IMAGE \
    swift-ring-builder \
      /etc/kolla/config/swift/account.builder create 10 1 1
  for i in $(seq 0 $drive_count); do
    docker run \
      --rm \
      -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
      $KOLLA_SWIFT_BASE_IMAGE \
      swift-ring-builder \
        /etc/kolla/config/swift/account.builder add r1z1-${KOLLA_INTERNAL_ADDRESS}:6001/d${i} 1;
  done
  # Container ring
  docker run \
    --rm \
    -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
    $KOLLA_SWIFT_BASE_IMAGE \
    swift-ring-builder \
      /etc/kolla/config/swift/container.builder create 10 1 1
  for i in $(seq 0 $drive_count); do
    docker run \
      --rm \
      -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
      $KOLLA_SWIFT_BASE_IMAGE \
      swift-ring-builder \
        etc/kolla/config/swift/container.builder add r1z1-${KOLLA_INTERNAL_ADDRESS}:6002/d${i} 1;
  done
  for ring in object account container; do
    docker run \
      --rm \
      -v /etc/kolla/config/swift/:/etc/kolla/config/swift/ \
      $KOLLA_SWIFT_BASE_IMAGE \
      swift-ring-builder \
        /etc/kolla/config/swift/${ring}.builder rebalance;
  done
done < /tmp/storage_hosts
rm -rf /tmp/storage_hosts
#################

#####################################  make sure all hosts are up
# shellcheck disable=SC2006
host_count_str=`cat /tmp/host_count`

test_loop_count=0
printf -v host_count '%d' $host_count_str 2>/dev/null
ansible -m ping all -i /etc/kolla/multinode > /tmp/ping.txt
# shellcheck disable=SC2006
ct=`grep -o -i SUCCESS /tmp/ping.txt | wc -l`
# shellcheck disable=SC2004
host_count=$(($host_count + 1))
echo "hosts to check -> $host_count current hosts up -> $ct"
while [ "$ct" != $host_count ]; do
  rm -rf /tmp/ping.txt
  ansible -m ping all -i /etc/kolla/multinode > /tmp/ping.txt
  # shellcheck disable=SC2006
  ct=`grep -o -i SUCCESS /tmp/ping.txt | wc -l`
  echo "hosts to check -> $host_count current hosts up -> $ct"

  ############ add keys
  working_dir=`pwd`
  chmod 700 /tmp/host-trust.sh
  runuser -l root -c  'cd /tmp; ./host-trust.sh'
  cd $working_dir

  sleep 10
  ((test_loop_count++))

  if [[ $test_loop_count -gt 10 ]]; then
    telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Not all Openstack VM's successfully came up, install ending.  Please check logs!"
    exit -1
  fi
done
rm -rf /tmp/ping.txt
rm -rf /tmp/host_count
#####################################

### host ping successful, all hosts came up properly
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "All Openstack VM's came up properly and are ready for install. continuing..."
#############

#### run host trust on all nodes
file=/tmp/host_list
for i in `cat $file`
do
  echo "$i"
  scp /tmp/host-trust.sh root@$i:/tmp
  runuser -l root -c "ssh root@$i '/tmp/host-trust.sh'"
done
rm -rf /tmp/host_trust
#####################

## generate octavia certs
kolla-ansible octavia-certificates
###########

kolla-ansible -i /etc/kolla/multinode bootstrap-servers
kolla-ansible -i /etc/kolla/multinode prechecks

#use for loading time as opposed to needing the image
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Downloading LiveCD debug image..."
curl -o /tmp/livecd.iso https://$GATEWAY_ROUTER_IP/isos/livecd.iso -s -k

export KOLLA_DEBUG=0
export ENABLE_EXT_NET=1
export EXT_NET_CIDR="$GATEWAY_ROUTER_IP/24"
export EXT_NET_RANGE="start=$OPENSTACK_DHCP_START,end=$OPENSTACK_DHCP_END"
export EXT_NET_GATEWAY=$GATEWAY_ROUTER_IP

### pull docker images
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Analyzing Kolla Openstack configuration and pull docker images for cache priming...."

## look for any failures and run again if any fail.   continue until cache is full or 10 tries are made
cache_ct=10
cache_out=`kolla-ansible -i /etc/kolla/multinode pull`
failure_occur=`echo $cache_out | grep -o 'FAILED' | wc -l`
while [ $failure_occur -gt 0 ]; do
  cache_out=`kolla-ansible -i /etc/kolla/multinode pull`
  failure_occur=`echo $cache_out | grep -o 'FAILED' | wc -l`
  if [[ $cache_ct == 0 ]]; then
    telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Cache prime failed after 10 retries, failing.  Check logs to resolve issue."
    exit -1
  fi
  ((cache_ct--))
done

rm -rf /opt/stack/cache_out
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Cache pull/prime complete!  Install continuing.."


telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Openstack Kolla Ansible deploy task execution begun....."
kolla-ansible -i /etc/kolla/multinode deploy

### grab last set of lines from log to send
LOG_TAIL=`tail -25 /tmp/openstack-install.log`
###

pip3 install python-openstackclient --ignore-installed
kolla-ansible post-deploy

telegram_debug_msg $TELEGRAM_API $TELEGRAM_CHAT_ID "End of Openstack Install log -> $LOG_TAIL"
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Openstack Kolla Ansible deploy task execution complete.  Performing post install tasks....."
#stupid hack
working_dir=`pwd`
chmod 700 /tmp/control-trust.sh
runuser -l root -c  'cd /tmp; ./control-trust.sh'
cd $working_dir
rm -rf /tmp/control-trust.sh

#load setup for validator
cd /etc/kolla
. ./admin-openrc.sh
sleep 180

## adding cinder v2 endpoints
openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
openstack endpoint create --region us-east volumev2 public https://$EXTERNAL_VIP_DNS:8776/v2/%\(project_id\)s
openstack endpoint create --region us-east volumev2 internal http://$INTERNAL_VIP_DNS:8776/v2/%\(project_id\)s
openstack endpoint create --region us-east volumev2 admin http://$INTERNAL_VIP_DNS:8776/v2/%\(project_id\)s
#############

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Installing LiveCD debug image into Openstack...."
openstack image create --disk-format iso --container-format bare --public --file /tmp/livecd.iso LiveCD-Debug

test=`openstack image show 'LiveCD-Debug'`
if [[ "No Image found" == *"$test"* ]]; then
#  cp /tmp/multinode /etc/kolla
#  kolla-ansible -i /etc/kolla/multinode destroy --yes-i-really-really-mean-it
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Openstack install failed!  Install quit, please check!"
  exit -1
fi
rm -rf /tmp/livecd.iso

cd /usr/local/share/kolla-ansible
./init-runonce

export HOME=/home/stack
cd /tmp

## install openstack python clients
pip install python-octaviaclient
pip install python-troveclient
pip install python-magnumclient
pip install python-swiftclient
#####

curl -o /tmp/magnum.qcow2 https://$GATEWAY_ROUTER_IP/isos/magnum.qcow2 -s -k
openstack image create \
                      --disk-format=qcow2 \
                      --container-format=bare \
                      --file=/tmp/magnum.qcow2\
                      --property os_distro='fedora-atomic' \
                      fedora-atomic-latest

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Magnum image installed, continuing install..."

## create network, subnet, and loadbalancer
openstack coe cluster template create swarm-cluster-template \
          --image fedora-atomic-latest \
          --external-network public1 \
          --dns-nameserver 8.8.8.8 \
          --network-driver docker \
          --docker-storage-driver overlay2 \
          --docker-volume-size 10 \
          --master-flavor m1.small \
          --flavor m1.small \
          --coe swarm

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Created magnum cluster..."

openstack coe cluster create swarm-cluster \
                        --cluster-template swarm-cluster-template \
                        --master-count 1 \
                        --node-count 1 \
                        --keypair mykey

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Openstack installed and accepting images, continuing install..."

#prepare openstack env for CF

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Preparing Openstack environment for BOSH install...."
## generate cloudfoundry admin pwd
HOWLONG=15 ## the number of characters
OPENSTACK_CLOUDFOUNDRY_PWD=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});

openstack project create cloudfoundry
openstack user create $OPENSTACK_CLOUDFOUNDRY_USERNAME --project cloudfoundry --password $OPENSTACK_CLOUDFOUNDRY_PWD
openstack role add --project cloudfoundry --project-domain default --user $OPENSTACK_CLOUDFOUNDRY_USERNAME --user-domain default admin

openstack quota set --cores 256 cloudfoundry
openstack quota set --instances 100 cloudfoundry
openstack quota set --ram 164000 cloudfoundry
openstack quota set --secgroups 100 cloudfoundry
openstack quota set --secgroup-rules 200 cloudfoundry
openstack quota set --volumes 100 cloudfoundry

### cloudfoundry flavors
openstack flavor create --ram 3840 --ephemeral 10 --vcpus 1 --public minimal
openstack flavor create --ram 7680 --ephemeral 14 --vcpus 2 --public small
openstack flavor create --ram 31232 --ephemeral 10 --vcpus 4 --public small-highmem
openstack flavor create --ram 7680 --ephemeral 50 --vcpus 2 --public small-50GB-ephemeral-disk
openstack flavor create --ram 31232 --ephemeral 100 --vcpus 4 --public small-highmem-100GB-ephemeral-disk
#####

### livecd flavor
openstack flavor create --ram 7680 --ephemeral 0 --vcpus 4 --public livecd
####

openstack quota set --cores -1 service
openstack quota set --instances -1 service
openstack quota set --ram -1 service
openstack quota set --secgroups -1 service
openstack quota set --secgroup-rules -1 service
openstack quota set --volumes -1 service

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Cloudfoundry Openstack project ready.  user -> $OPENSTACK_CLOUDFOUNDRY_USERNAME pwd -> $OPENSTACK_CLOUDFOUNDRY_PWD"
telegram_debug_msg $TELEGRAM_API $TELEGRAM_CHAT_ID "Openstack admin pwd is $ADMIN_PWD"

#download and configure homebrew to run bbl install
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Starting Homebrew install...."
curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh -o /tmp/homebrew.sh > /dev/null
chmod 777 homebrew.sh

PUBLIC_NETWORK_ID="$(openstack network list --name public1 | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }')"

runuser -l stack -c  '/tmp/homebrew.sh </dev/null'
runuser -l stack -c  'echo "eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" >> /opt/stack/.bash_profile'
runuser -l stack -c  'eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)'
runuser -l stack -c  'brew install cloudfoundry/tap/bosh-cli'
runuser -l stack -c  'brew install bbl'

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Starting BOSH infrastructure install...."
runuser -l stack -c  "echo 'export BBL_IAAS=openstack' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_AUTH_URL=https://$EXTERNAL_VIP_DNS:5000/v3' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_AZ=nova' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_NETWORK_ID=$PUBLIC_NETWORK_ID' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_NETWORK_NAME=public1' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_PASSWORD=$OPENSTACK_CLOUDFOUNDRY_PWD' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_USERNAME=$OPENSTACK_CLOUDFOUNDRY_USERNAME' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_PROJECT=cloudfoundry' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_DOMAIN=default' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_REGION=us-east' >> /opt/stack/.bash_profile"

runuser -l stack -c  "echo 'export OS_PROJECT_DOMAIN_NAME=$OS_PROJECT_DOMAIN_NAME' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_USER_DOMAIN_NAME=$OS_USER_DOMAIN_NAME' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_PROJECT_NAME=$OS_PROJECT_NAME' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_TENANT_NAME=$OS_TENANT_NAME' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_USERNAME=$OS_USERNAME' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_PASSWORD=$OS_PASSWORD' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_AUTH_URL=https://$EXTERNAL_VIP_DNS:5000/v3' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_INTERFACE=$OS_INTERFACE' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_ENDPOINT_TYPE=$OS_ENDPOINT_TYPE' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_IDENTITY_API_VERSION=$OS_IDENTITY_API_VERSION' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_REGION_NAME=$OS_REGION_NAME' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_AUTH_PLUGIN=$OS_AUTH_PLUGIN' >> /opt/stack/.bash_profile"
runuser -l stack -c  'bbl up --debug'

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "BOSH jumpbox and director installed, amphora build/install..."

############# build octavia image
runuser -l root -c  'yum install -y debootstrap qemu-img git e2fsprogs policycoreutils-python-utils'
git clone https://opendev.org/openstack/octavia -b master
pip3 install diskimage-builder
cd octavia/diskimage-create
chmod 700 diskimage-create.sh
runuser -l root -c  '/tmp/octavia/diskimage-create/diskimage-create.sh'

### load octavia creds and upload amphora image
source /etc/kolla/octavia-openrc.sh
openstack image create amphora-x64-haproxy \
  --container-format bare \
  --disk-format qcow2 \
  --tag amphora \
  --private \
  --file /root/amphora-x64-haproxy.qcow2 \
  --property hw_architecture='x86_64' \
  --property hw_rng_model=virtio

test=`openstack image show 'amphora-x64-haproxy'`
if [[ "No Image found" == *"$test"* ]]; then
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Amphora image install failed! Please review!"
  exit -1
fi
#########################

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Amphora image install complete, beginning cloudfoundry install..."
####

### reload openstack admin creds
source /etc/kolla/admin-openrc.sh
######

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Pulling terraform 0.11.15 for prepare script..."
#### prepare env for cloudfoundry
git clone https://github.com/cloudfoundry-attic/bosh-openstack-environment-templates.git /tmp/bosh-openstack-environment-templates
cd /tmp/bosh-openstack-environment-templates/cf-deployment-tf

wget -q https://releases.hashicorp.com/terraform/0.11.15/terraform_0.11.15_linux_amd64.zip
unzip terraform_0.11.15_linux_amd64.zip
chmod 700 terraform

sed  '/provider "openstack" {/a use_octavia   = true' ./cf.tf >> cf.tf-new
rm -rf cf.tf
mv cf.tf-new cf.tf

## add availability zones to the list below for a full HA deploy
cat > terraform.tfvars <<EOF
auth_url = "https://$EXTERNAL_VIP_DNS:5000/v3"
domain_name = "default"
user_name = "$OPENSTACK_CLOUDFOUNDRY_USERNAME"
password = "$OPENSTACK_CLOUDFOUNDRY_PWD"
project_name = "cloudfoundry"
region_name = "us-east"
availability_zones = ["nova"]
ext_net_name = "public1"

# the OpenStack router id which can be used to access the BOSH network
bosh_router_id = "`openstack router list --project cloudfoundry | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'`"

# in case Openstack has its own DNS servers
dns_nameservers = ["$GATEWAY_ROUTER_IP"]

# does BOSH use a local blobstore? Set to 'false', if your BOSH Director uses e.g. S3 to store its blobs
use_local_blobstore = "true" #default is true

# enable TCP routing setup
use_tcp_router = "true" #default is true
num_tcp_ports = $CF_TCP_PORT_COUNT #default is 100, needs to be > 0

# in case of self signed certificate select one of the following options
# cacert_file = "<path-to-certificate>"
insecure = "false"
EOF

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Executing env prep script..."

runuser -l root -c  "cd /tmp/bosh-openstack-environment-templates/cf-deployment-tf; ./terraform init;"
runuser -l root -c  "cd /tmp/bosh-openstack-environment-templates/cf-deployment-tf; ./terraform apply -auto-approve > /tmp/terraf-bbl.out;"
################

### update cf-lb to preconfigured address
LB_FIXED_IP="$CLOUDFOUNDRY_VIP"
LB_PROJECT_ID=`openstack loadbalancer show cf-lb -f value -c project_id`
LB_VIP_ADDRESS=`openstack loadbalancer show cf-lb -f value -c vip_address`
LB_VIP_PORT_ID=`openstack loadbalancer show cf-lb -f value -c vip_port_id`
LB_FLOATING_IP=`openstack floating ip list -f value -c "Floating IP Address" -c "Fixed IP Address" | grep ${LB_VIP_ADDRESS} | cut -d" " -f1`
LB_FIP_SUBNET=`openstack subnet show  public1-subnet -f value -c id`
LB_FIP_NETWORK_ID=`openstack network show public1 -f value -c id`

openstack floating ip delete ${LB_FLOATING_IP}
openstack floating ip create --subnet ${LB_FIP_SUBNET} --project ${LB_PROJECT_ID} --port ${LB_VIP_PORT_ID} --fixed-ip-address ${LB_VIP_ADDRESS} --floating-ip-address ${LB_FIXED_IP} ${LB_FIP_NETWORK_ID}
###

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Env prep script complete, pulling CF deployment repo...."
git clone https://github.com/cloudfoundry/cf-deployment /tmp/cf-deployment
chown -R stack /tmp/cf-deployment

###  build swift tmp url key to use below
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Setting up swift blobstore key..."

### generate swift container key
HOWLONG=15 ## the number of characters
SWIFT_KEY=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});

cat > /tmp/swift.key <<EOF
$SWIFT_KEY
EOF

swift post -m "Temp-URL-Key:$SWIFT_KEY" -A http://$INTERNAL_VIP_DNS:5000/v3 -U $OPENSTACK_CLOUDFOUNDRY_USERNAME -K $OPENSTACK_CLOUDFOUNDRY_PWD -V 3 --os-project-name cloudfoundry --os-project-domain-name default

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Swift blobstores key ready, pulling latest CF stemcell..."

### load bbl/bosh env
cp /etc/kolla/admin-openrc.sh /opt/stack/admin-openrc.sh
chown stack /opt/stack/admin-openrc.sh
runuser -l stack -c  "source /opt/stack/admin-openrc.sh"
runuser -l stack -c  "source /opt/stack/.bash_profile"

#### prep variables

### download latest stemcell
runuser -l stack -c  "bosh interpolate /tmp/cf-deployment/cf-deployment.yml --path=/stemcells/alias=default/version > /opt/stack/stemcell_version"

runuser -l stack -c  "cd /opt/stack; bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
                      chmod 700 /tmp/bbl_env.sh; \
                      source /tmp/bbl_env.sh; \
                      bosh upload-stemcell https://bosh-core-stemcells.s3-accelerate.amazonaws.com/`cat /opt/stack/stemcell_version`/bosh-stemcell-`cat /opt/stack/stemcell_version`-openstack-kvm-ubuntu-xenial-go_agent-raw.tgz"

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Stemcell installed, finalizing environment for CF install..."
## add cf and cf-deployment-for-bosh security groups to bosh director
## very important!
## change to cloudfoundry account
export OS_PROJECT_NAME=cloudfoundry
export OS_USERNAME=$OPENSTACK_CLOUDFOUNDRY_USERNAME
export OS_PASSWORD=$OPENSTACK_CLOUDFOUNDRY_PWD

## execute server security group changes
openstack server add security group bosh/0 cf
openstack server add security group bosh/0 cf-lb
openstack server add security group bosh/0 cf-deployment-for-bosh
openstack server add security group bosh/0 cf-lb-ssh-diego-brain
openstack server add security group bosh/0 cf-lb-tcp-router
openstack server add security group bosh/0 cf-lb-https-router
openstack server add security group bosh/0 default

## switch back to admin
source /etc/kolla/admin-openrc.sh

### update runtime and cloud config
export CF_NET_ID_1=`openstack network list --project cloudfoundry --name cf-z0 | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'`
#export CF_NET_ID_2=`openstack network list --project cloudfoundry --name cf-z1 | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'`
#export CF_NET_ID_3=`openstack network list --project cloudfoundry --name cf-z2 | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'`
## modify net id's if AZ's added to terraform script above for HA
runuser -l stack -c  "cd /opt/stack; \
                      bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
                      chmod 700 /tmp/bbl_env.sh; \
                      source /tmp/bbl_env.sh; \
                      bosh update-runtime-config /opt/stack/bosh-deployment/runtime-configs/dns.yml --name dns -n"

runuser -l stack -c  "cd /opt/stack; \
                      bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
                      chmod 700 /tmp/bbl_env.sh; \
                      source /tmp/bbl_env.sh; \
                      bosh update-cloud-config  -v availability_zone1=nova \
                          -v availability_zone2=nova \
                          -v availability_zone3=nova \
                          -v network_id1=$CF_NET_ID_1 \
                          -v network_id2=$CF_NET_ID_1 \
                          -v network_id3=$CF_NET_ID_1 \
                          /tmp/cf-deployment/iaas-support/openstack/cloud-config.yml -n"

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Executing Cloudfoundry install.  Should take about 30 - 45 min..."

### prepare google SAML config and include it in deploy

### deploy cloudfoundry
runuser -l stack -c  "cd /opt/stack; \
                  bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
                  chmod 700 /tmp/bbl_env.sh; \
                  source /tmp/bbl_env.sh; \
                  bosh -d cf deploy -o /tmp/cf-deployment/operations/use-external-blobstore.yml \
                  -o /tmp/cf-deployment/operations/use-swift-blobstore.yml \
                  -o /tmp/cf-deployment/operations/openstack.yml \
                  -o /tmp/cf-deployment/operations/scale-to-one-az.yml \
                  -o /tmp/cf-deployment/operations/use-compiled-releases.yml \
                  --vars-store /tmp/vars/deployment-vars.yml \
                  /tmp/cf-deployment/cf-deployment.yml \
                  -v system_domain=$DOMAIN_NAME \
                  -v auth_url=https://$EXTERNAL_VIP_DNS:5000/v3 \
                  -v openstack_project=cloudfoundry \
                  -v openstack_domain=default \
                  -v openstack_username=$OPENSTACK_CLOUDFOUNDRY_USERNAME \
                  -v openstack_password=$OPENSTACK_CLOUDFOUNDRY_PWD \
                  -v cf_admin_password=$OPENSTACK_CLOUDFOUNDRY_PWD \
                  -v openstack_temp_url_key=$SWIFT_KEY \
                  -v app_package_directory_key=app_package_directory \
                  -v buildpack_directory_key=buildpack_directory \
                  -v droplet_directory_key=droplet_directory \
                  -v resource_directory_key=resource_directory \
                  -n" > /tmp/cloudfoundry-install.log

### Cloudfoundry instal can fail at times.  BOSH can handle this and retry is fine.  Retry a few times and if faile still occurs, alert admin
error_count=`grep "error" /tmp/cloudfoundry-install.log | wc -l`
retry_count=3
if [[ $error_count -gt 0 ]]; then
  while [ $retry_count -gt 0 ]; do
    rm -rf /tmp/cloudfoundry-install.log
    telegram_debug_msg $TELEGRAM_API $TELEGRAM_CHAT_ID "Cloudfoundry install failed, retrying $retry_count more times..."
    runuser -l stack -c  "cd /opt/stack; \
                      bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
                      chmod 700 /tmp/bbl_env.sh; \
                      source /tmp/bbl_env.sh; \
                      bosh -d cf deploy -o /tmp/cf-deployment/operations/use-external-blobstore.yml \
                      -o /tmp/cf-deployment/operations/use-swift-blobstore.yml \
                      -o /tmp/cf-deployment/operations/openstack.yml \
                      -o /tmp/cf-deployment/operations/scale-to-one-az.yml \
                      -o /tmp/cf-deployment/operations/use-compiled-releases.yml \
                      --vars-store /tmp/vars/deployment-vars.yml \
                      /tmp/cf-deployment/cf-deployment.yml \
                      -v system_domain=$DOMAIN_NAME \
                      -v auth_url=https://$EXTERNAL_VIP_DNS:5000/v3 \
                      -v openstack_project=cloudfoundry \
                      -v openstack_domain=default \
                      -v openstack_username=$OPENSTACK_CLOUDFOUNDRY_USERNAME \
                      -v openstack_password=$OPENSTACK_CLOUDFOUNDRY_PWD \
                      -v cf_admin_password=$OPENSTACK_CLOUDFOUNDRY_PWD \
                      -v openstack_temp_url_key=$SWIFT_KEY \
                      -v app_package_directory_key=app_package_directory \
                      -v buildpack_directory_key=buildpack_directory \
                      -v droplet_directory_key=droplet_directory \
                      -v resource_directory_key=resource_directory \
                      -n" > /tmp/cloudfoundry-install.log

    error_count=`grep "error" /tmp/cloudfoundry-install.log | wc -l`
    ((retry_count--))
  done
fi

### grab last set of lines from log to send
LOG_TAIL=`tail -25 /tmp/cloudfoundry-install.log`
###

telegram_debug_msg $TELEGRAM_API $TELEGRAM_CHAT_ID "Cloudfoundry install tail -> $LOG_TAIL"
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Cloudfoundry install complete!  Beginning Stratos UI deploy"

## install cf cli
runuser -l root -c  "wget -O /etc/yum.repos.d/cloudfoundry-cli.repo https://packages.cloudfoundry.org/fedora/cloudfoundry-cli.repo"
runuser -l root -c  "yum install -y cf7-cli"

# cf api login
cf login -a api.$DOMAIN_NAME -u admin -p $OPENSTACK_CLOUDFOUNDRY_PWD

## create org
cf create-org $DOMAIN_NAME

# create cf spaces
cf create-space -o system system
cf create-space -o $DOMAIN_NAME prod
cf create-space -o $DOMAIN_NAME uat

# enable docker support
cf enable-feature-flag diego_docker

## change to prod dir for deploy
cf target -o "system" -s "system"

#push stratos
cd /tmp
git clone https://github.com/cloudfoundry/stratos
cd stratos
cf push console -f manifest-docker.yml -k 2G

## Stratos complete!
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Stratos deployment complete!  access at console.$DOMAIN_NAME user -> admin , pwd -> $OPENSTACK_CLOUDFOUNDRY_PWD"

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

###post install cleanup
post_install_cleanup

restrict_to_root
}

stop() {
    # code to stop app comes here
    # example: killproc program_name
    /bin/true
}

case "$1" in
    start)
       start
       ;;
    stop)
        /bin/true
       stop
       ;;
    restart)
       stop
       start
       ;;
    status)
        /bin/true
       # code to check status of app comes here
       # example: status program_name
       ;;
    *)
       echo "Usage: $0 {start|stop|status|restart}"
esac

exit 0
