# tools

This script is to build Openstack private cloud install ISO.  

It is executed by creating proper config in openstack-env.sh file and then executing 

    ./toolbox-kvm-openstack.sh <location of openstack-env.sh file>

to build /var/tmp/openstack-iso.iso which can then be burned to DVD and used to boot on empty hardware