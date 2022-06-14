#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/openstack-env.sh
. /tmp/project_config.sh

# shellcheck disable=SC2120
start() {

exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

### system profile
tuned-adm profile virtual-guest
#############

# add stack user with passwordless sudo privs
add_stack_user

### module recommended on openstack.org
modprobe vhost_net

#####  setup global VIPs
SUPPORT_VIP_DNS="$SUPPORT_HOST.$INTERNAL_DOMAIN_NAME"
INTERNAL_VIP_DNS="$APP_INTERNAL_HOSTNAME.$INTERNAL_DOMAIN_NAME"
EXTERNAL_VIP_DNS="$APP_EXTERNAL_HOSTNAME.$INTERNAL_DOMAIN_NAME"
###################

############ add keys
working_dir=$(pwd)
chmod +x /tmp/host-trust.sh
runuser -l root -c  'cd /tmp; ./host-trust.sh'
cd "$working_dir" || exit

ADMIN_PWD={CENTOS_ADMIN_PWD_123456789012}

########### set up registry connection to docker hub
export etext=$(echo -n "admin:$ADMIN_PWD" | base64)
status_code=$(curl https://$SUPPORT_VIP_DNS/api/v2.0/registries --write-out %{http_code} -k --silent --output /dev/null -H "authorization: Basic $etext" )

if [[ "$status_code" -ne 200 ]] ; then
  telegram_notify  "Harbor install failed!"
  exit 1
else
  telegram_notify  "Harbor install successful. Hypervisor SSH keys added to VM's. continuing install..."
fi

unset HOME

###  Make sure noting goes into the /home/stack folder
mkdir /home/stack
chown stack /home/stack
runuser -l root -c  'su - stack'
########################


export PYTHONIOENCODING=UTF-8;
# update pip to required version
PATH=$PATH:$HOME/bin:/usr/local/bin
####
pip3 install --no-index --find-links="/root/PyRepo" pip==21.3.1
pip3 install --ignore-installed --no-index --find-links="/root/PyRepo" -r /root/python.modules

python3 -m venv /opt/stack/venv
source /opt/stack/venv/bin/activate

pip3 install --no-index --find-links="/root/PyRepo" pip==21.3.1
pip3 install --ignore-installed --no-index --find-links="/root/PyRepo" -r /root/python.modules
####

mkdir -p /etc/kolla

cp -r /opt/stack/venv/share/kolla-ansible/etc_examples/kolla/* /etc/kolla
cp /opt/stack/venv/share/kolla-ansible/ansible/inventory/* /etc/kolla
mkdir -p /var/lib/kolla/config_files

telegram_notify  "Loading Openstack Kolla deployment playbook and performing env customization...."
cp /tmp/globals.yml /etc/kolla/globals.yml

sed -i "s/{INTERNAL_VIP}/${INTERNAL_VIP}/g" /etc/kolla/globals.yml
sed -i "s/{INTERNAL_VIP_DNS}/${INTERNAL_VIP_DNS}/g" /etc/kolla/globals.yml
sed -i "s/{EXTERNAL_VIP}/${EXTERNAL_VIP}/g" /etc/kolla/globals.yml
sed -i "s/{EXTERNAL_VIP_DNS}/${EXTERNAL_VIP_DNS}/g" /etc/kolla/globals.yml
sed -i "s/{SUPPORT_HOST}/${SUPPORT_VIP_DNS}/g" /etc/kolla/globals.yml
sed -i "s/{LB_NETWORK}/${LB_NETWORK}/g" /etc/kolla/globals.yml
sed -i "s/{LB_ROUTER_IP}/${LB_ROUTER_IP}/g" /etc/kolla/globals.yml
sed -i "s/{LB_DHCP_START}/${LB_DHCP_START}/g" /etc/kolla/globals.yml
sed -i "s/{LB_DHCP_END}/${LB_DHCP_END}/g" /etc/kolla/globals.yml
sed -i "s/{INTERNAL_DOMAIN_NAME}/${INTERNAL_DOMAIN_NAME}/g" /etc/kolla/globals.yml

kolla-genpwd

#### Replace passwords
sed -i "s/docker_registry_password: null/docker_registry_password: ${ADMIN_PWD}/g" /etc/kolla/passwords.yml
sed -i "s/keystone_admin_password: .*/keystone_admin_password: ${ADMIN_PWD}/g" /etc/kolla/passwords.yml
sed -i "s/kibana_password: .*/kibana_password: ${ADMIN_PWD}/g" /etc/kolla/passwords.yml
sed -i "s/grafana_admin_password: .*/grafana_admin_password: ${ADMIN_PWD}/g" /etc/kolla/passwords.yml
#####

######  prepare storage rings
export KOLLA_SWIFT_BASE_IMAGE="${SUPPORT_VIP_DNS}/kolla/centos-binary-swift-base:$OPENSTACK_VERSION"
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
  chmod +x /tmp/host-trust.sh
  runuser -l root -c  'cd /tmp; ./host-trust.sh'
  cd $working_dir

  sleep 10
  ((test_loop_count++))

  if [[ $test_loop_count -gt 10 ]]; then
    telegram_notify  "Not all Openstack VM's successfully came up, install ending.  Please check logs!"
    exit 1
  fi
done
rm -rf /tmp/ping.txt
rm -rf /tmp/host_count
#####################################

### host ping successful, all hosts came up properly
telegram_notify  "All Openstack VM's came up properly and are ready for install. continuing..."
#############

#### run host trust on all nodes
file=/tmp/host_list

### configure docker repo to pull from local cache
echo "runuser -l root -c  'echo 127.0.0.1 download.docker.com >> /etc/hosts;'" | cat - /tmp/host-trust.sh > temp && mv -f temp /tmp/host-trust.sh
for i in `cat $file`
do
  echo "$i"
  scp /tmp/host-trust.sh root@$i:/tmp
  runuser -l root -c "ssh root@$i 'chmod 777 /tmp/host-trust.sh; /tmp/host-trust.sh'"
done
rm -rf /tmp/host_trust
#####################

## generate octavia certs
kolla-ansible octavia-certificates
###########

sed -i 's/docker_yum_url: "https:\/\/download.docker.com\/linux\/{{ ansible_facts.distribution | lower }}"/docker_yum_url: http:\/\/localhost:8080/g' /usr/local/share/kolla-ansible/ansible/roles/baremetal/defaults/main.yml
sed -i 's/docker_yum_baseurl: "{{ docker_yum_url }}\/\$releasever\/\$basearch\/stable"/docker_yum_baseurl: "{{ docker_yum_url }}\/docker-ce-stable"/g' /usr/local/share/kolla-ansible/ansible/roles/baremetal/defaults/main.yml

kolla-ansible -i /etc/kolla/multinode bootstrap-servers
kolla-ansible -i /etc/kolla/multinode prechecks

export KOLLA_DEBUG=0
export ENABLE_EXT_NET=1
export EXT_NET_CIDR="$GATEWAY_ROUTER_IP/24"
export EXT_NET_RANGE="start=$OPENSTACK_DHCP_START,end=$OPENSTACK_DHCP_END"
export EXT_NET_GATEWAY=$GATEWAY_ROUTER_IP

### pull docker images
telegram_notify  "Analyzing Kolla Openstack configuration and pull docker images for cache priming...."

## look for any failures and run again if any fail.   continue until cache is full or 10 tries are made
cache_ct=10
cache_out=`kolla-ansible -i /etc/kolla/multinode pull`
failure_occur=`echo $cache_out | grep -o 'FAILED' | wc -l`
while [ $failure_occur -gt 0 ]; do
  cache_out=`kolla-ansible -i /etc/kolla/multinode pull`
  failure_occur=`echo $cache_out | grep -o 'FAILED' | wc -l`
  if [[ $cache_ct == 0 ]]; then
    telegram_notify  "Cache prime failed after 10 retries, failing.  Check logs to resolve issue."
    exit 1
  fi
  ((cache_ct--))
done

rm -rf /opt/stack/cache_out
telegram_notify  "Cache pull/prime complete!  Install continuing.."

### nova.conf options
#echo "[libvirt]" >> /etc/kolla/config/nova.conf
#echo "swtpm_enabled=true" >> /etc/kolla/config/nova.conf
echo "[DEFAULT]" >> /etc/kolla/config/nova.conf
echo "resume_guests_state_on_host_boot=true" >> /etc/kolla/config/nova.conf

#echo "[vnc]" >> /etc/kolla/config/nova.conf
#echo "novncproxy_base_url=https://$APP_EXTERNAL_HOSTNAME.$EXTERNAL_DOMAIN_NAME:6080/vnc_auto.html" >> /etc/kolla/config/nova.conf
#####
#
##### keystone.conf options
#echo "[cors]" >> /etc/kolla/config/keystone.conf
#echo "allowed_origin = https://$APP_EXTERNAL_HOSTNAME.$EXTERNAL_DOMAIN_NAME:3000" >> /etc/kolla/config/keystone.conf
#######

telegram_notify  "Openstack Kolla Ansible deploy task execution begun....."
kolla-ansible -i /etc/kolla/multinode deploy

### grab last set of lines from log to send
LOG_TAIL=`tail -25 /tmp/openstack-install.log`
###

## point to local docker repo
sed -i "s/docker_yum_url: \"http:\/\/localhost:8080/docker-ce-stable\"/g"  /usr/local/share/kolla-ansible/ansible/roles/baremetal/defaults/main.yml
sed -i "s/docker_yum_baseurl: \"{{ docker_yum_url }}\"/g"   /usr/local/share/kolla-ansible/ansible/roles/baremetal/defaults/main.yml

kolla-ansible post-deploy

telegram_debug_msg  "End of Openstack Install log -> $LOG_TAIL"
telegram_notify  "Openstack Kolla Ansible deploy task execution complete.  Performing post install tasks....."
#stupid hack
working_dir=`pwd`
chmod +x /tmp/control-trust.sh
runuser -l root -c  'cd /tmp; ./control-trust.sh'
cd $working_dir
rm -rf /tmp/control-trust.sh

#load setup for validator
export REQUESTS_CA_BUNDLE=/etc/ipa/ca.crt
cd /etc/kolla
. ./admin-openrc.sh
sleep 180

## adding cinder v2 endpoints
###  Only for Openstack Wallaby and below, CinderV2 is NOT POSSIBLE TO ENABLE on Xena and above!
openstack service create --name cinderv2 --description "OpenStack Block Storage" volumev2
openstack endpoint create --region us-east volumev2 public http://$INTERNAL_VIP_DNS:8776/v2/%\(project_id\)s
openstack endpoint create --region us-east volumev2 internal http://$INTERNAL_VIP_DNS:8776/v2/%\(project_id\)s
openstack endpoint create --region us-east volumev2 admin http://$INTERNAL_VIP_DNS:8776/v2/%\(project_id\)s
#############

cd /opt/stack/venv/share/kolla-ansible
./init-runonce

export HOME=/home/stack
cd /tmp

### trove setup
export TROVE_CIDR="$TROVE_NETWORK.0/24"
export TROVE_RANGE="start=$TROVE_DHCP_START,end=$TROVE_DHCP_END"
export TROVE_GATEWAY="$TROVE_NETWORK.1"

openstack image create trove-master-guest-ubuntu --private --disk-format qcow2 --container-format bare --tag trove --tag mysql --tag mariadb --tag postgresql --file /tmp/trove_db-$TROVE_DB_VERSION.img
openstack image create trove-base --disk-format qcow2 --container-format bare --file /tmp/trove_instance-$UBUNTU_VERSION.img

test=`openstack image show 'trove-base'`
if [[ "No Image found" == *"$test"* ]]; then
  telegram_notify  "Trove base image install failed! Please review!"
  exit 1
fi

openstack network create trove-net
openstack subnet create --subnet-range $TROVE_CIDR  --gateway $TROVE_GATEWAY --network trove-net --allocation-pool $TROVE_RANGE --dns-nameserver $IDENTITY_VIP trove-subnet0

openstack router create trove-router
openstack router set --external-gateway public1 trove-router
openstack router add subnet trove-router trove-subnet0

####

### make change to cluster.yaml for magnum upstream error, remove when resolved

####

### magnum cluster create
openstack image create \
                      --disk-format=qcow2 \
                      --container-format=bare \
                      --file=/tmp/magnum-$MAGNUM_IMAGE_VERSION.qcow2 \
                      --property os_distro='fedora-atomic' \
                      fedora-atomic-latest

telegram_notify  "Magnum image installed, continuing install..."

## create network, subnet, and loadbalancer
openstack coe cluster template create swarm-cluster-template \
          --image fedora-atomic-latest \
          --external-network public1 \
          --dns-nameserver $IDENTITY_VIP \
          --network-driver docker \
          --docker-storage-driver overlay2 \
          --docker-volume-size 10 \
          --master-flavor m1.small \
          --flavor m1.small \
          --coe swarm-mode

telegram_notify  "Created magnum cluster..."

openstack coe cluster create gocd-cluster \
                        --cluster-template swarm-cluster-template \
                        --master-count 1 \
                        --node-count 2 \
                        --keypair mykey

telegram_notify  "Openstack installed and accepting images, continuing install..."
##############

#prepare openstack env for CF
telegram_notify  "Preparing Openstack environment for BOSH install...."
## generate cloudfoundry admin pwd
OPENSTACK_CLOUDFOUNDRY_PWD=$(generate_random_pwd 31)

export OPENSTACK_CLOUDFOUNDRY_USERNAME=osuser

openstack project create cloudfoundry
openstack user create $OPENSTACK_CLOUDFOUNDRY_USERNAME --project cloudfoundry --password $OPENSTACK_CLOUDFOUNDRY_PWD
openstack role add --project cloudfoundry --project-domain default --user $OPENSTACK_CLOUDFOUNDRY_USERNAME --user-domain default admin

##### quota configuration
## get max available memory
memStr=`runuser -l root -c "ssh root@compute01 'cat /proc/meminfo | grep MemTotal'"`
mem=`echo $memStr | awk -F' ' '{ print $2 }'`
### allocation for openstack docker processes & os
quotaRam=$((mem / 1024 - 8000))

## get cpu count for quota
cat > /tmp/cpu_count.sh <<EOF
grep -c ^processor /proc/cpuinfo
EOF
scp /tmp/cpu_count.sh root@compute01:/tmp
CPU_COUNT=`runuser -l root -c "ssh root@compute01 'chmod +x /tmp/cpu_count.sh; cd /tmp; ./cpu_count.sh'"`

## get cinder volume size
cinder_vol_size="`runuser -l root -c "ssh root@compute01 'df -h / --block-size G' | sed 1d"`"
cinder_quota=$(echo "$cinder_vol_size" | awk '{print $4}' | tr -d '<G')
cinder_q=`printf "%.${2:-0}f" "$cinder_quota"`
## overcommit scale by 10
openstack quota set --cores $((CPU_COUNT * 3)) cloudfoundry

### cloudfoundry quotas
openstack quota set --instances 100 cloudfoundry
openstack quota set --ram $quotaRam cloudfoundry
openstack quota set --secgroups 100 cloudfoundry
openstack quota set --secgroup-rules 200 cloudfoundry
openstack quota set --volumes 100 cloudfoundry
openstack quota set --gigabytes $cinder_q cloudfoundry
###########

### octavia quotas
openstack quota set --cores -1 service
openstack quota set --instances -1 service
openstack quota set --ram -1 service
openstack quota set --secgroups -1 service
openstack quota set --secgroup-rules -1 service
openstack quota set --volumes -1 service
###############

### cloudfoundry flavors
openstack flavor create --ram 3840 --ephemeral 10 --vcpus 1 --public minimal
openstack flavor create --ram 7680 --ephemeral 14 --vcpus 2 --public small
openstack flavor create --ram 31232 --ephemeral 60 --vcpus 4 --public small-highmem
openstack flavor create --ram 7680 --ephemeral 50 --vcpus 2 --public small-50GB-ephemeral-disk
openstack flavor create --ram 31232 --ephemeral 100 --vcpus 4 --public small-highmem-100GB-ephemeral-disk
#####

## enable TPM for all flavors
#flavor_list=`openstack flavor list | awk '{print $4}' | sed 2d`
#read -ra flavors -d '' <<<"$flavor_list"
#for f in "${flavors[@]}"; do
#  openstack flavor set $f \
#      --property hw:tpm_version=2.0 \
#      --property hw:tpm_model=tpm-crb
#done
###########

telegram_notify  "Cloudfoundry Openstack project ready.  user -> $OPENSTACK_CLOUDFOUNDRY_USERNAME pwd -> $OPENSTACK_CLOUDFOUNDRY_PWD"
telegram_debug_msg  "Openstack admin pwd is $ADMIN_PWD"

#### start logstash container on monitoring01

cat > /tmp/monitoring01-logstash.sh <<EOF
# Create logstash configurations
mkdir /root/logstash-docker
cd /root/logstash-docker

# Clone sample files
git clone https://github.com/pfelk/docker.git
cp -r docker/etc .

# Remove repository
rm -rf docker

# Update elasticsearch hostname
sed -i "s/es01/$INTERNAL_VIP_DNS/g" etc/logstash/config/logstash.yml
sed -i "s/es01/$INTERNAL_VIP_DNS/g" etc/pfelk/conf.d/50-outputs.conf

# Port 5140 is already in use by some other process, going to use a different port range (5540,5541)
sed -i "s/5140/5540/g" etc/pfelk/conf.d/01-inputs.conf
sed -i "s/5141/5541/g" etc/pfelk/conf.d/01-inputs.conf

# Set Device names
sed -i "s/OPNsense/pfSense/g" etc/pfelk/conf.d/02-types.conf
sed -i "s/Supermicro/$INTERNAL_DOMAIN_NAME/g" etc/pfelk/conf.d/01-inputs.conf

# Create Index Patterns for indexes
# Need to run this command on any of control node
# It will through an error related to (_ilm) policy which is fine, since we don't have x-pack on elasticsearch server
ssh root@control01 curl -q https://raw.githubusercontent.com/pfelk/pfelk/main/etc/pfelk/scripts/pfelk-template-installer.sh | sed -e "s/localhost/control01/g" | bash

# ISSUE: unboubd, _grokparsefailure
#
# https://githubmemory.com/repo/pfelk/pfelk/issues/213
# Requires to set pfSense->Services->DNS Rsolver->Advanced Settings->Advanced Resolver Options->Log Level to "Level 0: No logging"
# Requires to add following option in pfSense->Services->DNS Rsolver->Custom Options
# server:
# log-queries: yes
# server:include: /var/unbound/pfb_dnsbl.*conf
#
# And apply changes to remove "unbound, _grokparsefailure" issue

# pfSense-Haproxy Logs
# Set value of pfSense->Services->HAproxy->Loggin->Remote syslog host to "monitoring01:5190"
# Set ->Syslog facility to "local0"
# Set ->Syslog level to "Informational"
# Set/Update ->HAproxy->Frontend->(*)->Advanced pass thru to "option httplog"
# OR add following line in haproxy.cf to enable it for all frontends instead of adding to every frontend manually
# defaults:
# option httplog

# Start the logstash container
docker run -d -v /root/logstash-docker/etc/logstash/config:/usr/share/logstash/config:ro -v /root/logstash-docker/etc/pfelk:/etc/pfelk:ro -e "LS_JAVA_OPTS=-Xmx1G -Xms1G" --network=host --restart=always --name logstash docker.elastic.co/logstash/logstash:7.10.2
EOF

scp /tmp/monitoring01-logstash.sh root@monitoring01:/tmp
runuser -l root -c "ssh root@monitoring01 'chmod +x /tmp/monitoring01-logstash.sh; cd /tmp; ./monitoring01-logstash.sh'"
runuser -l root -c "ssh root@monitoring01 'docker exec grafana grafana-cli plugins install grafana-worldmap-panel'"
runuser -l root -c "ssh root@monitoring01 'docker restart grafana'"
####

### enable haproxy (and any others) to log to monitoring01:5190
### <remotesyslog>monitoring01:5190</remotesyslog>

### load octavia creds and upload amphora image
source /etc/kolla/octavia-openrc.sh
openstack image create amphora-x64-haproxy \
  --container-format bare \
  --disk-format qcow2 \
  --tag amphora \
  --private \
  --file /tmp/amphora-x64-haproxy-$AMPHORA_VERSION.qcow2 \
  --property hw_architecture='x86_64' \
  --property hw_rng_model=virtio

test=`openstack image show 'amphora-x64-haproxy'`
if [[ "No Image found" == *"$test"* ]]; then
  telegram_notify  "Amphora image install failed! Please review!"
  exit 1
fi
#########################

### reload openstack admin creds
source /etc/kolla/admin-openrc.sh
######

telegram_notify  "Amphora image install complete"
####

#download and configure homebrew to run bbl install
telegram_notify  "Starting Homebrew install...."

telegram_notify  "Found Homebrew cache, using cache for install...."
runuser -l root -c  'mkdir -p /home/linuxbrew'
runuser -l root -c  "tar -xf /tmp/homebrew-$CF_BBL_INSTALL_TERRAFORM_VERSION.tar -C /home/linuxbrew"
runuser -l stack -c  "echo 'PATH=$PATH:/home/linuxbrew/.linuxbrew/bin' >> /opt/stack/.bash_profile"
runuser -l stack -c  'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)" >> /opt/stack/.bash_profile'
runuser -l root -c  'chown -R stack /home/linuxbrew/.linuxbrew/Cellar /home/linuxbrew/.linuxbrew/Homebrew /home/linuxbrew/.linuxbrew/bin /home/linuxbrew/.linuxbrew/etc /home/linuxbrew/.linuxbrew/etc/bash_completion.d /home/linuxbrew/.linuxbrew/include /home/linuxbrew/.linuxbrew/lib /home/linuxbrew/.linuxbrew/lib/pkgconfig /home/linuxbrew/.linuxbrew/opt /home/linuxbrew/.linuxbrew/sbin /home/linuxbrew/.linuxbrew/share /home/linuxbrew/.linuxbrew/share/doc /home/linuxbrew/.linuxbrew/share/info /home/linuxbrew/.linuxbrew/share/man /home/linuxbrew/.linuxbrew/share/man/man1 /home/linuxbrew/.linuxbrew/share/man/man3 /home/linuxbrew/.linuxbrew/share/man/man7 /home/linuxbrew/.linuxbrew/share/zsh /home/linuxbrew/.linuxbrew/share/zsh/site-functions /home/linuxbrew/.linuxbrew/var/homebrew/linked /home/linuxbrew/.linuxbrew/var/homebrew/locks'
runuser -l root -c  'chmod u+w /home/linuxbrew/.linuxbrew/Cellar /home/linuxbrew/.linuxbrew/Homebrew /home/linuxbrew/.linuxbrew/bin /home/linuxbrew/.linuxbrew/etc /home/linuxbrew/.linuxbrew/etc/bash_completion.d /home/linuxbrew/.linuxbrew/include /home/linuxbrew/.linuxbrew/lib /home/linuxbrew/.linuxbrew/lib/pkgconfig /home/linuxbrew/.linuxbrew/opt /home/linuxbrew/.linuxbrew/sbin /home/linuxbrew/.linuxbrew/share /home/linuxbrew/.linuxbrew/share/doc /home/linuxbrew/.linuxbrew/share/info /home/linuxbrew/.linuxbrew/share/man /home/linuxbrew/.linuxbrew/share/man/man1 /home/linuxbrew/.linuxbrew/share/man/man3 /home/linuxbrew/.linuxbrew/share/man/man7 /home/linuxbrew/.linuxbrew/share/zsh /home/linuxbrew/.linuxbrew/share/zsh/site-functions /home/linuxbrew/.linuxbrew/var/homebrew/linked /home/linuxbrew/.linuxbrew/var/homebrew/locks'
runuser -l stack -c  'cd /opt/stack; source .bash_profile;'

PUBLIC_NETWORK_ID="$(openstack network list --name public1 | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }')"

telegram_notify  "Starting BOSH infrastructure install...."
runuser -l stack -c  "echo 'export BBL_IAAS=openstack' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export BBL_OPENSTACK_AUTH_URL=http://$INTERNAL_VIP_DNS:5000/v3' >> /opt/stack/.bash_profile"
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
runuser -l stack -c  "echo 'export OS_AUTH_URL=http://$INTERNAL_VIP_DNS:5000/v3' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_INTERFACE=$OS_INTERFACE' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_ENDPOINT_TYPE=$OS_ENDPOINT_TYPE' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_IDENTITY_API_VERSION=$OS_IDENTITY_API_VERSION' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_REGION_NAME=$OS_REGION_NAME' >> /opt/stack/.bash_profile"
runuser -l stack -c  "echo 'export OS_AUTH_PLUGIN=$OS_AUTH_PLUGIN' >> /opt/stack/.bash_profile"
runuser -l stack -c  'bbl plan'

sed -i "s/~> 1.16/$CF_BBL_OPENSTACK_CPI_VERSION/g" /opt/stack/terraform/bbl-template.tf
sed -i "s/8.8.8.8/$IDENTITY_VIP/g" /opt/stack/terraform/bbl-template.tf
sed -i "s/8.8.8.8/$IDENTITY_VIP/g" /opt/stack/jumpbox-deployment/jumpbox.yml
sed -i "s/8.8.8.8/$IDENTITY_VIP/g" /opt/stack/bosh-deployment/bosh.yml
sed -i "s/8.8.8.8/$IDENTITY_VIP/g" /opt/stack/cloud-config/ops.yml

runuser -l stack -c  "cat > /opt/stack/trusted-certs.vars.yml <<EOF
trusted_certs: |-
EOF"

cp /etc/ipa/ca.crt /opt/stack
sed -i 's/^/  /' /opt/stack/ca.crt
runuser -l stack -c  'cat /opt/stack/ca.crt >> /opt/stack/trusted-certs.vars.yml'

runuser -l stack -c  "cat > /opt/stack/add-trusted-certs-to-director-vm.ops.yml <<EOF
- type: replace
  path: /releases/name=os-conf?
  value:
    name: os-conf
    version: $CF_BBL_OS_CONF_RELEASE
    url: https://bosh.io/d/github.com/cloudfoundry/os-conf-release?v=$CF_BBL_OS_CONF_RELEASE
    sha1: $CF_BBL_OS_CONF_HASH

- type: replace
  path: /instance_groups/name=bosh/jobs/-
  value:
    name: ca_certs
    release: os-conf
    properties:
      certs: ((trusted_certs))
EOF"

length=$(wc -c </opt/stack/create-director.sh)
if [ "$length" -ne 0 ] && [ -z "$(tail -c -1 </opt/stack/create-director.sh)" ]; then
  # The file ends with a newline or null
  dd if=/dev/null of=/opt/stack/create-director.sh obs="$((length-1))" seek=1
fi

length=$(wc -c </opt/stack/create-jumpbox.sh)
if [ "$length" -ne 0 ] && [ -z "$(tail -c -1 </opt/stack/create-jumpbox.sh)" ]; then
  # The file ends with a newline or null
  dd if=/dev/null of=/opt/stack/create-jumpbox.sh obs="$((length-1))" seek=1
fi

### modify director / jumpbox  here
### create-director changes
chown -R stack /tmp/bosh-*.tgz
runuser -l stack -c  "echo '-o /opt/stack/bosh-deployment/misc/trusted-certs.yml --var-file=trusted_ca_cert=/opt/stack/id_rsa.crt \
                            -o /opt/stack/add-trusted-certs-to-director-vm.ops.yml  -l /opt/stack/trusted-certs.vars.yml  \
                            -o /opt/stack/bosh-deployment/misc/no-internet-access/stemcell.yml -v local_stemcell=/tmp/bosh-$STEMCELL_STAMP.tgz' >> /opt/stack/create-director.sh"

## create-jumpbox changes
runuser -l stack -c  "echo ' -o /opt/stack/bosh-deployment/misc/no-internet-access/stemcell.yml -v local_stemcell=/tmp/bosh-$STEMCELL_STAMP.tgz ' >> /opt/stack/create-jumpbox.sh"
####

### deploy bosh!
echo "error" > /tmp/bbl_up.log
bbl_error_count=`grep -i "error" /tmp/bbl_up.log | wc -l`
bbl_retry_count=5
if [[ $bbl_error_count -gt 0 ]]; then
  while [ $bbl_retry_count -gt 0 ]; do
    rm -rf /tmp/bbl_up.log
    runuser -l stack -c  'bbl up --debug > /tmp/bbl_up.log'
    bbl_error_count=`grep -i "error" /tmp/bbl_up.log | wc -l`
    if [[ $bbl_error_count == 0 ]]; then
      break
    fi
    sleep 30
    ((bbl_retry_count--))
  done
fi
#####

telegram_notify  "BOSH jumpbox and director installed, loading terraform cf for prepare script..."
#### prepare env for cloudfoundry
unzip /tmp/cf-templates.zip -d /tmp/bosh-openstack-environment-templates
mv /tmp/bosh-openstack-environment-templates/bosh-openstack-environment-templates-master/* /tmp/bosh-openstack-environment-templates
cd /tmp/bosh-openstack-environment-templates
chown -R stack cf-deployment-tf/
cd cf-deployment-tf
cp /tmp/terraform_cf-$CF_ATTIC_TERRAFORM_VERSION.zip ./

unzip terraform_cf-$CF_ATTIC_TERRAFORM_VERSION.zip
chmod +x terraform
chown -R stack terraform

sed -i '/provider "openstack" {/a use_octavia   = true' ./cf.tf
sed -i "/use_octavia   = true/a version = \"$CF_BBL_OPENSTACK_CPI_VERSION\"" ./cf.tf
## add availability zones to the list below for a full HA deploy
cat > terraform.tfvars <<EOF
auth_url = "http://$INTERNAL_VIP_DNS:5000/v3"
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
dns_nameservers = ["$IDENTITY_VIP"]

# does BOSH use a local blobstore? Set to 'false', if your BOSH Director uses e.g. S3 to store its blobs
use_local_blobstore = "true" #default is true

# enable TCP routing setup
use_tcp_router = "true" #default is true
num_tcp_ports = $CF_TCP_PORT_COUNT #default is 100, needs to be > 0

# in case of self signed certificate select one of the following options
cacert_file = "/etc/ipa/ca.crt"
insecure = "false"
EOF

telegram_notify  "Executing env prep script..."
runuser -l stack -c  "cd /tmp/bosh-openstack-environment-templates/cf-deployment-tf; ./terraform init; ./terraform plan;"

echo "error" > /tmp/terraf-bbl.out
tf_error_count=`grep -i "error" /tmp/terraf-bbl.out | wc -l`
tf_retry_count=5
if [[ $tf_error_count -gt 0 ]]; then
  while [ $tf_retry_count -gt 0 ]; do
    rm -rf /tmp/terraf-bbl.out
    runuser -l stack -c  "cd /tmp/bosh-openstack-environment-templates/cf-deployment-tf; ./terraform apply -auto-approve" > /tmp/terraf-bbl.out
    tf_error_count=`grep -i "error" /tmp/terraf-bbl.out | wc -l`
    if [[ $tf_error_count == 0 ]]; then
      break
    else
      runuser -l stack -c  "cd /tmp/bosh-openstack-environment-templates/cf-deployment-tf; ./terraform destroy -auto-approve"
    fi
    sleep 30
    ((tf_retry_count--))
  done
fi
################
sleep 30;
### update cf-lb to preconfigured address
LB_FIXED_IP="$CLOUDFOUNDRY_VIP"
LB_PROJECT_ID=`openstack loadbalancer show cf-lb -f value -c project_id`
LB_VIP_ADDRESS=`openstack loadbalancer show cf-lb -f value -c vip_address`
LB_VIP_PORT_ID=`openstack loadbalancer show cf-lb -f value -c vip_port_id`
LB_FLOATING_IP=`openstack floating ip list -f value -c "Floating IP Address" -c "Fixed IP Address" | grep ${LB_VIP_ADDRESS} | cut -d" " -f1`
LB_FIP_SUBNET=`openstack subnet show  public1-subnet -f value -c id`
LB_FIP_NETWORK_ID=`openstack network show public1 -f value -c id`

openstack floating ip delete ${LB_FLOATING_IP}
openstack floating ip create --subnet ${LB_FIP_SUBNET} \
                              --project ${LB_PROJECT_ID} \
                              --port ${LB_VIP_PORT_ID} \
                              --fixed-ip-address ${LB_VIP_ADDRESS} \
                              --floating-ip-address ${LB_FIXED_IP} ${LB_FIP_NETWORK_ID}
###

telegram_notify  "Env prep script complete, pulling CF deployment repo...."
unzip /tmp/cf_deployment-$CF_DEPLOY_VERSION.zip -d /tmp/cf-deployment
mv /tmp/cf-deployment/cf-deployment-main/* /tmp/cf-deployment
chown -R stack /tmp/cf-deployment

###  build swift tmp url key to use below
telegram_notify  "Setting up swift blobstore key..."

### generate swift container key
SWIFT_KEY=$(generate_random_pwd 31)

cat > /tmp/swift.key <<EOF
$SWIFT_KEY
EOF

swift post -m "Temp-URL-Key:$SWIFT_KEY" \
            -A http://$INTERNAL_VIP_DNS:5000/v3 \
            -U $OPENSTACK_CLOUDFOUNDRY_USERNAME \
            -K $OPENSTACK_CLOUDFOUNDRY_PWD \
            -V 3 \
            --os-project-name cloudfoundry \
            --os-project-domain-name default

telegram_notify  "Swift blobstores key ready, pulling latest CF stemcell..."

### load bbl/bosh env
cp /etc/kolla/admin-openrc.sh /opt/stack/admin-openrc.sh
chown stack /opt/stack/admin-openrc.sh
runuser -l stack -c  "source /opt/stack/admin-openrc.sh"
runuser -l stack -c  "source /opt/stack/.bash_profile"

#### prep variables

### push cached stemcells to cloud
stemcell_path="/tmp/stemcell-*-$STEMCELL_STAMP.tgz"
chown -R stack /tmp/stemcell-*-$STEMCELL_STAMP.tgz

for stemcell in $stemcell_path; do
  echo "queued" > /tmp/stemcell-upload.log
  queued_count=`grep -i "queued" /tmp/stemcell-upload.log | wc -l`
  while [ $queued_count -gt 0 ]; do
    rm -rf /tmp/stemcell-upload.log
    IFS=$'\n'
    for image in $(openstack image list | grep 'queued' | awk -F'|' '{ print $2 }' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'); do
      openstack image delete $image
    done
    runuser -l stack -c  "cd /opt/stack; bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
                              chmod +x /tmp/bbl_env.sh; \
                              source /tmp/bbl_env.sh; \
                              bosh upload-stemcell $stemcell"
    runuser -l stack -c "openstack image list | grep 'queued'" > /tmp/stemcell-upload.log
    queued_count=`grep -i "queued" /tmp/stemcell-upload.log | wc -l`
    sleep 30
  done
  rm -rf /tmp/stemcell-upload.log
  sleep 30
done

telegram_notify  "Stemcell installed, finalizing environment for CF install..."
## add cf and cf-deployment-for-bosh security groups to bosh director
## very important!
## change to cloudfoundry account
export OS_PROJECT_NAME=cloudfoundry
export OS_USERNAME=$OPENSTACK_CLOUDFOUNDRY_USERNAME
export OS_PASSWORD=$OPENSTACK_CLOUDFOUNDRY_PWD

openstack server add security group bosh/0 cf-deployment-for-bosh
openstack security group create bosh
openstack security group rule create --proto tcp --dst-port 22:22 bosh
openstack security group rule create --proto tcp --dst-port 6868:6868 bosh
openstack security group rule create --proto tcp --dst-port 25555:25555 bosh
openstack security group rule create --proto tcp --dst-port 1:65535 --remote-group $(openstack security group show bosh | grep id | head -n 1 | cut -d"|" -f3 | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }') bosh
openstack security group rule create --proto tcp --dst-port 1:65535 --remote-group $(openstack security group show cf | grep id | head -n 1 | cut -d"|" -f3 | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }') bosh
openstack security group rule create --proto tcp --dst-port 1:65535 --remote-group $(openstack security group show bosh | grep id | head -n 1 | cut -d"|" -f3 | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }') cf
openstack server add security group bosh/0 bosh
openstack server add security group bosh/0 cf

## switch back to admin
source /etc/kolla/admin-openrc.sh

### update runtime and cloud config
export CF_NET_ID_1=`openstack network list --project cloudfoundry --name cf-z0 | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'`
#export CF_NET_ID_2=`openstack network list --project cloudfoundry --name cf-z1 | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'`
#export CF_NET_ID_3=`openstack network list --project cloudfoundry --name cf-z2 | awk -F'|' ' NR > 3 && !/^+--/ { print $2} ' | awk '{ gsub(/^[ \t]+|[ \t]+$/, ""); print }'`
## modify net id's if AZ's added to terraform script above for HA
runuser -l stack -c  "cd /opt/stack; \
                      bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
                      chmod +x /tmp/bbl_env.sh; \
                      source /tmp/bbl_env.sh; \
                      bosh update-runtime-config /opt/stack/bosh-deployment/runtime-configs/dns.yml --name dns -n"

runuser -l stack -c  "cd /opt/stack; \
                      bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
                      chmod +x /tmp/bbl_env.sh; \
                      source /tmp/bbl_env.sh; \
                      bosh update-cloud-config  -v availability_zone1=nova \
                          -v availability_zone2=nova \
                          -v availability_zone3=nova \
                          -v network_id1=$CF_NET_ID_1 \
                          -v network_id2=$CF_NET_ID_1 \
                          -v network_id3=$CF_NET_ID_1 \
                          /tmp/cf-deployment/iaas-support/openstack/cloud-config.yml -n"

telegram_notify  "Executing Cloudfoundry install.  Should take about 30 - 45 min..."

## pull logging repo
#git clone https://github.com/bosh-prometheus/prometheus-boshrelease /tmp/prometheus-boshrelease
#chown -R stack /tmp/prometheus-boshrelease

### prepare google SAML config and include it in deploy

### prep cloudfoundry ca cert
runuser -l stack -c  "cat > /opt/stack/trusted-certs-cf.vars.yml <<EOF
trusted_cert_for_apps:
  ca: |
EOF"

cp /etc/ipa/ca.crt /opt/stack/ca.crt
sed -i 's/^/  /' /opt/stack/ca.crt
runuser -l stack -c  'cat /opt/stack/ca.crt >> /opt/stack/trusted-certs-cf.vars.yml'
######

### add internal override to director
cat > /opt/stack/expect.sh <<FILEEND
#!/usr/bin/expect -f
set timeout -1
spawn /bin/bash
send "source /opt/stack/.bash_profile\r"
send "source /tmp/bbl_env.sh\r"

send "bbl ssh --director\r"
expect "yes/no"
send -- "yes\r"
expect "bosh/0"
send -- "echo '$GATEWAY_ROUTER_IP $INTERNAL_VIP_DNS' | sudo tee -a /etc/hosts > /dev/null; echo '$GATEWAY_ROUTER_IP $EXTERNAL_VIP_DNS' | sudo tee -a /etc/hosts > /dev/null; exit;\r"
expect "closed."
exit;
expect eof
FILEEND

chmod +x /opt/stack/expect.sh
pwd=`pwd`
cd /opt/stack
./expect.sh
cd $pwd
#########

### deploy cloudfoundry
#this is to make the CF install fall into the below loop as it seems to need 2 deployments to fully deploy
## would be good to fix but was suggested by community so....
echo "error" > /tmp/cloudfoundry-install.log
### Cloudfoundry install can fail at times.  BOSH can handle this and retry is fine.  Retry a few times and if fail still occurs, alert admin
error_count=`grep -i "error" /tmp/cloudfoundry-install.log | wc -l`
retry_count=5
if [[ $error_count -gt 0 ]]; then
  while [ $retry_count -gt 0 ]; do
    rm -rf /tmp/cloudfoundry-install.log
    runuser -l stack -c  "cd /opt/stack; \
                      bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
                      chmod +x /tmp/bbl_env.sh; \
                      source /tmp/bbl_env.sh; \
                      bosh -d cf deploy \
                      -o /tmp/cf-deployment/operations/openstack.yml \
                      -o /tmp/cf-deployment/operations/scale-to-one-az.yml \
                      -o /tmp/cf-deployment/operations/use-trusted-ca-cert-for-apps.yml \
                      -o /tmp/cf-deployment/operations/use-latest-stemcell.yml \
                      -o /tmp/cf-deployment/operations/use-compiled-releases.yml \
                      -o /tmp/cf-deployment/operations/use-external-blobstore.yml \
                      -o /tmp/cf-deployment/operations/use-swift-blobstore.yml \
                      -l /opt/stack/trusted-certs-cf.vars.yml \
                      -v system_domain=$INTERNAL_DOMAIN_NAME \
                      -v auth_url=http://$INTERNAL_VIP_DNS:5000/v3 \
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
                      --vars-store /tmp/vars/deployment-vars.yml \
                      /tmp/cf-deployment/cf-deployment.yml \
                      -n" > /tmp/cloudfoundry-install.log

    error_count1=`grep -i "error" /tmp/cloudfoundry-install.log | wc -l`
    error_count2=`grep -i "Error" /tmp/cloudfoundry-install.log | wc -l`
    error_count=$(($error_count1 + $error_count2))
    if [[ $error_count == 0 ]]; then
      break
    fi
    telegram_debug_msg  "Cloudfoundry install failed, retrying $retry_count more times..."
    sleep 30
    ((retry_count--))
  done
fi

### grab last set of lines from log to send
LOG_TAIL=`tail -25 /tmp/cloudfoundry-install.log`
###

## run volume errand
#runuser -l stack -c "bosh -d cf run-errand nfs-broker-push"

telegram_debug_msg  "Cloudfoundry install tail -> $LOG_TAIL"
telegram_notify  "Cloudfoundry install complete!  Beginning Stratos UI deploy"

# cf api login
## use folder for auth token
CF_HOME=$(mktemp -d /tmp/cfhome.9999.XXX)
runuser -l stack -c "cf login -a http://api.$INTERNAL_DOMAIN_NAME -u admin -p $OPENSTACK_CLOUDFOUNDRY_PWD"

## create org
runuser -l stack -c "cf create-org $INTERNAL_DOMAIN_NAME"

# create cf spaces
runuser -l stack -c "cf create-space -o system system"
runuser -l stack -c "cf create-space -o $INTERNAL_DOMAIN_NAME prod"
runuser -l stack -c "cf create-space -o $INTERNAL_DOMAIN_NAME uat"

# enable docker support
runuser -l stack -c "cf enable-feature-flag diego_docker"
#cf enable-service-access nfs -o $INTERNAL_DOMAIN_NAME

## change to prod dir for deploy
runuser -l stack -c "cf target -o 'system' -s 'system'"
runuser -l stack -c "cf update-quota default -i 2G -m 4G"

### determine quota formula.  this is memory on compute server to be made available for cloudfoundry org.
memStrFree=`runuser -l root -c "ssh root@compute01 'cat /proc/meminfo | grep MemFree'"`
memFree=`echo $memStrFree | awk -F' ' '{ print $2 }'`
memGB=$((memFree / 1024 / 1024 * CF_MEMORY_ALLOCATION_PCT / 100))
runuser -l stack -c "cf create-quota $INTERNAL_DOMAIN_NAME -i 8096M -m "$memGB"G -r 1000 -s 1000 -a 1000 --allow-paid-service-plans --reserved-route-ports $CF_TCP_PORT_COUNT"
runuser -l stack -c "cf set-quota $INTERNAL_DOMAIN_NAME $INTERNAL_DOMAIN_NAME"

### install security group
export PT_CT="$CF_TCP_PORT_COUNT"
export PORTS=()
while [ $PT_CT -gt -1 ]; do
  PORTS+=($((1024 + $PT_CT)))
  ((PT_CT--))
done
PORTS+=("80")
PORTS+=("443")
PORTS+=("2222")
printf -v cf_tcp_ports '%s,' "${PORTS[@]}"
cf_tcp_ports=`echo $cf_tcp_ports | rev | cut -c 2- | rev`
cat > /opt/stack/asg.json <<EOF
[
  {
    "protocol": "icmp",
    "destination": "0.0.0.0/0",
    "type": 0,
    "code": 0
  },
  {
    "protocol": "tcp",
    "destination": "10.1.0.0/24",
    "ports": "$cf_tcp_ports",
    "log": true,
    "description": "Allow http and https traffic to Gateway Net"
  }
]
EOF

runuser -l stack -c "cf create-security-group ASG /opt/stack/asg.json"
runuser -l stack -c "cf bind-running-security-group ASG"
## push logging
# get latest stemcell
#runuser -l stack -c  "cd /opt/stack; bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
#                      chmod 700 /tmp/bbl_env.sh; \
#                      source /tmp/bbl_env.sh; \
#                      bosh upload-release https://github.com/bosh-prometheus/node-exporter-boshrelease/releases/download/v5.0.0/node-exporter-5.0.0.tgz"
#
#cat > /tmp/node-exporter.yml <<EOF
#releases:
#  - name: node-exporter
#    version: 5.0.0
#
#addons:
#  - name: node_exporter
#    jobs:
#      - name: node_exporter
#        release: node-exporter
#    include:
#      stemcell:
#        - os: ubuntu-trusty
#        - os: ubuntu-xenial
#        - os: ubuntu-bionic
#    properties: {}
#EOF
#
#runuser -l stack -c  "cd /opt/stack; bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
#                      chmod 700 /tmp/bbl_env.sh; \
#                      source /tmp/bbl_env.sh; \
#                      bosh update-runtime-config /tmp/node-exporter.yml"
#
#
#
### update cloud-config
### vm_type used for prometheus/grafana
#runuser -l stack -c  "cd /opt/stack; \
#                      bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
#                      chmod 700 /tmp/bbl_env.sh; \
#                      source /tmp/bbl_env.sh; \
#                      bosh cloud-config > /tmp/cloud-config.yml"
#
#cat > /tmp/default.yml <<EOF
#- cloud_properties:
#    instance_type: m1.small
#  name: default
#EOF
#
#
#
#echo -e "$(grep "directorSSLCA" /opt/stack/bbl-state.json | awk '{print $2, $3, $4}' | tr -d '",')" > /tmp/bosh_ca
#runuser -l stack -c  "cd /opt/stack; \
#                      bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
#                      chmod 700 /tmp/bbl_env.sh; \
#                      source /tmp/bbl_env.sh; \
#                      bosh -d prometheus deploy /tmp/prometheus-boshrelease/manifests/prometheus.yml \
#                        --vars-store /tmp/vars/deployment-vars.yml \
#                        -o /tmp/prometheus-boshrelease/manifests/operators/monitor-bosh.yml \
#                        -o /tmp/prometheus-boshrelease/manifests/operators/enable-cf-route-registrar.yml \
#                        -o /tmp/prometheus-boshrelease/manifests/operators/monitor-cf.yml \
#                        -v bosh_url="$(grep "directorAddress" /opt/stack/bbl-state.json | awk '{print $2}' | tr -d '",')" \
#                        -v bosh_username="$(grep "directorUsername" /opt/stack/bbl-state.json | awk '{print $2}' | tr -d '",')" \
#                        -v bosh_password="$(grep "directorPassword" /opt/stack/bbl-state.json | awk '{print $2}' | tr -d '",')" \
#                        --var-file bosh_ca_cert=/tmp/bosh_ca \
#                        -v metrics_environment=prod \
#                        -v metron_deployment_name=cf \
#                        -v system_domain=$INTERNAL_DOMAIN_NAME \
#                        -v traffic_controller_external_port=443 \
#                        -v skip_ssl_verify=true \
#                        -v uaa_clients_cf_exporter_secret=test \
#                        -v uaa_clients_firehose_exporter_secret=test \
#                        -v cf_deployment_name=cf \
#  -n" > /tmp/prometheus-install.log

#runuser -l stack -c  "cd /opt/stack; \
#                      bbl print-env -s /opt/stack > /tmp/bbl_env.sh; \
#                      chmod 700 /tmp/bbl_env.sh; \
#                      source /tmp/bbl_env.sh; \
#bosh -d prometheus deploy /tmp/prometheus-boshrelease/manifests/prometheus.yml \
#  --vars-store tmp/deployment-vars.yml \
#    -n" > /tmp/prometheus-install.log

#push stratos
git clone https://github.com/SUSE/stratos.git /tmp/stratos
runuser -l stack -c "cf push console -f /tmp/stratos/manifest-docker.yml -k 2G"
runuser -l stack -c "cf scale console -i 2"

## Stratos complete!
rm -rf $CF_HOME
telegram_notify  "Stratos deployment complete!  access at console.$INTERNAL_DOMAIN_NAME user -> admin , pwd -> $OPENSTACK_CLOUDFOUNDRY_PWD"

#### update keystone for ldap, run at the very end as it disables keystone db auth.  disables admin and osuser accounts!
#DIRECTORY_MGR_PWD=`cat /tmp/directory_mgr_pwd`
#control_ct=$CONTROL_COUNT
#cat > /tmp/ldap.sh <<EOF
#echo "[identity]" >> /etc/kolla/keystone/keystone.conf
#echo "driver = ldap" >> /etc/kolla/keystone/keystone.conf
#echo "[assignment]" >> /etc/kolla/keystone/keystone.conf
#echo "driver = sql" >> /etc/kolla/keystone/keystone.conf
#
#echo "[ldap]" >> /etc/kolla/keystone/keystone.conf
#echo "url = ldap://$IDENTITY_VIP" >> /etc/kolla/keystone/keystone.conf
#echo "user = cn=Directory Manager" >> /etc/kolla/keystone/keystone.conf
#echo "password = $DIRECTORY_MGR_PWD" >> /etc/kolla/keystone/keystone.conf
#echo "suffix = $(baseDN)" >> /etc/kolla/keystone/keystone.conf
#
#echo "user_tree_dn = cn=users,cn=accounts,$(baseDN)" >> /etc/kolla/keystone/keystone.conf
#echo "user_objectclass = inetOrgPerson" >> /etc/kolla/keystone/keystone.conf
#echo "group_tree_dn = cn=groups,cn=accounts,$(baseDN)" >> /etc/kolla/keystone/keystone.conf
#echo "group_objectclass = groupOfNames" >> /etc/kolla/keystone/keystone.conf
#echo "user_filter = (memberof=cn=openstack-admins,cn=groups,cn=accounts,$(baseDN))" >> /etc/kolla/keystone/keystone.conf
#
#### user mapping
#echo "user_id_attribute      = cn" >> /etc/kolla/keystone/keystone.conf
#echo "user_name_attribute    = sn" >> /etc/kolla/keystone/keystone.conf
#echo "user_mail_attribute    = mail" >> /etc/kolla/keystone/keystone.conf
#echo "user_pass_attribute    = userPassword" >> /etc/kolla/keystone/keystone.conf
#echo "user_enabled_attribute = userAccountControl" >> /etc/kolla/keystone/keystone.conf
#echo "user_enabled_mask      = 2" >> /etc/kolla/keystone/keystone.conf
#echo "user_enabled_invert    = false" >> /etc/kolla/keystone/keystone.conf
#echo "user_enabled_default   = 512" >> /etc/kolla/keystone/keystone.conf
#echo "user_default_project_id_attribute =" >> /etc/kolla/keystone/keystone.conf
#echo "user_additional_attribute_mapping =" >> /etc/kolla/keystone/keystone.conf
#
#echo "group_id_attribute     = cn" >> /etc/kolla/keystone/keystone.conf
#echo "group_name_attribute   = ou" >> /etc/kolla/keystone/keystone.conf
#echo "group_member_attribute = member" >> /etc/kolla/keystone/keystone.conf
#echo "group_desc_attribute   = description" >> /etc/kolla/keystone/keystone.conf
#echo "group_additional_attribute_mapping =" >> /etc/kolla/keystone/keystone.conf
#docker restart keystone;
#EOF
#while [[ $control_ct -gt 0 ]]; do
#  scp /tmp/ldap.sh root@control0$control_ct:/tmp
#  runuser -l root -c "ssh root@control0$control_ct 'cd /tmp; chmod 777 ldap.sh; ./ldap.sh'"
#  ((control_ct--))
#done
#####

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

restrict_to_root

chmod +x /etc/rc.d/rc.local
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