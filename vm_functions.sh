#!/bin/bash

. /tmp/project_config.sh
. /tmp/openstack-env.sh

function parse_json() {
  echo "$1" |
    sed -e 's/[{}]/''/g' |
    sed -e 's/", "/'\",\"'/g' |
    sed -e 's/" ,"/'\",\"'/g' |
    sed -e 's/" , "/'\",\"'/g' |
    sed -e 's/","/'\"---SEPERATOR---\"'/g' |
    awk -F=':' -v RS='---SEPERATOR---' "\$1~/\"$2\"/ {print}" |
    sed -e "s/\"$2\"://" |
    tr -d "\n\t" |
    sed -e 's/\\"/"/g' |
    sed -e 's/\\\\/\\/g' |
    sed -e 's/^[ \t]*//g' |
    sed -e 's/^"//' -e 's/"$//'
}

function load_cert_loc_info() {
    IP=$(curl --silent "$EXTERNAL_IP_SERVICE")
    curl --silent "$EXTERNAL_IP_INFO_SERVICE$IP" -o /tmp/ip_out
    tr -d '\n\r ' < /tmp/ip_out > /tmp/ip_out_update
}

function get_drive_name() {
  dir_name=$(find /dev/mapper -maxdepth 1 -type l -name '*cs*' -print -quit)
  DRIVE_NAME=$(grep -oP '(?<=_).*?(?=-)' <<< "$dir_name")
  echo "$DRIVE_NAME"
}

function load_system_info() {
  source /tmp/project_config.sh
  INSTALLED_RAM=$(runuser -l root -c  'dmidecode -t memory | grep  Size: | grep -v "No Module Installed"' | awk '{sum+=$2}END{print sum}')
  RESERVED_RAM=$(( $INSTALLED_RAM * $RAM_PCT_AVAIL_CLOUD/100 ))
  CPU_COUNT=$(lscpu | awk -F':' '$1 == "CPU(s)" {print $2}' | awk '{ gsub(/ /,""); print }')
  DISK_COUNT=$(get_disk_count)
  IP_ADDR=$(ip -f inet addr show ext-con | grep inet | awk -F' ' '{ print $2 }' | cut -d '/' -f1)
  if [ "$DISK_COUNT" -lt 2 ]; then
    DISK_INFO=$(fdisk -l | head -n 1 | awk -F',' '{ print $1 }')
  else
    DISK_INFO="unknown yet"
  fi
  ## build system output to send via telegram
  CPU_INFO="CPU Count: $CPU_COUNT"
  RAM_INFO="Installed RAM: $INSTALLED_RAM GB \r\nReserved RAM: $RESERVED_RAM GB"
  DISK_INFO="Disk Count: $DISK_COUNT \r\n $DISK_INFO"
  IP_INFO="Hypervisor IP: $IP_ADDR"
  DMI_DECODE=$(runuser -l root -c  "dmidecode -t system")
  source /etc/os-release
  OS_INFO=$PRETTY_NAME
  export SYSTEM_INFO="$DMI_DECODE\n\n$OS_INFO\n\n$CPU_INFO\n\n$RAM_INFO\n\n$DISK_INFO\n\n$IP_INFO"
}

function grow_fs() {
  DRIVE_NAME_UPDATE=$(get_drive_name)

  #One time machine setup
  xfsdump -f /tmp/home.dump /home

  umount /home
  lvreduce -L 4G -f /dev/mapper/cs_"${DRIVE_NAME_UPDATE}"-home
  mkfs.xfs -f /dev/mapper/cs_"${DRIVE_NAME_UPDATE}"-home
  lvextend -l +100%FREE /dev/mapper/cs_"${DRIVE_NAME_UPDATE}"-root
  xfs_growfs /dev/mapper/cs_"${DRIVE_NAME_UPDATE}"-root
  mount /dev/mapper/cs_"${DRIVE_NAME_UPDATE}"-home /home
  xfsrestore -f /tmp/home.dump /home
}

function add_stack_user() {
  NEWPW=$(generate_random_pwd 31)

  runuser -l root -c  'mkdir /opt/stack'
  runuser -l root -c  'useradd -s /bin/bash -d /opt/stack -m stack'
  runuser -l root -c  'echo "stack ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/stack'
  runuser -l root -c  'chown -R stack /opt/stack'
  runuser -l root -c  'su - stack'
  runuser -l root -c  "echo $NEWPW | passwd stack --stdin"
}

function restrict_to_root() {
  chmod 700 /tmp/*
  if [[ -d "/etc/kolla" ]]; then
    chmod 700 /etc/kolla/*
    chmod 700 /etc/kolla
  fi
}

function vtpm() {
  unzip /tmp/libtpms-"$SWTPM_VERSION".zip -d /root/libtpms
  unzip /tmp/swtpm-"$SWTPM_VERSION".zip -d /root/swtpm
  mv /root/libtpms/libtpms-master/* /root/libtpms
  mv /root/swtpm/swtpm-master/* /root/swtpm
  ###### vTPM setup #####
  cd /root || exit

  cd libtpms \
   && runuser -l root -c  "echo $(date) > /.date" \
   && runuser -l root -c  'cd libtpms; ./autogen.sh --prefix=/usr --with-openssl --with-tpm2;' \
   && make -j"$(nproc)" V=1 \
   && make -j"$(nproc)" V=1 check \
   && make install

  cd ../swtpm \
   && runuser -l root -c  'cd /root/swtpm; ./autogen.sh --prefix=/usr --with-openssl;' \
   && make -j"$(nproc)" V=1 \
   && make -j"$(nproc)" V=1 VERBOSE=1 check \
   && make -j"$(nproc)" install

  runuser -l root -c  'cd /usr/share/swtpm; ./swtpm-create-user-config-files --overwrite --root;'
  runuser -l root -c  'chown tss:tss /root/.config/*'
  runuser -l root -c  "rm -rf /tmp/libtpms-$SWTPM_VERSION.zip"
  runuser -l root -c  "rm -rf /tmp/swtpm-$SWTPM_VERSION.zip"
  runuser -l root -c  "rm -rf /root/swtpm"
  runuser -l root -c  "rm -rf /root/libtpms"
  #####################
}

function telegram_notify() {
  token=$TELEGRAM_API
  chat_id=$TELEGRAM_CHAT_ID
  msg_text=$1
  curl -X POST  \
        -H 'Content-Type: application/json' -d "{\"chat_id\": \"$chat_id\", \"text\":\"$msg_text\", \"disable_notification\":false}"  \
        -s \
        https://api.telegram.org/bot"$token"/sendMessage > /dev/null
}

function telegram_debug_msg() {
  if [[ $HYPERVISOR_DEBUG == 0 ]]; then
    return
  fi
  token=$TELEGRAM_API
  chat_id=$TELEGRAM_CHAT_ID
  msg_text=$1
  curl -X POST  \
        -H 'Content-Type: application/json' -d "{\"chat_id\": \"$chat_id\", \"text\":\"$msg_text\", \"disable_notification\":false}"  \
        -s \
        https://api.telegram.org/bot"$token"/sendMessage > /dev/null
}

function prep_project_config() {
  source ./project_config.sh
  ### prep project config
  cp ./project_config.sh /tmp/project_config.sh
  ## replace variables using sed as this does not work the way one would think it would
  ###  remember to replace all variables that are nested in project config!
  sed -i 's/$NETWORK_PREFIX/'$NETWORK_PREFIX'/g' /tmp/project_config.sh
  sed -i 's/$TROVE_NETWORK/'$TROVE_NETWORK'/g' /tmp/project_config.sh
  sed -i 's/$LB_NETWORK/'$LB_NETWORK'/g' /tmp/project_config.sh
  sed -i 's/$HARBOR_VERSION/'$HARBOR_VERSION'/g' /tmp/project_config.sh
  sed -i 's/$MAGNUM_IMAGE_VERSION/'$MAGNUM_IMAGE_VERSION'/g' /tmp/project_config.sh
  sed -i 's/$CF_ATTIC_TERRAFORM_VERSION/'$CF_ATTIC_TERRAFORM_VERSION'/g' /tmp/project_config.sh
  sed -i 's/$DOCKER_COMPOSE_VERSION/'$DOCKER_COMPOSE_VERSION'/g' /tmp/project_config.sh
  sed -i 's/$UBUNTU_VERSION/'$UBUNTU_VERSION'/g' /tmp/project_config.sh
  ####
}

function post_install_cleanup() {
  ## cleanup kolla node
  source /tmp/project_config.sh
  if [[ $HYPERVISOR_DEBUG == 1 ]]; then
    return
  fi
  rm -rf /tmp/host-trust.sh
  rm -rf /tmp/project_config.sh
  rm -rf /tmp/swift.key

  ### cleanup
  runuser -l root -c  'rm -rf /root/*.log'
  runuser -l root -c  'rm -rf /tmp/*.log'
  ######

  runuser -l root -c  'rm -rf /root/*.log'
  runuser -l root -c  'rm -rf /tmp/*.log'
  sed -i 's/\(PermitRootLogin\).*/\1 no/' /etc/ssh/sshd_config
  sed -i 's/\(PasswordAuthentication\).*/\1 no/' /etc/ssh/sshd_config
  /usr/sbin/service sshd restart
  #### cleanup nodes
  file=/tmp/host_list
cat > /tmp/server_cleanup.sh <<EOF
sed -i 's/\(PermitRootLogin\).*/\1 no/' /etc/ssh/sshd_config
sed -i 's/\(PasswordAuthentication\).*/\1 no/' /etc/ssh/sshd_config
/usr/sbin/service sshd restart
rm -rf /tmp/host-trust.sh
rm -rf /tmp/project_config.sh
rm -rf /tmp/vm_functions.sh
rm -rf /tmp/server_cleanup.sh
EOF
  chmod +x /tmp/server_cleanup.sh
  for i in $(cat "$file")
  do
    echo "cleanup server $i"
    scp /tmp/server_cleanup.sh root@"$i":/tmp
    runuser -l root -c "ssh root@$i '/tmp/server_cleanup.sh'"
  done
  rm -rf /tmp/host_list
  rm -rf /tmp/server_cleanup.sh
}

function create_ca_cert() {
  cert_dir=$1

  if [ -f "/tmp/ip_out_update" ]; then
    INFO=$(cat /tmp/ip_out_update)
    COUNTRY=$(parse_json "$INFO" "country")
    STATE=$(parse_json "$INFO" "region")
    LOCATION=$(parse_json "$INFO" "city")
  fi

  echo "Country: $COUNTRY"
  echo "State: $STATE"
  echo "Location: $LOCATION"
  echo "Organization: $ORGANIZATION"

  IP=$(hostname -I | awk '{print $1}')

  runuser -l root -c  "touch $cert_dir/id_rsa"
  runuser -l root -c  "touch $cert_dir/id_rsa.pub"
  runuser -l root -c  "touch $cert_dir/id_rsa.crt"

  source /tmp/project_config.sh

cat > "$cert_dir"/ca_conf.cnf <<EOF
##Required
[ req ]
default_bits                                         = 4096
distinguished_name                           = req_distinguished_name
x509_extensions                                   = v3_ca
prompt = no

##About the system for the request. Ensure the CN = FQDN
[ req_distinguished_name ]
commonName                                    = $IDENTITY_HOST.$INTERNAL_DOMAIN_NAME
countryName                 = $COUNTRY
stateOrProvinceName         = $STATE
localityName               = $LOCATION
organizationName           = $ORGANIZATION

##Extensions to add to a certificate request for how it will be used
[ v3_ca ]
basicConstraints        = critical, CA:TRUE
subjectKeyIdentifier    = hash
authorityKeyIdentifier  = keyid:always, issuer:always
keyUsage                = critical, cRLSign, digitalSignature, keyCertSign
subjectAltName          = @alt_names
nsCertType              = server
nsComment               = "$INTERNAL_DOMAIN_NAME CA Certificate"

##The other names your server may be connected to as
[alt_names]
DNS.1                                                 = $IDENTITY_HOST.$INTERNAL_DOMAIN_NAME
IP.1                                                  = $IDENTITY_VIP
EOF

  runuser -l root -c  "chmod 600 $cert_dir/*"
  runuser -l root -c  "openssl genrsa -out $cert_dir/id_rsa 4096"

  ### make sure keys are same size
  file_length_pk=$(wc -c "$cert_dir/id_rsa" | awk -F' ' '{ print $1 }')
  file_length_old=$(wc -c "/tmp/id_rsa" | awk -F' ' '{ print $1 }')
  while [ "$file_length_pk" != "$file_length_old" ]; do
    runuser -l root -c  "openssl genrsa -out $cert_dir/id_rsa 4096"
    file_length_pk=$(wc -c "$cert_dir/id_rsa" | awk -F' ' '{ print $1 }')
  done
  # create CA key and cert
  runuser -l root -c  "ssh-keygen -f $cert_dir/id_rsa -y > $cert_dir/id_rsa.pub"

  ### make sure certs are same size
  runuser -l root -c  "openssl req -new -x509 -days 7300 \
                              -key $cert_dir/id_rsa -out $cert_dir/id_rsa.crt \
                              -sha256 \
                              -config $cert_dir/ca_conf.cnf"

  file_length_crt=$(wc -c "$cert_dir/id_rsa.crt" | awk -F' ' '{ print $1 }')
  file_length_old_crt=$(wc -c "/tmp/id_rsa.crt" | awk -F' ' '{ print $1 }')
  while [ "$file_length_crt" != "$file_length_old_crt" ]; do
    runuser -l root -c  "openssl req -new -x509 -days 7300 \
                            -key $cert_dir/id_rsa -out $cert_dir/id_rsa.crt \
                            -sha256 \
                            -config $cert_dir/ca_conf.cnf"
    file_length_crt=$(wc -c "$cert_dir/id_rsa.crt" | awk -F' ' '{ print $1 }')
  done
}

function create_server_cert() {
    cert_dir=$1
    cert_name=$2
    host_name=$3

    if [ -f "/tmp/ip_out_update" ]; then
      INFO=$(cat /tmp/ip_out_update)
      COUNTRY=$(parse_json "$INFO" "country")
      STATE=$(parse_json "$INFO" "region")
      LOCATION=$(parse_json "$INFO" "city")
    fi

    runuser -l root -c  "touch $cert_dir/$cert_name.pass.key"
    runuser -l root -c  "touch $cert_dir/$cert_name.key"
    runuser -l root -c  "touch $cert_dir/$cert_name.crt"

    IP=$(hostname -I | awk '{print $1}')
    source /tmp/project_config.sh

cat > "$cert_dir/$cert_name.cnf" <<EOF
##Required
[ req ]
default_bits                                         = 4096
distinguished_name                           = req_distinguished_name
req_extensions                                   = v3_vpn_server
prompt = no

##About the system for the request. Ensure the CN = FQDN
[ req_distinguished_name ]
commonName                                    = $host_name.$INTERNAL_DOMAIN_NAME
countryName                 = $COUNTRY
stateOrProvinceName         = $STATE
localityName               = $LOCATION
organizationName           = $ORGANIZATION

##Extensions to add to a certificate request for how it will be used
[ v3_vpn_server ]
basicConstraints        = critical, CA:FALSE
subjectKeyIdentifier    = hash
nsCertType              = client, server, email
keyUsage                = digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment,keyAgreement
extendedKeyUsage        = critical, serverAuth, clientAuth, codeSigning, emailProtection
subjectAltName          = @alt_vpn_server
nsComment               = "Certificate for host -> $host_name.$INTERNAL_DOMAIN_NAME"

##The other names your server may be connected to as
[alt_vpn_server]
DNS.1                                                 = $host_name.$INTERNAL_DOMAIN_NAME
IP.1                                                  = $IP
IP.2                                                  = $LAN_CENTOS_IP
IP.3                                                  = $LB_CENTOS_IP
EOF

node_ct=255
while [ $node_ct -gt 0 ]; do
  echo "IP.$node_ct = $NETWORK_PREFIX.$node_ct" >> "$cert_dir/$cert_name.cnf"
  ((node_ct--))
done

  extFile=$(gen_extfile "$host_name.$INTERNAL_DOMAIN_NAME")
  runuser -l root -c  "openssl genrsa -out $cert_dir/$cert_name.pass.key 4096"
  runuser -l root -c  "openssl rsa -in $cert_dir/$cert_name.pass.key -out $cert_dir/$cert_name.key"
  runuser -l root -c  "openssl req -new -key $cert_dir/$cert_name.key \
                          -out $cert_dir/$cert_name.csr \
                          -config $cert_dir/$cert_name.cnf"

  runuser -l root -c  "openssl x509 -CAcreateserial -req -days 7300 \
                          -in $cert_dir/$cert_name.csr \
                          -CA $cert_dir/id_rsa.crt \
                          -CAkey $cert_dir/id_rsa \
                          -sha256 \
                          -extfile <(printf \"$extFile\") \
                          -out $cert_dir/$cert_name.crt"
}

function gen_extfile()
{
    domain=$1
cat << EOF
authorityKeyIdentifier=keyid,issuer\n
basicConstraints=CA:FALSE\n
keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment,keyAgreement\n
extendedKeyUsage        = critical, serverAuth, clientAuth, codeSigning, emailProtection\n
subjectKeyIdentifier=hash\n
nsCertType              = client, server, email\n
subjectAltName = @alt_names\n
[alt_names]\n
DNS.1 = $domain
EOF
}

function remove_ip_from_adapter() {
  adapter_name=$1
  sed -i '/^IPADDR/d' /etc/sysconfig/network-scripts/ifcfg-"$adapter_name"
  sed -i '/^DNS1/d' /etc/sysconfig/network-scripts/ifcfg-"$adapter_name"
  sed -i '/^NETMASK/d' /etc/sysconfig/network-scripts/ifcfg-"$adapter_name"
  sed -i '/^GATEWAY/d' /etc/sysconfig/network-scripts/ifcfg-"$adapter_name"
}

function generate_random_pwd() {
  length=$1
  RANDOM_PWD=$(date +%s | sha256sum | base64 | head -c "$length" ; echo)
  echo "$RANDOM_PWD"
}

function generate_specific_pwd() {
  head -c "$1" < /dev/zero | tr '\0' 'x'
}

function join_machine_to_domain() {
  ## kill selinux to join domain
  runuser -l root -c "sed -i 's/\(SELINUX\=\).*/\1disabled/' /etc/selinux/config"

  IP_ADDRESS=$(hostname -I | awk '{print $1}')
  HOSTNAME=$(hostname).$INTERNAL_DOMAIN_NAME

  runuser -l root -c "echo '$IP_ADDRESS $HOSTNAME' >> /etc/hosts"
  runuser -l root -c "echo $HOSTNAME > /etc/hostname"
  runuser -l root -c "sysctl kernel.hostname=$HOSTNAME"

  IPA_SERVER=$IDENTITY_HOST.$INTERNAL_DOMAIN_NAME
  ADMIN_PASSWORD=$1
  REALM_NAME=$(echo "$INTERNAL_DOMAIN_NAME" | tr '[:lower:]' '[:upper:]')

  ipa-client-install -p admin \
                      --domain="$INTERNAL_DOMAIN_NAME" \
                      --realm="$REALM_NAME" \
                      --hostname="$HOSTNAME" \
                      --server="$IPA_SERVER" \
                      --mkhomedir \
                      --enable-dns-updates \
                      --force-join \
                      -w "$ADMIN_PASSWORD" -U -q > /tmp/ipa-join

  ### if possible, restart selinux
  runuser -l root -c "sed -i 's/\(SELINUX\=\).*/\1enabled/' /etc/selinux/config"
}

function baseDN() {
  ### BaseDN
  BASE_DN=""
  IFS='.' read -ra ADDR <<< "$INTERNAL_DOMAIN_NAME"
  LEN="${#ADDR[@]}"
  CT=1
  for i in "${ADDR[@]}"; do
    BASE_DN+="dc=$i"
    if [[ $CT -lt $LEN ]]; then
      BASE_DN+=","
      ((CT++))
    fi
  done
  echo $BASE_DN
  ####
}

function replace_string_in_iso() {
  iso_file=$1
  replacement_string=$2
  replace_with=$3

tmp_file="/tmp/out-$(generate_random_pwd 10)"
cat > "$tmp_file" <<EOF
$replace_with
EOF

  occur=$(grep -oba "$replacement_string" "$iso_file" | wc -l)
  entries=($(grep -oba "$replacement_string" "$iso_file"))
  while [ "$occur" -gt 0 ]; do
    ((occur--))
    start_index=$(echo "${entries[$occur]}" | awk -F':' '{ print $1 }')
    dd if="$tmp_file" of="$iso_file" conv=notrunc bs=1 seek="$start_index" count="${#replacement_string}"
  done

  rm -rf /tmp/out-*
}

function prepare_special_file() {
  in_file=$1
  ## create duplicate of key to find, remove first line (----BEGIN, etc) so as not to return the index of other keys in iso
  ## and then replace from that index.  The headers (and footers technically) are the same so should be safe.
  if [ -f "$in_file".repl ]; then
    #echo "$in_file : replace contents exist, no prep needed"
    return
  fi
  #echo "$in_file : creating replace contents file"
  cp "$in_file" "$in_file".repl
  sed -i '1d' "$in_file".repl
  sed -i '$d' "$in_file".repl
}

function replace_oneline_file_in_iso() {
  iso_file=$1
  replacement_file=$2
  replace_with=$3

  start_index=$(grep -oba -f "$replacement_file" "$iso_file" -m1 | awk -F':' '{ print $1 }')
  file_length=$(wc -c "$replace_with" | awk -F' ' '{ print $1 }')
  dd if="$replace_with" of="$iso_file" conv=notrunc bs=1 seek="$start_index" count="$file_length"
}

function get_disk_count() {
  lsblk -S -n | grep -v usb -c
}

function grub_update() {
  DRIVE_NAME_UPDATE=$(get_drive_name)

  runuser -l root -c  'rm -rf /etc/default/grub'
  runuser -l root -c  'touch /etc/default/grub'
  runuser -l root -c  'chmod +x /etc/default/grub'

cat > /tmp/grub <<EOF
GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="resume=/dev/mapper/cs_${DRIVE_NAME_UPDATE}-swap rd.lvm.lv=cs_${DRIVE_NAME_UPDATE}/root rd.lvm.lv=cs_${DRIVE_NAME_UPDATE}/swap net.ifnames=0 intel_iommu=on rhgb quiet splash biosdevname=0"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
EOF

  runuser -l root -c  'cat /tmp/grub > /etc/default/grub'
  runuser -l root -c  'grub2-mkconfig  -o /boot/grub2/grub.cfg'

  rm -rf /tmp/grub
}

function cleanUpNetwork() {

ct=0
for FILE in /etc/sysconfig/network-scripts/*;
do
    echo "$FILE"
    IP=$(awk -F'=' '$1 == "IPADDR" {print $2}' "$FILE")
    GATEWAY=$(awk -F'=' '$1 == "GATEWAY" {print $2}' "$FILE")
    DNS1=$(awk -F'=' '$1 == "DNS1" {print $2}' "$FILE")
    NETMASK=$(awk -F'=' '$1 == "NETMASK" {print $2}' "$FILE")
    runuser -l root -c  "touch /etc/sysconfig/network-scripts/ifcfg-eth$ct"

    if [[ -n "$IP" ]]; then
#static ip addr
cat > /tmp/eth$ct <<EOF
# Generated by parse-kickstart
TYPE="Ethernet"
NAME="eth$ct"
DEVICE="eth$ct"
UUID="5844195f-b0d7-4d15-9442-87d1340cca2$ct"
ONBOOT="yes"
IPADDR=$IP
BOOTPROTO="static"
GATEWAY=$GATEWAY
DNS1=$DNS1
NETMASK=$NETMASK
EOF
else
#dynamic ip addr (use DHCP)
cat > /tmp/eth$ct <<EOF
# Generated by parse-kickstart
TYPE="Ethernet"
NAME="eth$ct"
DEVICE="eth$ct"
UUID="5844195f-b0d7-4d15-9442-87d1340cca2$ct"
ONBOOT="yes"
BOOTPROTO="dhcp"
EOF

    fi

    runuser -l root -c  "cat /tmp/eth$ct > /etc/sysconfig/network-scripts/ifcfg-eth$ct"
    runuser -l root -c  "rm -rf $FILE"
    ((ct++))
done
rm -rf /tmp/eth*
}

function replace_values_in_root_isos() {

  shopt -s nullglob
  ### replace values in isos for certs and pwds ########
  ## cert list
#  DIRECTORY_MGR_PWD=$(generate_random_pwd 31)
#  ADMIN_PWD=$(generate_random_pwd 31)
#  GEN_PWD=$(generate_random_pwd 15)
  DIRECTORY_MGR_PWD=$(generate_random_pwd 31)
  ADMIN_PWD=$(generate_random_pwd 31)
  ## gen_pwd is not stored anywhere, it is meant to lost and never found
  GEN_PWD=$(generate_specific_pwd 15)

  ## Files can only be replaced if they can be considered to be on "one line"
  ##  ssh keys are on one line as would most binary files.  text files, scripts, etc have multiple lines and DO NOT work!

  ## These files are special due to multiline
  ##  Remove first and last tine from each
  prepare_special_file /tmp/id_rsa.crt
  prepare_special_file /tmp/id_rsa

  prepare_special_file /root/.ssh/id_rsa.crt
  prepare_special_file /root/.ssh/id_rsa
  ##########

  iso_images="/tmp/*.iso"
  for img in $iso_images; do
      echo "replacing centos admin in $img"
      replace_string_in_iso "$img" "{CENTOS_ADMIN_PWD_123456789012}" "$ADMIN_PWD"

      echo "replace generated pwd in $img"
      replace_string_in_iso "$img" "{GENERATED_PWD}" "$GEN_PWD"

      echo "replacing directory mgr admin in $img"
      replace_string_in_iso "$img" "{DIRECTORY_MGR_PWD_12345678901}" "$DIRECTORY_MGR_PWD"

      ##########
      echo "replacing id_rsa  in $img"
      replace_oneline_file_in_iso "$img" /tmp/id_rsa.repl /root/.ssh/id_rsa.repl

      echo "replacing id_rsa.pub  in $img"
      replace_oneline_file_in_iso "$img" /tmp/id_rsa.pub /root/.ssh/id_rsa.pub
      ##########
  done

  if [[ -f "/tmp/identity-iso.iso" ]]; then
    echo "replacing id_rsa.crt  in /tmp/identity-iso.iso"
    replace_oneline_file_in_iso /tmp/identity-iso.iso /tmp/id_rsa.crt.repl /root/.ssh/id_rsa.crt.repl
  fi

  iso_images="/tmp/*.img"
  for img in $iso_images; do
      echo "replacing centos admin in $img"
      replace_string_in_iso "$img" "{CENTOS_ADMIN_PWD_123456789012}" "$ADMIN_PWD"

      echo "replacing directory mgr admin in $img"
      replace_string_in_iso "$img" "{DIRECTORY_MGR_PWD_12345678901}" "$DIRECTORY_MGR_PWD"
  done
  ##############
}

function setup_keys_certs_for_vm() {
  mkdir -p /root/.ssh
  rm -rf /root/.ssh/id_rsa*
  cp /tmp/id_rsa /root/.ssh/id_rsa
  cp /tmp/id_rsa.pub /root/.ssh/id_rsa.pub
  chmod 600 /root/.ssh/id_rsa
  chmod 600 /root/.ssh/id_rsa.pub

  #### add hypervisor host key to authorized keys
  ## this allows the hypervisor to ssh without password to openstack vms
  runuser -l root -c 'cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys'
  runuser -l root -c 'chmod 600 /root/.ssh/authorized_keys'
  ######
}

function hypervisor_debug() {
  #Disable root login in ssh and disable password login
  if [[ $HYPERVISOR_DEBUG == 0 ]]; then
      generate_random_pwd 31 |  passwd --stdin  root
      sed -i 's/\(PermitRootLogin\).*/\1 no/' /etc/ssh/sshd_config
      sed -i 's/\(PasswordAuthentication\).*/\1 no/' /etc/ssh/sshd_config
  fi
}

function enable_kvm_module() {
  ### enable nested virtualization
  is_intel=$(cat </proc/cpuinfo | grep vendor | uniq | grep -c 'Intel')
  if [[ $is_intel -gt 0 ]]; then
      if [[ -f /etc/modprobe.d/kvm.conf ]]; then
          sed -i "s/#options kvm_intel nested=1/options kvm_intel nested=1/g" /etc/modprobe.d/kvm.conf
      else
          runuser -l root -c  'echo "options kvm_intel nested=1" >> /etc/modprobe.d/kvm.conf;'
      fi
      runuser -l root -c  'echo "options kvm-intel enable_shadow_vmcs=1" >> /etc/modprobe.d/kvm.conf;'
      runuser -l root -c  'echo "options kvm-intel enable_apicv=1" >> /etc/modprobe.d/kvm.conf;'
      runuser -l root -c  'echo "options kvm-intel ept=1" >> /etc/modprobe.d/kvm.conf;'
  else
      if [[ -f /etc/modprobe.d/kvm.conf ]]; then
          sed -i "s/#options kvm_amd nested=1/options kvm_amd nested=1/g" /etc/modprobe.d/kvm.conf
      else
          runuser -l root -c  'echo "options kvm_amd nested=1" >> /etc/modprobe.d/kvm.conf;'
      fi
      runuser -l root -c  'echo "options kvm-amd enable_shadow_vmcs=1" >> /etc/modprobe.d/kvm.conf;'
      runuser -l root -c  'echo "options kvm-amd enable_apicv=1" >> /etc/modprobe.d/kvm.conf;'
      runuser -l root -c  'echo "options kvm-amd ept=1" >> /etc/modprobe.d/kvm.conf;'
  fi

  ##############
}

function install_packages_openstack() {
  dnf clean all
  dnf module enable idm:DL1 -y
  dnf distro-sync -y
  dnf reposync
  dnf update -y

  dnf groupinstall -y virtualization-client
  dnf install -y openvpn ruby-devel nodejs
  dnf install -y freeipa-server freeipa-server-dns
  dnf install -y docker-ce
  systemctl enable docker
  systemctl start docker
  chkconfig docker on
  systemctl restart docker
}

function install_packages_hypervisor() {
  dnf clean all
  dnf distro-sync -y
  dnf reposync
  dnf update -y

  dnf groupinstall -y virtualization-client
}
