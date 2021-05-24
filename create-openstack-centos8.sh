source ./functions.sh
source ./iso-functions.sh
source ./vm-configurations.sh
source ./openstack-env.sh

ESXI_HOST=$1
ESXI_PASSWORD=$2
#### ESXi hostname #1 VM Name arg #2
setupENV ${ESXI_HOST}
########  ESXi password arg #2
installESXiTools

########## remove openstack
removeVM ${ESXI_PASSWORD} "openstack"
####################

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
esxi-scp -H $HOSTNAME -n /var/tmp/openstack-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos

esxi-vm-create -n openstack --summary --iso /vmfs/volumes/$ISO_DISK_NAME/isos/openstack-iso.iso \
  -c 24 -m 332 -S HP-Disk -v HP-Disk:3000,HP-SSD:1500 -N Openstack-Internal-Static -V --summary \
  -o 'cpuid.coresPerSocket = "4",
              vhv.enable = "TRUE",
              vvtd.enable = "TRUE",
              guestOS="centos8-64",
              virtualHW.version = "17",
              tools.upgrade.policy = "upgradeAtPowerCycle",
              autostart = "TRUE",
              tools.syncTime = "TRUE"'

