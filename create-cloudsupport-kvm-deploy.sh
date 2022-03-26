#!/bin/bash

rm -rf /tmp/cloudsupport-deploy.log
exec 1>/root/cloudsupport-deploy.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x

source /tmp/vm_functions.sh
source /tmp/project_config.sh
source /tmp/vm-configurations.sh

if (virsh list --name | grep -q "cloudsupport"); then
  return
else
  telegram_notify"Removing existing cloudsupport vm and building image for new one...."
fi

DISK_COUNT=$(get_disk_count)
if [[ $DISK_COUNT -lt 2 ]]; then
  size_avail=`df /VM-VOL-ALL | awk '{print $2}' | sed 1d`
  DRIVE_SIZE=$(($((size_avail * 5/100)) / 1024 / 1024))
else
  size_avail=`df /VM-VOL-MISC | awk '{print $2}' | sed 1d`
  DRIVE_SIZE=$(($((size_avail * 45/100)) / 1024 / 1024))
fi

create_line="virt-install "
create_line+="--hvm "
create_line+="--virt-type=kvm "
create_line+="--name=cloudsupport "
create_line+="--memory=${CLOUDSUPPORT_RAM}000 "
create_line+="--cpu=host-passthrough,cache.mode=passthrough "
create_line+="--cpuset=auto "
create_line+="--tpm emulator,model=tpm-tis,version=2.0 "
create_line+="--memorybacking hugepages=yes "
create_line+="--vcpus=4,maxvcpus=4,sockets=2,cores=1,threads=2 "
create_line+="--controller type=scsi,model=virtio-scsi "
create_line+="--disk pool=$(getDiskMapping "misc" "1"),size=$DRIVE_SIZE,bus=virtio,sparse=no "
create_line+="--cdrom=/var/tmp/cloudsupport-iso.iso "
create_line+="--network type=bridge,source=loc-static,model=virtio "
create_line+="--os-variant=centos8 "
create_line+="--graphics=vnc "
create_line+="--autostart --wait 0"

telegram_notify  "Creating cloudsupport vm"

echo $create_line
eval $create_line &
