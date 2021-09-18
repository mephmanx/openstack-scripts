#!/bin/sh

#################
#  Encrypt these passwords using some sort of hardware specific key (TPM maybe?) so they are not unencrypted in the iso.
###############

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
export SMTP_ACCOUNT=<gmail username>
export SMTP_KEY=<gmail application auth key>
export SMTP_ADDRESS=smtp.gmail.com
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
