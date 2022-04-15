#!/bin/sh
## this script will run on pfsense reboot and then remove itself
## this script is run on a FreeBSD system, not centos, not bash.  Makes some things slightly different

. /root/project_config.sh
. /root/pf_functions.sh

exec 1>/root/init-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

IP_DATA=$(ifconfig vtnet0 | grep inet | awk -F' ' '{ print $2 }' | head -2 | tail -1)

telegram_notify  "PFSense initialization script beginning... \n\nCloud DMZ IP: $IP_DATA"
####  initial actions

install_pkg "pfsense-pkg-squid"
install_pkg "pfsense-pkg-haproxy-devel"

## DO NOT USE $() notation below!!!   IT WILL NOT WORK ON PFSENSE!!
# shellcheck disable=SC2006
DRIVE_KB=`geom disk list | grep Mediasize | sed 2d | awk '{ print $2 }'`
DRIVE_SIZE=$(($DRIVE_KB / 1024 / 1024 * 75/100))
echo "Setting cache size to $DRIVE_SIZE"

## the pfsense method for changing config via cli is f*ed up:
##  change all backup files, delete primary file, and let system "restore" a changed backup file
##  makes a lot of sense, huh?
files="/cf/conf/backup/*"
for file in $files; do
  echo "Changing contents of file $file"
  perl -pi.back -e "s/{CACHE_SIZE}/$DRIVE_SIZE/g;" "$file"
done

rm -rf /cf/conf/config.xml
rm -rf /root/pfsense-init.sh

####  building second init script
cat <<EOF >/usr/local/etc/rc.d/pfsense-init-2.sh
#!/bin/sh

exec 1>/root/init2-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

## this script will run on pfsense reboot and then remove itself
## this script is run on a FreeBSD system, not centos, not bash.  Makes some things slightly different

. /root/project_config.sh
. /root/pf_functions.sh

telegram_notify  "PFSense init: Second init script running"

## kickoff cloud build
ssh root@$LAN_CENTOS_IP 'cd /tmp; ./create-identity-kvm-deploy.sh;' &

### install remaining packages here
install_pkg "pfsense-pkg-openvpn-client-export"
install_pkg "pfsense-pkg-pfBlockerNG-devel"
install_pkg "pfsense-pkg-snort"
install_pkg "pfsense-pkg-cron"
install_pkg "pfsense-pkg-Telegraf"

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

telegram_notify  "PFSense init: init complete! removing script and rebooting.."
reboot