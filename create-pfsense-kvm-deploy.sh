#!/bin/bash

rm -rf /tmp/pfsense-install.log
exec 1>/root/pfsense-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x

source /tmp/vm_functions.sh
source /tmp/project_config.sh
source /tmp/vm-configuration.sh

DISK_COUNT=`lshw -json -class disk | grep -o -i disk: | wc -l`
if [[ $DISK_COUNT -lt 2 ]]; then
  size_avail=`df /VM-VOL-ALL | awk '{print $2}' | sed 1d`
  DRIVE_SIZE=$(($((size_avail * 5/100)) / 1024 / 1024))
else
  size_avail=`df /VM-VOL-MISC | awk '{print $2}' | sed 1d`
  DRIVE_SIZE=$(($((size_avail * 20/100)) / 1024 / 1024))
fi

### copy pfsense files to folder for host
rm -rf /tmp/pftransfer/*.sh
cp -nf /tmp/openstack-env.sh /tmp/pftransfer
cp -nf /tmp/pf_functions.sh /tmp/pftransfer
cp -nf /tmp/project_config.sh /tmp/pftransfer
cp -nf /tmp/pfsense-init.sh /tmp/pftransfer
##################

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
create_line+="--autostart --wait 0"

echo $create_line
telegram_notify "PFSense install beginning...."
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
  echo 'S';
  sleep 5;
) | telnet

## remove install disk from pfsense
virsh detach-disk --domain pfsense /tmp/pfSense-CE-memstick-ADI.img --persistent --config --live
virsh reboot pfsense

sleep 120;
telegram_notify  "PFSense first reboot in progress, continuing to package install...."

### cleanup
runuser -l root -c  "rm -rf /tmp/usb"
#####

root_pw=$(generate_random_pwd 31)

telegram_debug_msg  "PFSense admin pwd is $root_pw"

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

telegram_notify  \
        "PFSense rebooting after package install, pfsense-init script should begin after reboot."

virsh reboot pfsense

