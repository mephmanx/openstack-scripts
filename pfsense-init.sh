#!/bin/sh
## this script will run on pfsense reboot and then remove itself
## this script is run on a FreeBSD system, not centos, not bash.  Makes some things slightly different

. /root/project_config.sh
. /root/pf_functions.sh

exec 1>/root/init-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x                             # tell sh to display commands before execution

IP_DATA=$(ifconfig vtnet0 | grep inet | awk -F' ' '{ print $2 }' | head -2 | tail -1)
telegram_notify  "PFSense initialization script beginning... \n\nCloud DMZ IP: $IP_DATA"
####  initial actions
install_pkg "pfsense-pkg-squid"
install_pkg "pfsense-pkg-haproxy-devel"
install_pkg "pfsense-pkg-openvpn-client-export"
install_pkg "pfsense-pkg-pfBlockerNG-devel"
install_pkg "pfsense-pkg-snort"
install_pkg "pfsense-pkg-cron"
install_pkg "pfsense-pkg-Telegraf"
install_pkg "qemu-guest-agent"

rm -rf /root/pfsense-init.sh
telegram_notify  "PFSense init: init complete!"