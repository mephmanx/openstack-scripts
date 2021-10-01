#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/openstack-scripts/vm_functions.sh
. /tmp/openstack-env.sh
. /tmp/project_config.sh

start() {

######## Openstack main server install

exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

yum clean all && yum update -y  #this is only to make the next call work, DONT remove!

systemctl stop firewalld
systemctl disable firewalld
systemctl mask firewalld

## Send System info
load_system_info
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Openstack Cloud System: $SYSTEM_INFO"
#### Notify admin pwd in debug mode
if [[ $HYPERVISOR_DEBUG == 1 ]]; then
  root_pw=`cat /home/admin/rootpw`
  telegram_debug_msg $TELEGRAM_API $TELEGRAM_CHAT_ID "Hypervisor root pw: $root_pw"
else
  HOWLONG=15 ## the number of characters
  root_pw=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
fi

ADMIN_PWD=`cat /root/env_admin_pwd`
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Hypervisor admin account pw: $ADMIN_PWD"
######

## generate OpenVPN TLS secret key
runuser -l root -c  'openvpn --genkey --secret /root/.ssh/openvpn-secret.key'

################# setup KVM and kick off openstack cloud create
dnf module install -y virt
dnf install -y cockpit-machines virt-install virt-viewer bridge-utils swtpm libtpms telnet
systemctl restart libvirtd
############################

### system profile
tuned-adm profile virtual-host
#############

########## configure and start networks
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Configuring networks on hypervisor...."
#### private net 1
ip link add dev vm1 type veth peer name vm2
ip link set dev vm1 up
ip tuntap add tapm mode tap
ip link set dev tapm up
ip link add loc-static type bridge

ip link set tapm master loc-static
ip link set vm1 master loc-static

ip addr add ${LAN_CENTOS_IP}/24 dev loc-static
ip addr add ${LAN_BRIDGE_IP}/24 dev vm2

ip link set loc-static up
ip link set vm2 up

nmcli connection modify loc-static ipv4.addresses ${LAN_CENTOS_IP}/24 ipv4.method manual connection.autoconnect yes ipv6.method "disabled"

### amp-net
ip link add dev vm3 type veth peer name vm4
ip link set dev vm3 up
ip tuntap add tapm1 mode tap
ip link set dev tapm1 up
ip link add amp-net type bridge

ip link set tapm1 master amp-net
ip link set vm3 master amp-net

ip addr add  10.1.0.1/24 dev amp-net
ip addr add  10.1.0.2/24 dev vm4

ip link set amp-net up
ip link set vm4 up

nmcli connection modify amp-net ipv4.addresses 10.1.0.1/24 ipv4.method manual connection.autoconnect yes ipv6.method "disabled"

## build vif devices and pair them for the bridge, 10 for each network created above
node_ct=20
while [ $node_ct -gt 0 ]; do
  ip link add dev Node${node_ct}s type veth peer name Node${node_ct}
  ((node_ct--))
done

node_ct=20
while [ $node_ct -gt 0 ]; do
  ip link set Node${node_ct} up
  ((node_ct--))
done

node_ct=20
while [ $node_ct -gt 0 ]; do
  ip link set Node${node_ct}s up
  ((node_ct--))
done

node_ct=10
while [ $node_ct -gt 0 ]; do
  brctl addif loc-static Node${node_ct}s
  ((node_ct--))
done

node_ct=10
while [ $node_ct -gt 0 ]; do
  brctl addif amp-net Node${node_ct}s
  ((node_ct--))
done
#############

virsh net-undefine default
###########################

#### vtpm
vtpm
######

############ Create and init storage pools
PART_LIST=`df | grep "VM-VOL" | awk '{print $6}' | tr -d '/'`
for part in "${PART_LIST[@]}"; do
  virsh pool-define-as $part dir - - - - "/$part"
  virsh pool-build $part
  virsh pool-autostart $part
  virsh pool-start $part
done
############################

### start image hosting
pwd=`pwd`
mkdir /tmp/iso
cp /tmp/linux.iso /tmp/iso
cd /tmp/iso
python3 -m http.server &
cd $pwd

########## build router
telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Fetching PFSense image....."
### make sure to get offset of fat32 partition to put config.xml file on stick to reload!
gunzip /tmp/pfSense-CE-memstick-ADI.img.gz

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
SUPPORT_VIP_DNS="$SUPPORT_HOST.$DOMAIN_NAME"
INTERNAL_VIP_DNS="$APP_INTERNAL_HOSTNAME.$DOMAIN_NAME"
EXTERNAL_VIP_DNS="$APP_EXTERNAL_HOSTNAME.$DOMAIN_NAME"
###################

### replace variables
## load generated cert variables
LETS_ENCRYPT_ACCOUNT_KEY=`cat /root/.ssh/id_rsa.key | base64 | tr -d '\n\r'`

CA_KEY=`cat /root/.ssh/id_rsa.key | base64 | tr -d '\n\r'`
CA_CRT=`cat /root/.ssh/id_rsa.crt | base64 | tr -d '\n\r'`

VPN_CRT=`cat /root/.ssh/cloud-vpn.crt | base64 | tr -d '\n\r'`
VPN_KEY=`cat /root/.ssh/cloud-vpn.key | base64 | tr -d '\n\r'`

OSUSER_CRT=`cat /root/.ssh/osuser.crt | base64 | tr -d '\n\r'`
OSUSER_KEY=`cat /root/.ssh/osuser.key | base64 | tr -d '\n\r'`

INITIAL_WILDCARD_CRT=`cat /root/.ssh/placeholder.crt | base64 | tr -d '\n\r'`
INITIAL_WILDCARD_KEY=`cat /root/.ssh/placeholder.key | base64 | tr -d '\n\r'`

OPEN_VPN_TLS_KEY=`cat /root/.ssh/openvpn-secret.key | base64 | tr -d '\n\r'`
#########

### godaddy dyndns key
GODADDY_KEY_BASE64=`echo -n $GODADDY_KEY | base64 | tr -d '\n\r'`

### cloudfoundry TCP ports
CF_TCP_START_PORT=1024
CF_TCP_END_PORT=$(($CF_TCP_START_PORT + $CF_TCP_PORT_COUNT))

##### replace PFSense template vars
sed -i 's/{CF_TCP_START_PORT}/'$CF_TCP_START_PORT'/g' /tmp/usb/config.xml
sed -i 's/{CF_TCP_END_PORT}/'$CF_TCP_END_PORT'/g' /tmp/usb/config.xml
sed -i 's/{INTERNAL_VIP}/'$INTERNAL_VIP'/g' /tmp/usb/config.xml
sed -i 's/{EXTERNAL_VIP}/'$EXTERNAL_VIP'/g' /tmp/usb/config.xml
sed -i 's/{LAN_CENTOS_IP}/'$LAN_CENTOS_IP'/g' /tmp/usb/config.xml
sed -i 's/{GATEWAY_ROUTER_IP}/'$GATEWAY_ROUTER_IP'/g' /tmp/usb/config.xml
sed -i 's/{GATEWAY_ROUTER_DHCP_START}/'$GATEWAY_ROUTER_DHCP_START'/g' /tmp/usb/config.xml
sed -i 's/{GATEWAY_ROUTER_DHCP_END}/'$GATEWAY_ROUTER_DHCP_END'/g' /tmp/usb/config.xml
sed -i 's/{DOMAIN_NAME}/'$DOMAIN_NAME'/g' /tmp/usb/config.xml
sed -i 's/{EXTERNAL_VIP_DNS}/'$EXTERNAL_VIP_DNS'/g' /tmp/usb/config.xml
sed -i 's/{INTERNAL_VIP_DNS}/'$INTERNAL_VIP_DNS'/g' /tmp/usb/config.xml
sed -i 's/{OPENSTACK_ADMIN_PWD}/'$ADMIN_PWD'/g' /tmp/usb/config.xml
sed -i 's/{TIMEZONE}/'$TIMEZONE'/g' /tmp/usb/config.xml
sed -i 's/{APP_INTERNAL_HOSTNAME}/'$APP_INTERNAL_HOSTNAME'/g' /tmp/usb/config.xml
sed -i 's/{APP_EXTERNAL_HOSTNAME}/'$APP_EXTERNAL_HOSTNAME'/g' /tmp/usb/config.xml
sed -i 's/{NETWORK_PREFIX}/'$NETWORK_PREFIX'/g' /tmp/usb/config.xml
sed -i 's/{OPENVPN_CERT_PWD}/'$ADMIN_PWD'/g' /tmp/usb/config.xml
sed -i 's/{GODADDY_ACCOUNT}/'$GODADDY_ACCOUNT'/g' /tmp/usb/config.xml
sed -i 's/{GODADDY_KEY}/'$GODADDY_KEY'/g' /tmp/usb/config.xml
sed -i 's/{GODADDY_KEY_BASE64}/'$GODADDY_KEY_BASE64'/g' /tmp/usb/config.xml
sed -i 's/{SMTP_ACCOUNT}/'$SMTP_ACCOUNT'/g' /tmp/usb/config.xml
sed -i 's/{SMTP_KEY}/'$SMTP_KEY'/g' /tmp/usb/config.xml
sed -i 's/{SMTP_ADDRESS}/'$SMTP_ADDRESS'/g' /tmp/usb/config.xml
sed -i 's/{TELEGRAM_API}/'$TELEGRAM_API'/g' /tmp/usb/config.xml
sed -i 's/{TELEGRAM_CHAT_ID}/'$TELEGRAM_CHAT_ID'/g' /tmp/usb/config.xml
sed -i 's/{OINKMASTER}/'$OINKMASTER'/g' /tmp/usb/config.xml
sed -i 's/{MAXMIND_KEY}/'$MAXMIND_KEY'/g' /tmp/usb/config.xml
sed -i 's/{LETSENCRYPT_KEY}/'$LETS_ENCRYPT_ACCOUNT_KEY'/g' /tmp/usb/config.xml
sed -i 's/{CA_CRT}/'$CA_CRT'/g' /tmp/usb/config.xml
sed -i 's/{CA_KEY}/'$CA_KEY'/g' /tmp/usb/config.xml
sed -i 's/{VPN_CRT}/'$VPN_CRT'/g' /tmp/usb/config.xml
sed -i 's/{VPN_KEY}/'$VPN_KEY'/g' /tmp/usb/config.xml
sed -i 's/{OSUSER_CRT}/'$OSUSER_CRT'/g' /tmp/usb/config.xml
sed -i 's/{OSUSER_KEY}/'$OSUSER_KEY'/g' /tmp/usb/config.xml
sed -i 's/{INITIAL_WILDCARD_CRT}/'$INITIAL_WILDCARD_CRT'/g' /tmp/usb/config.xml
sed -i 's/{INITIAL_WILDCARD_KEY}/'$INITIAL_WILDCARD_KEY'/g' /tmp/usb/config.xml
sed -i 's/{OPEN_VPN_TLS_KEY}/'$OPEN_VPN_TLS_KEY'/g' /tmp/usb/config.xml
sed -i 's/{ADMIN_EMAIL}/'$ADMIN_EMAIL'/g' /tmp/usb/config.xml
sed -i 's/{CLOUDFOUNDRY_VIP}/'$CLOUDFOUNDRY_VIP'/g' /tmp/usb/config.xml
sed -i 's/{SUPPORT_VIP}/'$SUPPORT_VIP'/g' /tmp/usb/config.xml
#######

runuser -l root -c  'umount /tmp/usb'

create_line="virt-install "
create_line+="--hvm "
create_line+="--virt-type=kvm "
create_line+="--name=pfsense "
create_line+="--memory=8192 "
create_line+="--cpu=host-passthrough,cache.mode=passthrough "
create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
create_line+="--memorybacking hugepages=yes "
create_line+="--vcpus=8 "
create_line+="--boot hd,menu=off,useserial=off "
create_line+="--disk /tmp/pfSense-CE-memstick-ADI.img "
create_line+="--disk pool=$(getDiskMapping "misc" "1"),size=25,bus=virtio,sparse=no "
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

## attach USB UPS to pfsense for monitoring
if [[ $UPS_PRESENT == 1 ]]; then
  #### prepare usb ups device
  # gather vendor and product id from lsusb if ups changes
  ### maybe somehow detect?

cat > /tmp/ups.xml <<EOF
<hostdev mode='subsystem' type='usb' managed='yes'>
  <source>
    <vendor id='0x$VENDOR_ID'/>
    <product id='0x$PRODUCT_ID'/>
  </source>
</hostdev>
EOF

  virsh attach-device pfsense /tmp/ups.xml --persistent
fi
#####

### cleanup
rm -rf /tmp/pfSense-CE-memstick-ADI.img
runuser -l root -c  "rm -rf /tmp/usb"
#####

HOWLONG=5 ## the number of characters
UNIQUE_SUFFIX_PF=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});

#### store suffix for future use
cat > /tmp/pf_suffix <<EOF
$UNIQUE_SUFFIX_PF
EOF

ssh-keygen -t rsa -b 4096 -C "pfsense" -N "" -f /tmp/pf_key-${UNIQUE_SUFFIX_PF}.key <<<y 2>&1 >/dev/null

HYPERVISOR_KEY=`cat /tmp/pf_key-${UNIQUE_SUFFIX_PF}.key | base64 | tr -d '\n\r'`
HYPERVISOR_PUB_KEY=`cat /tmp/pf_key-${UNIQUE_SUFFIX_PF}.key.pub | base64 | tr -d '\n\r'`
OPENSTACK_SETUP_FILE=`cat /tmp/openstack-env.sh | base64 | tr -d '\n\r'`
OPENSTACK_SETUP_REPO=`cat /tmp/repo.zip | base64 | tr -d '\n\r'`

runuser -l root -c "cat /tmp/pf_key-${UNIQUE_SUFFIX_PF}.key.pub >> /root/.ssh/authorized_keys"

### pfsense prep
hypervisor_key_array=( $(echo $HYPERVISOR_KEY | fold -c250 ))
hypervisor_pub_array=( $(echo $HYPERVISOR_PUB_KEY | fold -c250 ))
openstack_env_file=( $(echo $OPENSTACK_SETUP_FILE | fold -c250 ))
openstack_repo_file=( $(echo $OPENSTACK_SETUP_REPO | fold -c250 ))
(echo open 127.0.0.1 4568;
  sleep 30;
  echo "8";
  sleep 60;
  echo "pfSsh.php playback changepassword admin";
  sleep 10;
  echo "$root_pw";
  sleep 10;
  echo "$root_pw";
  sleep 10;
  echo "pfSsh.php playback changepassword osuser";
  sleep 10;
  echo "$ADMIN_PWD";
  sleep 10;
  echo "$ADMIN_PWD";
  sleep 10;
  echo "yes | pkg install git &";
  sleep 90;
  echo "yes | pkg install bash &";
  sleep 90;
  echo "yes | pkg install pfsense-pkg-Shellcmd &";
  sleep 90;
  echo "mkdir /root/.ssh";
  sleep 20;
  echo "touch /root/.ssh/id_rsa; touch /root/.ssh/id_rsa.pub; touch /root/.ssh/id_rsa.pub.enc; touch /root/.ssh/id_rsa.enc; touch /root/openstack-env.sh.enc;";
  sleep 30;
  for element in "${hypervisor_pub_array[@]}"
  do
    echo "echo '$element' >> /root/.ssh/id_rsa.pub.enc";
    sleep 10;
  done
  for element in "${hypervisor_key_array[@]}"
  do
    echo "echo '$element' >> /root/.ssh/id_rsa.enc";
    sleep 10;
  done
  echo "openssl base64 -d -in /root/.ssh/id_rsa.pub.enc -out /root/.ssh/id_rsa.pub;";
  sleep 30;
  echo "openssl base64 -d -in /root/.ssh/id_rsa.enc -out /root/.ssh/id_rsa;";
  sleep 30;
  for element in "${openstack_env_file[@]}"
  do
    echo "echo '$element' >> /root/openstack-env.sh.enc";
    sleep 10;
  done
  echo "openssl base64 -d -in /root/openstack-env.sh.enc -out /root/openstack-env.sh";
  sleep 30;
  echo "chmod 600 /root/.ssh/*";
  sleep 30;
  echo "ssh-keyscan -H $LAN_CENTOS_IP >> ~/.ssh/known_hosts;";
  sleep 30;
  for element in "${openstack_repo_file[@]}"
  do
    echo "echo '$element' >> /tmp/repo.zip.enc";
    sleep 10;
  done
  echo "openssl base64 -d -in /tmp/repo.zip.enc -out /tmp/repo.zip";
  sleep 30;
  echo "unzip /tmp/repo.zip -d /root/openstack-scripts";
  sleep 90;
) | telnet

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID \
        "PFSense rebooting after package install, \
          pfsense-init script should begin after reboot. Remember to configure wildcard DNS properly on DNS provider site! \
           \n For eaxmple, a CNAME record with Host: * and Value: @ on GoDaddy."

virsh reboot pfsense

## cleanup key
rm -rf /tmp/pf_key*

#remove so as to not run again
rm -rf /etc/rc.d/rc.local

restrict_to_root

}

stop() {
    # code to stop app comes here
    # example: killproc program_name
    /bin/true
}

case "$1" in
    start)
       start
       ;;
    stop)
        /bin/true
       stop
       ;;
    restart)
       stop
       start
       ;;
    status)
        /bin/true
       # code to check status of app comes here
       # example: status program_name
       ;;
    *)
       echo "Usage: $0 {start|stop|status|restart}"
esac

exit 0
