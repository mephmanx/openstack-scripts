#!/bin/bash

chmod 777 /tmp/openstack-env.sh
cd /tmp
. ./openstack-env.sh

. /tmp/vm_functions.sh

#### Common setup
common_second_boot_setup
#################

############ add keys
working_dir=`pwd`
chmod 777 /tmp/host-trust.sh
runuser -l root -c  'cd /tmp; ./host-trust.sh'
cd $working_dir

unset HOME

mkdir /home/stack
chmod 777 /home/stack
#change to stack user
runuser -l root -c  'su - stack'
########################

pip3 install --upgrade pip
pip3 install 'ansible==2.9.10' --ignore-installed
pip3 install kolla-ansible --ignore-installed

mkdir -p /etc/kolla

cp -r /usr/local/share/kolla-ansible/etc_examples/kolla/* /etc/kolla
cp /usr/local/share/kolla-ansible/ansible/inventory/* /etc/kolla

mkdir -p /var/lib/kolla/config_files
mkdir /etc/kolla/certificates
cp /tmp/*.pem /etc/kolla/certificates

curl -o /etc/kolla/globals.yml https://mephmanx:$GITHUB_TOKEN@raw.githubusercontent.com/mephmanx/openstack-scripts/master/globals.yml

sed -i "s/{INTERNAL_VIP}/${INTERNAL_VIP}/g" /etc/kolla/globals.yml
sed -i "s/{INTERNAL_VIP_DNS}/${INTERNAL_VIP_DNS}/g" /etc/kolla/globals.yml
sed -i "s/{EXTERNAL_VIP}/${EXTERNAL_VIP}/g" /etc/kolla/globals.yml
sed -i "s/{EXTERNAL_VIP_DNS}/${EXTERNAL_VIP_DNS}/g" /etc/kolla/globals.yml
sed -i "s/{SUPPORT_HOST}/${SUPPORT_HOST}/g" /etc/kolla/globals.yml
sed -i "s/{SUPPORT_USERNAME}/${SUPPORT_USERNAME}/g" /etc/kolla/globals.yml

kolla-genpwd

#### Replace passwords
sed -i "s/docker_registry_password: null/docker_registry_password: ${SUPPORT_PASSWORD}/g" /etc/kolla/passwords.yml
sed -i "s/keystone_admin_password: .*/keystone_admin_password: ${OPENSTACK_ADMIN_PWD}/g" /etc/kolla/passwords.yml
sed -i "s/kibana_password: .*/kibana_password: ${KIBANA_ADMIN_PWD}/g" /etc/kolla/passwords.yml
#####

######  prepare storage rings
export KOLLA_SWIFT_BASE_IMAGE="kolla/centos-source-swift-base:4.0.0"
mkdir -p /etc/kolla/config/swift
# 0 based (ie 0=1, so 2=3)
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
#################

#####################################  make sure all hosts are up
# shellcheck disable=SC2006
#host_count_str=`grep -o -i ssh-keyscan /tmp/host-trust.sh | wc -l`
host_count_str=`cat /tmp/host_count`
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
  chmod 777 /tmp/host-trust.sh
  runuser -l root -c  'cd /tmp; ./host-trust.sh'
  cd $working_dir

  sleep 10
done
#####################################

#### run host trust on all nodes
file=/tmp/host_list
for i in `cat $file`
do
  echo "$i"
  scp /tmp/host-trust.sh root@$i:/tmp
  runuser -l root -c "ssh root@$i '/tmp/host-trust.sh'"
done
#####################

##### get ca password to encrypt key
mkdir -p /etc/kolla/config/octavia
cp /tmp/client.cert-and-key.pem /etc/kolla/config/octavia
cp /tmp/client_ca.cert.pem /etc/kolla/config/octavia
cp /tmp/server_ca.cert.pem /etc/kolla/config/octavia
cp /tmp/server_ca.key.pem /etc/kolla/config/octavia
chmod 777 /etc/kolla/config/octavia/*.*
ca_pwd=`awk '/^octavia_ca_password/{print $NF}' /etc/kolla/passwords.yml`
### pull generated password from password.yml file in /etc/kolla/passwords.yml
openssl rsa -aes192 -in /etc/kolla/config/octavia/server_ca.key.pem -out /etc/kolla/config/octavia/server_ca2.key.pem -passout pass:$ca_pwd
rm -rf server_ca.key.pem
mv /etc/kolla/config/octavia/server_ca2.key.pem /etc/kolla/config/octavia/server_ca.key.pem
chmod 600 /etc/kolla/config/octavia/*.*
#########################

kolla-ansible -i /etc/kolla/multinode bootstrap-servers
kolla-ansible -i /etc/kolla/multinode prechecks

DEPLOY=1
while [[ $DEPLOY > 0 ]]; do

  kolla-ansible -i /etc/kolla/multinode deploy

  pip3 install python-openstackclient --ignore-installed
  kolla-ansible post-deploy

  #stupid hack
  working_dir=`pwd`
  chmod 777 /tmp/control-trust.sh
  runuser -l root -c  'cd /tmp; ./control-trust.sh'
  cd $working_dir
  #sleep 5

  #load setup for validator
  cd /etc/kolla
  . ./admin-openrc.sh

  export KOLLA_DEBUG=0
  export ENABLE_EXT_NET=1
  export EXT_NET_CIDR=192.168.1.0/24
  export EXT_NET_RANGE='start=192.168.1.149,end=192.168.1.220'
  export EXT_NET_GATEWAY=192.168.1.1

  #use for loading time as opposed to needing the image
  wget https://cloud-images.ubuntu.com/bionic/current/bionic-server-cloudimg-amd64.img
  openstack image create --public --min-disk 3 --container-format bare \
  --disk-format qcow2 --property architecture=x86_64 \
  --property hw_disk_bus=virtio --property hw_vif_model=virtio \
  --file bionic-server-cloudimg-amd64.img \
  "bionic x86_64"

  test=`openstack image show 'bionic x86_64'`
  if [[ "No Image found" == *"$test"* ]]; then
    kolla-ansible -i /etc/kolla/multinode destroy
  else
    DEPLOY=0
  fi
done


cd /usr/local/share/kolla-ansible
./init-runonce

export HOME=/home/stack
cd /tmp

#prepare openstack env for CF
openstack project create cloudfoundry
openstack user create $OPENSTACK_CLOUDFOUNDRY_USERNAME --project cloudfoundry --password $OPENSTACK_CLOUDFOUNDRY_PWD
openstack role add --project cloudfoundry --project-domain default --user $OPENSTACK_CLOUDFOUNDRY_USERNAME --user-domain default Member

openstack floating ip create --description cloudfoundry --project cloudfoundry --project-domain default public1 > /tmp/fip.out
FIP=$(awk '/floating_ip_address/{print $4}' /tmp/fip.out)

ssh-keygen -t rsa -b 4096 -C "bosh" -N "" -f "bosh.pem"
mv -f bosh.pem.pub bosh.pub
openstack keypair create --public-key /tmp/bosh.pub bosh

#download and configure homebrew to run bbl install
curl -fsSL https://mephmanx:$GITHUB_TOKEN@raw.githubusercontent.com/Homebrew/install/master/install.sh -o homebrew.sh
chmod 777 homebrew.sh

PUBLIC_NETWORK_ID="$(openstack network list --name public1 | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }')"

runuser -l stack -c  '/tmp/homebrew.sh </dev/null'
runuser -l stack -c  'echo "eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" >> /opt/stack/.bash_profile'
runuser -l stack -c  'eval $(/home/linuxbrew/.linuxbrew/bin/brew shellenv)'
runuser -l stack -c  'brew tap cloudfoundry/tap'
runuser -l stack -c  'brew install bosh-cli'
runuser -l stack -c  'brew install bbl'

runuser -l stack -c  "echo 'export BBL_IAAS=openstack' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_AUTH_URL=$OS_AUTH_URL' >> /opt/stack/.bash_profile"
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
runuser -l stack -c  "echo 'export OS_AUTH_URL=$OS_AUTH_URL' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_INTERFACE=$OS_INTERFACE' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_ENDPOINT_TYPE=$OS_ENDPOINT_TYPE' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_IDENTITY_API_VERSION=$OS_IDENTITY_API_VERSION' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_REGION_NAME=$OS_REGION_NAME' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_AUTH_PLUGIN=$OS_AUTH_PLUGIN' >> /opt/stack/.bash_profile"

runuser -l stack -c  'bbl up --debug'

############# build octavia image
#curl -L https://install.perlbrew.pl | bash
#source ~/perl5/perlbrew/etc/bashrc
#perlbrew init
#perlbrew install --force perl-5.16.3
#perlbrew switch perl-5.16.3
runuser -l root -c  'yum install -y debootstrap qemu-img git e2fsprogs policycoreutils-python-utils'
git clone https://opendev.org/openstack/octavia -b master
pip3 install diskimage-builder
cd octavia/diskimage-create
chmod 777 diskimage-create.sh
runuser -l root -c  '/tmp/octavia/diskimage-create/diskimage-create.sh'

openstack image create amphora-x64-haproxy \
  --container-format bare \
  --disk-format qcow2 \
  --private \
  --tag amphora \
  --file /root/amphora-x64-haproxy.qcow2 \
  --property hw_architecture='x86_64' \
  --property hw_rng_model=virtio

test=`openstack image show 'amphora-x64-haproxy'`
while [[ "No Image found" == *"$test"* ]]
do
  openstack image create amphora-x64-haproxy \
    --container-format bare \
    --disk-format qcow2 \
    --private \
    --tag amphora \
    --file /root/amphora-x64-haproxy.qcow2 \
    --property hw_architecture='x86_64' \
    --property hw_rng_model=virtio
  test=`openstack image show 'amphora-x64-haproxy'`
  sleep 10
done
#########################

git clone https://github.com/cloudfoundry-attic/bosh-openstack-environment-templates.git
cd bosh-openstack-environment-templates/cf-deployment-tf

wget https://releases.hashicorp.com/terraform/0.11.14/terraform_0.11.14_linux_amd64.zip
unzip terraform_0.11.14_linux_amd64.zip

CF_NET_ID=`openstack network list --project cloudfoundry | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'`

sed  '/provider "openstack" {/a use_octavia   = true' ./cf.tf >> cf.tf-new
rm -rf cf.tf
mv cf.tf-new cf.tf

cat > terraform.tfvars <<EOF
auth_url = "$OS_AUTH_URL"
domain_name = "default"
user_name = "lguser"
password = "$OPENSTACK_LGUSER_PWD"
project_name = "cloudfoundry"
region_name = "us-east"
availability_zones = ["nova","nova","nova"]
ext_net_name = "public1"

# the OpenStack router id which can be used to access the BOSH network
bosh_router_id = "`openstack router list --project cloudfoundry | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'`"

# in case Openstack has its own DNS servers
dns_nameservers = ["8.8.8.8","8.8.4.4"]

# does BOSH use a local blobstore? Set to 'false', if your BOSH Director uses e.g. S3 to store its blobs
use_local_blobstore = "true" #default is true

# enable TCP routing setup
use_tcp_router = "true" #default is true
num_tcp_ports = 100 #default is 100, needs to be > 0

# in case of self signed certificate select one of the following options
# cacert_file = "<path-to-certificate>"
# insecure = "true"
EOF
./terraform init
./terraform apply -auto-approve > /tmp/terraf.out

#openstack security group create --project cloudfoundry cf  --description "CloudFoundry Security Group"
#openstack security group rule create cf --protocol any --remote-ip 0.0.0.0/0 --egress
#openstack security group rule create cf --protocol any --remote-ip ::/0 --egress
#openstack security group rule create cf --protocol udp --remote-ip 0.0.0.0/0 --ingress --dst-port 68
#openstack security group rule create cf --protocol icmp --remote-ip 0.0.0.0/0 --ingress
#openstack security group rule create cf --protocol tcp --remote-ip 0.0.0.0/0 --ingress --dst-port 22
#openstack security group rule create cf --protocol tcp --remote-ip 0.0.0.0/0 --ingress --dst-port 80
#openstack security group rule create cf --protocol tcp --remote-ip 0.0.0.0/0 --ingress --dst-port 443
#openstack security group rule create cf --protocol tcp --remote-ip 0.0.0.0/0 --ingress --dst-port 4443
#openstack security group rule create cf --protocol tcp --remote-ip 0.0.0.0/0 --ingress
#
#openstack flavor create minimal --id 6 --ram 3840 --ephemeral 10 --vcpus 1
#openstack flavor create small --id 7 --ram 7680 --ephemeral 14 --vcpus 2
#openstack flavor create small-highmem --id 8 --ram 31232 --ephemeral 10 --vcpus 4
#openstack flavor create small-50GB-ephemeral-disk --id 9 --ram 7680 --ephemeral 50 --vcpus 2
#openstack flavor create small-highmem-100GB-ephemeral-disk --id 10 --ram 31232 --ephemeral 100 --vcpus 4

cd /tmp
git clone https://github.com/cloudfoundry/cf-deployment

source /opt/stack/.bash_profile
eval "$(bbl print-env -s /opt/stack)"

export STEMCELL_VERSION=$(bosh interpolate /tmp/cf-deployment/cf-deployment.yml --path=/stemcells/alias=default/version)
bosh upload-stemcell https://bosh-core-stemcells.s3-accelerate.amazonaws.com/$STEMCELL_VERSION/bosh-stemcell-$STEMCELL_VERSION-openstack-kvm-ubuntu-xenial-go_agent-raw.tgz
bosh update-runtime-config /opt/stack/bosh-deployment/runtime-configs/dns.yml --name dns -n

bosh update-cloud-config \
     -v availability_zone1="nova" \
     -v availability_zone2="nova" \
     -v availability_zone3="nova" \
     -v network_id1="$CF_NET_ID" \
     -v network_id2="$CF_NET_ID" \
     -v network_id3="$CF_NET_ID" \
     /tmp/cf-deployment/iaas-support/openstack/cloud-config.yml -n
bosh -d cf deploy /tmp/cf-deployment/cf-deployment.yml -o /tmp/cf-deployment/operations/openstack.yml \
  --vars-store /tmp/vars/deployment-vars.yml \
  -v system_domain=app.lyonsgroup.family -n

#prepare jumpbox access
#bosh int /opt/stack/vars/jumpbox-vars-store.yml --path /jumpbox_ssh/private_key > jumpbox.key
#chmod 600 jumpbox.key
#export JP_IP=`bosh int /tmp/vars/jumpbox-vars-file.yml --path /external_ip`
#
#git clone https://github.com/cloudfoundry/cf-deployment
#export STEMCELL_VERSION=$(bosh int /cf-deployment/cf-deployment.yml --path /stemcells/alias=default/version)
#export DIRECTOR_ADDRESS=`bbl director-address`
#bbl print-env > /tmp/init.sh
#bbl director-ca-cert > bosh-director.crt
#echo 'export BOSH_ENVIRONMENT='$DIRECTOR_ADDRESS >> /tmp/init.sh
#echo 'bosh alias-env cloudfoundry;bosh log-in;' >> /tmp/init.sh
#
##delete proxy line
#sed '/BOSH_ALL_PROXY/d' /tmp/init.sh > /tmp/init-env.sh
#rm -rf init.sh
#sed '/CREDHUB_PROXY/d' /tmp/init-env.sh > /tmp/init.sh
#
#scp -i jumpbox.key bosh-director.crt jumpbox@192.168.0.183:/tmp
#scp -i jumpbox.key init.sh jumpbox@192.168.0.183:/tmp
#
##use jumpbox to build out cloudfoundry env
#SCRIPT="
#source /tmp/init.sh
#sudo curl -o /usr/local/bin/jumpbox https://raw.githubusercontent.com/starkandwayne/jumpbox/master/bin/jumpbox;
#sudo chmod 0755 /usr/local/bin/jumpbox;
#sudo jumpbox system;
#
#bosh upload-stemcell https://bosh-core-stemcells.s3-accelerate.amazonaws.com/$STEMCELL_VERSION/bosh-stemcell-$STEMCELL_VERSION-openstack-kvm-ubuntu-xenial-go_agent-raw.tgz
#bosh update-cloud-config /cf-deployment/iaas-support/openstack/cloud-config.yml
#
#bosh -d cf deploy /cf-deployment/cf-deployment.yml -o /cf-deployment/operations/openstack.yml --vars-store /vars/deployment-vars.yml -v system_domain=app.lyonsgroup.family
#"
#
#ssh jumpbox@$JP_IP  -i jumpbox.key '$SCRIPT'

alternatives --set python /usr/bin/python3
#remove so as to not run again
rm -rf /etc/rc.d/rc.local
