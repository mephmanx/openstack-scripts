#!/bin/bash

rm -rf /root/identity-install.log
exec 1>/root/identity-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x

. ./iso-functions.sh
. ./project_config.sh

KICKSTART_DIR=/tmp/openstack-scripts

IFS=
rm -rf ${KICKSTART_DIR}/centos-8-kickstart-ld.cfg
cp ${KICKSTART_DIR}/centos-8-kickstart-identity.cfg ${KICKSTART_DIR}/centos-8-kickstart-ld.cfg
echo "copied kickstart -> ${KICKSTART_DIR}/centos-8-kickstart-identity.cfg to -> ${KICKSTART_DIR}/centos-8-kickstart-ld.cfg"
kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-ld.cfg
echo "kickstart file -> ${kickstart_file}"
kickstart_file=centos-8-kickstart-ld.cfg

########### add passwords in
sed -i "s/{IDENTITY_VIP}/$IDENTITY_VIP/g" ${kickstart_file}
sed -i "s/{HOST}/$IDENTITY_HOST/g" ${kickstart_file}
sed -i "s/{GATEWAY_ROUTER_IP}/$GATEWAY_ROUTER_IP/g" ${kickstart_file}
sed -i "s/{NETMASK}/$NETMASK/g" ${kickstart_file}
###########################

embed_files=('/tmp/openstack-scripts/project_config.sh'
              '/tmp/openstack-scripts/init-identity.sh'
              '/tmp/openstack-scripts/vm_functions.sh')

printf -v embed_files_string '%s ' "${embed_files[@]}"
closeOutAndBuildKickstartAndISO "${kickstart_file}" "identity" "$embed_files_string"

rm -rf ${kickstart_file}