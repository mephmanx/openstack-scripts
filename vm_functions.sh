#!/bin/bash

function get_drive_name() {
  dir_name=`find /dev/mapper -maxdepth 1 -type l -name '*cl*' -print -quit`
  DRIVE_NAME=`grep -oP '(?<=_).*?(?=-)' <<< "$dir_name"`
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
      "cloudsupport")
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
            #One time machine setup
            #install yum libs here
            yum install -y wget \
            unzip \
            epel-release \
            gcc \
            openssl-devel \
            git \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            tar
    ;;
    "control")
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
            #One time machine setup
            #install yum libs here
            yum install -y wget \
            unzip \
            epel-release \
            gcc \
            openssl-devel \
            git \
            make \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            tar
    ;;
    "network")
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
            #One time machine setup
            #install yum libs here
            yum install -y wget \
            unzip \
            epel-release \
            gcc \
            openssl-devel \
            git \
            make \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            tar
    ;;
    "compute")
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
            #One time machine setup
            #install yum libs here
            yum install -y wget \
            unzip \
            epel-release \
            gcc \
            openssl-devel \
            git \
            make \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            tar
    ;;
    "monitoring")
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
            #One time machine setup
            #install yum libs here
            yum install -y wget \
            unzip \
            epel-release \
            gcc \
            openssl-devel \
            git \
            make \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            tar
    ;;
    "storage")
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
            #One time machine setup
            #install yum libs here
            yum install -y wget \
            unzip \
            epel-release \
            gcc \
            openssl-devel \
            git \
            make \
            docker-ce \
            docker-ce-cli \
            containerd.io \
            tar
    ;;
    "kolla")
          yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
          yum clean all && yum update -y  #this is only to make the next call work, DONT remove!
          yum install -y wget \
          ruby \
          unzip \
          virt-install \
          qemu-kvm \
          epel-release \
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
          tar
    ;;
  esac
}

function add_stack_user() {
  runuser -l root -c  'mkdir /opt/stack'
  runuser -l root -c  'useradd -s /bin/bash -d /opt/stack -m stack'
  runuser -l root -c  'echo "stack ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/stack'
  runuser -l root -c  'chown -R stack /opt/stack'
  runuser -l root -c  'su - stack'
}

function prep_next_script() {
  systemctl start cockpit.socket
  systemctl enable --now cockpit.socket

  ## Prep OpenStack install
  rm -rf /etc/rc.d/rc.local
  curl -o /etc/rc.d/rc.local https://mephmanx:$GITHUB_TOKEN@raw.githubusercontent.com/mephmanx/openstack-scripts/master/$1.sh
  chmod +x /etc/rc.d/rc.local
}

function load_secrets() {
  #########load secrets into env
  chmod 777 /tmp/openstack-env.sh
  source ./tmp/openstack-env.sh
  ############################
}

function restrict_to_root() {
  chmod 700 /tmp/*
}

function common_second_boot_setup() {

  exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
  set -x                             # tell sh to display commands before execution

  ########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
  sleep 30
  ###########################

  systemctl restart docker
  docker login -u $SUPPORT_USERNAME -p $SUPPORT_PASSWORD $SUPPORT_HOST.$DOMAIN_NAME

  mkdir /root/.ssh
  cp /tmp/openstack-setup.key.pub /root/.ssh/authorized_keys
  mv /tmp/openstack-setup.key.pub /root/.ssh/id_rsa.pub
  mv /tmp/openstack-setup.key /root/.ssh/id_rsa
  chmod 600 /root/.ssh/id_rsa
  chmod 600 /root/.ssh/authorized_keys

  systemctl stop firewalld
  systemctl mask firewalld
}

function delete_all_veth_interfaces() {

  ip link delete Node11
  ip link delete Node12
  ip link delete Node13
  ip link delete Node14
  ip link delete Node15
  ip link delete Node16
  ip link delete Node17
  ip link delete Node18
  ip link delete Node19
  ip link delete Node20

  ip link delete vm3

  ip link delete tapm1

  ip link delete ext-static
}