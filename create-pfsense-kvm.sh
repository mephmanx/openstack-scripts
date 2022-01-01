#!/bin/bash

rm -rf /tmp/pfsense-install.log
exec 1>/root/pfsense-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x

source /tmp/openstack-scripts/iso-functions.sh
source /tmp/openstack-scripts/vm_functions.sh
source /tmp/openstack-env.sh
source /tmp/project_config.sh

KICKSTART_DIR=/tmp/openstack-scripts

### if pfsense" images exists, skip this file
removeVM_kvm "pfsense"
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Building PFSense VM"

########## build router
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Fetching PFSense image....."
### make sure to get offset of fat32 partition to put config.xml file on stick to reload!

## watch this logic on update and make sure it gets the last fat32 partition
startsector=$(file /tmp/pfSense-CE-memstick-ADI.img | sed -n -e 's/.* startsector *\([0-9]*\),.*/\1/p')
offset=$(expr $startsector '*' 512)

rm -rf /tmp/usb
mkdir /tmp/usb
runuser -l root -c  "mount -o loop,offset=$offset /tmp/pfSense-CE-memstick-ADI.img /tmp/usb"
rm -rf /tmp/usb/config.xml
cp /tmp/openstack-scripts/openstack-pfsense.xml /tmp/usb
mv /tmp/usb/openstack-pfsense.xml /tmp/usb/config.xml

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Preparing PFSense configuration...."
#####  setup global VIPs
SUPPORT_VIP_DNS="$SUPPORT_HOST.$INTERNAL_DOMAIN_NAME"
INTERNAL_VIP_DNS="$APP_INTERNAL_HOSTNAME.$INTERNAL_DOMAIN_NAME"
EXTERNAL_VIP_DNS="$APP_EXTERNAL_HOSTNAME.$INTERNAL_DOMAIN_NAME"
###################

### copy pfsense files to folder for host
rm -rf /tmp/pftransfer/*.sh
cp -nf /tmp/openstack-env.sh /tmp/pftransfer
cp -nf /tmp/openstack-scripts/pf_functions.sh /tmp/pftransfer
cp -nf /tmp/project_config.sh /tmp/pftransfer
cp -nf /tmp/openstack-scripts/pfsense-init.sh /tmp/pftransfer
##################

## generate OpenVPN TLS secret key
runuser -l root -c  'openvpn --genkey --secret /root/.ssh/openvpn-secret.key'

### replace variables
## load generated cert variables
CA_KEY=`cat /root/.ssh/id_rsa.key | base64 | tr -d '\n\r'`
CA_CRT=`cat /root/.ssh/id_rsa.crt | base64 | tr -d '\n\r'`

INITIAL_WILDCARD_CRT=`cat /root/.ssh/wildcard.crt | base64 | tr -d '\n\r'`
INITIAL_WILDCARD_KEY=`cat /root/.ssh/wildcard.key | base64 | tr -d '\n\r'`

OPEN_VPN_TLS_KEY=`cat /root/.ssh/openvpn-secret.key | base64 | tr -d '\n\r'`
#########

### cloudfoundry TCP ports
CF_TCP_START_PORT=1024
CF_TCP_END_PORT=$(($CF_TCP_START_PORT + $CF_TCP_PORT_COUNT))

DISK_COUNT=`lshw -json -class disk | grep -o -i disk: | wc -l`
if [[ $DISK_COUNT -lt 2 ]]; then
  size_avail=`df /VM-VOL-ALL | awk '{print $2}' | sed 1d`
  DRIVE_SIZE=$(($((size_avail * 5/100)) / 1024 / 1024))
else
  size_avail=`df /VM-VOL-MISC | awk '{print $2}' | sed 1d`
  DRIVE_SIZE=$(($((size_avail * 20/100)) / 1024 / 1024))
fi

DIRECTORY_MGR_PWD=$(generate_random_pwd 31)
echo "$DIRECTORY_MGR_PWD" >> /root/directory_mgr_pwd
ADMIN_PWD=`cat /root/env_admin_pwd`

#### backend to change host header from whatever it comes in as to internal domain
ADVANCED_BACKEND=`echo "http-request replace-value Host ^(.*)(\.[^\.]+){2}$ \1.$INTERNAL_DOMAIN_NAME" | base64 | tr -d '\n\r'`

## generate random hostname suffix so that if multiple instances are run on the same network there are no issues
HOWLONG=5 ## the number of characters
HOSTNAME_SUFFIX=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
HOSTNAME="$APP_EXTERNAL_HOSTNAME-$HOSTNAME_SUFFIX"
###
TZ=`timedatectl | awk '/Time zone:/ {print $3}'`
TIMEZONE=`echo $TZ | sed 's/\//\\\\\//g'`
##### replace PFSense template vars
sed -i 's/{HOSTNAME}/'$HOSTNAME'/g' /tmp/usb/config.xml
sed -i 's/{CF_TCP_START_PORT}/'$CF_TCP_START_PORT'/g' /tmp/usb/config.xml
sed -i 's/{CF_TCP_END_PORT}/'$CF_TCP_END_PORT'/g' /tmp/usb/config.xml
sed -i 's/{INTERNAL_VIP}/'$INTERNAL_VIP'/g' /tmp/usb/config.xml
sed -i 's/{EXTERNAL_VIP}/'$EXTERNAL_VIP'/g' /tmp/usb/config.xml
sed -i 's/{LAN_CENTOS_IP}/'$LAN_CENTOS_IP'/g' /tmp/usb/config.xml
sed -i 's/{GATEWAY_ROUTER_IP}/'$GATEWAY_ROUTER_IP'/g' /tmp/usb/config.xml
sed -i 's/{GATEWAY_ROUTER_DHCP_START}/'$GATEWAY_ROUTER_DHCP_START'/g' /tmp/usb/config.xml
sed -i 's/{GATEWAY_ROUTER_DHCP_END}/'$GATEWAY_ROUTER_DHCP_END'/g' /tmp/usb/config.xml
sed -i 's/{INTERNAL_DOMAIN_NAME}/'$INTERNAL_DOMAIN_NAME'/g' /tmp/usb/config.xml
sed -i 's/{EXTERNAL_VIP_DNS}/'$EXTERNAL_VIP_DNS'/g' /tmp/usb/config.xml
sed -i 's/{INTERNAL_VIP_DNS}/'$INTERNAL_VIP_DNS'/g' /tmp/usb/config.xml
sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' /tmp/usb/config.xml
sed -i 's/{APP_INTERNAL_HOSTNAME}/'$APP_INTERNAL_HOSTNAME'/g' /tmp/usb/config.xml
sed -i 's/{APP_EXTERNAL_HOSTNAME}/'$APP_EXTERNAL_HOSTNAME'/g' /tmp/usb/config.xml
sed -i 's/{NETWORK_PREFIX}/'$NETWORK_PREFIX'/g' /tmp/usb/config.xml
sed -i 's/{OPENVPN_CERT_PWD}/'$ADMIN_PWD'/g' /tmp/usb/config.xml
sed -i 's/{TELEGRAM_API}/'$TELEGRAM_API'/g' /tmp/usb/config.xml
sed -i 's/{TELEGRAM_CHAT_ID}/'$TELEGRAM_CHAT_ID'/g' /tmp/usb/config.xml
sed -i 's/{OINKMASTER}/'$OINKMASTER'/g' /tmp/usb/config.xml
sed -i 's/{MAXMIND_KEY}/'$MAXMIND_KEY'/g' /tmp/usb/config.xml
sed -i 's/{LETSENCRYPT_KEY}/'$LETS_ENCRYPT_ACCOUNT_KEY'/g' /tmp/usb/config.xml
sed -i 's/{CA_CRT}/'$CA_CRT'/g' /tmp/usb/config.xml
sed -i 's/{CA_KEY}/'$CA_KEY'/g' /tmp/usb/config.xml
sed -i 's/{INITIAL_WILDCARD_CRT}/'$INITIAL_WILDCARD_CRT'/g' /tmp/usb/config.xml
sed -i 's/{INITIAL_WILDCARD_KEY}/'$INITIAL_WILDCARD_KEY'/g' /tmp/usb/config.xml
sed -i 's/{OPEN_VPN_TLS_KEY}/'$OPEN_VPN_TLS_KEY'/g' /tmp/usb/config.xml
sed -i 's/{CLOUDFOUNDRY_VIP}/'$CLOUDFOUNDRY_VIP'/g' /tmp/usb/config.xml
sed -i 's/{IDENTITY_VIP}/'$IDENTITY_VIP'/g' /tmp/usb/config.xml
sed -i 's/{SUPPORT_VIP}/'$SUPPORT_VIP'/g' /tmp/usb/config.xml
sed -i 's/{DIRECTORY_MGR_PWD_12345678901}/'$DIRECTORY_MGR_PWD'/g' /tmp/usb/config.xml
sed -i 's/{BASE_DN}/'$(baseDN)'/g' /tmp/usb/config.xml
sed -i 's/{LB_ROUTER_IP}/'$LB_ROUTER_IP'/g' /tmp/usb/config.xml
sed -i 's/{LB_DHCP_START}/'$LB_DHCP_START'/g' /tmp/usb/config.xml
sed -i 's/{LB_DHCP_END}/'$LB_DHCP_END'/g' /tmp/usb/config.xml
sed -i 's/{ADVANCED_BACKEND}/'$ADVANCED_BACKEND'/g' /tmp/usb/config.xml
sed -i 's/{VPN_NETWORK}/'$VPN_NETWORK'/g' /tmp/usb/config.xml
#######

runuser -l root -c  'umount /tmp/usb'

create_line="virt-install "
create_line+="--hvm "
create_line+="--virt-type=kvm "
create_line+="--name=pfsense "
create_line+="--memory=${PFSENSE_RAM}000 "
create_line+="--cpu=host-passthrough,cache.mode=passthrough "
create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
create_line+="--memorybacking hugepages=yes "
create_line+="--vcpus=8 "
create_line+="--boot hd,menu=off,useserial=off "
create_line+="--disk /tmp/pfSense-CE-memstick-ADI.img "
create_line+="--disk pool=$(getDiskMapping "misc" "1"),size=$DRIVE_SIZE,bus=virtio,sparse=no "
create_line+="--connect qemu:///system "
create_line+="--os-type=freebsd "
create_line+="--serial tcp,host=0.0.0.0:4567,mode=bind,protocol=telnet "
create_line+="--serial tcp,host=0.0.0.0:4568,mode=bind,protocol=telnet "
create_line+="--network type=direct,source=ext-con,model=virtio,source_mode=bridge "
create_line+="--network type=bridge,source=loc-static,model=virtio "
create_line+="--network type=bridge,source=amp-net,model=virtio "
create_line+="--os-variant=freebsd11.0 "
create_line+="--graphics=vnc "
create_line+="--autostart"

echo $create_line
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense install beginning...."
eval $create_line &

sleep 30;

(echo open 127.0.0.1 4568;
  sleep 60;
  echo "ansi";
  sleep 5;
  echo 'A'
  sleep 5;
  echo -ne '\r\n';
  sleep 5;
  echo -ne '\r\n';
  sleep 5;
  echo -ne '\r\n';
  sleep 5;
  echo -ne '\r\n';
  sleep 5;
  echo -ne '\r\n';
  sleep 5;
  echo 'v';
  echo ' ';
  echo -ne '\r\n';
  sleep 5;
  echo 'Y'
  sleep 160;
  echo 'N';
  sleep 5;
) | telnet

## remove install disk from pfsense
virsh detach-disk --domain pfsense /tmp/pfSense-CE-memstick-ADI.img --persistent --config --live
virsh reboot pfsense

sleep 120;
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense first reboot in progress, continuing to package install...."

### cleanup
runuser -l root -c  "rm -rf /tmp/usb"
#####

root_pw=$(generate_random_pwd 31)

telegram_debug_msg $TELEGRAM_API $TELEGRAM_CHAT_ID "PFSense admin pwd is $root_pw"

(echo open 127.0.0.1 4568;
  sleep 120;
  echo "pfSsh.php playback changepassword admin";
  sleep 10;
  echo "$root_pw";
  sleep 10;
  echo "$root_pw";
  sleep 10;
  echo "yes | pkg install git &";
  sleep 120;
  echo "yes | pkg install bash &";
  sleep 120;
  echo "yes | pkg install pfsense-pkg-Shellcmd &";
  sleep 120;
  echo "mkdir /root/.ssh";
  sleep 20;
  echo "curl -o /root/.ssh/id_rsa.pub http://$LAN_CENTOS_IP:8000/pf_key.pub > /dev/null";
  sleep 30;
  echo "curl -o /root/.ssh/id_rsa http://$LAN_CENTOS_IP:8000/pf_key > /dev/null";
  sleep 30;
  echo "chmod 600 /root/.ssh/*";
  sleep 10;
  echo "ssh-keyscan -H $LAN_CENTOS_IP >> ~/.ssh/known_hosts;";
  sleep 30;
  echo "mkdir /root/openstack-scripts";
  sleep 10;
  echo "curl -o /root/openstack-env.sh http://$LAN_CENTOS_IP:8000/openstack-env.sh > /dev/null";
  sleep 30;
  echo "curl -o /root/openstack-scripts/pf_functions.sh http://$LAN_CENTOS_IP:8000/pf_functions.sh > /dev/null";
  sleep 30;
  echo "curl -o /root/project_config.sh http://$LAN_CENTOS_IP:8000/project_config.sh > /dev/null";
  sleep 30;
  echo "curl -o /root/openstack-scripts/pfsense-init.sh http://$LAN_CENTOS_IP:8000/pfsense-init.sh > /dev/null";
  sleep 30;
  echo "chmod 777 /root/openstack-scripts/*.sh"
  sleep 10;
  echo "chmod 777 /root/*.sh"
  sleep 10;
) | telnet

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID \
        "PFSense rebooting after package install, pfsense-init script should begin after reboot."

virsh reboot pfsense

