source ./vm-configurations.sh

#MariaDB seems to have a problem with 172 addresses.  Dont use!
LOCAL_ADDRESS_PREFIX="10.0.20."
LOCAL_GATEWAY="10.0.20.1"
LOCAL_ADDRESS_INC=20

INTERNAL_ADDRESS_PREFIX="192.168.1."
INTERNAL_GATEWAY="192.168.1.1"
INTERNAL_ADDRESS_INC=20

#do not use external address unless it is a DIRECT connection to the public internet, not through router
EXTERNAL_ADDRESS_PREFIX="10.0.10."
EXTERNAL_GATEWAY="10.0.10.1"
EXTERNAL_ADDRESS_INC=20

NETMASK="255.255.255.0"

#Storage network needs to be one of Internal, External, or Local
STORAGE_NETWORK="loc"

#Default route for system internet connection needs to be one of Internal, External, or Local
DEFAULT_ROUTE="int"

function networkInformation {
  kickstart_file=$1
  vm_type=$2
  host=$3

  if [[ "kolla" != "$vm_type" ]]; then
    echo "$host" >> /tmp/host_list
  else
    echo "" >> /tmp/host_list
  fi

  vmstr=$(vm_definitions_esxi "$vm_type")
  vm_str=${vmstr//[$'\t\r\n ']}

  network_string=$(parse_json "$vm_str" "network_string")

  IFS=',' read -r -a net_array <<< "$network_string"
  network_lines=()
  ct=0
  addresses=()
  default_flag="0"
  for element in "${net_array[@]}"
  do
    default_set="--nodefroute"
    if [[ "${element}" =~ .*"static".* ]]; then
      ##check if internal or external network and set ip/gateway accordingly
      if [[ "${element}" =~ .*"loc".* ]]; then
        ip_addr="${LOCAL_ADDRESS_PREFIX}${LOCAL_ADDRESS_INC}"

        if ! grep -q $host "/tmp/dns_hosts"; then
          #add localhost entry
          echo "echo '$ip_addr $host' >> /etc/hosts;" >> /tmp/dns_hosts
          addresses+=($ip_addr)
        fi

        # If storage address, add to array to build rings later
        if [[ "${element}" =~ .*"$STORAGE_NETWORK".* ]]; then
          if [[ "$vm_type" == "storage" ]]; then
            echo "$ip_addr" >> /tmp/storage_hosts
          fi
        fi

        if [[ $DEFAULT_ROUTE == "loc" ]]; then
          if [[ $default_flag == "0" ]]; then
            default_set=""
            network_lines+=("network  --device=ens${ct} --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$LOCAL_GATEWAY --netmask=$NETMASK --nameserver=$LOCAL_GATEWAY ${default_set}\n")
            default_flag="1"
          else
            network_lines+=("network  --device=ens${ct} --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$LOCAL_GATEWAY --netmask=$NETMASK --nameserver=$LOCAL_GATEWAY ${default_set}\n")
          fi
        else
          network_lines+=("network  --device=ens${ct} --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --netmask=$NETMASK ${default_set}\n")
        fi

        ((LOCAL_ADDRESS_INC++))

      elif [[ "${element}" =~ .*"int".* ]]; then
        ip_addr="${INTERNAL_ADDRESS_PREFIX}${INTERNAL_ADDRESS_INC}"

        if ! grep -q $host "/tmp/dns_hosts"; then
          #add localhost entry
          echo "echo '$ip_addr $host' >> /etc/hosts;" >> /tmp/dns_hosts
          addresses+=($ip_addr)
        fi

        # If storage address, add to array to build rings later
        if [[ "${element}" =~ .*"$STORAGE_NETWORK".* ]]; then
          if [[ "$vm_type" == "storage" ]]; then
            echo "$ip_addr" >> /tmp/storage_hosts
          fi
        fi

        if [[ $DEFAULT_ROUTE == "int" ]]; then
          if [[ $default_flag == "0" ]]; then
            default_set=""
            network_lines+=("network  --device=ens${ct} --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$INTERNAL_GATEWAY --netmask=$NETMASK --nameserver=$INTERNAL_GATEWAY ${default_set}\n")
            default_flag="1"
          else
            network_lines+=("network  --device=ens${ct} --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$INTERNAL_GATEWAY --netmask=$NETMASK --nameserver=$INTERNAL_GATEWAY ${default_set}\n")
          fi
        else
          network_lines+=("network  --device=ens${ct} --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --netmask=$NETMASK ${default_set}\n")
        fi

        ((INTERNAL_ADDRESS_INC++))
      else
        ip_addr="${EXTERNAL_ADDRESS_PREFIX}${EXTERNAL_ADDRESS_INC}"

        if ! grep -q $host "/tmp/dns_hosts"; then
          #add localhost entry
          echo "echo '$ip_addr $host' >> /etc/hosts;" >> /tmp/dns_hosts
          addresses+=($ip_addr)
        fi

        # If storage address, add to array to build rings later
        if [[ "${element}" =~ .*"$STORAGE_NETWORK".* ]]; then
          if [[ "$vm_type" == "storage" ]]; then
            echo "$ip_addr" >> /tmp/storage_hosts
          fi
        fi

        if [[ $DEFAULT_ROUTE == "ext" ]]; then
          if [[ $default_flag == "0" ]]; then
            default_set=""
            network_lines+=("network  --device=ens${ct} --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$EXTERNAL_GATEWAY --netmask=$NETMASK --nameserver=$EXTERNAL_GATEWAY ${default_set}\n")
            default_flag="1"
          else
            network_lines+=("network  --device=ens${ct} --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --gateway=$EXTERNAL_GATEWAY --netmask=$NETMASK --nameserver=$EXTERNAL_GATEWAY ${default_set}\n")
          fi
        else
          network_lines+=("network  --device=ens${ct} --bootproto=static --onboot=yes --noipv6 --activate --ip=$ip_addr --netmask=$NETMASK ${default_set}\n")
        fi

        ((EXTERNAL_ADDRESS_INC++))
      fi

    #not static, do DHCP
    else
      network_lines+=("network  --device=ens${ct} --bootproto=dhcp --noipv6 --onboot=yes --activate\n")
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

