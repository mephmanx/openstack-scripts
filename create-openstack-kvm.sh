source ./iso-functions.sh
source ./openstack-env.sh

cd /tmp/openstack-scripts;
git pull;
cd /tmp/openstack-setup;
git pull;

rm -rf /var/tmp/*.*;

cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;

removeVM_kvm "openstack"

IFS=
kickstart_file=centos-8-kickstart-openstack.cfg
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

closeOutAndBuildKickstartAndISO "${kickstart_file}" "openstack"

echo "virt-install --virt-type kvm --name openstack --memory 160000 --vcpus 2 --disk pool=HP-Disk,size=400,bus=scsi,sparse=no --cdrom /var/tmp/openstack-iso.iso --network type=direct,source=os-int-static,model=rtl8139  --network type=direct,source=br0-loc-static,model=rtl8139 --os-variant centos8 --graphics vnc"

eval "virt-install --virt-type kvm --name openstack --memory 160000 --vcpus 2 --disk pool=HP-Disk,size=400,bus=scsi,sparse=no --cdrom /var/tmp/openstack-iso.iso --network type=direct,source=os-int-static,model=rtl8139  --network type=direct,source=br0-loc-static,model=rtl8139 --os-variant centos8 --graphics vnc" &

