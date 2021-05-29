source ./openstack-setup/openstack-env.sh

rm -rf /tmp/openstack-setup;
rm -rf /tmp/openstack-scripts;

git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git /tmp/openstack-setup;
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git /tmp/openstack-scripts;

cp /tmp/openstack-scripts/*.sh /tmp/openstack-setup;
cp /tmp/openstack-scripts/*.cfg /tmp/openstack-setup;

cd /tmp/openstack-setup

source ./iso-functions.sh
source ./vm-configurations.sh
source ./openstack-env.sh

ESXI_HOST=$1
ESXI_PASSWORD=$2
#### ESXi hostname #1 VM Name arg #2
setupENV ${ESXI_HOST}
########  ESXi password arg #2
installESXiTools


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