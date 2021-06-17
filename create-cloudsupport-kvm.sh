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

############### Secrets file ################
echo 'cat > /tmp/openstack-env.sh <<EOF' >> ${kickstart_file}
cat ./openstack-env.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

closeOutAndBuildKickstartAndISO "${kickstart_file}" "cloudsupport"

echo "virt-install --virt-type kvm --name cloudsupport --memory 16000 --hvm --cpu host-passthrough,cache.mode=passthrough --vcpus 2,maxvcpus=8,sockets=2,cores=1,threads=4 --disk pool=HP-EXT,size=400,bus=scsi,sparse=no --cdrom /var/tmp/cloudsupport-iso.iso --network type=direct,source=int-static,model=virtio  --network type=network,source=loc-static,model=virtio --os-variant centos8 --graphics vnc --autostart"

eval "virt-install --virt-type kvm --name cloudsupport --memory 16000 --hvm --cpu host-passthrough,cache.mode=passthrough --vcpus 2,maxvcpus=8,sockets=2,cores=1,threads=4 --disk pool=HP-EXT,size=400,bus=scsi,sparse=no --cdrom /var/tmp/cloudsupport-iso.iso --network type=direct,source=int-static,model=virtio  --network type=network,source=loc-static,model=virtio --os-variant centos8 --graphics vnc --autostart" &

