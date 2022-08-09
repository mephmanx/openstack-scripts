#!/bin/bash

. ./project_config.sh
. ./iso-functions.sh

#can ONLY be run as root!  sudo to root
rm -rf /var/tmp/*
rm -rf /tmp/linux.iso
rm -rf /tmp/configs/*

## this requires the original version of cdrtools
## https://www.berlios.de/software/cdrtools/ or
#  https://negativo17.org/cdrtools/

# login to docker hub using .bash_profile env secrets
docker login -u "$DOCKER_LOGIN" -p "$DOCKER_SECRET"

docker run -v /tmp:/opt/mount --rm -ti "$DOCKER_LINUX_BUILD_IMAGE:$DOCKER_LINUX_BUILD_IMAGE_VERSION" bash -c "mv CentOS-x86_64-minimal.iso linux.iso; cp linux.iso /opt/mount"
mkdir -p /tmp/configs
docker run -v /tmp:/opt/mount --rm -ti "$DOCKER_LINUX_BUILD_IMAGE:$DOCKER_LINUX_BUILD_IMAGE_VERSION" bash -c "cp /root/ks_configs/* /opt/mount/configs"

## download files to be embedded
if [ ! -f "/tmp/amphora-x64-haproxy-$OPENSTACK_VERSION.qcow2" ]; then
  curl -L -o /tmp/amphora-x64-haproxy-"$OPENSTACK_VERSION".qcow2 https://github.com/mephmanx/openstack-amphora-build/releases/download/"$OPENSTACK_VERSION"/amphora-x64-haproxy.qcow2
fi

if [ ! -f "/tmp/pfSense-CE-memstick-ADI-prod.img" ]; then
  for i in $(docker images |grep "$PFSENSE_CACHE_IMAGE"|awk '{print $3}');do docker rmi "$i";done
  docker run -v /out:/out -v /var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock -v /tmp:/tmp -v /dev:/dev -v /root:/root --rm -ti --network=host --privileged "$PFSENSE_CACHE_IMAGE:$PFSENSE_VERSION" dev
  sleep 20;
  rm -rf /tmp/pfSense-CE-memstick-ADI-dev.img
  docker run -v /out:/out -v /var/run/libvirt/libvirt-sock:/var/run/libvirt/libvirt-sock -v /tmp:/tmp -v /dev:/dev -v /root:/root --rm -ti --network=host --privileged "$PFSENSE_CACHE_IMAGE:$PFSENSE_VERSION" prod
  ## iterate over loop devices and remove them
  for i in /dev/loop*; do
    losetup -d "$i";
  done
fi

if [ ! -f "/tmp/cirros-0.5.1-x86_64-disk.img" ]; then
  curl --fail -L -o /tmp/cirros-0.5.1-x86_64-disk.img "$CIRROS_IMAGE_URL"
fi

if [ ! -f "/var/tmp/pfSense-CE-memstick-ADI-prod.img" ]; then
  cp /tmp/pfSense-CE-memstick-ADI-prod.img /var/tmp
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

if [ ! -f "/tmp/cf-templates.zip" ]; then
  wget -O /tmp/cf-templates.zip "${BOSH_OPENSTACK_ENVIRONMENT_TEMPLATES}"
fi

if [ ! -f "/tmp/cf_deployment-$CF_DEPLOY_VERSION.zip" ]; then
  wget -O /tmp/cf_deployment-"$CF_DEPLOY_VERSION".zip "${CF_DEPLOYMENT}"
fi

if [ ! -f "/tmp/docker-compose-$DOCKER_COMPOSE_VERSION" ]; then
  wget -O /tmp/docker-compose-"$DOCKER_COMPOSE_VERSION" "${DOCKER_COMPOSE}"
fi

if [ ! -f "/tmp/stratos.tar" ]; then
  docker pull splatform/stratos:stable && docker save splatform/stratos:stable >/tmp/stratos.tar
fi

if [ ! -f "/tmp/docker-repo.tar" ]; then
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  mkdir -p /tmp/repo/docker-ce/linux/centos/8/x86_64/stable
  reposync -p /tmp/repo/docker-ce/linux/centos/8/x86_64/stable --repo=docker-ce-stable --download-metadata
  mv /tmp/repo/docker-ce/linux/centos/8/x86_64/stable/docker-ce-stable/* /tmp/repo/docker-ce/linux/centos/8/x86_64/stable/
  rm -rf /tmp/repo/docker-ce/linux/centos/8/x86_64/stable/docker-ce-stable
  wget -O /tmp/repo/docker-ce/linux/centos/gpg https://download.docker.com/linux/centos/gpg
  pwd=$(pwd)
  cd /tmp/repo/docker-ce || exit
  tar -cf /tmp/docker-repo.tar ./*
  rm -rf /tmp/repo
  cd "$pwd" || exit
fi

if [ ! -f "/tmp/harbor_python_modules.tar" ]; then
  mkdir /tmp/Pyrepo
  rm -rf /tmp/harbor_python_requirements
cat > /tmp/harbor_python_requirements <<EOF
netcontrold
elasticsearch==7.13.*
EOF
  pip3 download -d /tmp/Pyrepo -r /tmp/harbor_python_requirements
  pwd=$(pwd)
  cd /tmp/Pyrepo || exit
  tar -cf /tmp/harbor_python_modules.tar ./*
  cd "$pwd" || exit
  rm -rf /tmp/Pyrepo
fi

### download director & jumpbox stemcell
if [ ! -f "/tmp/bosh-$STEMCELL_STAMP.tgz" ]; then
  curl -L https://bosh.io/d/stemcells/bosh-openstack-kvm-"$BOSH_STEMCELL"-go_agent --output /tmp/bosh-"$STEMCELL_STAMP".tgz > /dev/null
fi

if [ ! -f "/tmp/homebrew-$CF_BBL_INSTALL_TERRAFORM_VERSION.tar" ]; then
  docker pull mephmanx/homebrew-cache:"$CF_BBL_INSTALL_TERRAFORM_VERSION"
  docker run --rm -v /tmp:/tmp/export "$HOMEBREW_CACHE_IMAGE:$CF_BBL_INSTALL_TERRAFORM_VERSION"
fi

IFS=' ' read -r -a stemcell_array <<< "$CF_STEMCELLS"
for stemcell in "${stemcell_array[@]}";
do
  if [ ! -f "/tmp/stemcell-$stemcell-$STEMCELL_STAMP.tgz" ]; then
    curl -L https://bosh.io/d/stemcells/bosh-openstack-kvm-"$stemcell"-go_agent --output /tmp/stemcell-"$stemcell"-"$STEMCELL_STAMP".tgz > /dev/null
  fi
done
####

mkdir -p "/tmp/harbor/$OPENSTACK_VERSION"
if [ ! -f "/tmp/harbor/$OPENSTACK_VERSION/centos-binary-base-${OPENSTACK_VERSION}.tar" ] && [ ! -f "/tmp/harbor/$OPENSTACK_VERSION/kolla_${OPENSTACK_VERSION}_rpm_repo.tar.gz" ]; then
    for i in $(docker images |grep rpm_repo|awk '{print $3}');do docker rmi "$i";done
    for i in $(docker images |grep kolla|awk '{print $3}');do docker rmi "$i";done
    mkdir /tmp/harbor/"$OPENSTACK_VERSION"
    rm -rf /out
    mkdir /out
    docker pull "$DOCKER_OPENSTACK_OFFLINE_IMAGE:$OPENSTACK_VERSION"
    rm -rf /tmp/openstack-build.log
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v /out:/out "$DOCKER_OPENSTACK_OFFLINE_IMAGE:$OPENSTACK_VERSION" "$OPENSTACK_VERSION"

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

./create-cloudsupport-kvm-iso.sh
./create-identity-kvm-iso.sh
./create-cloud-kvm-iso.sh

embed_files=('/tmp/openstack-setup/openstack-env.sh'
              '/tmp/openstack-scripts/project_config.sh'
              '/tmp/openstack-scripts/openstack.sh'
              '/tmp/openstack-scripts/vm_functions.sh'
              '/tmp/openstack-scripts/vm-configurations.sh'
              '/tmp/openstack-scripts/create-cloud-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-kolla-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-cloudsupport-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-identity-kvm-deploy.sh'
              '/tmp/openstack-scripts/create-pfsense-kvm-deploy.sh'
              '/var/tmp/pfSense-CE-memstick-ADI-prod.img')

iso_images="/var/tmp/*.iso"
for img in $iso_images; do
  embed_files+=("$img")
done

printf -v embed_files_string '%s ' "${embed_files[@]}"
closeOutAndBuildKickstartAndISO centos-8-kickstart-openstack.cfg "openstack" "$embed_files_string"

isohybrid /var/tmp/openstack-iso.iso
## cleanup work dir
# Use to write to disk
# dd if=/var/tmp/openstack-iso.iso of=/dev/sdb bs=16M status=progress
rm -rf ./tmp