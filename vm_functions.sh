#!/bin/bash

. /tmp/project_config.sh
. /tmp/openstack-env.sh

function get_drive_name() {
  dir_name=`find /dev/mapper -maxdepth 1 -type l -name '*cl*' -print -quit`
  DRIVE_NAME=`grep -oP '(?<=_).*?(?=-)' <<< "$dir_name"`
}

function load_system_info() {
  source /tmp/project_config.sh
  export INSTALLED_RAM=`runuser -l root -c  'dmidecode -t memory | grep  Size: | grep -v "No Module Installed"' | awk '{sum+=$2}END{print sum}'`
  export RESERVED_RAM=$(( $INSTALLED_RAM * $RAM_PCT_AVAIL_CLOUD/100 ))
  export CPU_COUNT=`lscpu | awk -F':' '$1 == "CPU(s)" {print $2}' | awk '{ gsub(/ /,""); print }'`
  export DISK_COUNT=`lshw -json -class disk | grep -o -i disk: | wc -l`
  export IP_ADDR=`ip -f inet addr show ext-con | grep inet`
#  ct=0
#  while [ $ct -lt $DISK_COUNT ]; do
#    export DISK_$ct=
#  done

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
  lvreduce -L 20G -f /dev/mapper/cl_$DRIVE_NAME-home
  mkfs.xfs -f /dev/mapper/cl_$DRIVE_NAME-home
  lvextend -l +100%FREE /dev/mapper/cl_$DRIVE_NAME-root
  xfs_growfs /dev/mapper/cl_$DRIVE_NAME-root
  mount /dev/mapper/cl_$DRIVE_NAME-home /home
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
          yum install -y wget \
                ruby \
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
                tpm-tools
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
    ;;
  esac
}

function add_stack_user() {
  NEWPW=$(generate_random_pwd)

  runuser -l root -c  'mkdir /opt/stack'
  runuser -l root -c  'useradd -s /bin/bash -d /opt/stack -m stack -G openstack'
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

function common_second_boot_setup() {

  exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
  set -x                             # tell sh to display commands before execution

  ########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
  sleep 30
  ###########################

  ADMIN_PWD=`cat /root/env_admin_pwd`
  systemctl restart docker

  mkdir /root/.ssh
  ## this allows openstack vm's to ssh to each other without password
  runuser -l root -c 'cp /tmp/openstack-setup.key.pub /root/.ssh/authorized_keys'
  #### add hypervisor host key to authorized keys
  ## this allows the hypervisor to ssh without password to openstack vms
  runuser -l root -c 'cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys'
  ######
  mv /tmp/openstack-setup.key.pub /root/.ssh/id_rsa.pub
  mv /tmp/openstack-setup.key /root/.ssh/id_rsa
  chmod 600 /root/.ssh/id_rsa
  chmod 600 /root/.ssh/authorized_keys

  pip3 install --upgrade  --trusted-host pypi.org --trusted-host files.pythonhosted.org pip
  ### module recommended on openstack.org
  modprobe vhost_net
}

function vtpm() {
  unzip /tmp/libtpms.zip -d /root/libtpms
  unzip /tmp/swtpm.zip -d /root/swtpm
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
  token=$1
  chat_id=$2
  msg_text=$3
  curl -X POST  \
        -H 'Content-Type: application/json' -d "{\"chat_id\": \"$chat_id\", \"text\":\"$msg_text\", \"disable_notification\":false}"  \
        -s \
        https://api.telegram.org/bot$token/sendMessage > /dev/null
}

function telegram_debug_msg() {
  source /tmp/project_config.sh
  if [[ $HYPERVISOR_DEBUG == 0 ]]; then
    return
  fi
  token=$1
  chat_id=$2
  msg_text=$3
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
  ####
}

function post_install_cleanup() {
  ## cleanup kolla node
  source /tmp/project_config.sh
  if [[ $HYPERVISOR_DEBUG == 1 ]]; then
    return
  fi
  rm -rf /tmp/host-trust.sh
  rm -rf /tmp/openstack-env.sh
  rm -rf /tmp/project_config.sh
  rm -rf /tmp/swift.key
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
rm -rf /tmp/openstack-env.sh
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
commonName                                    = ca.$INTERNAL_DOMAIN_NAME
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
DNS.1                                                 = ca
DNS.2                                                 = ca.$INTERNAL_DOMAIN_NAME
IP.1                                                  = $IP
IP.2                                                  = $LAN_CENTOS_IP
IP.3                                                  = $LB_CENTOS_IP
EOF

  extFile=$(gen_ca_extfile)
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
    source /tmp/openstack-scripts/project_config.sh

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
keyUsage                = critical, nonRepudiation, digitalSignature, keyEncipherment, keyAgreement
extendedKeyUsage        = critical, serverAuth
subjectAltName          = @alt_vpn_server
nsCertType              = server
nsComment               = "Certificate for host -> $host_name.$INTERNAL_DOMAIN_NAME"

##The other names your server may be connected to as
[alt_vpn_server]
DNS.1                                                 = $host_name.$INTERNAL_DOMAIN_NAME
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
                          -purpose server \
                          -extfile <(printf \"$extFile\") \
                          -out $cert_dir/$cert_name.crt"
}

function gen_extfile()
{
    domain=$1
cat << EOF
authorityKeyIdentifier=keyid,issuer\n
basicConstraints=CA:FALSE\n
keyUsage=digitalSignature,nonRepudiation,keyEncipherment,dataEncipherment\n
subjectAltName = @alt_names\n
[alt_names]\n
DNS.1 = $domain
EOF
}

function create_user_cert() {
  ca_pwd=$1
  cert_dir=$2
  user_name=$3

  runuser -l root -c  "touch $cert_dir/$user_name.csr"
  runuser -l root -c  "touch $cert_dir/$user_name.pass.key"
  runuser -l root -c  "touch $cert_dir/$user_name.crt"
  runuser -l root -c  "touch $cert_dir/$user_name.key"

  source /tmp/openstack-scripts/project_config.sh

  runuser -l root -c  "openssl genrsa -aes256 -passout pass:$ca_pwd -out $cert_dir/$user_name.pass.key 4096 "
  runuser -l root -c  "openssl rsa -passin pass:$ca_pwd -in $cert_dir/$user_name.pass.key -out $cert_dir/$user_name.key"
  runuser -l root -c  "openssl req -new -key $cert_dir/$user_name.key \
                        -subj '/C=$COUNTRY/ST=$STATE/L=$LOCATION/O=$ORGANIZATION/OU=$OU/CN=$user_name.$INTERNAL_DOMAIN_NAME' \
                        -out $cert_dir/$user_name.csr"

  runuser -l root -c  "openssl x509 -CAcreateserial -req -days 3650 \
                        -in $cert_dir/$user_name.csr \
                        -CA $cert_dir/id_rsa.crt \
                        -CAkey $cert_dir/id_rsa \
                        -passin pass:$ca_pwd \
                        -out $cert_dir/$user_name.crt"
  ##########
}

function remove_ip_from_adapter() {
  adapter_name=$1
  sed -i '/^IPADDR/d' /etc/sysconfig/network-scripts/ifcfg-$adapter_name
  sed -i '/^DNS1/d' /etc/sysconfig/network-scripts/ifcfg-$adapter_name
  sed -i '/^NETMASK/d' /etc/sysconfig/network-scripts/ifcfg-$adapter_name
  sed -i '/^GATEWAY/d' /etc/sysconfig/network-scripts/ifcfg-$adapter_name
}

function generate_random_pwd() {
  RANDOM_PWD=`date +%s | sha256sum | base64 | head -c 32 ; echo`
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
                      --ip-address=$IP_ADDRESS \
                      --domain=$INTERNAL_DOMAIN_NAME \
                      --realm=$REALM_NAME \
                      --hostname=$HOSTNAME \
                      --server=$IPA_SERVER \
                      --mkhomedir \
                      -w $ADMIN_PASSWORD -U -q > /tmp/ipa-join

  ### if possible, restart selinux
  runuser -l root -c "sed -i 's/\(SELINUX\=\).*/\1enabled/' /etc/selinux/config"
}