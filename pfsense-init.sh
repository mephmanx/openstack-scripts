#!/bin/sh
## this script will run on pfsense reboot and then remove itself
## this script is run on a FreeBSD system, not centos, not bash.  Makes some things slightly different

. /root/project_config.sh
. /root/openstack-env.sh
. /root/openstack-scripts/pf_functions.sh

exec 1>/root/init-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

IP_DATA=`ifconfig vtnet0 | grep inet`
DRIVE_SIZE=`geom disk list | grep Mediasize | sed 2d | awk '{ print $2 }'`
sed -i 's/{CACHE_SIZE}/'$(($DRIVE_SIZE / 1024 / 1024 * 75/100))'/g' /conf/config.xml
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense initialization script beginning... \n\nCloud DMZ IP: $IP_DATA"

### perform downloads first so that VM installs can continue
mkdir /usr/local/www/isos

if [ ! -f "/usr/local/www/isos/linux.iso" ]; then
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: pulling linux image"
  rm -rf /usr/local/www/isos/linux.iso
  curl -o /usr/local/www/isos/linux.iso http://$LAN_CENTOS_IP:8000/linux.iso -s --retry 10
fi
################

## preparing next reboot
## build next reboot script to start cloud build.  overwrite contents of this file so it is executed on next reboot
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: Building second init script to kick off cloud build."

cat <<EOF >/usr/local/etc/rc.d/pfsense-init-2.sh
#!/bin/sh

exec 1>/root/init2-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

## this script will run on pfsense reboot and then remove itself
## this script is run on a FreeBSD system, not centos, not bash.  Makes some things slightly different

. /root/project_config.sh
. /root/openstack-env.sh
. /root/openstack-scripts/pf_functions.sh

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: Second init script running"

## kickoff cloud build
ssh root@$LAN_CENTOS_IP 'cd /tmp/openstack-scripts; ./create-identity-kvm.sh;' &

### install remaining packages here
install_pkg "pfsense-pkg-openvpn-client-export" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-pfBlockerNG-devel" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-snort" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-cron" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-Telegraf" $TELEGRAM_API $TELEGRAM_CHAT_ID

### start services after install/reboot
cd /usr/local/etc/rc.d
# start snort
./snort.sh start
# start telegraf
./telegraf.sh start &
####

## perform any cleanup here

####

### remove from starting on boot
rm -rf /usr/local/etc/rc.d/pfsense-init-2.sh

EOF

chmod a+rx /usr/local/etc/rc.d/pfsense-init-2.sh
#########

## additional packages
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: Installing packages..."

install_pkg "pfsense-pkg-squid" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-haproxy-devel" $TELEGRAM_API $TELEGRAM_CHAT_ID

rm -rf /root/openstack-scripts/pfsense-init.sh

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: init complete! removing script and rebooting.."
reboot