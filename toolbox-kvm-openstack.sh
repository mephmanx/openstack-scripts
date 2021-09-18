#!/bin/bash
#can ONLY be run as root!  sudo to root

source ./vm_functions.sh
### openstack-env needs to be in same directory as this script
rm -rf /tmp/openstack-env.sh
cp $1 /tmp/openstack-env.sh
source /tmp/openstack-env.sh

rm -rf /var/tmp/openstack-iso.iso

## prep project config by replacing nested vars
prep_project_config
#########

source ./iso-functions.sh
source /tmp/project_config.sh

mkdir ./tmp
cp centos-8-kickstart-openstack.cfg ./tmp

IFS=
kickstart_file=./tmp/centos-8-kickstart-openstack.cfg

#### generate random password and reload env
export RANDOM_PWD=`date +%s | sha256sum | base64 | head -c 32 ; echo`
######

########### add passwords in
sed -i 's/{CENTOS_ADMIN_PWD}/'$RANDOM_PWD'/g' ${kickstart_file}
sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' ${kickstart_file}
sed -i 's/{DYNAMIC_CONFIG}/'$DYNAMIC_CONFIG'/g' ${kickstart_file}
###########################

############### Secrets file ################
echo 'cat > /tmp/openstack-env.sh <<EOF' >> ${kickstart_file}
cat $1 >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

#### zip repo and embed in iso
zip -r /tmp/repo.zip ./* -x "*.git"
echo 'cat > /tmp/repo.zip <<EOF' >> ${kickstart_file}
cat /tmp/repo.zip >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
#####

## download files to be embedded
echo "downloading pfsense from ${PFSENSE}"
wget -q -O /tmp/pfSense-CE-memstick-ADI.img.gz ${PFSENSE}
echo "downloading harbor from ${HARBOR}"
wget -q -O /tmp/harbor.tgz ${HARBOR}
echo "downloading magnum image from $MAGNUM_IMAGE"
curl -o /tmp/magnum.qcow2 $MAGNUM_IMAGE -s -k
####

embed_files=("/tmp/pfSense-CE-memstick-ADI.img.gz" "/tmp/harbor.tgz" "/tmp/magnum.qcow2")
closeOutAndBuildKickstartAndISO "${kickstart_file}" "openstack" $embed_files

## cleanup kickstart file
rm -rf ./tmp/centos-8-kickstart-openstack.cfg
rm -rf ./tmp