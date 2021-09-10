#!/bin/bash

source ./iso-functions.sh
source ./vm-configurations.sh
source /tmp/openstack-env.sh
source /tmp/project_config.sh
source /tmp/vm_functions.sh

IFS=
HOWLONG=5 ## the number of characters
UNIQUE_SUFFIX=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});

#### store suffix for future use
cat > /tmp/suffix <<EOF
$UNIQUE_SUFFIX
EOF

ssh-keygen -t rsa -b 4096 -C "openstack-setup" -N "" -f /tmp/openstack-setup-${UNIQUE_SUFFIX}.key <<<y 2>&1 >/dev/null
##################### Prep
runuser -l root -c 'rm -rf /tmp/additional_hosts'
touch /tmp/additional_hosts
chmod 700 /tmp/additional_hosts

runuser -l root -c 'rm -rf /tmp/dns_hosts'
touch /tmp/dns_hosts
chmod 700 /tmp/dns_hosts

runuser -l root -c 'rm -rf /tmp/storage_hosts'
touch /tmp/storage_hosts
chmod 700 /tmp/storage_hosts

runuser -l root -c 'rm -rf /tmp/host_list'
touch /tmp/host_list
chmod 700 /tmp/host_list
####################

#################### Global address setup
INTERNAL_VIP_DNS="$APP_INTERNAL_HOSTNAME.$DOMAIN_NAME"
EXTERNAL_VIP_DNS="$APP_EXTERNAL_HOSTNAME.$DOMAIN_NAME"
SUPPORT_VIP_DNS="$SUPPORT_HOST.$DOMAIN_NAME"
##############################################

#### setup static network local DNS entries
echo "runuser -l root -c  'echo "$EXTERNAL_VIP $EXTERNAL_VIP_DNS" >> /etc/hosts;'" >> /tmp/dns_hosts
echo "runuser -l root -c  'echo "$INTERNAL_VIP $INTERNAL_VIP_DNS" >> /etc/hosts;'" >> /tmp/dns_hosts
####  make sure to use an in-memory network for docker pull through cache otherwise 500's occur
echo "runuser -l root -c  'echo "$SUPPORT_VIP $SUPPORT_VIP_DNS" >> /etc/hosts;'" >> /tmp/dns_hosts
#########################
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Building cloud install data structures...."
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

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Deleting any existing cloud vm's....."

echo "VM's to be created"
echo "${vms[@]}"
############## remove vm's
for d in "${vms[@]}"; do
  echo "removing vm -> $d"
  removeVM_kvm "$d"
  sleep 15
done

########## remove kolla
removeVM_kvm "kolla"
####################

############  Build and push custom iso's for VM types
for d in "${vms[@]}"; do
  echo "building and pushing ISO for $d"
  buildAndPushVMTypeISO $d
done
#############################

########### create vm's
index=0
for d in "${vms[@]}"; do
  printf -v vm_type_n '%s\n' "${d//[[:digit:]]/}"
  vm_type=$(tr -dc '[[:print:]]' <<< "$vm_type_n")
  echo "creating vm of type -> $vm_type"
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Creating cloud vm: $d"
  create_vm_kvm $vm_type $d
  sleep 30
  ((index++))
done

wait
#############  create setup vm
printf -v host_trust_string '%s ' "${host_trust_script[@]}"
printf -v control_hack_string '%s ' "${control_hack_script[@]}"
echo "creating openstack setup vm"
buildAndPushOpenstackSetupISO "$host_trust_string" "$control_hack_string" "$(($(getVMCount "control") + $(getVMCount "network") + $(getVMCount "compute") + $(getVMCount "monitoring") + $(getVMCount "storage")))"
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Creating cloud vm: kolla"
create_vm_kvm "kolla" "kolla"
########################

###wait until jobs complete and servers come up
wait
sleep 300
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "All cloud VM's performed 2nd reboot.  Openstack install will begin if VM's came up correctly."
##########

### delete isos when done as they have private info
rm -rf /var/tmp/*.iso
### run host trust to add keys to hypervisor
host_trust_script+=("runuser -l root -c  'ssh-keyscan -H kolla >> ~/.ssh/known_hosts';")
echo $host_trust_script >> /tmp/additional_hosts
runuser -l root -c  'rm -rf /root/.ssh/known_hosts; touch /root/.ssh/known_hosts'
runuser -l root -c  'cd /tmp; ./dns_hosts'
runuser -l root -c  'cd /tmp; ./additional_hosts'
### cleanup
if [[ $HYPERVISOR_DEBUG == 0 ]]; then
  runuser -l root -c  'rm -rf /tmp/additional_hosts'
  runuser -l root -c  'rm -rf /tmp/dns_hosts'
  runuser -l root -c  'rm -rf /tmp/host_list'
  runuser -l root -c  "rm -rf /tmp/openstack-setup-$UNIQUE_SUFFIX.key*"
  runuser -l root -c  'rm -rf /tmp/storage_hosts'
  runuser -l root -c  'rm -rf /tmp/additional_hosts'
  runuser -l root -c  'rm -rf /tmp/suffix'
  runuser -l root -c  'rm -rf /root/*.log'
  runuser -l root -c  'rm -rf /tmp/*.log'
  runuser -l root -c  'rm -rf /tmp/openstack-scripts'
  runuser -l root -c  'rm -rf /tmp/openstack-setup'
fi
######
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Host trust and cleanup scripts run.  Cloud create script is complete.  Next messages will come from cloud VM's."
