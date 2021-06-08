source ./iso-functions.sh
source ./openstack-env.sh

ESXI_HOST=$1
ESXI_PASSWORD=$2
#### ESXi hostname #1 VM Name arg #2
setupENV ${ESXI_HOST}
########  ESXi password arg #2
installESXiTools
removeVM ${ESXI_PASSWORD} "cloudsupport"

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
esxi-scp -H $HOSTNAME -n /var/tmp/cloudsupport-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos

esxi-vm-create -n cloudsupport --summary --iso /vmfs/volumes/$ISO_DISK_NAME/isos/cloudsupport-iso.iso \
  -c 2 -m 16 -S HP-Disk -v HP-Disk:400 -N os-int,os-loc -V --summary \
  -o 'cpuid.coresPerSocket = "1",
              vhv.enable = "TRUE",
              vvtd.enable = "TRUE",
              guestOS="centos8-64",
              virtualHW.version = "17",
              tools.upgrade.policy = "upgradeAtPowerCycle",
              autostart = "TRUE",
              tools.syncTime = "TRUE"'
