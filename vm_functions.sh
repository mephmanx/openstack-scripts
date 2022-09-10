#!/bin/bash

. /tmp/project_config.sh

function get_drive_name() {
  dir_name=$(find /dev/mapper -maxdepth 1 -type l -name '*cs*' -print -quit)
  DRIVE_NAME=$(grep -oP '(?<=_).*?(?=-)' <<< "$dir_name")
  echo "$DRIVE_NAME"
}

function grow_fs() {
  DRIVE_NAME_UPDATE=$(get_drive_name)

  umount /home
  lvreduce -L 4G -f /dev/mapper/cs_"${DRIVE_NAME_UPDATE}"-home
  mkfs.xfs -f /dev/mapper/cs_"${DRIVE_NAME_UPDATE}"-home
  lvextend -l +100%FREE /dev/mapper/cs_"${DRIVE_NAME_UPDATE}"-root
  xfs_growfs /dev/mapper/cs_"${DRIVE_NAME_UPDATE}"-root
  mount /dev/mapper/cs_"${DRIVE_NAME_UPDATE}"-home /home
}

function telegram_notify() {
#  token=$TELEGRAM_API
#  chat_id=$TELEGRAM_CHAT_ID
#  msg_text=$1
#  curl -X POST  \
#        -H 'Content-Type: application/json' -d "{\"chat_id\": \"$chat_id\", \"text\":\"$msg_text\", \"disable_notification\":false}"  \
#        -s \
#        https://api.telegram.org/bot"$token"/sendMessage > /dev/null
  echo "$@" >&2
  SCRIPT_NAME="$(hostname -s)-$(basename "$0")"
  logger -p news.alert -t "$SCRIPT_NAME" "$@"
}

function create_server_cert() {
    cert_dir=$1
    cert_name=$2
    host_name=$3

    runuser -l root -c  "touch $cert_dir/$cert_name.pass.key"
    runuser -l root -c  "touch $cert_dir/$cert_name.key"
    runuser -l root -c  "touch $cert_dir/$cert_name.crt"

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
IP.1                                                  = 10.0.200.3
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

  runuser -l root -c  "openssl x509 -CAcreateserial -req -days 365 \
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

function setup_keys_certs_for_vm() {
  mkdir -p /root/.ssh
  rm -rf /root/.ssh/id_rsa*
  curl -o /root/.ssh/id_rsa "http://$IDENTITY_HOST.$INTERNAL_DOMAIN_NAME:$IDENTITY_SIGNAL/sub-ca.key"
  curl -o /root/.ssh/id_rsa.pub "http://$IDENTITY_HOST.$INTERNAL_DOMAIN_NAME:$IDENTITY_SIGNAL/sub-ca.pub"
  chmod 600 /root/.ssh/id_rsa
  chmod 600 /root/.ssh/id_rsa.pub

  #### add hypervisor host key to authorized keys
  ## this allows the hypervisor to ssh without password to openstack vms
  runuser -l root -c 'cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys'
  runuser -l root -c 'chmod 600 /root/.ssh/authorized_keys'
  ######
}

function generate_pwd() {
  generate_specific_pwd "$1"
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
  grep -oba "$replacement_string" "$iso_file" > /tmp/fileentries.txt
  readarray -t entries < /tmp/fileentries.txt
  rm -rf /tmp/fileentries.txt
#  entries=($(grep -oba "$replacement_string" "$iso_file"))
  while [ "$occur" -gt 0 ]; do
    ((occur--))
    start_index=$(echo "${entries[$occur]}" | awk -F':' '{ print $1 }')
    dd if="$tmp_file" of="$iso_file" conv=notrunc bs=1 seek="$start_index" count="${#replacement_string}"
  done

  rm -rf /tmp/out-*
}

function grub_update() {
  is_intel=$(cat </proc/cpuinfo | grep vendor | uniq | grep -c 'Intel')
  arch="intel"
  if [[ $is_intel -lt 0 ]]; then
  arch="amd"
  fi

  grub2-editenv - set "$(grub2-editenv - list | grep kernelopts) ${arch}_iommu=on"
  grub2-editenv - set "$(grub2-editenv - list | grep kernelopts) iommu=on"
  grub2-editenv - set "$(grub2-editenv - list | grep kernelopts) rhgb"
  grub2-editenv - set "$(grub2-editenv - list | grep kernelopts) splash"
  grub2-editenv - set "$(grub2-editenv - list | grep kernelopts) quiet"
  grub2-editenv - set "$(grub2-editenv - list | grep kernelopts) systemd.log_level=0"
  grub2-editenv - set "$(grub2-editenv - list | grep kernelopts) systemd.show_status=0"
  grub2-editenv - set "$(grub2-editenv - list | grep kernelopts) rd.plymouth=0"
  grub2-editenv - set "$(grub2-editenv - list | grep kernelopts) plymouth.enable=0"
  grub2-editenv - set menu_auto_hide=1
}

function replace_values_in_root_isos() {

  shopt -s nullglob
  ### replace values in isos for certs and pwds ########
  ## cert list
  DIRECTORY_MGR_PWD=$(generate_pwd 31)
  ADMIN_PWD=$(generate_pwd 31)
  ## gen_pwd is not stored anywhere, it is meant to lost and never found
  GEN_PWD=$(generate_pwd 15)

  iso_images="/tmp/*.iso"
  for img in $iso_images; do
      echo "replacing centos admin in $img"
      replace_string_in_iso "$img" "{CENTOS_ADMIN_PWD_123456789012}" "$ADMIN_PWD"

      echo "replace generated pwd in $img"
      replace_string_in_iso "$img" "{GENERATED_PWD}" "$GEN_PWD"

      echo "replacing directory mgr admin in $img"
      replace_string_in_iso "$img" "{DIRECTORY_MGR_PWD_12345678901}" "$DIRECTORY_MGR_PWD"
  done

  iso_images="/tmp/*.img"
  for img in $iso_images; do
      echo "replacing centos admin in $img"
      replace_string_in_iso "$img" "{CENTOS_ADMIN_PWD_123456789012}" "$ADMIN_PWD"

      echo "replacing directory mgr admin in $img"
      replace_string_in_iso "$img" "{DIRECTORY_MGR_PWD_12345678901}" "$DIRECTORY_MGR_PWD"
  done
  ##############
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
  dnf install -y ruby-devel nodejs freeipa-client
  dnf install -y docker-ce
  systemctl enable docker
  chkconfig docker on

  ###configure rsyslog
  cat <<EOT >> /etc/rsyslog.conf
*.* @@$LAN_CENTOS_IP:514
EOT
}

function install_packages_identity() {
  dnf clean all
  dnf module enable idm:DL1 -y
  dnf distro-sync -y
  dnf reposync
  dnf update -y

  dnf groupinstall -y virtualization-client
  dnf install -y ruby-devel nodejs
  dnf install -y freeipa-server freeipa-server-dns

  ###configure rsyslog
  cat <<EOT >> /etc/rsyslog.conf
*.* @@$LAN_CENTOS_IP:514
EOT
}

function install_packages_hypervisor() {
  dnf clean all
  dnf distro-sync -y
  dnf reposync
  dnf update -y
  dnf groupinstall -y virtualization-client
  dnf install -y telnet automake libtool cockpit-machines

  ###configure rsyslog
  sed -i "s/#module(load=\"imudp\")/module(load=\"imudp\")/g" /etc/rsyslog.conf
  sed -i "s/#input(type=\"imudp\" port=\"514\")/input(type=\"imudp\" port=\"514\")/g" /etc/rsyslog.conf

  sed -i "s/#module(load=\"imtcp\")/module(load=\"imtcp\")/g" /etc/rsyslog.conf
  sed -i "s/#input(type=\"imtcp\" port=\"514\")/input(type=\"imtcp\" port=\"514\")/g" /etc/rsyslog.conf

  grep -n "input(type=\"imtcp\" port=\"514\")" /etc/rsyslog.conf > /tmp/fileentries.txt
  readarray -t entries < /tmp/fileentries.txt
  rm -rf /tmp/fileentries.txt
  lines_to_modify=()
  for entry in ${#entries[@]}; do
    IFS=':' read -ra line_entry <<<"$entry"
    line_num=${line_entry[0]}
    lines_to_modify+=("$line_num")
  done

  arr_len=${#lines_to_modify}
  line_num="${lines_to_modify[((arr_len - 1))]}"
  totalLines=$(wc -l < /etc/rsyslog.conf)
  line_from_bottom=$((totalLines - lines_to_modify[arr_len - 1]))

  tail -n "$line_from_bottom" /etc/rsyslog.conf > /etc/rsyslog-end.conf
  head -n "$line_num" /etc/rsyslog.conf > /etc/rsyslog-start.conf
  cat <<EOT >> /etc/rsyslog-start.conf
\$template remote-incoming-logs, "/var/log/%HOSTNAME%/%PROGRAMNAME%.log"
*.* ?remote-incoming-logs
EOT
  cat /etc/rsyslog-end.conf >> /etc/rsyslog-start.conf
  rm -rf /etc/rsyslog.conf
  mv /etc/rsyslog-start.conf /etc/rsyslog.conf
  rm -rf /etc/rsyslog-start.conf
  rm -rf /etc/rsyslog-end.conf
}

function get_base64_string_for_file() {
  file="$1"
  conv_file_name="/tmp/convert-file-$(generate_random_pwd 10)"
  conv_file_name_reencoded="/tmp/convert-file-$(generate_random_pwd 10)-reencoded"
  sed -e '40{N;s/\n//;}' "$file" | sed -e ':a;N;$!ba;s/\n/\r\n/g' > "$conv_file_name"
  truncate -s -1 "$conv_file_name"
  base64 -w 0 < "$conv_file_name" > "$conv_file_name_reencoded"
  echo >> "$conv_file_name_reencoded"
  cat "$conv_file_name_reencoded"
}