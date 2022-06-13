#!/bin/bash

rm -rf /tmp/pfsense-install.log
exec 1>/root/pfsense-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x

telegram_notify  "PFSense deployment beginning"

source /tmp/vm_functions.sh
source /tmp/project_config.sh
source /tmp/vm-configurations.sh

size_avail=$(df /VM-VOL-MISC | awk '{print $2}' | sed 1d)
DRIVE_SIZE=$(($((size_avail * 20/100)) / 1024 / 1024))

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
create_line+="--os-variant=freebsd12.0 "
create_line+="--graphics=vnc "

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
  sleep 5;
  echo 'mount -u -o rw /'
  sleep 10;
  echo 'mkdir /tmp/test-mnt';
  sleep 10;
  echo 'mount -v -t msdosfs /dev/vtbd0s3 /tmp/test-mnt';
  sleep 10;
  echo 'cp /tmp/test-mnt/openstack-env.sh /mnt/root/openstack-env.sh';
  sleep 10;
  echo 'cp /tmp/test-mnt/pf_functions.sh /mnt/root/pf_functions.sh';
  sleep 10;
  echo 'cp /tmp/test-mnt/project_config.sh /mnt/root/project_config.sh';
  sleep 10;
  echo 'cp /tmp/test-mnt/pfsense-init.sh /mnt/root/pfsense-init.sh';
  sleep 10;
  echo "chmod 777 /mnt/root/*.sh"
  sleep 10;
 ) | telnet

## remove install disk from pfsense
virsh detach-disk --domain pfsense /tmp/pfSense-CE-memstick-ADI.img --persistent --config --live
virsh destroy pfsense
sleep 20;
virsh start pfsense

### cleanup
runuser -l root -c  "rm -rf /tmp/usb"
#####

telegram_notify  "PFSense reboot, pfsense-init script should begin after reboot."

rm -rf /tmp/pfSense-CE-memstick-ADI.img