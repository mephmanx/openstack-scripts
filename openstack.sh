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

exec 1>/tmp/openstack-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

## Send System info
load_system_info
telegram_notify  "Openstack Cloud System: $SYSTEM_INFO"

################# setup KVM and kick off openstack cloud create
systemctl restart libvirtd
############################

### system profile
tuned-adm profile virtual-host
#############

#### restart cockpit to make sure it is up
if [[ $HYPERVISOR_DEBUG == 1 ]]; then
  systemctl enable --now cockpit.socket
  systemctl restart cockpit
fi
####################

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
rm /etc/libvirt/qemu/networks/autostart/default.xml
rm -rf /usr/lib/firewalld/zones/libvirt.xml
firewall-cmd --reload
###########################

#### vtpm
#telegram_notify  "Installing VTPM"
#vtpm
######

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
      # add key and cert data into pfsense install img

      # fetch subordiante ca from identity
      curl -x GET -o /tmp/subca.cert http://$IDENTITY_VIP:$IDENTITY_SIGNAL/subca.cert
      curl -x GET -o /tmp/subca.key http://$IDENTITY_VIP:$IDENTITY_SIGNAL/sub-ca.key
      if [ ! -f /tmp/subca.cert ] && [ ! -f /tmp/subca.key ]; then
        continue;
      fi
      rm -rf /tmp/id_rsa*
      cp /tmp/subca.cert /tmp/id_rsa.crt
      cp /tmp/subca.key /tmp/id_rsa

      # generate wildcard cert using subordinate CA
      create_server_cert /tmp "wildcard" "*"

      ## run format replace on each file below

      sed -e '40{N;s/\n//;}' /tmp/wildcard.key | sed -e ':a;N;\$!ba;s/\n/\r\n/g' > /tmp/wildcard-converted.key
      truncate -s -1 /tmp/wildcard-converted.key
      base64 -w 0 < /tmp/wildcard-converted.key > /tmp/wildcard-reencoded.key
      echo >> /tmp/wildcard-reencoded.key

      sed -e '40{N;s/\n//;}' /tmp/subca.key | sed -e ':a;N;\$!ba;s/\n/\r\n/g' > /tmp/subca-converted.key
      truncate -s -1 /tmp/subca-converted.key
      base64 -w 0 < /tmp/subca-converted.key > /tmp/subca-reencoded.key
      echo >> /tmp/subca-reencoded.key

      sed -e '40{N;s/\n//;}' /tmp/wildcard.crt | sed -e ':a;N;\$!ba;s/\n/\r\n/g' > /tmp/wildcard-converted.crt
      truncate -s -1 /tmp/wildcard-converted.crt
      base64 -w 0 < /tmp/wildcard-converted.crt > /tmp/wildcard-reencoded.crt
      echo >> /tmp/wildcard-reencoded.crt

      sed -e '40{N;s/\n//;}' /tmp/subca.cert | sed -e ':a;N;\$!ba;s/\n/\r\n/g' > /tmp/subca-converted.cert
      truncate -s -1 /tmp/subca-converted.cert
      base64 -w 0 < /tmp/subca-converted.cert > /tmp/subca-reencoded.cert
      echo >> /tmp/subca-reencoded.cert


      #run iso replace to load certs into pfsense
      ## replace longest first
      replace_string_in_iso "/tmp/pfSense-CE-memstick-ADI-prod.img" "\$(generate_specific_pwd 4393)" "\$(cat </tmp/wildcard-reencoded.key)"
      replace_string_in_iso "/tmp/pfSense-CE-memstick-ADI-prod.img" "\$(generate_specific_pwd 4389)" "\$(cat </tmp/subca-reencoded.key)"
      replace_string_in_iso "/tmp/pfSense-CE-memstick-ADI-prod.img" "\$(generate_specific_pwd 2765)" "\$(cat </tmp/wildcard-reencoded.crt)"
      replace_string_in_iso "/tmp/pfSense-CE-memstick-ADI-prod.img" "\$(generate_specific_pwd 2465)" "\$(cat </tmp/subca-reencoded.cert)"

      runuser -l root -c "cd /tmp || exit; ./create-pfsense-kvm-deploy.sh;" &
      sleep 60;
      runuser -l root -c "cd /tmp || exit; ./create-cloudsupport-kvm-deploy.sh;" &
      runuser -l root -c "cd /tmp || exit; ./create-cloud-kvm-deploy.sh;" &
      rm -rf /tmp/identity-test.sh
      exit
    else
      sleep 5
    fi
done
EOF

cat > /tmp/cloudsupport-test.sh <<EOF
while [ true ]; do
    if [ \`< /dev/tcp/$SUPPORT_VIP/$CLOUDSUPPORT_SIGNAL ; echo \$?\` -lt 1 ]; then
      runuser -l root -c "cd /tmp || exit; ./create-kolla-kvm-deploy.sh;" &
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
