#!/bin/bash

source /tmp/openstack-scripts/iso-functions.sh
source /tmp/openstack-scripts/vm_functions.sh
source /tmp/openstack-env.sh
source /tmp/project_config.sh

KICKSTART_DIR=/tmp/openstack-scripts

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Removing existing openldap vm and building image for new one...."

removeVM_kvm "openldap"

IFS=
rm -rf ${KICKSTART_DIR}/centos-8-kickstart-openldap.cfg
cp ${KICKSTART_DIR}/centos-8-kickstart-cloudsupport.cfg ${KICKSTART_DIR}/centos-8-kickstart-ld.cfg
echo "copied kickstart -> ${KICKSTART_DIR}/centos-8-kickstart-openldap.cfg to -> ${KICKSTART_DIR}/centos-8-kickstart-ld.cfg"
kickstart_file=${KICKSTART_DIR}/centos-8-kickstart-ld.cfg
echo "kickstart file -> ${kickstart_file}"
kickstart_file=centos-8-kickstart-ld.cfg
rootpwd=`cat /root/env_admin_pwd`

ADMIN_PWD=`cat /home/admin/env_osuser_pwd`

########### add passwords in
sed -i 's/{CENTOS_ADMIN_PWD}/'$ADMIN_PWD'/g' ${kickstart_file}
sed -i 's/{OPENLDAP_VIP}/'$OPENLDAP_VIP'/g' ${kickstart_file}
sed -i 's/{HOST}/'$OPENLDAP_HOST'/g' ${kickstart_file}
sed -i 's/{NTP_SERVER}/'$GATEWAY_ROUTER_IP'/g' ${kickstart_file}
sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' ${kickstart_file}
sed -i 's/{GATEWAY_ROUTER_IP}/'$GATEWAY_ROUTER_IP'/g' ${kickstart_file}
sed -i 's/{NETMASK}/'$NETMASK'/g' ${kickstart_file}
sed -i 's/{GENERATED_PWD}/'$rootpwd'/g' ${kickstart_file}
###########################

embed_files=('/root/.ssh/id_rsa.crt'
              '/root/.ssh/id_rsa.key'
              '/tmp/openstack-env.sh'
              '/tmp/project_config.sh'
              '/tmp/openstack-scripts/init-openldap.sh'
              '/tmp/openstack-scripts/vm_functions.sh')

printf -v embed_files_string '%s ' "${embed_files[@]}"
closeOutAndBuildKickstartAndISO "${kickstart_file}" "openldap" $embed_files_string

DISK_COUNT=`lshw -json -class disk | grep -o -i disk: | wc -l`
if [[ $DISK_COUNT -lt 2 ]]; then
  size_avail=`df /VM-VOL-ALL | awk '{print $4}' | sed 1d`
  DRIVE_SIZE=$(($((size_avail * 2/100)) / 1024 / 1024))
else
  size_avail=`df /VM-VOL-MISC | awk '{print $4}' | sed 1d`
  DRIVE_SIZE=$(($((size_avail * 20/100)) / 1024 / 1024))
fi

create_line="virt-install "
create_line+="--hvm "
create_line+="--virt-type=kvm "
create_line+="--name=openldap "
create_line+="--memory=$OPENLDAP_RAM "
create_line+="--cpu=host-passthrough,cache.mode=passthrough "
create_line+="--cpuset=auto "
create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
create_line+="--memorybacking hugepages=yes "
create_line+="--vcpus=4,maxvcpus=4,sockets=2,cores=1,threads=2 "
create_line+="--controller type=scsi,model=virtio-scsi "
create_line+="--disk pool=$(getDiskMapping "misc" "1"),size=$DRIVE_SIZE,bus=virtio,sparse=no "
create_line+="--cdrom=/var/tmp/openldap-iso.iso "
create_line+="--network type=bridge,source=loc-static,model=virtio "
create_line+="--os-variant=centos8 "
create_line+="--graphics=vnc "
create_line+="--autostart"

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Creating openldap vm"

echo $create_line
eval $create_line
