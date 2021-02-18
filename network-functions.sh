source ./vm-functions.sh

ADDRESS=1

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
    if [[ "${element}" =~ .*"Internal".* ]]; then
      ip_addr="11.0.0.${ADDRESS}"
      addresses+=($ip_addr)
      network_lines+=("network  --device=ens${net_names[ct]} --bootproto=static --onboot=yes --ipv6=auto --activate --ip=$ip_addr\n")
    else
      network_lines+=("network  --device=ens${net_names[ct]} --bootproto=dhcp --onboot=yes --ipv6=auto --activate\n")
    fi
    ((ADDRESS++))
    ((ct++))
  done

  for ip in "${addresses[@]}"
  do
    echo "runuser -l root -c  'ssh-keyscan -H $ip >> ~/.ssh/known_hosts';" >> /tmp/additional_hosts
  done

  printf -v net_line_string '%s ' "${network_lines[@]}"
  sed -i 's/{NETWORK}/'$net_line_string'/g' ${kickstart_file}
}

