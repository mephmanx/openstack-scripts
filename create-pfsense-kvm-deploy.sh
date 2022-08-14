#!/bin/bash

rm -rf /tmp/pfsense-install.log
exec 1>/root/pfsense-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x

source /tmp/vm_functions.sh
source /tmp/project_config.sh
source /tmp/vm-configurations.sh

telegram_notify  "PFSense deployment beginning"

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
create_line+="--disk /tmp/pfSense-CE-memstick-ADI-prod.img "
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

cat > /tmp/pf-init-1.sh <<EOF
mount -u -o rw /
mkdir /tmp/test-mnt
mount -v -t msdosfs /dev/vtbd0s3 /tmp/test-mnt
cp /tmp/test-mnt/* /mnt/root/
chmod +x /mnt/root/*.sh
cd /mnt/root
yes | cp /tmp/test-mnt/pfSense-repo.conf /mnt/usr/local/share/pfSense/pfSense-repo.conf;
yes | cp /tmp/test-mnt/pfSense-repo.conf /mnt/usr/local/share/pfSense/pkg/repos/pfSense-repo.conf;
yes | cp /tmp/test-mnt/pfSense-repo.conf /mnt/etc/pkg/FreeBSD.conf;
mkdir /mnt/tmp/repo-dir
tar xf /mnt/root/repo.tar -C /mnt/tmp/repo-dir/
./init.sh
rm -rf init.sh
rm -rf pf-init-1.sh
EOF

PFSENSE_INIT=$(cat </tmp/pf-init-1.sh | base64 | tr -d '\n\r')

pfsense_init_array=( $(echo "$PFSENSE_INIT" | fold -c250 ))

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
  echo "touch /mnt/root/pf-init-1.sh; touch /mnt/root/pf-init-1.sh.enc;";
  sleep 10;
  for element in "${pfsense_init_array[@]}"
    do
      echo "echo '$element' >> /mnt/root/pf-init-1.sh.enc";
      sleep 5;
    done
  echo "openssl base64 -d -in /mnt/root/pf-init-1.sh.enc -out /mnt/root/pf-init-1.sh;";
  sleep 10;
  echo "rm -rf /mnt/root/*.enc";
  sleep 10;
  echo "cd /mnt/root/;"
  sleep 10;
  echo "chmod +x pf-init-1.sh;"
  sleep 10;
  echo "./pf-init-1.sh;"
  sleep 10;
 ) | telnet

rm -rf /tmp/pf-init-1.sh
## remove install disk from pfsense
virsh detach-disk --domain pfsense /tmp/pfSense-CE-memstick-ADI-prod.img --persistent --config --live
virsh destroy pfsense
sleep 20;
virsh start pfsense

### cleanup
runuser -l root -c  "rm -rf /tmp/usb"
#####

telegram_notify  "PFSense reboot, pfsense-init script should begin after reboot."

rm -rf /tmp/pfSense-CE-memstick-ADI-prod.img
rm -rf /tmp/create-pfsense-kvm-deploy.sh
