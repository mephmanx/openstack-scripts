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
yum -y install epel-release
yum update -y

yum install -y perl \
              yum-utils \
              cockpit \
              wget \
              git \
              python3-devel \
              python38 \
              make \
              ruby \
              ruby-devel \
              gcc-c++ \
              mysql-devel \
              nodejs \
              mysql-server \
              open-vm-tools \
              cockpit-machines \
              cockpit-networkmanager \
              cockpit-packagekit \
              cockpit-storaged

dnf module enable idm:DL1 -y
dnf distro-sync -y
dnf update -y
#####

## enable auto updates if selected
if [[ $LINUX_AUTOUPDATE == 1 ]]; then
  dnf install -y dnf-automatic

  cat > /etc/dnf/automatic.conf <<EOF
[commands]
upgrade_type = default
random_sleep = 0
network_online_timeout = 60
download_updates = yes
apply_updates = yes
EOF

  systemctl enable --now dnf-automatic.timer
fi

mkdir /root/.ssh
## this allows openstack vm's to ssh to each other without password
runuser -l root -c 'cp /tmp/openstack-setup.key.pub /root/.ssh/authorized_keys'
#### add hypervisor host key to authorized keys
## this allows the hypervisor to ssh without password to openstack vms
runuser -l root -c 'cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys'
######
mv /tmp/openstack-setup.key.pub /root/.ssh/id_rsa.pub
mv /tmp/openstack-setup.key /root/.ssh/id_rsa
chmod 600 /root/.ssh/id_rsa
chmod 600 /root/.ssh/authorized_keys

# load libraries for this VM "type"
load_libs "cloudsupport"

systemctl start docker
systemctl enable docker
chkconfig docker on

systemctl restart docker
docker login -u $DOCKER_HUB_USER -p $DOCKER_HUB_PWD

cp /tmp/docker-compose /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

cd /root
tar xzvf /tmp/harbor.tgz

SUPPORT_VIP_DNS="$SUPPORT_HOST.$INTERNAL_DOMAIN_NAME"
ADMIN_PWD=`cat /root/env_admin_pwd`

cp /tmp/harbor.yml /root/harbor/harbor.yml
sed -i "s/{SUPPORT_HOST}/${SUPPORT_VIP_DNS}/g" /root/harbor/harbor.yml
sed -i "s/{SUPPORT_PASSWORD}/${ADMIN_PWD}/g" /root/harbor/harbor.yml
sed -i "s/{DATABASE_PASSWORD}/$(generate_random_pwd)/g" /root/harbor/harbor.yml
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
