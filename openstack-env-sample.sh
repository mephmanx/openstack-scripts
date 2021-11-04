#!/bin/sh

## domain name
export DOMAIN_NAME=<internal cloud domain name>;
export EXTERNAL_DOMAIN_NAME=<domain name on external requests>

###timezone
## escape the separator otherwise sed will have an error and nothing will be built
export TIMEZONE="America\/New_York";

### Enable auto-update
## This enables the centos/stream auto update function on install.
## Auto update can be enabled later if not enabled here, this just sets it up and enables it for you.
export LINUX_AUTOUPDATE=1

## Cert params
# these parameters will be used to generate CSR for all certificates
export COUNTRY="<country 2 char>"
export STATE="<state 2 char>"
export LOCATION="<location 255 char string>"
export ORGANIZATION="<organization name 255 char string>"
export OU="<OU 2 char>"

### harbor and docker accounts
export DOCKER_HUB_USER=<docker hub username>
export DOCKER_HUB_PWD=<dokcer hub access token>
##########

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
