#!/bin/sh
## this script will run on pfsense reboot and then remove itself
## this script is run on a FreeBSD system, not centos, not bash.  Makes some things slightly different

. /root/openstack-scripts/project_config.sh
. /root/openstack-env.sh
. /root/openstack-scripts/pf_functions.sh

exec 1>/root/init-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense initialization script beginning..."

### perform downloads first so that VM installs can continue
mkdir /usr/local/www/isos

if [ ! -f "/usr/local/www/isos/linux.iso" ]; then
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: downloading linux image"
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

. /root/openstack-scripts/project_config.sh
. /root/openstack-env.sh
. /root/openstack-scripts/pf_functions.sh

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: Second init script running"

## kickoff cloud build
ssh root@$LAN_CENTOS_IP 'cd /tmp/openstack-scripts; ./create-cloudsupport-kvm.sh;' &
ssh root@$LAN_CENTOS_IP 'cd /tmp/openstack-scripts; ./create-cloud-kvm.sh;' &

### install remaining packages here
install_pkg "pfsense-pkg-openvpn-client-export" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-bandwidthd" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-Lightsquid" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-pfBlockerNG-devel" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-snort" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-cron" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-Telegraf" $TELEGRAM_API $TELEGRAM_CHAT_ID

## perform any cleanup here
rm -rf /root/openstack-scripts
####

### remove from starting on boot
rm -rf /usr/local/etc/rc.d/pfsense-init-2.sh

EOF

chmod a+rx /usr/local/etc/rc.d/pfsense-init-2.sh
#########

## additional packages
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: Installing packages..."

install_pkg "pfsense-pkg-acme" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-squid" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-haproxy-devel" $TELEGRAM_API $TELEGRAM_CHAT_ID

if [ $UPS_PRESENT == 1 ]; then
  install_pkg "pfsense-pkg-nut" $TELEGRAM_API $TELEGRAM_CHAT_ID
fi

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: additional packages installed...  Pulling repos.."
#####################
### perform ACME init
cur_dir=`pwd`
cd /usr/local/pkg/acme
### if cert exists, skip...
if [ ! -d "/tmp/acme/$DOMAIN_NAME-external-wildcard" ]; then
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Registering account for $DOMAIN_NAME with LetsEncrypt"
  ./acme.sh --register-account
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Requesting cert issue for *.$DOMAIN_NAME with LetsEncrypt"
  ./acme_command.sh -- -perform=issue -certname=$DOMAIN_NAME-external-wildcard -force
  ## analyze logs to pull actualy result
  results=`grep -C 10 "status" /root/init-install.log`
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "LetsEncrypt results: $results"
else
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "LetsEncrypt cert already exists, skipping issue request..."
fi
####
rm -rf /root/openstack-scripts/pfsense-init.sh

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: init complete! removing script and rebooting.."
reboot