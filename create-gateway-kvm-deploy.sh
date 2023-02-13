#!/bin/bash

exec 1> >(logger --priority user.notice --tag "$(basename "$0")") \
     2> >(logger --priority user.error --tag "$(basename "$0")")

source /tmp/vm_functions.sh
source /tmp/project_config.sh
source /tmp/vm-configurations.sh

telegram_notify  "$EDGE_ROUTER_NAME deployment beginning"

size_avail=$(df /VM-VOL-MISC | awk '{print $2}' | sed 1d)
DRIVE_SIZE=$(($((size_avail * 20/100)) / 1024 / 1024))

create_line="virt-install "
create_line+="--hvm "
create_line+="--virt-type=kvm "
create_line+="--name=$EDGE_ROUTER_NAME "
create_line+="--memory=${PFSENSE_RAM}000 "
create_line+="--cpu=host-passthrough,cache.mode=passthrough "
create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
create_line+="--memorybacking hugepages=yes "
create_line+="--vcpus=8 "
create_line+="--boot hd,menu=off,useserial=off "
create_line+="--disk /tmp/pfSense-CE-memstick-ADI-prod.img "
create_line+="--disk pool=$(getDiskMapping "misc" "1"),size=$DRIVE_SIZE,bus=virtio,sparse=no "
create_line+="--connect qemu:///system "
create_line+="--os-type=freebsd "
create_line+="--serial tcp,host=0.0.0.0:4567,mode=bind,protocol=telnet "
create_line+="--serial tcp,host=0.0.0.0:4568,mode=bind,protocol=telnet "
create_line+="--network type=direct,source=ext-bond,model=virtio,source_mode=bridge "
create_line+="--network type=bridge,source=int-net,model=virtio "
create_line+="--os-variant=freebsd12.0 "
create_line+="--nographics "

create_line+="--channel unix,target.type=virtio,target.name='org.qemu.guest_agent.0' "

create_line+="--autostart --wait 0"

eval "$create_line"

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
  echo 'S';
  sleep 10;
  echo "./pf-init-3.sh;"
  sleep 10;
 ) | telnet

## remove install disk from pfsense
virsh detach-disk --domain "$EDGE_ROUTER_NAME" /tmp/pfSense-CE-memstick-ADI-prod.img --persistent --config --live
virsh destroy "$EDGE_ROUTER_NAME"
sleep 20;
virsh start "$EDGE_ROUTER_NAME"

losetup -d /dev/loop0
### cleanup
runuser -l root -c  "rm -rf /tmp/usb"
#####

telegram_notify  "$EDGE_ROUTER_NAME reboot, pfsense-init script should begin after reboot."

rm -rf /tmp/pfSense-CE-memstick-ADI-prod.img
rm -rf /tmp/create-gateway-kvm-deploy.sh
