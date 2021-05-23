#!/bin/bash

IFS=
ssh-keygen -t rsa -b 4096 -C "openstack-setup" -N "" -f /tmp/openstack-setup.key <<<y 2>&1 >/dev/null
##################### Prep
rm -rf /tmp/additional_hosts
touch /tmp/additional_hosts
chmod 777 /tmp/additional_hosts

rm -rf /tmp/dns_hosts
touch /tmp/dns_hosts
chmod 777 /tmp/dns_hosts

rm -rf /tmp/storage_hosts
touch /tmp/storage_hosts
chmod 777 /tmp/storage_hosts

rm -rf /tmp/host_list
touch /tmp/host_list
chmod 777 /tmp/host_list

rm -rf /tmp/global_addresses.sh
touch /tmp/global_addresses.sh
chmod 777 /tmp/global_addresses.sh
####################

#################### Global address setup
INTERNAL_VIP="10.0.20.254"
INTERNAL_VIP_DNS="$APP_INTERNAL_HOSTNAME.$DOMAIN_NAME"

EXTERNAL_VIP="192.168.1.252"
EXTERNAL_VIP_DNS="$APP_EXTERNAL_HOSTNAME.$DOMAIN_NAME"
##############################################

#### setup static network local DNS entries
echo "export EXTERNAL_VIP=$EXTERNAL_VIP" >> /tmp/global_addresses.sh
echo "export INTERNAL_VIP=$INTERNAL_VIP" >> /tmp/global_addresses.sh
echo "export EXTERNAL_VIP_DNS=$EXTERNAL_VIP_DNS" >> /tmp/global_addresses.sh
echo "export INTERNAL_VIP_DNS=$INTERNAL_VIP_DNS" >> /tmp/global_addresses.sh

echo "echo '$EXTERNAL_VIP $EXTERNAL_VIP_DNS' >> /etc/hosts;" >> /tmp/dns_hosts
echo "echo '$INTERNAL_VIP $INTERNAL_VIP_DNS' >> /etc/hosts;" >> /tmp/dns_hosts
####  make sure to use an in-memory network for docker pull through cache otherwise 500's occur
echo "echo '10.0.20.200 cloudsupport.lyonsgroup.family' >> /etc/hosts;" >> /tmp/dns_hosts
#########################

######### Openstack VM types

######### VM Counts
control_count=$(getVMCount "control")
network_count=$(getVMCount "network")
compute_count=$(getVMCount "compute")
monitoring_count=$(getVMCount "monitoring")
storage_count=$(getVMCount "storage")

### add vm's to array
vms=()
host_trust_script=()
control_hack_script=()
while [ $control_count -gt 0 ]; do
  printf -v control_count_format "%02d" $control_count
  echo "add vm to create string -> control$control_count_format"
  vms+=("control$control_count_format")
  host_trust_script+=("runuser -l root -c  'ssh-keyscan -H control$control_count_format >> ~/.ssh/known_hosts';")
  control_hack_script+=("runuser -l root -c  'ssh root@control$control_count_format \"sed -i 's/www_authenticate_uri/auth_uri/g' /etc/kolla/swift-proxy-server/proxy-server.conf\"';")
  control_count=$[$control_count - 1]
done

while [ $network_count -gt 0 ]; do
  printf -v network_count_format "%02d" $network_count
  echo "add vm to create string -> network$network_count_format"
  vms+=("network$network_count_format")
  host_trust_script+=("runuser -l root -c  'ssh-keyscan -H network$network_count_format >> ~/.ssh/known_hosts';")
  network_count=$[$network_count - 1]
done

while [ $compute_count -gt 0 ]; do
  printf -v compute_count_format "%02d" $compute_count
  echo "add vm to create string -> compute$compute_count_format"
  vms+=("compute$compute_count_format")
  host_trust_script+=("runuser -l root -c  'ssh-keyscan -H compute$compute_count_format >> ~/.ssh/known_hosts';")
  compute_count=$[$compute_count - 1]
done

while [ $monitoring_count -gt 0 ]; do
  printf -v monitoring_count_format "%02d" $monitoring_count
  echo "add vm to create string -> monitoring$monitoring_count_format"
  vms+=("monitoring$monitoring_count_format")
  host_trust_script+=("runuser -l root -c  'ssh-keyscan -H monitoring$monitoring_count_format >> ~/.ssh/known_hosts';")
  monitoring_count=$[$monitoring_count - 1]
done

while [ $storage_count -gt 0 ]; do
  printf -v storage_count_format "%02d" $storage_count
  echo "add vm to create string -> storage$storage_count_format"
  vms+=("storage$storage_count_format")
  host_trust_script+=("runuser -l root -c  'ssh-keyscan -H storage$storage_count_format >> ~/.ssh/known_hosts';")
  storage_count=$[$storage_count - 1]
done
