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
  curl -o /usr/local/www/isos/linux.iso $LINUX_ISO -s
fi

if [ ! -f "/usr/local/www/isos/livecd.iso" ]; then
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: downloading livecd debug image"
  rm -rf /usr/local/www/isos/livecd.iso
  curl -o /usr/local/www/isos/livecd.iso $DEBUG_VM_IMAGE -s -L
fi

if [ ! -f "/usr/local/www/isos/magnum.qcow2" ]; then
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: downloading magnum image"
  rm -rf /usr/local/www/isos/magnum.qcow2
  curl -o /usr/local/www/isos/magnum.qcow2 $MAGNUM_IMAGE -s -L
fi
################

## preparing next reboot
## build next reboot script to start cloud build.  overwrite contents of this file so it is executed on next reboot
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: Building second init script to kick off cloud build."

cat <<EOF >/root/pfsense-init.sh
#!/bin/sh

exec 1>/root/init2-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

## this script will run on pfsense reboot and then remove itself
## this script is run on a FreeBSD system, not centos, not bash.  Makes some things slightly different

. /root/openstack-scripts/project_config.sh
. /root/openstack-env.sh
. /root/openstack-scripts/pf_functions.sh

if [ $PFSENSE_REBOOT_REBUILD == 1 ]; then
  ssh root@$LAN_CENTOS_IP 'cd /tmp/openstack-scripts; ./create-cloudsupport-kvm.sh;' &
  ssh root@$LAN_CENTOS_IP 'cd /tmp/openstack-scripts; ./create-cloud-kvm.sh;' &
fi

install_pkg "pfsense-pkg-openvpn-client-export" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-bandwidthd" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-Lightsquid" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-pfBlockerNG-devel" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-snort" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-cron" $TELEGRAM_API $TELEGRAM_CHAT_ID
install_pkg "pfsense-pkg-Telegraf" $TELEGRAM_API $TELEGRAM_CHAT_ID

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
  results=`cat -l 20 /tmp/init-install.log`
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "LetsEncrypt results: $results"
else
  telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "LetsEncrypt cert already exists, skipping issue request..."
fi
####

## perform any cleanup here
rm -rf /root/openstack-scripts
####

rm -rf /root/pfsense-init.sh

EOF
chmod +x /root/pfsense-init.sh
#########

sed -i 's/\/root\/openstack-scripts\/pfsense-init.sh/\/root\/pfsense-init.sh/g' /conf/config.xml

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

## remove once template is complete and verified.
rm -rf /root/pfsense-scripts
rm -rf /root/pfsense-backup

git clone https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/pfsense-scripts.git /root/pfsense-scripts
git clone https://$GITHUB_USER:$GITHUB_TOKEN@github.com/$GITHUB_USER/pfsense-backup.git /root/pfsense-backup
###

rm -rf /root/openstack-scripts/pfsense-init.sh

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense init: init complete! removing script and rebooting.."
reboot