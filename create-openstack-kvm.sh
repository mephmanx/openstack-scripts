#!/bin/bash

source ./iso-functions.sh
source ./openstack-env.sh

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

############### Global Addresses ################
echo 'cat > /tmp/global_addresses.sh <<EOF' >> ${kickstart_file}
cat ./global_addresses.sh >> ${kickstart_file}
echo 'EOF' >> ${kickstart_file}
###############################

closeOutAndBuildKickstartAndISO "${kickstart_file}" "openstack"

