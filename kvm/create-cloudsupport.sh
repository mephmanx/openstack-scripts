source ./kvm-functions.sh
source ../iso-functions.sh
source ../openstack-env.sh

export VM_NAME=cloudsupport

setupENV

########  ESXi password arg #2
removeVMESXi $2 $VM_NAME
installESXiTools

IFS=
kickstart_file=centos-8-kickstart-$VM_NAME.cfg
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

closeOutAndBuildKickstartAndISO "${kickstart_file}" "${VM_NAME}"
esxi-scp -H $HOSTNAME -n /var/tmp/$VM_NAME-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos

esxi-vm-create -n $VM_NAME --summary --iso /vmfs/volumes/$ISO_DISK_NAME/isos/$VM_NAME-iso.iso \
  -c 2 -m 16 -S HP-Disk -v HP-Disk:400 -N Openstack-Internal,Openstack-Local -V --summary \
  -o 'cpuid.coresPerSocket = "1",
              vhv.enable = "TRUE",
              vvtd.enable = "TRUE",
              guestOS="centos8-64",
              virtualHW.version = "17",
              tools.upgrade.policy = "upgradeAtPowerCycle",
              autostart = "TRUE",
              tools.syncTime = "TRUE"'
