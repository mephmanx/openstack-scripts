#!/bin/bash

. /tmp/project_config.sh
. /tmp/openstack-env.sh

function parse_json() {
  echo $1 |
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

function export_cert_info() {
  kickstart_file=$1
  ## Cert params
  # these parameters will be used to generate CSR for all certificates
  export IP=`curl --silent $EXTERNAL_IP_SERVICE`
  export INFO=`curl --silent $EXTERNAL_IP_INFO_SERVICE$IP`

  export COUNTRY=$(parse_json "$INFO" "country")
  export STATE=$(parse_json "$INFO" "region")
  export LOCATION=$(parse_json "$INFO" "city")
  export ORGANIZATION="Platform-Internal-Placeholder-CA"
  export OU="CloudStick"

  echo "Country: $COUNTRY"
  echo "State: $STATE"
  echo "Location: $LOCATION"
  echo "Organization: $ORGANIZATION"
  echo "OU: $OU"

  ####  stamp into ISO
  sed -i 's/{COUNTRY}/'$COUNTRY'/g' ${kickstart_file}
  sed -i 's/{STATE}/'$STATE'/g' ${kickstart_file}
  sed -i 's/{LOCATION}/'$LOCATION'/g' ${kickstart_file}
  sed -i 's/{ORGANIZATION}/'$ORGANIZATION'/g' ${kickstart_file}
  sed -i 's/{OU}/'$OU'/g' ${kickstart_file}
}

function get_drive_name() {
  dir_name=`find /dev/mapper -maxdepth 1 -type l -name '*cs*' -print -quit`
  DRIVE_NAME=`grep -oP '(?<=_).*?(?=-)' <<< "$dir_name"`
}

function load_system_info() {
  source /tmp/project_config.sh
  export INSTALLED_RAM=`runuser -l root -c  'dmidecode -t memory | grep  Size: | grep -v "No Module Installed"' | awk '{sum+=$2}END{print sum}'`
  export RESERVED_RAM=$(( $INSTALLED_RAM * $RAM_PCT_AVAIL_CLOUD/100 ))
  export CPU_COUNT=`lscpu | awk -F':' '$1 == "CPU(s)" {print $2}' | awk '{ gsub(/ /,""); print }'`
  export DISK_COUNT=$(get_disk_count)
  export IP_ADDR=`ip -f inet addr show ext-con | grep inet | awk -F' ' '{ print $2 }' | cut -d '/' -f1`

  ## build system output to send via telegram
  CPU_INFO="CPU Count: $CPU_COUNT"
  RAM_INFO="Installed RAM: $INSTALLED_RAM GB \r\n Reserved RAM: $RESERVED_RAM GB"
  DISK_INFO="Disk Count: $DISK_COUNT"
  IP_INFO="Hypervisor IP: $IP_ADDR"
  DMI_DECODE=`runuser -l root -c  "dmidecode -t system"`
  source /etc/os-release
  OS_INFO=$PRETTY_NAME
  export SYSTEM_INFO="$DMI_DECODE\n\n$OS_INFO\n\n$CPU_INFO\n\n$RAM_INFO\n\n$DISK_INFO\n\n$IP_INFO"
}

function grow_fs() {
  get_drive_name

  #One time machine setup
  xfsdump -f /tmp/home.dump /home

  umount /home
  lvreduce -L 4G -f /dev/mapper/cs_${DRIVE_NAME}-home
  mkfs.xfs -f /dev/mapper/cs_${DRIVE_NAME}-home
  lvextend -l +100%FREE /dev/mapper/cs_${DRIVE_NAME}-root
  xfs_growfs /dev/mapper/cs_${DRIVE_NAME}-root
  mount /dev/mapper/cs_${DRIVE_NAME}-home /home
  xfsrestore -f /tmp/home.dump /home
}

function load_libs() {
  option="${1}"
  case "${option}" in
    "kolla")
          # Kolla Openstack setup VM
          yum install -y yum-utils
          yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
          yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
          yum install -y ruby \
                unzip \
                virt-install \
                qemu-kvm \
                libffi-devel \
                gcc \
                openssl-devel \
                git \
                python3-devel \
                python38 \
                chrony \
                make \
                python2 \
                gcc-c++ \
                ruby \
                ruby-devel \
                mysql-devel \
                postgresql-devel \
                postgresql-libs \
                sqlite-devel \
                libxslt-devel \
                libxml2-devel \
                patch \
                openssl \
                docker-ce \
                docker-ce-cli \
                containerd.io \
                tar \
                tpm-tools \
                expect

            systemctl start docker
            systemctl enable docker
            chkconfig docker on
            systemctl restart docker
    ;;
      *)
        # All other Openstack VM's
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
        #One time machine setup
        #install yum libs here
        yum install -y unzip \
            gcc \
            openssl-devel \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            tar \
            tpm-tools

        systemctl start docker
        systemctl enable docker
        chkconfig docker on
        systemctl restart docker
    ;;
  esac
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

function prep_next_script() {
  vm_type=$1

  ## Prep OpenStack install
  rm -rf /etc/rc.d/rc.local
  cp /tmp/$vm_type.sh /etc/rc.d/rc.local
  chmod +x /etc/rc.d/rc.local
}

function restrict_to_root() {
  chmod 700 /tmp/*
  if [[ -d "/etc/kolla" ]]; then
    chmod 700 /etc/kolla/*
    chmod 700 /etc/kolla
  fi
}

function vtpm() {
  unzip /tmp/libtpms-$SWTPM_VERSION.zip -d /root/libtpms
  unzip /tmp/swtpm-$SWTPM_VERSION.zip -d /root/swtpm
  mv /root/libtpms/libtpms-master/* /root/libtpms
  mv /root/swtpm/swtpm-master/* /root/swtpm
  ###### vTPM setup #####
  cd /root
  dnf -y update \
   && dnf -y install diffutils make file automake autoconf libtool gcc gcc-c++ openssl-devel gawk git \
   && dnf -y install which python3 python3-cryptography python3-pip python3-setuptools expect libtasn1-devel \
      socat trousers tpm-tools gnutls-devel gnutls-utils net-tools libseccomp-devel json-glib-devel \
   && pip3 install  --trusted-host pypi.org --trusted-host files.pythonhosted.org twisted

  cd libtpms \
   && runuser -l root -c  'echo ${date} > /.date' \
   && runuser -l root -c  'cd libtpms; ./autogen.sh --prefix=/usr --with-openssl --with-tpm2;' \
   && make -j$(nproc) V=1 \
   && make -j$(nproc) V=1 check \
   && make install

  cd ../swtpm \
   && runuser -l root -c  'cd /root/swtpm; ./autogen.sh --prefix=/usr --with-openssl;' \
   && make -j$(nproc) V=1 \
   && make -j$(nproc) V=1 VERBOSE=1 check \
   && make -j$(nproc) install

  runuser -l root -c  'cd /usr/share/swtpm; ./swtpm-create-user-config-files --overwrite --root;'
  runuser -l root -c  'chown tss:tss /root/.config/*'
  #####################
}

function telegram_notify() {
  token=$TELEGRAM_API
  chat_id=$TELEGRAM_CHAT_ID
  msg_text=$1
  curl -X POST  \
        -H 'Content-Type: application/json' -d "{\"chat_id\": \"$chat_id\", \"text\":\"$msg_text\", \"disable_notification\":false}"  \
        -s \
        https://api.telegram.org/bot$token/sendMessage > /dev/null
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
        https://api.telegram.org/bot$token/sendMessage > /dev/null
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
  sed -i 's/$PFSENSE_VERSION/'$PFSENSE_VERSION'/g' /tmp/project_config.sh
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
  runuser -l root -c  "rm -rf /tmp/openstack-setup.key*"
  runuser -l root -c  'rm -rf /root/*.log'
  runuser -l root -c  'rm -rf /tmp/*.log'
  runuser -l root -c  'rm -rf /tmp/openstack-scripts'
  ######

  rm -rf /tmp/type
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
rm -rf /tmp/type
rm -rf /tmp/server_cleanup.sh
EOF
  chmod +x /tmp/server_cleanup.sh
  for i in `cat $file`
  do
    echo "cleanup server $i"
    scp /tmp/server_cleanup.sh root@$i:/tmp
    runuser -l root -c "ssh root@$i '/tmp/server_cleanup.sh'"
  done
  rm -rf /tmp/host_list
  rm -rf /tmp/server_cleanup.sh
}

function create_ca_cert() {
  ca_pwd=$1
  cert_dir=$2
  IP=`hostname -I | awk '{print $1}'`

  runuser -l root -c  "touch $cert_dir/ca_pwd"
  runuser -l root -c  "touch $cert_dir/id_rsa"
  runuser -l root -c  "touch $cert_dir/id_rsa.pub"
  runuser -l root -c  "touch $cert_dir/id_rsa.crt"

  ### record password to dir
  echo $NEWPW > $cert_dir/ca_pwd

  IP=`hostname -I | awk '{print $1}'`
  source /tmp/project_config.sh

cat > $cert_dir/ca_conf.cnf <<EOF
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
  runuser -l root -c  "openssl genrsa -aes256 -passout pass:$ca_pwd -out $cert_dir/id_rsa 4096"
  # create CA key and cert
  runuser -l root -c  "ssh-keygen -P $ca_pwd -f $cert_dir/id_rsa -y > $cert_dir/id_rsa.pub"
  runuser -l root -c  "openssl rsa -passin pass:$ca_pwd -in $cert_dir/id_rsa -out $cert_dir/id_rsa.key"
  runuser -l root -c  "openssl req -new -x509 -days 7300 \
                        -key $cert_dir/id_rsa.key -out $cert_dir/id_rsa.crt \
                        -sha256 \
                        -config $cert_dir/ca_conf.cnf"
}

function create_server_cert() {
    ca_pwd=$1
    cert_dir=$2
    cert_name=$3
    host_name=$4

    runuser -l root -c  "touch $cert_dir/$cert_name.pass.key"
    runuser -l root -c  "touch $cert_dir/$cert_name.key"
    runuser -l root -c  "touch $cert_dir/$cert_name.crt"

    IP=`hostname -I | awk '{print $1}'`
    source /tmp/project_config.sh

cat > $cert_dir/$cert_name.cnf <<EOF
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
  echo "IP.$node_ct = $NETWORK_PREFIX.$node_ct" >> $cert_dir/$cert_name.cnf
  ((node_ct--))
done

  extFile=$(gen_extfile $host_name.$INTERNAL_DOMAIN_NAME)
  runuser -l root -c  "openssl genrsa -aes256 -passout pass:$ca_pwd -out $cert_dir/$cert_name.pass.key 4096"
  runuser -l root -c  "openssl rsa -passin pass:$ca_pwd -in $cert_dir/$cert_name.pass.key -out $cert_dir/$cert_name.key"
  runuser -l root -c  "openssl req -new -key $cert_dir/$cert_name.key \
                          -out $cert_dir/$cert_name.csr \
                          -config $cert_dir/$cert_name.cnf"

  runuser -l root -c  "openssl x509 -CAcreateserial -req -days 7300 \
                          -in $cert_dir/$cert_name.csr \
                          -CA $cert_dir/id_rsa.crt \
                          -CAkey $cert_dir/id_rsa \
                          -passin pass:$ca_pwd \
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
  sed -i '/^IPADDR/d' /etc/sysconfig/network-scripts/ifcfg-$adapter_name
  sed -i '/^DNS1/d' /etc/sysconfig/network-scripts/ifcfg-$adapter_name
  sed -i '/^NETMASK/d' /etc/sysconfig/network-scripts/ifcfg-$adapter_name
  sed -i '/^GATEWAY/d' /etc/sysconfig/network-scripts/ifcfg-$adapter_name
}

function generate_random_pwd() {
  length=$1
  RANDOM_PWD=`date +%s | sha256sum | base64 | head -c $length ; echo`
  echo $RANDOM_PWD
}

function join_machine_to_domain() {
  ## kill selinux to join domain
  runuser -l root -c "sed -i 's/\(SELINUX\=\).*/\1disabled/' /etc/selinux/config"

  IP_ADDRESS=`hostname -I | awk '{print $1}'`
  HOSTNAME=`hostname`.$INTERNAL_DOMAIN_NAME

  runuser -l root -c "echo '$IP_ADDRESS $HOSTNAME' >> /etc/hosts"
  runuser -l root -c "echo $HOSTNAME > /etc/hostname"
  runuser -l root -c "sysctl kernel.hostname=$HOSTNAME"

  IPA_SERVER=$IDENTITY_HOST.$INTERNAL_DOMAIN_NAME
  ADMIN_PASSWORD=$1
  DOMAIN_NAME=$INTERNAL_DOMAIN_NAME
  REALM_NAME=$(echo "$INTERNAL_DOMAIN_NAME" | tr '[:lower:]' '[:upper:]')

  ipa-client-install -p admin \
                      --domain=$INTERNAL_DOMAIN_NAME \
                      --realm=$REALM_NAME \
                      --hostname=$HOSTNAME \
                      --server=$IPA_SERVER \
                      --mkhomedir \
                      --enable-dns-updates \
                      -w $ADMIN_PASSWORD -U -q > /tmp/ipa-join

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

function generate_random_word() {
  # Constants
  X=0
  ALL_NON_RANDOM_WORDS=/usr/share/dict/words

  # total number of non-random words available
  non_random_words=`cat $ALL_NON_RANDOM_WORDS | wc -l`

  # while loop to generate random words
  # number of random generated words depends on supplied argument

  random_number=`od -N3 -An -i /dev/urandom | awk -v f=0 -v r="$non_random_words" '{printf "%i\n", f + r * $1 / 16777216}'`
  sed `echo $random_number`"q;d" $ALL_NON_RANDOM_WORDS
}

function replace_string_in_iso() {
  iso_file=$1
  replacement_string=$2
  replace_with=$3

tmp_file="/tmp/out-$(generate_random_pwd 10)"
cat > $tmp_file <<EOF
$replace_with
EOF

  occur=`grep -oba "$replacement_string" $iso_file | wc -l`
  entries=($(grep -oba "$replacement_string" $iso_file))
  while [ $occur -gt 0 ]; do
    ((occur--))
    start_index=`echo ${entries[$occur]} | awk -F':' '{ print $1 }'`
    dd if=$tmp_file of=$iso_file conv=notrunc bs=1 seek=$start_index count=${#replacement_string}
  done

  rm -rf /tmp/out-*
}

function replace_file_in_iso() {
  iso_file=$1
  replacement_file=$2
  replace_with=$3

  start_index=`grep -oba -f $replacement_file $iso_file -m1 | awk -F':' '{ print $1 }'`
  file_length=`wc -c $replace_with | awk -F' ' '{ print $1 }'`
  dd if=$replace_with of=$iso_file conv=notrunc bs=1 seek=$start_index count=$file_length
}

function get_disk_count() {
  echo `lsblk -S -n | grep -v usb | wc -l`
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
GRUB_CMDLINE_LINUX="crashkernel=auto resume=/dev/mapper/cs_${DRIVE_NAME_UPDATE}-swap rd.lvm.lv=cs_${DRIVE_NAME_UPDATE/root rd.lvm.lv=cs_${DRIVE_NAME_UPDATE/swap net.ifnames=0 intel_iommu=on rhgb quiet"
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
    IP=(`awk -F'=' '$1 == "IPADDR" {print $2}' $FILE`)
    GATEWAY=(`awk -F'=' '$1 == "GATEWAY" {print $2}' $FILE`)
    DNS1=(`awk -F'=' '$1 == "DNS1" {print $2}' $FILE`)
    NETMASK=(`awk -F'=' '$1 == "NETMASK" {print $2}' $FILE`)
    runuser -l root -c  "touch /etc/sysconfig/network-scripts/ifcfg-eth$ct"

    if [[ ! -z "$IP" ]]; then
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

function auto_update() {
  # If autoupdate is enabled
  if [[ $LINUX_AUTOUPDATE == 1 ]]; then
      dnf install -y dnf-automatic

cat > /etc/dnf/automatic.conf <<EOF
[commands]
upgrade_type = default
random_sleep = 0
network_online_timeout = 60
download_updates = yes
apply_updates = yes
EOF
  fi
}

function replace_values_in_root_isos() {
  ### replace values in isos for certs and pwds ########
  ## cert list
  DIRECTORY_MGR_PWD=$(generate_random_pwd 31)
  ADMIN_PWD=$(generate_random_pwd 31)

  echo $ADMIN_PWD > /root/env_admin_pwd
  echo $DIRECTORY_MGR_PWD > /tmp/directory_mgr_pwd

  iso_images="/tmp/*.iso"
  for img in $iso_images; do
      echo "replacing centos admin in $img"
      replace_string_in_iso $img {CENTOS_ADMIN_PWD_123456789012} $ADMIN_PWD

      echo "replacing id_rsa.crt  in $img"
      replace_file_in_iso $img /tmp/id_rsa.crt /root/.ssh/id_rsa.crt
      echo "replacing id_rsa.pub  in $img"
      replace_file_in_iso $img /tmp/id_rsa.pub /root/.ssh/id_rsa.pub
      echo "replacing id_rsa.key  in $img"
      replace_file_in_iso $img /tmp/id_rsa.key /root/.ssh/id_rsa.key

      echo "replacing openstack-setup.key  in $img"
      replace_file_in_iso $img /tmp/key-bak/openstack-setup.key /tmp/openstack-setup.key
      echo "replacing openstack-setup.key.pub  in $img"
      replace_file_in_iso $img /tmp/key-bak/openstack-setup.key.pub /tmp/openstack-setup.key.pub
  done

  iso_images="/tmp/*.img"
  for img in $iso_images; do
      echo "replacing centos admin in $img"
      replace_string_in_iso $img {CENTOS_ADMIN_PWD_123456789012} $ADMIN_PWD
      echo "replacing directory mgr admin in $img"
      replace_string_in_iso $img {DIRECTORY_MGR_PWD_12345678901} $DIRECTORY_MGR_PWD
  done
  ##############
}

function hypervisor_debug() {
  #Disable root login in ssh and disable password login
  if [[ $HYPERVISOR_DEBUG == 0 ]]; then
      echo "$(generate_random_pwd 31)" |  passwd --stdin  root
      sed -i 's/\(PermitRootLogin\).*/\1 no/' /etc/ssh/sshd_config
      sed -i 's/\(PasswordAuthentication\).*/\1 no/' /etc/ssh/sshd_config
  fi
}

function enable_kvm_module() {
  ### enable nested virtualization
  is_intel=`cat /proc/cpuinfo | grep vendor | uniq | grep 'Intel' | wc -l`
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