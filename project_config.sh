#!/bin/bash

###  Cert constants
export ORGANIZATION="{ORGANIZATION}"

## domain name
## generate internal domain name
export INTERNAL_DOMAIN_NAME="cloud.local";

##  Docker linux build name
export DOCKER_LINUX_BUILD_IMAGE="mephmanx/centos-8-stream-airgap";
export DOCKER_LINUX_BUILD_IMAGE_VERSION="20220804";

## Docker Openstack offline resources
export DOCKER_OPENSTACK_OFFLINE_IMAGE="mephmanx/os-airgap";
## be careful changing these as they need to be matched with each other and they need to exist on their upstream endpoints
export OPENSTACK_VERSION="xena"
export TROVE_OPENSTACK_VERSION="wallaby"
export OPENSTACK_KOLLA_PYLIB_VERSION="13.3.0"

## Homebrew caching image
export HOMEBREW_CACHE_IMAGE="mephmanx/homebrew-cache";
export CF_BBL_INSTALL_TERRAFORM_VERSION="1.0.4"

## pfSense airgap caching image
export PFSENSE_CACHE_IMAGE="mephmanx/pfsense-airgap-resources";
export PFSENSE_VERSION="2.6.0";

## library versions
## this will force cache update if changed
export HARBOR_VERSION="v2.6.0"
export MAGNUM_IMAGE_VERSION="Fedora-Atomic-27-20180419.0"
export CF_ATTIC_TERRAFORM_VERSION="0.11.15"
export DOCKER_COMPOSE_VERSION="1.29.2"
export UBUNTU_VERSION="18.04"
export UBUNTU_RELEASE_NAME="bionic"
export CF_DEPLOY_VERSION="v21.8.0"
export STEMCELL_STAMP="08-19-2022"
export STRATOS_VERSION="4.4.0"

### hostnames for infra vms
export SUPPORT_HOST=registry;
export IDENTITY_HOST=identity;
export EDGE_ROUTER_NAME=gateway;
export STRATOS_CONSOLE=app-console
export APP_INTERNAL_HOSTNAME=sysadmin-local;
export APP_EXTERNAL_HOSTNAME=sysadmin;

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
export CF_BBL_OPENSTACK_CPI_VERSION=1.40
export CF_BBL_OS_CONF_RELEASE=22.1.2
### be careful about changing the version of os-conf as the hash below is REQUIRED to match!
export CF_BBL_OS_CONF_HASH=386293038ae3d00813eaa475b4acf63f8da226ef

## how much available memory (after operating system, vm overhead, openstack overhead, and other misc resources are allocated) is allocated to cloudfoundry
export CF_MEMORY_ALLOCATION_PCT=80
export CF_DISK_ALLOCATION=80
## stemcells to cache, will be pulled from https://bosh.io/d/stemcells/bosh-openstack-kvm-ubuntu-$stemcell-go_agent
export CF_STEMCELLS="ubuntu-jammy ubuntu-bionic ubuntu-xenial ubuntu-trusty"
export BOSH_STEMCELL="ubuntu-jammy"
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

#### signal ports
export IDENTITY_SIGNAL=10111
export CLOUDSUPPORT_SIGNAL=10112

### Harbor version
# Be careful changing this as API's DO change so errors could result from breaking changes
export HARBOR="https://github.com/goharbor/harbor/releases/download/$HARBOR_VERSION/harbor-offline-installer-$HARBOR_VERSION.tgz"

### Magnum docker image
export MAGNUM_IMAGE="https://download.fedoraproject.org/pub/alt/atomic/stable/$MAGNUM_IMAGE_VERSION/CloudImages/x86_64/images/$MAGNUM_IMAGE_VERSION.x86_64.qcow2"

### cloudfoundry attic terraform
export CF_ATTIC_TERRAFORM="https://releases.hashicorp.com/terraform/$CF_ATTIC_TERRAFORM_VERSION/terraform_${CF_ATTIC_TERRAFORM_VERSION}_linux_amd64.zip"

### image for trove instances
export TROVE_INSTANCE_IMAGE="https://cloud-images.ubuntu.com/releases/$UBUNTU_RELEASE_NAME/release/ubuntu-$UBUNTU_VERSION-server-cloudimg-amd64.img"

### image for trove DB's
export TROVE_DB_IMAGE="https://tarballs.opendev.org/openstack/trove/images/trove-$TROVE_OPENSTACK_VERSION-guest-ubuntu-bionic.qcow2"

### cloudfoundry repos
export BOSH_OPENSTACK_ENVIRONMENT_TEMPLATES="https://github.com/cloudfoundry-attic/bosh-openstack-environment-templates/archive/master/cf-templates.zip"
export CF_DEPLOYMENT="https://github.com/cloudfoundry/cf-deployment/archive/main/cf_deployment.zip"

## docker compose
export DOCKER_COMPOSE="https://github.com/docker/compose/releases/download/$DOCKER_COMPOSE_VERSION/docker-compose-linux-x86_64"

## cirros test image
export CIRROS_IMAGE_URL="https://github.com/cirros-dev/cirros/releases/download/0.5.1/cirros-0.5.1-x86_64-disk.img"

## amphora image
export AMPHORA_IMAGE="https://github.com/mephmanx/openstack-amphora-build/releases/download/$OPENSTACK_VERSION/amphora-x64-haproxy.qcow2"
