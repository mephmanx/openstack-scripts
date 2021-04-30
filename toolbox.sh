#can ONLY be run as root!  sudo to root
source ./openstack-setup/openstack-env.sh
CMD=$(cat <<END

rm -rf /root/openstack-setup;
rm -rf /root/openstack-scripts;

git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git /root/openstack-setup;
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git /root/openstack-scripts;

cp -r /root/openstack-scripts/*.sh /root/openstack-setup;
cp /root/openstack-scripts/*.cfg /root/openstack-setup;

cd /root/openstack-setup
/root/openstack-setup/$1/create-$2.sh 192.168.3.100 $3;

END)

ssh -l root 192.168.3.101 "$CMD"