#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/project_config.sh

start() {

######## Openstack main server install

exec 1>/var/log/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

################# setup KVM and kick off openstack cloud create
systemctl restart libvirtd
############################

### disable once syslogs are being sent
systemctl enable --now cockpit.socket
####

########## configure and start networks
telegram_notify  "Configuring networks on hypervisor...."

while [ ! -f /etc/sysconfig/network-scripts/ifcfg-loc-static ]; do
  #### private net 1
  ip link add dev vm1 type veth peer name vm2
  ip link set dev vm1 up
  ip tuntap add tapm mode tap
  ip link set dev tapm up
  ip link add loc-static type bridge

  ip link set tapm master loc-static
  ip link set vm1 master loc-static

  ip addr add "${LAN_CENTOS_IP}"/24 dev loc-static
  ip addr add "${LAN_BRIDGE_IP}"/24 dev vm2

  ip link set loc-static up
  ip link set vm2 up

  nmcli connection modify loc-static ipv4.addresses "${LAN_CENTOS_IP}"/24 ipv4.method manual connection.autoconnect yes ipv6.method "disabled"
done

while [ ! -f /etc/sysconfig/network-scripts/ifcfg-amp-net ]; do
  ### amp-net
  ip link add dev vm3 type veth peer name vm4
  ip link set dev vm3 up
  ip tuntap add tapn mode tap
  ip link set dev tapn up
  ip link add amp-net type bridge

  ip link set tapn master amp-net
  ip link set vm3 master amp-net

  ip addr add "${LB_CENTOS_IP}"/24 dev amp-net
  ip addr add "${LB_BRIDGE_IP}"/24 dev vm4

  ip link set amp-net up
  ip link set vm4 up

  nmcli connection modify amp-net ipv4.addresses "${LB_CENTOS_IP}"/24 ipv4.method manual connection.autoconnect yes ipv6.method "disabled"
done

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

node_ct=10
while [ $node_ct -gt 0 ]; do
  nmcli conn add type bridge-slave ifname Node${node_ct}s master loc-static
  ((node_ct--))
done

node_ct=20
while [ $node_ct -gt 10 ]; do
  nmcli conn add type bridge-slave ifname Node${node_ct}s master amp-net
  ((node_ct--))
done
#############

virsh net-destroy default
virsh net-undefine default
rm -rf /usr/lib/firewalld/zones/libvirt.xml

firewall-cmd --permanent --add-port=514/udp
firewall-cmd --permanent --add-port=514/tcp
firewall-cmd --reload
###########################

############ Create and init storage pools
telegram_notify  "Build storage pools"
for part in $(df | grep "VM-VOL" | awk '{print $6, " " }' | tr -d '/' | tr -d '\n'); do
  virsh pool-define-as "$part" dir - - - - "/$part"
  virsh pool-build "$part"
  virsh pool-autostart "$part"
  virsh pool-start "$part"
done
############################

runuser -l root -c "cd /tmp || exit; ./create-identity-kvm-deploy.sh;" &

### waitloops for vm signals
cat > /tmp/identity-test.sh <<EOF
source /tmp/vm_functions.sh

exec 1>/tmp/identity-signal-install.log 2>&1
while [ true ]; do
    if [ \`< /dev/tcp/$IDENTITY_VIP/$IDENTITY_SIGNAL ; echo \$?\` -lt 1 ]; then

      # fetch subordinate ca from identity
      curl -o /tmp/id_rsa.crt http://$IDENTITY_VIP:$IDENTITY_SIGNAL/subca.cert
      curl -o /tmp/id_rsa http://$IDENTITY_VIP:$IDENTITY_SIGNAL/sub-ca.key

      # generate wildcard cert using subordinate CA
      create_server_cert /tmp "wildcard" "*"

      #run iso replace to load certs into pfsense
      # add key and cert data into pfsense install img
      runuser -l root -c  'mkdir -p /tmp/usb'
      loop_Device=\$(losetup -f --show -P /tmp/pfSense-CE-memstick-ADI-prod.img)
      runuser -l root -c  "mount \${loop_Device}p3 /tmp/usb"
      sed -i "s/{CA_CRT}/\$(get_base64_string_for_file /tmp/id_rsa.crt)/g" /tmp/usb/config.xml
      sed -i "s/{CA_KEY}/\$(get_base64_string_for_file /tmp/id_rsa)/g" /tmp/usb/config.xml
      sed -i "s/{INITIAL_WILDCARD_CRT}/\$(get_base64_string_for_file /tmp/wildcard.crt)/g" /tmp/usb/config.xml
      sed -i "s/{INITIAL_WILDCARD_KEY}/\$(get_base64_string_for_file /tmp/wildcard.key)/g" /tmp/usb/config.xml
      runuser -l root -c  'umount /tmp/usb'
      rm -rf "/tmp/convert-file-*"

      runuser -l root -c "cd /tmp || exit; ./create-gateway-kvm-deploy.sh;" &
      sleep 60;
      runuser -l root -c "cd /tmp || exit; ./create-registry-kvm-deploy.sh;" &
      runuser -l root -c "cd /tmp || exit; ./create-cloud-kvm-deploy.sh;" &
      rm -rf /tmp/identity-test.sh
      rm -rf /tmp/id_rsa*
      rm -rf /tmp/wildcard*
      exit
    else
      sleep 5
    fi
done
EOF

cat > /tmp/cloudsupport-test.sh <<EOF
exec 1>/tmp/cloudsupport-signal-install.log 2>&1
while [ true ]; do
    if [ \`< /dev/tcp/$SUPPORT_VIP/$CLOUDSUPPORT_SIGNAL ; echo \$?\` -lt 1 ]; then
      runuser -l root -c "cd /tmp || exit; ./create-jumpserver-kvm-deploy.sh;" &
      rm -rf /tmp/cloudsupport-test.sh
      exit
    else
      sleep 5
    fi
done
EOF

chmod +x /tmp/identity-test.sh
chmod +x /tmp/cloudsupport-test.sh

cd /tmp || exit
./identity-test.sh &
./cloudsupport-test.sh &

#remove so as to not run again
rm -rf /etc/rc.d/rc.local
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
