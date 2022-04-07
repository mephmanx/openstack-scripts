#!/bin/bash

rm -rf /root/cloud-install.log
exec 1>/root/cloud-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x

source /tmp/vm_functions.sh
source /tmp/vm-configurations.sh
source /tmp/project_config.sh

IFS=

telegram_notify  "Building cloud install data structures...."
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

echo "VM's to be created"
echo "${vms[@]}"

########### create vm's
index=0
for d in "${vms[@]}"; do
  printf -v vm_type_n '%s\n' "${d//[[:digit:]]/}"
  vm_type=$(tr -dc '[[:print:]]' <<< "$vm_type_n")
  echo "creating vm of type -> $vm_type"
  telegram_notify  "Creating cloud vm: $d"
  create_vm_kvm $vm_type $d
  sleep 30
  ((index++))
done

wait
