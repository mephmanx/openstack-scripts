source ./functions.sh
source ./iso-functions.sh
source ./portus-env.sh
source ./openstack-env.sh

export VM_NAME=cloudsupport
#### ESXi hostname #1 VM Name arg #2
setupENV $1
########  ESXi password arg #2
removeVM $2 $VM_NAME
installESXiTools

IFS=
kickstart_file=centos-8-kickstart-$VM_NAME.cfg
####initial certs###############
letsEncryptAndCockpitCerts ${kickstart_file}

###############################

#########concourse compose##############

echo 'cat > /tmp/docker-compose.yml <<EOF' >> ${kickstart_file}
cat ./concourse-compose.yml >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}

#######################

############# Docker account
echo 'cat > /tmp/docker.pass <<EOF' >> ${kickstart_file}
echo ${DOCKER_HUB_PWD} >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

############### Github Token ################
echo 'cat > /tmp/openstack-env.sh <<EOF' >> ${kickstart_file}
cat ./openstack-env.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

#########portus env##############
echo 'cat > /tmp/portus-env.sh <<EOF' >> ${kickstart_file}
cat ./portus-env.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
#######################

closeOutAndBuildKickstartAndISO "${kickstart_file}" "${VM_NAME}"
esxi-scp -H $HOSTNAME -n /var/tmp/$VM_NAME-iso.iso -l /vmfs/volumes/$ISO_DISK_NAME/isos

esxi-vm-create -n $VM_NAME --summary --iso /vmfs/volumes/$ISO_DISK_NAME/isos/$VM_NAME-iso.iso \
  -c 2 -m 16 -S HP-Disk -v HP-Disk:400 -N Openstack-External,Openstack-Internal -V --summary \
  -o 'cpuid.coresPerSocket = "1",
              vhv.enable = "TRUE",
              vvtd.enable = "TRUE",
              guestOS="centos8-64",
              virtualHW.version = "17",
              tools.upgrade.policy = "upgradeAtPowerCycle",
              tools.syncTime = "TRUE"'
