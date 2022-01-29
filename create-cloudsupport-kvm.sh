#!/bin/bash

rm -rf /tmp/cloudsupport-install.log
exec 1>/root/cloudsupport-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x

source /tmp/openstack-scripts/iso-functions.sh
source /tmp/openstack-scripts/vm_functions.sh
source /tmp/openstack-env.sh
source /tmp/project_config.sh

KICKSTART_DIR=/tmp/openstack-scripts
if (virsh list --name | grep -q "cloudsupport"); then
  return
else
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Removing existing cloudsupport vm and building image for new one...."
fi

IFS=
rm -rf ${KICKSTART_DIR}/centos-8-kickstart-cs.cfg
cp ${KICKSTART_DIR}/centos-8-kickstart-cloudsupport.cfg ${KICKSTART_DIR}/centos-8-kickstart-cs.cfg
echo "copied kickstart -> ${KICKSTART_DIR}/centos-8-kickstart-cloud_common.cfg to -> ${KICKSTART_DIR}/centos-8-kickstart-cs.cfg"
kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-cs.cfg
echo "kickstart file -> ${kickstart_file}"
kickstart_file=centos-8-kickstart-cs.cfg

TZ=`timedatectl | awk '/Time zone:/ {print $3}'`
TIMEZONE=`echo $TZ | sed 's/\//\\\\\//g'`
########### add passwords in
#sed -i 's/{CENTOS_ADMIN_PWD_123456789012}/'$ADMIN_PWD'/g' ${kickstart_file}
sed -i 's/{HOST}/'$SUPPORT_HOST'/g' ${kickstart_file}
sed -i 's/{NTP_SERVER}/'$GATEWAY_ROUTER_IP'/g' ${kickstart_file}
sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' ${kickstart_file}
sed -i 's/{SUPPORT_VIP}/'$SUPPORT_VIP'/g' ${kickstart_file}
sed -i 's/{GATEWAY_ROUTER_IP}/'$GATEWAY_ROUTER_IP'/g' ${kickstart_file}
sed -i 's/{IDENTITY_VIP}/'$IDENTITY_VIP'/g' ${kickstart_file}
sed -i 's/{NETMASK}/'$NETMASK'/g' ${kickstart_file}
sed -i 's/{GENERATED_PWD}/'$(generate_random_pwd 31)'/g' ${kickstart_file}
###########################

embed_files=("/tmp/harbor-$HARBOR_VERSION.tgz"
              '/root/.ssh/id_rsa.crt'
              '/root/.ssh/wildcard.crt'
              '/root/.ssh/wildcard.key'
              '/tmp/openstack-scripts/harbor.yml'
              '/tmp/openstack-env.sh'
              '/tmp/project_config.sh'
              "/tmp/docker-compose-$DOCKER_COMPOSE_VERSION"
              '/tmp/openstack-scripts/init-cloudsupport.sh'
              '/tmp/openstack-scripts/vm_functions.sh')

harbor_images="/tmp/harbor/*"
for img in $harbor_images; do
  embed_files+=($img)
done

printf -v embed_files_string '%s ' "${embed_files[@]}"
closeOutAndBuildKickstartAndISO "${kickstart_file}" "cloudsupport" $embed_files_string

DISK_COUNT=`lshw -json -class disk | grep -o -i disk: | wc -l`
if [[ $DISK_COUNT -lt 2 ]]; then
  size_avail=`df /VM-VOL-ALL | awk '{print $2}' | sed 1d`
  DRIVE_SIZE=$(($((size_avail * 5/100)) / 1024 / 1024))
else
  size_avail=`df /VM-VOL-MISC | awk '{print $2}' | sed 1d`
  DRIVE_SIZE=$(($((size_avail * 40/100)) / 1024 / 1024))
fi

## find minimum drive size and test for that

create_line="virt-install "
create_line+="--hvm "
create_line+="--virt-type=kvm "
create_line+="--name=cloudsupport "
create_line+="--memory=${CLOUDSUPPORT_RAM}000 "
create_line+="--cpu=host-passthrough,cache.mode=passthrough "
create_line+="--cpuset=auto "
create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
create_line+="--memorybacking hugepages=yes "
create_line+="--vcpus=4,maxvcpus=4,sockets=2,cores=1,threads=2 "
create_line+="--controller type=scsi,model=virtio-scsi "
create_line+="--disk pool=$(getDiskMapping "misc" "1"),size=$DRIVE_SIZE,bus=virtio,sparse=no "
create_line+="--cdrom=/var/tmp/cloudsupport-iso.iso "
create_line+="--network type=bridge,source=loc-static,model=virtio "
create_line+="--os-variant=centos8 "
create_line+="--graphics=vnc "
create_line+="--autostart"

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Creating cloudsupport vm"

echo $create_line
eval $create_line &
