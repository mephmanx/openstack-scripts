#!/bin/bash

### NOTE: Variable replacement does NOT work as expected in this file so do not rely on it!!
## see 'prep_project_config' function in vm_functions.sh script for more info

### Harbor version
# Be careful changing this as API's DO change so errors could result from breaking changes
export HARBOR=https://github.com/goharbor/harbor/releases/download/v2.4.0/harbor-offline-installer-v2.4.0.tgz;

## SWTPM libs
export LIBTPMS_GIT=https://github.com/stefanberger/libtpms/archive/master/libtpms.zip;
export SWTPM_GIT=https://github.com/stefanberger/swtpm/archive/master/swtpm.zip;

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

### cloudfoundry repos
export BOSH_OPENSTACK_ENVIRONMENT_TEMPLATES=https://github.com/cloudfoundry-attic/bosh-openstack-environment-templates/archive/master/cf-templates.zip
export CF_DEPLOYMENT=https://github.com/cloudfoundry/cf-deployment/archive/main/cf_deployment.zip

## docker compose
export DOCKER_COMPOSE=https://github.com/docker/compose/releases/download/1.29.2/docker-compose-linux-x86_64

### hostnames for infra vms
export SUPPORT_HOST=harbor;
export IDENTITY_HOST=identity;
export APP_INTERNAL_HOSTNAME=openstack-local;
export APP_EXTERNAL_HOSTNAME=openstack;

### Network prefix, used for all networks below
#MariaDB seems to have a problem with 172 addresses.  Dont use!
export NETWORK_PREFIX="10.0.200";
export LB_NETWORK="10.1.0";
export TROVE_NETWORK="10.2.0";
export VPN_NETWORK="10.0.9";

## vips for openstack
export SUPPORT_VIP="$NETWORK_PREFIX.10";
export IDENTITY_VIP="$NETWORK_PREFIX.11";
export CLOUDFOUNDRY_VIP="$NETWORK_PREFIX.252";
export EXTERNAL_VIP="$NETWORK_PREFIX.253";
export INTERNAL_VIP="$NETWORK_PREFIX.254";

### Internal IP config
export LAN_CENTOS_IP="$NETWORK_PREFIX.1";
export LAN_BRIDGE_IP="$NETWORK_PREFIX.2";
export GATEWAY_ROUTER_IP="$NETWORK_PREFIX.3";
export LB_CENTOS_IP="$LB_NETWORK.1";
export LB_BRIDGE_IP="$LB_NETWORK.2";
export LB_ROUTER_IP="$LB_NETWORK.3";
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
### LB network DHCP range
export LB_DHCP_START="$LB_NETWORK.100";
export LB_DHCP_END="$LB_NETWORK.200";
### Trove network settings
export TROVE_DHCP_START="$TROVE_NETWORK.100";
export TROVE_DHCP_END="$TROVE_NETWORK.200";

##### Infrastructure debug mode
## This is used to enabled/disable logs and root pwd saving.
##  DISABLE FOR PRODUCTION USE!
export HYPERVISOR_DEBUG=1

### Infrastructure tuning params
## These control various build infrastructure decisions on machine size.
##  Adjust based on your system needs
export RAM_PCT_AVAIL_CLOUD=96

### Cloudfoundry variables
export CF_TCP_PORT_COUNT=10
export CF_BBL_INSTALL_TERRAFORM_VERSION=1.0.2
export CF_BBL_OPENSTACK_CPI_VERSION=1.40
export CF_BBL_OS_CONF_RELEASE=22.1.2
### be careful about changing the version of os-conf as the hash below is REQUIRED to match!
export CF_BBL_OS_CONF_HASH=386293038ae3d00813eaa475b4acf63f8da226ef

## how much available memory (after operating system, vm overhead, openstack overhead, and other misc resources are allocated) is allocated to cloudfoundry
export CF_MEMORY_ALLOCATION_PCT=90
export CF_DISK_ALLOCATION=80
### this must be in FreeBSD compatible array format or will break the pfsense init!
## stemcells to cache, will be pulled from https://bosh.io/d/stemcells/bosh-openstack-kvm-ubuntu-$stemcell-go_agent
export CF_STEMCELLS="ubuntu-bionic centos-7 ubuntu-xenial ubuntu-trusty"
export BOSH_STEMCELL="ubuntu-bionic"
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