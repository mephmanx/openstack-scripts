#!/bin/bash
#can ONLY be run as root!  sudo to root

### openstack-env needs to be in same directory as this script
source ./openstack-env.sh

git reset --hard
git pull

rm -rf /tmp/vm_functions.sh
cp /tmp/openstack-scripts/vm_functions.sh /tmp

rm -rf /var/tmp/openstack-iso.iso

## prep project config by replacing nested vars
source /tmp/vm_functions.sh
prep_project_config
#########

source ./iso-functions.sh
source /tmp/project_config.sh

IFS=
kickstart_file=centos-8-kickstart-openstack.cfg

#### generate random password and reload env
export RANDOM_PWD=`date +%s | sha256sum | base64 | head -c 32 ; echo`
######

########### add passwords in
sed -i 's/{GITHUB_TOKEN}/'$GITHUB_TOKEN'/g' ${kickstart_file}
sed -i 's/{GITHUB_USER}/'$GITHUB_USER'/g' ${kickstart_file}
sed -i 's/{CENTOS_ADMIN_PWD}/'$RANDOM_PWD'/g' ${kickstart_file}
sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' ${kickstart_file}
###########################

############### Secrets file ################
echo 'cat > /tmp/openstack-env.sh <<EOF' >> ${kickstart_file}
cat ./openstack-env.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

closeOutAndBuildKickstartAndISO "${kickstart_file}" "openstack"