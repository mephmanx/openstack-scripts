#!/bin/sh

### Enable auto-update
## This enables the centos/stream auto update function on install.
## Auto update can be enabled later if not enabled here, this just sets it up and enables it for you.
export LINUX_AUTOUPDATE=1

### harbor and docker accounts
export DOCKER_HUB_USER=<docker hub username>
export DOCKER_HUB_PWD=<dokcer hub access token>
##########

### telegram
export TELEGRAM_API=<telegram api key>
export TELEGRAM_CHAT_ID=<telegram chat id>
#########

#### Snort key
export OINKMASTER=<oinkmaster key>
#########

###### Maxmind key
export MAXMIND_KEY=<maxmind key>
##########