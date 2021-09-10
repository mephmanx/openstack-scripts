#!/bin/sh

#################
#  Encrypt these passwords using some sort of hardware specific key (TPM maybe?) so they are not unencrypted in the iso.
###############

## RANDOM_PWD is generated ONCE and used wherever the token is.  It is NOT a random password for each use!

### potentially remove all random pwd entries...make them internal to code
## admin password for all hypervisor and openstack linux vms
export CENTOS_ADMIN_PWD={RANDOM_PWD}
####

### cloud accounts and passwords, admin internal only
export OPENSTACK_ADMIN_PWD={RANDOM_PWD}
export KIBANA_ADMIN_PWD={RANDOM_PWD}
export GRAFANA_ADMIN_PWD={RANDOM_PWD}
########

### internal
export SUPPORT_PASSWORD={RANDOM_PWD}
export OPENVPN_CERT_PWD={RANDOM_PWD}
############

### github
## for prod move repo contents to disk during image create so this is no longer needed.
export GITHUB_USER=<github username>
export GITHUB_TOKEN=<github PAT token>
###

### CloudFoundry admin account name. ## Password is generated and sent via telegram once deploy is complete
export OPENSTACK_CLOUDFOUNDRY_USERNAME=osuser

### harbor and docker accounts
export SUPPORT_USERNAME=admin
export DOCKER_HUB_USER=<docker hub username>
export DOCKER_HUB_PWD=<dokcer hub access token>
##########

##### pfsense related

### godaddy info
export GODADDY_ACCOUNT=<godaddy api key>
export GODADDY_KEY=<godaddy api secret>
####

#### gmail info
## prefer telegram over SMTP...remove if possible
export GMAIL_ACCOUNT=<gmail username>
export GMAIL_KEY=<gmail application auth key>
export GMAIL_ADDRESS=smtp.gmail.com
#######

### telegram
export TELEGRAM_API=<telegram api key>
export TELEGRAM_CHAT_ID=<telegram chat id>
#  -549260306  -  group chat id (the minus is important!)
#  1861939024 - original chat id
#########

#### Snort key
export OINKMASTER=<oinkmaster key>
#########

###### Maxmind key
export MAXMIND_KEY=<maxmind key>
##########

### always leave extra blank line at the bottom
