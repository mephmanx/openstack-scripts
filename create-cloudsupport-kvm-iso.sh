#!/bin/bash

rm -rf /root/cloudsupport-install.log
exec 1>/root/cloudsupport-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x

source /tmp/openstack-scripts/iso-functions.sh
source /tmp/project_config.sh

KICKSTART_DIR=/tmp/openstack-scripts

IFS=
rm -rf ${KICKSTART_DIR}/centos-8-kickstart-cs.cfg
cp ${KICKSTART_DIR}/centos-8-kickstart-cloudsupport.cfg ${KICKSTART_DIR}/centos-8-kickstart-cs.cfg
echo "copied kickstart -> ${KICKSTART_DIR}/centos-8-kickstart-cloud_common.cfg to -> ${KICKSTART_DIR}/centos-8-kickstart-cs.cfg"
kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-cs.cfg
echo "kickstart file -> ${kickstart_file}"
kickstart_file=centos-8-kickstart-cs.cfg

########### add passwords in
sed -i "s/{HOST}/$SUPPORT_HOST/g" ${kickstart_file}
sed -i "s/{SUPPORT_VIP}/$SUPPORT_VIP/g" ${kickstart_file}
sed -i "s/{GATEWAY_ROUTER_IP}/$GATEWAY_ROUTER_IP/g" ${kickstart_file}
sed -i "s/{IDENTITY_VIP}/$IDENTITY_VIP/g" ${kickstart_file}
sed -i "s/{NETMASK}/$NETMASK/g" ${kickstart_file}
###########################

embed_files=("/tmp/harbor-$HARBOR_VERSION.tgz"
              '/tmp/id_rsa'
              '/tmp/id_rsa.pub'
              '/tmp/openstack-scripts/harbor.yml'
              '/tmp/openstack-env.sh'
              '/tmp/project_config.sh'
              '/tmp/harbor_python_modules.tar'
              "/tmp/docker-compose-$DOCKER_COMPOSE_VERSION"
              '/tmp/openstack-scripts/init-cloudsupport.sh'
              '/tmp/openstack-scripts/vm_functions.sh')

harbor_images="/tmp/harbor/$OPENSTACK_VERSION/*"
for img in $harbor_images; do
  embed_files+=("$img")
done

printf -v embed_files_string '%s ' "${embed_files[@]}"
closeOutAndBuildKickstartAndISO "${kickstart_file}" "cloudsupport" "$embed_files_string"

rm -rf ${kickstart_file}