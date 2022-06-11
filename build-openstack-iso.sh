#!/bin/bash
#can ONLY be run as root!  sudo to root

### openstack-env needs to be in same directory as this script
rm -rf /tmp/openstack-env.sh
cp "$1" /tmp/openstack-env.sh
source /tmp/openstack-env.sh
cp project_config.sh /tmp
cp vm_functions.sh /tmp
source vm_functions.sh
## prep project config by replacing nested vars
prep_project_config
source /tmp/project_config.sh
#########
source iso-functions.sh

rm -rf /var/tmp/*

## make sure libs are installed
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
sudo yum install epel-release -y
sudo yum install -y rsync genisoimage pykickstart isomd5sum make python2 gcc yum-utils createrepo syslinux bzip2 curl file sshpass wget zip

yum update -y
dnf update -y

rm -rf /tmp/linux.iso
rm -rf /tmp/configs/*

# login to docker hub using .bash_profile env secrets
docker login -u "$DOCKER_LOGIN" -p "$DOCKER_SECRET"

docker pull "$DOCKER_LINUX_BUILD_IMAGE:latest"
docker run -v /tmp:/opt/mount --rm -ti "$DOCKER_LINUX_BUILD_IMAGE:latest" bash -c "mv CentOS-x86_64-minimal.iso linux.iso; cp linux.iso /opt/mount"
docker run -v /tmp:/opt/mount --rm -ti "$DOCKER_LINUX_BUILD_IMAGE:latest" bash -c "cp /root/ks_configs/* /opt/mount/configs"

rm -rf ./tmp
mkdir ./tmp
cp centos-8-kickstart-openstack.cfg ./tmp

IFS=
kickstart_file=./tmp/centos-8-kickstart-openstack.cfg
########### replace variables in project_config
## generate random hostname suffix
HOWLONG=5 ## the number of characters
HOSTNAME_SUFFIX=$(< /dev/urandom 2>/dev/null tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
sed -i 's/{HOSTNAME_SUFFIX}/'"$HOSTNAME_SUFFIX"'/g' ${kickstart_file}
###########################

## download files to be embedded
if [ ! -f "/tmp/amphora-x64-haproxy-$AMPHORA_VERSION.qcow2" ]; then
  ############# build octavia image
  yum -y install epel-release
  yum install -y debootstrap qemu-img git e2fsprogs policycoreutils-python-utils
  git clone https://opendev.org/openstack/octavia -b master /tmp/octavia
  pip3 install  --trusted-host pypi.org --trusted-host files.pythonhosted.org diskimage-builder
  chmod +x /tmp/octavia/diskimage-create/diskimage-create.sh
  pwd=$(pwd)
  cd /tmp/octavia/diskimage-create || exit;
  ./diskimage-create.sh;
  cd "$pwd" || exit
  cp /tmp/octavia/diskimage-create/amphora-x64-haproxy.qcow2 /tmp/amphora-x64-haproxy-"$AMPHORA_VERSION".qcow2
  rm -rf /tmp/octavia
fi

if [ ! -f "/tmp/pfSense-CE-memstick-ADI.img" ]; then
  for i in $(docker images |grep "$PFSENSE_CACHE_IMAGE"|awk '{print $3}');do docker rmi "$i";done
  docker run -v /out:/out -v /var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock -v /tmp:/tmp --rm -ti --network=host --privileged "$PFSENSE_CACHE_IMAGE:latest"
  cp /tmp/pfSense-CE-memstick-ADI.img /var/tmp
fi

if [ ! -f "/tmp/harbor-$HARBOR_VERSION.tgz" ]; then
  wget -O /tmp/harbor-"$HARBOR_VERSION".tgz "${HARBOR}"
fi

if [ ! -f "/tmp/magnum-$MAGNUM_IMAGE_VERSION.qcow2" ]; then
  wget -O /tmp/magnum-"$MAGNUM_IMAGE_VERSION".qcow2 "${MAGNUM_IMAGE}"
fi

if [ ! -f "/tmp/terraform_cf-$CF_ATTIC_TERRAFORM_VERSION.zip" ]; then
  wget -O /tmp/terraform_cf-"$CF_ATTIC_TERRAFORM_VERSION".zip "${CF_ATTIC_TERRAFORM}"
fi

if [ ! -f "/tmp/trove_instance-$UBUNTU_VERSION.img" ]; then
  wget -O /tmp/trove_instance-"$UBUNTU_VERSION".img "${TROVE_INSTANCE_IMAGE}"
fi

if [ ! -f "/tmp/trove_db-$TROVE_DB_VERSION.img" ]; then
  wget -O /tmp/trove_db-"$TROVE_DB_VERSION".img "${TROVE_DB_IMAGE}"
fi

if [ ! -f "/tmp/libtpms-$SWTPM_VERSION.zip" ]; then
  wget -O /tmp/libtpms-"$SWTPM_VERSION".zip "${LIBTPMS_GIT}"
fi

if [ ! -f "/tmp/swtpm-$SWTPM_VERSION.zip" ]; then
  wget -O /tmp/swtpm-"$SWTPM_VERSION".zip "${SWTPM_GIT}"
fi

if [ ! -f "/tmp/cf-templates.zip" ]; then
  wget -O /tmp/cf-templates.zip "${BOSH_OPENSTACK_ENVIRONMENT_TEMPLATES}"
fi

if [ ! -f "/tmp/cf_deployment-$CF_DEPLOY_VERSION.zip" ]; then
  wget -O /tmp/cf_deployment-"$CF_DEPLOY_VERSION".zip "${CF_DEPLOYMENT}"
fi

if [ ! -f "/tmp/docker-compose-$DOCKER_COMPOSE_VERSION" ]; then
  wget -O /tmp/docker-compose-"$DOCKER_COMPOSE_VERSION" "${DOCKER_COMPOSE}"
fi

if [ ! -f "/tmp/docker-repo.tar" ]; then
  rm -rf /tmp/repo
  mkdir /tmp/repo
  reposync -p /tmp/repo/docker-ce --repo=docker-ce-stable --download-metadata
  wget -O /tmp/repo/docker-ce/docker-ce-stable/gpg https://download.docker.com/linux/centos/gpg
  pwd=$(pwd)
  cd /tmp/repo/docker-ce || exit
  tar -cf /tmp/docker-repo.tar *
  cd "$pwd" || exit
fi

if [ ! -f "/tmp/harbor_python_modules.tar" ]; then
  mkdir /tmp/Pyrepo
  rm -rf /tmp/harbor_python_requirements
cat > /tmp/harbor_python_requirements <<EOF
netcontrold
EOF
  pip3 download -d /tmp/Pyrepo -r /tmp/harbor_python_requirements
  pwd=$(pwd)
  cd /tmp/Pyrepo || exit
  tar -cf /tmp/harbor_python_modules.tar *
  cd "$pwd" || exit
fi

### download director & jumpbox stemcell
if [ ! -f "/tmp/bosh-$STEMCELL_STAMP.tgz" ]; then
  curl -L https://bosh.io/d/stemcells/bosh-openstack-kvm-"$BOSH_STEMCELL"-go_agent --output /tmp/bosh-"$STEMCELL_STAMP".tgz > /dev/null
fi

##### build openstack vm keys
CERT_DIR="/tmp"

rm -rf "$CERT_DIR/id_rsa*"
if [ ! -f "$CERT_DIR/id_rsa" ]; then
  #### generate ssh keys
  # create CA cert before the network goes down to add ip to SAN
  load_cert_loc_info

  create_ca_cert $CERT_DIR
fi

rm -rf "$CERT_DIR/wildcard.*"
if [ ! -f "$CERT_DIR/wildcard.key" ]; then
  ### initial wildcard cert
  load_cert_loc_info

  create_server_cert $CERT_DIR "wildcard" "*"
  #############
fi

if [ ! -f "/tmp/homebrew-$CF_BBL_INSTALL_TERRAFORM_VERSION.tar" ]; then
  docker pull mephmanx/homebrew-cache:latest
  docker run --rm -v /tmp:/tmp/export "$HOMEBREW_CACHE_IMAGE:latest" "$CF_BBL_INSTALL_TERRAFORM_VERSION"
fi

IFS=' ' read -r -a stemcell_array <<< "$CF_STEMCELLS"
for stemcell in "${stemcell_array[@]}";
do
  if [ ! -f "/tmp/stemcell-$stemcell-$STEMCELL_STAMP.tgz" ]; then
    curl -L https://bosh.io/d/stemcells/bosh-openstack-kvm-"$stemcell"-go_agent --output /tmp/stemcell-"$stemcell"-"$STEMCELL_STAMP".tgz > /dev/null
  fi
done
####

yum install -y centos-release-openstack-"${OPENSTACK_VERSION}"
yum install -y openstack-kolla
if [ ! -f "/tmp/harbor/$OPENSTACK_VERSION/centos-binary-base-${OPENSTACK_VERSION}.tar" ] && [ ! -f "/tmp/harbor/$OPENSTACK_VERSION/kolla_${OPENSTACK_VERSION}_rpm_repo.tar.gz" ]; then
    for i in $(docker images |grep rpm_repo|awk '{print $3}');do docker rmi "$i";done
    for i in $(docker images |grep kolla|awk '{print $3}');do docker rmi "$i";done
    mkdir /tmp/harbor/"$OPENSTACK_VERSION"
    rm -rf /out
    mkdir /out
    docker pull "$DOCKER_OPENSTACK_OFFLINE_IMAGE:latest"
    rm -rf /tmp/openstack-build.log
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v /out:/out "$DOCKER_OPENSTACK_OFFLINE_IMAGE:latest" "$OPENSTACK_VERSION"

    #### add build images
    mv /out/centos-binary-base-"${OPENSTACK_VERSION}".tar /tmp/harbor/"$OPENSTACK_VERSION"
    mv /out/kolla_"${OPENSTACK_VERSION}"_rpm_repo.tar.gz /tmp/harbor/"$OPENSTACK_VERSION"
    mv /out/globals.yml /tmp/harbor/"$OPENSTACK_VERSION"
    ### add copied images

    docker pull codekoala/pypi && docker save codekoala/pypi >/tmp/harbor/"$OPENSTACK_VERSION"/pypi.tar
    docker pull kolla/centos-source-kuryr-libnetwork:"$OPENSTACK_VERSION" && docker save kolla/centos-source-kuryr-libnetwork:"$OPENSTACK_VERSION" >/tmp/harbor/"$OPENSTACK_VERSION"/centos-source-kuryr-libnetwork.tar
    docker pull kolla/centos-source-kolla-toolbox:"$OPENSTACK_VERSION" && docker save kolla/centos-source-kolla-toolbox:"$OPENSTACK_VERSION" >/tmp/harbor/"$OPENSTACK_VERSION"/centos-source-kolla-toolbox.tar
    docker pull kolla/centos-source-zun-compute:"$OPENSTACK_VERSION" && docker save kolla/centos-source-zun-compute:"$OPENSTACK_VERSION" >/tmp/harbor/"$OPENSTACK_VERSION"/centos-source-zun-compute.tar
    docker pull kolla/centos-source-zun-wsproxy:"$OPENSTACK_VERSION" && docker save kolla/centos-source-zun-wsproxy:"$OPENSTACK_VERSION" >/tmp/harbor/"$OPENSTACK_VERSION"/centos-source-zun-wsproxy.tar
    docker pull kolla/centos-source-zun-api:"$OPENSTACK_VERSION" && docker save kolla/centos-source-zun-api:"$OPENSTACK_VERSION" >/tmp/harbor/"$OPENSTACK_VERSION"/centos-source-zun-api.tar
    docker pull kolla/centos-source-zun-cni-daemon:"$OPENSTACK_VERSION" && docker save kolla/centos-source-zun-cni-daemon:"$OPENSTACK_VERSION" >/tmp/harbor/"$OPENSTACK_VERSION"/centos-source-zun-cni-daemon.tar
    docker pull kolla/centos-binary-fluentd:"$OPENSTACK_VERSION" && docker save kolla/centos-binary-fluentd:"$OPENSTACK_VERSION" >/tmp/harbor/"$OPENSTACK_VERSION"/centos-binary-fluentd.tar
    docker pull kolla/centos-binary-grafana:"$OPENSTACK_VERSION" && docker save kolla/centos-binary-grafana:"$OPENSTACK_VERSION" >/tmp/harbor/"$OPENSTACK_VERSION"/centos-binary-grafana.tar
    docker pull kolla/centos-binary-elasticsearch-curator:"$OPENSTACK_VERSION" && docker save kolla/centos-binary-elasticsearch-curator:"$OPENSTACK_VERSION" >/tmp/harbor/"$OPENSTACK_VERSION"/centos-binary-elasticsearch-curator.tar
fi


./create-pfsense-kvm-iso.sh
./create-cloudsupport-kvm-iso.sh
./create-identity-kvm-iso.sh
./create-cloud-kvm-iso.sh

embed_files=('/tmp/openstack-env.sh'
              '/tmp/project_config.sh'
              '/tmp/id_rsa'
              '/tmp/id_rsa.crt'
              '/tmp/id_rsa.pub'
              '/tmp/wildcard.crt'
              '/tmp/wildcard.key'
              '/tmp/ip_out_update'
              "/tmp/libtpms-$SWTPM_VERSION.zip"
              "/tmp/swtpm-$SWTPM_VERSION.zip"
              '/tmp/openstack-scripts/pf_functions.sh'
              '/tmp/openstack-scripts/pfsense-init.sh'
              '/tmp/openstack-scripts/openstack.sh'
              '/tmp/openstack-scripts/vm_functions.sh'
              '/tmp/openstack-scripts/vm-configurations.sh'
              '/tmp/openstack-scripts/create-cloud-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-kolla-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-cloudsupport-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-identity-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-pfsense-kvm-deploy.sh'
              "/var/tmp/pfSense-CE-memstick-ADI.img")

iso_images="/var/tmp/*.iso"
for img in $iso_images; do
  embed_files+=("$img")
done

printf -v embed_files_string '%s ' "${embed_files[@]}"
closeOutAndBuildKickstartAndISO "${kickstart_file}" "openstack" "$embed_files_string"

## this requires the original version of cdrtools
## https://www.berlios.de/software/cdrtools/ or
#  https://negativo17.org/cdrtools/
isohybrid /var/tmp/openstack-iso.iso
## cleanup work dir
# Use to write to disk
# dd if=/var/tmp/openstack-iso.iso of=/dev/sdb bs=16M status=progress
rm -rf ./tmp