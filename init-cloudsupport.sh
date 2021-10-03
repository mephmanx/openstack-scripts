#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/project_config.sh
. /tmp/openstack-env.sh

start() {
# code to start app comes here
# example: daemon program_name &
exec 1>/root/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

### cleanup from previous boot
rm -rf /tmp/eth*
########

## trust generated ca
cp /etc/cockpit/ws-certs.d/certificate.cert /etc/pki/ca-trust/source/anchors
runuser -l root -c  'update-ca-trust extract'
#########

## enable auto updates if selected
if [[ $LINUX_AUTOUPDATE == 1 ]]; then
  systemctl enable --now dnf-automatic.timer
fi

# load libraries for this VM "type"
load_libs "cloudsupport"

systemctl start docker
systemctl enable docker
chkconfig docker on

systemctl restart docker
docker login -u $DOCKER_HUB_USER -p $DOCKER_HUB_PWD

curl -s -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose > /dev/null
chmod +x /usr/local/bin/docker-compose

cd /root
tar xzvf /tmp/harbor.tgz

SUPPORT_VIP_DNS="$SUPPORT_HOST.$DOMAIN_NAME"
ADMIN_PWD=`cat /root/env_admin_pwd`
### Generate database pwd
HOWLONG=15 ## the number of characters
NEWPW=$(< /dev/urandom tr -dc A-Za-z0-9 | head -c100 | head -c$((20+($RANDOM%20))) | tail -c$((20+($RANDOM%20))) | head -c${HOWLONG});
###

cp /tmp/harbor.yml /root/harbor/harbor.yml
sed -i "s/{SUPPORT_HOST}/${SUPPORT_VIP_DNS}/g" /root/harbor/harbor.yml
sed -i "s/{SUPPORT_PASSWORD}/${ADMIN_PWD}/g" /root/harbor/harbor.yml
sed -i "s/{DATABASE_PASSWORD}/${NEWPW}/g" /root/harbor/harbor.yml
cd /root/harbor
chmod 700 *.sh

runuser -l root -c  "cd /root/harbor; ./install.sh --with-notary --with-trivy --with-chartmuseum"

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Cloudsupport VM ready for use"
##########################
#remove so as to not run again
rm -rf /etc/rc.d/rc.local

}

stop() {
    # code to stop app comes here 
    # example: killproc program_name
    /bin/true
}

case "$1" in 
    start)
       start
       ;;
    stop)
        /bin/true
       stop
       ;;
    restart)
       stop
       start
       ;;
    status)
        /bin/true
       # code to check status of app comes here 
       # example: status program_name
       ;;
    *)
       echo "Usage: $0 {start|stop|status|restart}"
esac

exit 0 
