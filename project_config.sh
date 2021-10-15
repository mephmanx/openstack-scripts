#!/bin/bash

### NOTE: Variable replacement does NOT work as expected in this file so do not rely on it!!
## see 'prep_project_config' function in vm_functions.sh script for more info

### Harbor version
# Be careful changing this as API's DO change so errors could result from breaking changes
export HARBOR=https://github.com/goharbor/harbor/releases/download/v2.3.3/harbor-offline-installer-v2.3.3.tgz;

## SWTPM libs
export LIBTPMS_GIT=https://github.com/stefanberger/libtpms.git;
export LIBTPMS_BRANCH=master;
export SWTPM_GIT=https://github.com/stefanberger/swtpm.git;
export SWTPM_BRANCH=master;

###  PFSense installer
## fat32 offset is added but logic NEEDS to be validated on update
export PFSENSE=https://nyifiles.netgate.com/mirror/downloads/pfSense-CE-memstick-ADI-2.5.2-RELEASE-amd64.img.gz;

## Linux iso
## This is cached on PFSense to be used as the base image by all other systems.
export LINUX_ISO=https://vault.centos.org/8.3.2011/isos/x86_64/CentOS-8.3.2011-x86_64-minimal.iso

### centos base image
## figure out how to build centos stream
#export CENTOS_BASE=http://isoredirect.centos.org/centos/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-20210916-dvd1.iso

### Magnum docker image
export MAGNUM_IMAGE=https://download.fedoraproject.org/pub/alt/atomic/stable/Fedora-Atomic-27-20180419.0/CloudImages/x86_64/images/Fedora-Atomic-27-20180419.0.x86_64.qcow2

### cloudfoundry attic terraform
export CF_ATTIC_TERRAFORM=https://releases.hashicorp.com/terraform/0.11.15/terraform_0.11.15_linux_amd64.zip

### image for trove instances
export TROVE_INSTANCE_IMAGE=https://cloud-images.ubuntu.com/releases/bionic/release-20210928/ubuntu-18.04-server-cloudimg-amd64.img

### image for trove DB's
export TROVE_DB_IMAGE=https://tarballs.opendev.org/openstack/trove/images/trove-master-guest-ubuntu-bionic.qcow2

## Administrator email.
# This is CRITICAL as OpenVPN profile will be email there, this email will receive ALL critical install and system emails until changed,
# This email will be used for Telegram auto register, will be used for LetsEncrypt, will be used for SNMP notifications, UPS alerts, and more.
export ADMIN_EMAIL=administrator@$DOMAIN_NAME

## external global domain name
export DOMAIN_NAME=lyonsgroup.family;

### hostname for harbor install
export SUPPORT_HOST=harbor;
export IDENTITY_HOST=identity;

## openstack hostnames
export APP_INTERNAL_HOSTNAME=openstack-local;
export APP_EXTERNAL_HOSTNAME=openstack;

### Network prefix, used for all networks below
#MariaDB seems to have a problem with 172 addresses.  Dont use!
export NETWORK_PREFIX="10.0.200";
export TROVE_NETWORK="10.2.0";

## vips for openstack
export INTERNAL_VIP="$NETWORK_PREFIX.254";
export EXTERNAL_VIP="$NETWORK_PREFIX.253";
export CLOUDFOUNDRY_VIP="$NETWORK_PREFIX.252";
export SUPPORT_VIP="$NETWORK_PREFIX.10";
export IDENTITY_VIP="$NETWORK_PREFIX.11";

### Internal IP config
export LAN_CENTOS_IP="$NETWORK_PREFIX.1";
export LAN_BRIDGE_IP="$NETWORK_PREFIX.2";
export GATEWAY_ROUTER_IP="$NETWORK_PREFIX.3";
export NETMASK="255.255.255.0";
## Openstack core VM static IP start address
export CORE_VM_START_IP=20;

### Must be on same subnet but separate so as not to collide
## these are for core VM's that use DHCP
export GATEWAY_ROUTER_DHCP_START="$NETWORK_PREFIX.50";
export GATEWAY_ROUTER_DHCP_END="$NETWORK_PREFIX.75";
## These are for OS project floating IP's
export OPENSTACK_DHCP_START="$NETWORK_PREFIX.100";
export OPENSTACK_DHCP_END="$NETWORK_PREFIX.200";

### Trove network settings
export TROVE_DHCP_START="$TROVE_NETWORK.100";
export TROVE_DHCP_END="$TROVE_NETWORK.200";

###timezone
## escape the separator otherwise sed will have an error and nothing will be built
export TIMEZONE="America\/New_York";

##### Infrastructure debug mode
## This is used to enabled/disable logs and root pwd saving.
##  DISABLE FOR PRODUCTION USE!
export HYPERVISOR_DEBUG=1

### Enable auto-update
## This enables the centos/stream auto update function on install.
## Auto update can be enabled later if not enabled here, this just sets it up and enables it for you.
export LINUX_AUTOUPDATE=1

## Cert params
# these parameters will be used to generate CSR for all certificates
export COUNTRY="US"
export STATE="PA"
export LOCATION="Scranton"
export ORGANIZATION="$DOMAIN_NAME"
export OU="HQ"
export COMMON_NAME="$DOMAIN_NAME"

### Infrastructure tuning params
## These control various build infrastructure decisions on machine size.
##  Adjust based on your system needs
export RAM_PCT_AVAIL_CLOUD=96

### UPS attachment
## If physical server, does it contain a UPS system?  This can be monitored through PFSense to send alerts when power is on battery.
export UPS_PRESENT=1
## if UPS present, gather ids from lsusb to attach to pfsense KVM
export VENDOR_ID='051d'
export PRODUCT_ID='0002'

### Cloudfoundry variables
export CF_TCP_PORT_COUNT=10
export CF_BBL_INSTALL_VERSION=1.0.2

## how much available memory (after operating system, vm overhead, openstack overhead, and other misc resources are allocated) is allocated to cloudfoundry
export CF_MEMORY_ALLOCATION_PCT=90
export CF_DISK_ALLOCATION=80

## openstack vm counts
### these counts can be adjusted if larger than 1 server
### below counts are based on single server
export CONTROL_COUNT=3
export NETWORK_COUNT=2
export MONITORING_COUNT=1
export STORAGE_COUNT=1
export COMPUTE_COUNT=1
######

### External openstack VM memory
## In GB
export PFSENSE_RAM=8
export CLOUDSUPPORT_RAM=8
export IDENTITY_RAM=8
export CONTROL_RAM=34
export NETWORK_RAM=12
export MONITORING_RAM=16
export STORAGE_RAM=20
export KOLLA_RAM=4
