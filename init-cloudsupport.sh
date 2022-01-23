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

### libs
yum update -y
yum -y install epel-release yum-utils
yum update -y
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y perl \
              python3-devel \
              python38 \
              make \
              ruby \
              ruby-devel \
              gcc-c++ \
              mysql-devel \
              nodejs \
              mysql-server \
              unzip \
              gcc \
              openssl-devel \
              docker-ce \
              docker-ce-cli \
              containerd.io \
              tar \
              tpm-tools \
              httpd

## enable auto updates if selected
if [[ $LINUX_AUTOUPDATE == 1 ]]; then
  systemctl enable --now dnf-automatic.timer
fi

systemctl start docker
systemctl enable docker
chkconfig docker on

systemctl restart docker
docker login -u $DOCKER_HUB_USER -p $DOCKER_HUB_PWD

cp /tmp/docker-compose-$DOCKER_COMPOSE_VERSION /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

cd /root
tar xzvf /tmp/harbor-$HARBOR_VERSION.tgz

SUPPORT_VIP_DNS="$SUPPORT_HOST.$INTERNAL_DOMAIN_NAME"

cp /tmp/harbor.yml /root/harbor/harbor.yml
sed -i "s/{SUPPORT_HOST}/${SUPPORT_VIP_DNS}/g" /root/harbor/harbor.yml
sed -i "s/{SUPPORT_PASSWORD}/{CENTOS_ADMIN_PWD_123456789012}/g" /root/harbor/harbor.yml
sed -i "s/{DATABASE_PASSWORD}/$(generate_random_pwd 31)/g" /root/harbor/harbor.yml
cd /root/harbor
chmod 700 *.sh

runuser -l root -c  "cd /root/harbor; ./install.sh --with-notary --with-trivy --with-chartmuseum"

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Cloudsupport VM ready for use"
##########################
#remove so as to not run again
rm -rf /etc/rc.d/rc.local

cat > /etc/rc.d/rc.local <<EOF
#!/bin/bash

start() {
rm -rf /tmp/harbor-boot.log
exec 1>/tmp/harbor-boot.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

sleep 30
export etext=`echo -n "admin:NmU1OTFlMGRmMTZhZmYzYThiYWM5ZDU" | base64`
status_code=`curl https://$SUPPORT_VIP_DNS/api/v2.0/projects/2 --write-out %{http_code} -k --silent --output /dev/null -H "authorization: Basic $etext" `
cd /root/harbor
while [ "$status_code" -ne 200 ] ; do
  docker-compose down
  sleep 20;
  docker-compose up -d
  sleep 30;
  status_code=`curl https://$SUPPORT_VIP_DNS/api/v2.0/projects/2 --write-out %{http_code} -k --silent --output /dev/null -H "authorization: Basic $etext" `
done
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
EOF
chmod +x /etc/rc.d/rc.local
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
