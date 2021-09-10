#!/bin/bash

source ./iso-functions.sh
source /tmp/openstack-env.sh
source /tmp/project_config.sh

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Removing existing cloudsupport vm and building image for new one...."

removeVM_kvm "cloudsupport"

IFS=
kickstart_file=centos-8-kickstart-cloudsupport.cfg
####initial certs###############
cockpitCerts ${kickstart_file}
###############################

if [[ $HYPERVISOR_DEBUG == 1 ]]; then
  #### use random root password from install
  rootpwd=`cat /home/admin/rootpw`
  ######
else
  #### Use autogen password
  HOWLONG=15 ## the number of characters
  rootpwd=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
fi

########### add passwords in
sed -i 's/{GITHUB_TOKEN}/'$GITHUB_TOKEN'/g' ${kickstart_file}
sed -i 's/{GITHUB_USER}/'$GITHUB_USER'/g' ${kickstart_file}
sed -i 's/{CENTOS_ADMIN_PWD}/'$CENTOS_ADMIN_PWD'/g' ${kickstart_file}
sed -i 's/{SUPPORT_VIP}/'$SUPPORT_VIP'/g' ${kickstart_file}
sed -i 's/{HOST}/'$SUPPORT_HOST'/g' ${kickstart_file}
sed -i 's/{NTP_SERVER}/'$GATEWAY_ROUTER_IP'/g' ${kickstart_file}
sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' ${kickstart_file}
sed -i 's/{SUPPORT_VIP}/'$SUPPORT_VIP'/g' ${kickstart_file}
sed -i 's/{GATEWAY_ROUTER_IP}/'$GATEWAY_ROUTER_IP'/g' ${kickstart_file}
sed -i 's/{NETMASK}/'$NETMASK'/g' ${kickstart_file}
sed -i 's/{GENERATED_PWD}/'$rootpwd'/g' ${kickstart_file}
###########################

############### External Project Configs ################
echo 'cat > /tmp/project_config.sh <<EOF' >> ${kickstart_file}
cat /tmp/project_config.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

############### Secrets file ################
echo 'cat > /tmp/openstack-env.sh <<EOF' >> ${kickstart_file}
cat /tmp/openstack-env.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

closeOutAndBuildKickstartAndISO "${kickstart_file}" "cloudsupport"

create_line="virt-install "
create_line+="--hvm "
create_line+="--virt-type=kvm "
create_line+="--name=cloudsupport "
create_line+="--memory=12000 "
create_line+="--cpu=host-passthrough,cache.mode=passthrough "
create_line+="--cpuset=auto "
create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
create_line+="--memorybacking hugepages=yes "
create_line+="--vcpus=4,maxvcpus=4,sockets=2,cores=1,threads=2 "
create_line+="--controller type=scsi,model=virtio-scsi "
create_line+="--disk pool=Disk,size=400,bus=virtio,sparse=no "
create_line+="--cdrom=/var/tmp/cloudsupport-iso.iso "
create_line+="--network type=bridge,source=loc-static,model=virtio "
create_line+="--os-variant=centos8 "
create_line+="--graphics=vnc "
create_line+="--autostart"

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Creating cloudsupport vm"

echo $create_line
eval $create_line &
