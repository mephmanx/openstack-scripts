#!/bin/bash

rm -rf /tmp/pfsense-install.log
exec 1>/root/pfsense-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x

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
create_line+="--os-variant=freebsd11.0 "
create_line+="--graphics=vnc "
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
) | telnet

## remove install disk from pfsense
virsh detach-disk --domain pfsense /tmp/pfSense-CE-memstick-ADI.img --persistent --config --live
virsh destroy pfsense
sleep 20
virsh start pfsense

sleep 120;
telegram_notify  "PFSense first reboot in progress, continuing to package install...."

### cleanup
runuser -l root -c  "rm -rf /tmp/usb"
#####

root_pw=$(generate_random_pwd 31)

### base64 files
HYPERVISOR_KEY=$(cat </tmp/pf_key | base64 | tr -d '\n\r')
HYPERVISOR_PUB_KEY=$(cat </tmp/pf_key.pub | base64 | tr -d '\n\r')
OPENSTACK_ENV=$(cat </tmp/openstack-env.sh | base64 | tr -d '\n\r')
PF_FUNCTIONS=$(cat </tmp/pf_functions.sh | base64 | tr -d '\n\r')
PROJECT_CONFIG=$(cat </tmp/project_config.sh | base64 | tr -d '\n\r')
PFSENSE_INIT=$(cat </tmp/pfsense-init.sh | base64 | tr -d '\n\r')
IP_OUT=$(cat </tmp/ip_out_update | base64 | tr -d '\n\r')

### pfsense prep
hypervisor_key_array=( $(echo $HYPERVISOR_KEY | fold -c250 ))
hypervisor_pub_array=( $(echo $HYPERVISOR_PUB_KEY | fold -c250 ))
openstack_env_array=( $(echo $OPENSTACK_ENV | fold -c250 ))
pf_functions_array=( $(echo $PF_FUNCTIONS | fold -c250 ))
project_config_array=( $(echo $PROJECT_CONFIG | fold -c250 ))
pfsense_init_array=( $(echo $PFSENSE_INIT | fold -c250 ))
ip_out_array=( $(echo $IP_OUT | fold -c250 ))

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
  echo "yes | pkg install pfsense-pkg-Shellcmd &";
  sleep 120;
  echo "mkdir /root/.ssh";
  sleep 20;
  echo "touch /root/.ssh/id_rsa; touch /root/.ssh/id_rsa.pub; touch /root/.ssh/id_rsa.pub.enc; touch /root/.ssh/id_rsa.enc;";
  sleep 10;
  for element in "${hypervisor_pub_array[@]}"
  do
    echo "echo '$element' >> /root/.ssh/id_rsa.pub.enc";
    sleep 5;
  done
  for element in "${hypervisor_key_array[@]}"
  do
    echo "echo '$element' >> /root/.ssh/id_rsa.enc";
    sleep 5;
  done
  echo "openssl base64 -d -in /root/.ssh/id_rsa.pub.enc -out /root/.ssh/id_rsa.pub;";
  sleep 10;
  echo "openssl base64 -d -in /root/.ssh/id_rsa.enc -out /root/.ssh/id_rsa;";
  sleep 10;
  echo "chmod 600 /root/.ssh/*";
  sleep 10;
  echo "ssh-keyscan -H $LAN_CENTOS_IP >> ~/.ssh/known_hosts;";
  sleep 30;

  echo "touch /root/openstack-env.sh; touch /root/openstack-env.sh.enc;";
  sleep 10;
  for element in "${openstack_env_array[@]}"
  do
    echo "echo '$element' >> /root/openstack-env.sh.enc";
    sleep 5;
  done
  echo "openssl base64 -d -in /root/openstack-env.sh.enc -out /root/openstack-env.sh;";
  sleep 10;

  echo "touch /root/pf_functions.sh; touch /root/pf_functions.sh.enc;";
  sleep 10;
  for element in "${pf_functions_array[@]}"
  do
    echo "echo '$element' >> /root/pf_functions.sh.enc";
    sleep 5;
  done
  echo "openssl base64 -d -in /root/pf_functions.sh.enc -out /root/pf_functions.sh;";
  sleep 10;

  echo "touch /root/project_config.sh; touch /root/project_config.sh.enc;";
  sleep 10;
  for element in "${project_config_array[@]}"
  do
    echo "echo '$element' >> /root/project_config.sh.enc";
    sleep 5;
  done
  echo "openssl base64 -d -in /root/project_config.sh.enc -out /root/project_config.sh;";
  sleep 10;

  echo "touch /root/ip_out_update; touch /root/ip_out_update.enc;";
  sleep 10;
  for element in "${ip_out_array[@]}"
  do
    echo "echo '$element' >> /root/ip_out_update.enc";
    sleep 5;
  done
  echo "openssl base64 -d -in /root/ip_out_update.enc -out /root/ip_out_update;";
  sleep 10;

  echo "touch /root/pfsense-init.sh; touch /root/pfsense-init.sh.enc;";
  sleep 10;
  for element in "${pfsense_init_array[@]}"
  do
    echo "echo '$element' >> /root/pfsense-init.sh.enc";
    sleep 5;
  done
  echo "openssl base64 -d -in /root/pfsense-init.sh.enc -out /root/pfsense-init.sh;";
  sleep 10;
  echo "rm -rf /root/*.enc";
  sleep 10;

  echo "chmod 777 /root/*.sh"
  sleep 10;
) | telnet

virsh destroy pfsense
sleep 20
virsh start pfsense

telegram_notify  "PFSense rebooting after package install, pfsense-init script should begin after reboot."

rm -rf /tmp/pfSense-CE-memstick-ADI.img



