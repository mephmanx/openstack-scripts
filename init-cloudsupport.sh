#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh

start() {
# code to start app comes here
# example: daemon program_name &
exec 1>/tmp/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

# load libraries for this VM "type"
load_libs "cloudsupport"

##### load secrets
load_secrets

chmod 777 /tmp/global_addresses.sh
source ./tmp/global_addresses.sh

systemctl start docker
systemctl enable docker
chkconfig docker on

systemctl restart docker
docker login -u $DOCKER_HUB_USER -p $DOCKER_HUB_PWD

curl -L "https://github.com/docker/compose/releases/download/1.27.4/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

cd /root

wget -O /tmp/harbor.tgz https://github.com/goharbor/harbor/releases/download/v2.2.2/harbor-offline-installer-v2.2.2.tgz
tar xzvf /tmp/harbor.tgz

SUPPORT_VIP_DNS="$SUPPORT_HOST.$DOMAIN_NAME"

wget -O /root/harbor/harbor.yml -d https://mephmanx:$GITHUB_TOKEN@raw.githubusercontent.com/mephmanx/openstack-scripts/master/harbor.yml
sed -i "s/{SUPPORT_HOST}/${SUPPORT_VIP_DNS}/g" /root/harbor/harbor.yml
sed -i "s/{SUPPORT_PASSWORD}/${SUPPORT_PASSWORD}/g" /root/harbor/harbor.yml
sed -i "s/{DATABASE_PASSWORD}/${DATABASE_PASSWORD}/g" /root/harbor/harbor.yml
cd /root/harbor
chmod 777 *.sh

runuser -l root -c  "cd /root/harbor; ./install.sh --with-notary --with-trivy --with-chartmuseum"

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
