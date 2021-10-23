#!/bin/sh

#################
#  Encrypt these passwords using some sort of hardware specific key (TPM maybe?) so they are not unencrypted in the iso.
###############

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
