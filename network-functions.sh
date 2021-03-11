source ./vm-configurations.sh

INTERNAL_ADDRESS_INC=20
EXTERNAL_ADDRESS_INC=20

INTERNAL_ADDRESS_PREFIX="11.0.0."
EXTERNAL_ADDRESS_PREFIX="192.168.0."

function networkInformation {
  kickstart_file=$1
  vm_type=$2

  vmstr=$(vm_definitions "$vm_type")
  vm_str=${vmstr//[$'\t\r\n ']}

  network_string=$(parse_json "$vm_str" "network_string")

  IFS=',' read -r -a net_array <<< "$network_string"
  network_lines=()
  ct=0
  net_names=("192" "224" "256" "161")
  addresses=()
  for element in "${net_array[@]}"
  do
    if [[ "${element}" =~ .*"Static".* ]]; then
      ##check if internal or external network and set ip/gateway accordingly
      if [[ "${element}" =~ .*"Internal".* ]]; then
        ip_addr="${INTERNAL_ADDRESS_PREFIX}${INTERNAL_ADDRESS_INC}"
        addresses+=($ip_addr)
        network_lines+=("network  --device=ens${net_names[ct]} --bootproto=static --onboot=yes --activate --ip=$ip_addr --gateway=11.0.0.1 --netmask=255.255.255.0 --nameserver=11.0.0.1\n")
        ((INTERNAL_ADDRESS_INC++))
      else
        ip_addr="${EXTERNAL_ADDRESS_PREFIX}${EXTERNAL_ADDRESS_INC}"
        addresses+=($ip_addr)
        network_lines+=("network  --device=ens${net_names[ct]} --bootproto=static --onboot=yes --activate --ip=$ip_addr --gateway=192.168.0.1 --netmask=255.255.255.0 --nameserver=192.168.0.1\n")
        ((EXTERNAL_ADDRESS_INC++))
      fi
      # If storage address, add to array to build rings later
      if [[ "$vm_type" == "storage" ]]; then
        echo "$ip_addr" >> /tmp/storage_hosts
      fi

    else
      network_lines+=("network  --device=ens${net_names[ct]} --bootproto=dhcp --onboot=yes --activate\n")
    fi
    ((ct++))
  done

  for ip in "${addresses[@]}"
  do
    echo "runuser -l root -c  'ssh-keyscan -H $ip >> ~/.ssh/known_hosts';" >> /tmp/additional_hosts
    echo "cat '$vm_type $ip > /etc/hosts';" >> /tmp/additional_hosts
  done

  printf -v net_line_string '%s ' "${network_lines[@]}"
  sed -i 's/{NETWORK}/'$net_line_string'/g' ${kickstart_file}
}

