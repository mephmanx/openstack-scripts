#!/bin/bash

source /tmp/openstack-scripts/vm-configurations.sh
source /tmp/project_config.sh

NETMASK="255.255.255.0"

function networkInformation {
  kickstart_file=$1
  vm_type=$2
  host=$3

  if [[ "kolla" != "$vm_type" ]]; then
    echo "$host" >> /tmp/host_list
  else
    echo "" >> /tmp/host_list
  fi

  vmstr=$(vm_definitions "$vm_type")
  vm_str=${vmstr//[$'\t\r\n ']}

  network_string=$(parse_json "$vm_str" "network_string")

  IFS=',' read -r -a net_array <<< "$network_string"
  network_lines=()
  ct=1
  addresses=()
  default_flag="0"
  for element in "${net_array[@]}"
  do
#    default_set="--nodefroute"
    default_set=""
    if [[ "${element}" =~ .*"static".* ]]; then
      ##check if internal or external network and set ip/gateway accordingly
      ip_addr="${NETWORK_PREFIX}.${CORE_VM_START_IP}"

      if ! grep -q $host "/tmp/dns_hosts"; then
          #add localhost entry
        echo "runuser -l root -c  'echo "$ip_addr $host" >> /etc/hosts;'" >> /tmp/dns_hosts
        addresses+=($ip_addr)
      fi

        # If storage address, add to array to build rings later
      if [[ "$vm_type" == "storage" ]]; then
          echo "$ip_addr" >> /tmp/storage_hosts
      fi

      if [[ $default_flag == "0" ]]; then
        default_set=""
        network_lines+=("network  --device=enp${ct}s0 --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$GATEWAY_ROUTER_IP --netmask=$NETMASK --nameserver=$GATEWAY_ROUTER_IP ${default_set}\n")
        default_flag="1"
      else
        network_lines+=("network  --device=enp${ct}s0 --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$GATEWAY_ROUTER_IP --netmask=$NETMASK --nameserver=$GATEWAY_ROUTER_IP ${default_set}\n")
      fi

      ((CORE_VM_START_IP++))

    #not static, do DHCP
    else
      network_lines+=("network  --device=enp${ct}s0 --bootproto=dhcp --noipv6 --onboot=yes --activate --nodefroute\n")
    fi
    ((ct++))
  done

  for ip in "${addresses[@]}"
  do
    echo "runuser -l root -c  'ssh-keyscan -H $ip >> ~/.ssh/known_hosts';" >> /tmp/additional_hosts
  done

  printf -v net_line_string '%s ' "${network_lines[@]}"
  sed -i 's/{NETWORK}/'$net_line_string'/g' ${kickstart_file}
}

