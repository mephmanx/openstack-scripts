source ./iso-functions.sh
source ./openstack-env.sh

cd /tmp/openstack-scripts;
git pull;
cd /tmp/openstack-setup;
git pull;

cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;

virsh destroy "cloudsupport"
virsh undefine "cloudsupport"
virsh vol-delete --pool HP-Disk cloudsupport

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

echo "virt-install --virt-type kvm --name cloudsupport --memory 16000 --vcpus 2 --disk pool=HP-EXT,size=400,bus=scsi --cdrom /var/tmp/cloudsupport-iso.iso --network type=direct,source=os-int-static,model=rtl8139  --network type=direct,source=os-loc-static,model=rtl8139 --os-variant centos8 --graphics vnc"

eval "virt-install --virt-type kvm --name cloudsupport --memory 16000 --vcpus 2 --disk pool=HP-EXT,size=400,bus=scsi --cdrom /var/tmp/cloudsupport-iso.iso --network type=direct,source=os-int-static,model=rtl8139  --network type=direct,source=os-loc-static,model=rtl8139 --os-variant centos8 --graphics vnc" &

