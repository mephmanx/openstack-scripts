#!/bin/bash

rm -rf /tmp/identity-install.log
exec 1>/root/identity-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x

source /tmp/openstack-scripts/iso-functions.sh
source /tmp/openstack-scripts/vm_functions.sh
source /tmp/openstack-env.sh
source /tmp/project_config.sh

KICKSTART_DIR=/tmp/openstack-scripts

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Removing existing identity vm and building image for new one...."

removeVM_kvm "identity"

IFS=
rm -rf ${KICKSTART_DIR}/centos-8-kickstart-ld.cfg
cp ${KICKSTART_DIR}/centos-8-kickstart-identity.cfg ${KICKSTART_DIR}/centos-8-kickstart-ld.cfg
echo "copied kickstart -> ${KICKSTART_DIR}/centos-8-kickstart-identity.cfg to -> ${KICKSTART_DIR}/centos-8-kickstart-ld.cfg"
kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-ld.cfg
echo "kickstart file -> ${kickstart_file}"
kickstart_file=centos-8-kickstart-ld.cfg
ADMIN_PWD=`cat /root/env_admin_pwd`
DIRECTORY_MGR_PWD=`cat /root/directory_mgr_pwd`
TZ=`timedatectl | awk '/Time zone:/ {print $3}'`
TIMEZONE=`echo $TZ | sed 's/\//\\\\\//g'`
########### add passwords in
sed -i 's/{CENTOS_ADMIN_PWD}/'$ADMIN_PWD'/g' ${kickstart_file}
sed -i 's/{IDENTITY_VIP}/'$IDENTITY_VIP'/g' ${kickstart_file}
sed -i 's/{HOST}/'$IDENTITY_HOST'/g' ${kickstart_file}
sed -i 's/{NTP_SERVER}/'$GATEWAY_ROUTER_IP'/g' ${kickstart_file}
sed -i 's/{GATEWAY_ROUTER_IP}/'$GATEWAY_ROUTER_IP'/g' ${kickstart_file}
sed -i 's/{NETMASK}/'$NETMASK'/g' ${kickstart_file}
sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' ${kickstart_file}
sed -i 's/{DIRECTORY_MGR_PWD}/'$DIRECTORY_MGR_PWD'/g' ${kickstart_file}
sed -i 's/{GENERATED_PWD}/'$(generate_random_pwd)'/g' ${kickstart_file}
###########################

embed_files=('/root/.ssh/id_rsa.crt'
              '/root/.ssh/id_rsa.pub'
              '/root/.ssh/id_rsa.key'
              '/tmp/openstack-env.sh'
              '/tmp/project_config.sh'
              '/tmp/openstack-scripts/init-identity.sh'
              '/tmp/openstack-scripts/vm_functions.sh')

printf -v embed_files_string '%s ' "${embed_files[@]}"
closeOutAndBuildKickstartAndISO "${kickstart_file}" "identity" $embed_files_string
