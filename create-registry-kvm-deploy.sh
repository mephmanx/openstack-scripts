#!/bin/bash

exec 1> >(logger --priority user.notice --tag "$(basename "$0")") \
     2> >(logger --priority user.error --tag "$(basename "$0")")

source /tmp/vm_functions.sh
source /tmp/project_config.sh
source /tmp/vm-configurations.sh

size_avail=$(df /VM-VOL-MISC | awk '{print $2}' | sed 1d)
DRIVE_SIZE=$(($((size_avail * 45/100)) / 1024 / 1024))

create_line="virt-install "
create_line+="--hvm "
create_line+="--virt-type=kvm "
create_line+="--name=$SUPPORT_HOST "
create_line+="--memory=${CLOUDSUPPORT_RAM}000 "
create_line+="--cpu=host-passthrough,cache.mode=passthrough "
create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
create_line+="--memorybacking hugepages=yes "
create_line+="--vcpus=4,maxvcpus=4,sockets=2,cores=1,threads=2 "
create_line+="--controller type=scsi,model=virtio-scsi "
create_line+="--disk pool=$(getDiskMapping "misc" "1"),size=$DRIVE_SIZE,bus=virtio,sparse=no "
create_line+="--cdrom=/tmp/cloudsupport-iso.iso "
create_line+="--network type=bridge,source=int-net,model=virtio "
create_line+="--os-variant=centos8 "
create_line+="--graphics=vnc "

create_line+="--channel unix,target.type=virtio,target.name='org.qemu.guest_agent.0' "

create_line+="--autostart --wait -1;  rm -rf /tmp/cloudsupport-iso.iso"

telegram_notify  "Creating $SUPPORT_HOST vm"

echo "$create_line"
eval "$create_line" &

rm -rf /tmp/create-registry-kvm-deploy.sh