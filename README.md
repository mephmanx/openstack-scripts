# Openstack/Cloudfoundry create scripts

This script is to build Openstack private cloud install ISO.  

It is executed by creating proper config in openstack-env.sh file and then executing 

    ./toolbox-kvm-openstack.sh <location of openstack-env.sh file>

to build /var/tmp/openstack-iso.iso which can then be dd'ed to USB drive or other large medium and used to boot on empty hardware

# Use to write to disk

dd if=/var/tmp/openstack-iso.iso of=/dev/sdb bs=16M status=progress
