#can ONLY be run as root!  sudo to root
source ./openstack-setup/openstack-env.sh
echo "$1" "$2" "$3" "$4"
CMD=$(cat <<END

rm -rf /root/openstack-setup;
rm -rf /root/openstack-scripts;

git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-setup.git /root/openstack-setup;
git clone https://mephmanx:$GITHUB_TOKEN@github.com/mephmanx/openstack-scripts.git /root/openstack-scripts;

cp -r /root/openstack-setup/openstack-env.sh /root/openstack-scripts;
mkdir /root/openstack-scripts/certs

cp -r /root/openstack-setup/certs/*.* /root/openstack-scripts/certs;
cd /root/openstack-scripts

echo "$1" | ./buildEnvironment.sh --"$2" --"$3" --"$4" -o 192.168.3.100 -p
END)

ssh -l root 192.168.3.101 "$CMD"