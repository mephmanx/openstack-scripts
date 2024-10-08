#!/bin/bash

rm -rf /var/log/cloud-install.log
exec 1>/var/log/cloud-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x

. ./iso-functions.sh
. ./vm-configurations.sh


######### VM Counts
control_count=$(getVMCount "control")
network_count=$(getVMCount "network")
compute_count=$(getVMCount "compute")
monitoring_count=$(getVMCount "monitoring")
storage_count=$(getVMCount "storage")

### add vm's to array
vms=()
while [ "$control_count" -gt 0 ]; do
  printf -v control_count_format "%02d" "$control_count"
  echo "add vm to create string -> control$control_count_format"
  vms+=("control$control_count_format")
  control_count=$((control_count - 1))
done

while [ "$network_count" -gt 0 ]; do
  printf -v network_count_format "%02d" "$network_count"
  echo "add vm to create string -> network$network_count_format"
  vms+=("network$network_count_format")
  network_count=$((network_count - 1))
done

while [ "$compute_count" -gt 0 ]; do
  printf -v compute_count_format "%02d" "$compute_count"
  echo "add vm to create string -> compute$compute_count_format"
  vms+=("compute$compute_count_format")
  compute_count=$((compute_count - 1))
done

while [ "$monitoring_count" -gt 0 ]; do
  printf -v monitoring_count_format "%02d" "$monitoring_count"
  echo "add vm to create string -> monitoring$monitoring_count_format"
  vms+=("monitoring$monitoring_count_format")
  monitoring_count=$((monitoring_count - 1))
done

while [ "$storage_count" -gt 0 ]; do
  printf -v storage_count_format "%02d" "$storage_count"
  echo "add vm to create string -> storage$storage_count_format"
  vms+=("storage$storage_count_format")
  storage_count=$((storage_count - 1))
done

############  Build and push custom iso's for VM types
for d in "${vms[@]}"; do
  echo "building and pushing ISO for $d"
  buildAndPushVMTypeISO "$d"
done
#############################

wait
#############  create setup vm
echo "creating openstack setup vm"

buildAndPushOpenstackSetupISO
########################

