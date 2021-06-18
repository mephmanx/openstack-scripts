source ./iso-functions.sh
source ./openstack-env.sh

removeVM_kvm "cloudsupport"

IFS=
kickstart_file=centos-8-kickstart-cloudsupport.cfg
####initial certs###############
letsEncryptAndCockpitCerts ${kickstart_file}
###############################

########### add passwords in
sed -i 's/{GITHUB_TOKEN}/'$GITHUB_TOKEN'/g' ${kickstart_file}
sed -i 's/{CENTOS_ROOT_PWD}/'$CENTOS_ROOT_PWD'/g' ${kickstart_file}
###########################

############### Global Addresses ################
echo 'cat > /tmp/global_addresses.sh <<EOF' >> ${kickstart_file}
echo 'export DOMAIN_NAME=lyonsgroup.family' >> ${kickstart_file}
echo 'export APP_INTERNAL_HOSTNAME=openstack-local' >> ${kickstart_file}
echo 'export APP_EXTERNAL_HOSTNAME=openstack' >> ${kickstart_file}
echo 'export SUPPORT_HOST=cloudsupport' >> ${kickstart_file}
echo 'export INTERNAL_VIP="10.0.20.254"' >> ${kickstart_file}
echo 'export EXTERNAL_VIP="192.168.1.252"' >> ${kickstart_file}
echo 'export SUPPORT_VIP="10.0.20.200"' >> ${kickstart_file}
cat /tmp/dns_hosts >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

############### Secrets file ################
echo 'cat > /tmp/openstack-env.sh <<EOF' >> ${kickstart_file}
cat ./openstack-env.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

closeOutAndBuildKickstartAndISO "${kickstart_file}" "cloudsupport"

create_line="virt-install "
create_line+="--hvm "
create_line+="--virt-type=kvm "
create_line+="--name=cloudsupport "
create_line+="--memory=16000 "
create_line+="--cpu=host-passthrough,cache.mode=passthrough "
create_line+="--cpuset=auto "
create_line+="--vcpus=4,maxvcpus=4,sockets=2,cores=1,threads=2 "
create_line+="--disk=pool=HP-Disk,size=400,bus=scsi,sparse=no "
create_line+="--cdrom=/var/tmp/cloudsupport-iso.iso "
create_line+="--network type=direct,source=int-static,model=virtio  --network type=network,source=loc-static,model=virtio "
create_line+="--os-variant=centos8 "
create_line+="--graphics=vnc "
create_line+="--autostart"

echo $create_line
eval $create_line &
