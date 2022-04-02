#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/project_config.sh

start() {
# code to start app comes here
# example: daemon program_name &
exec 1>/root/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x                             # tell sh to display commands before execution

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

telegram_notify  "Cloudsupport VM ready for use"
##########################
cat > /tmp/harbor.json << EOF
{"project_name": "kolla","metadata": {"public": "true"}}
EOF

harbor_api_password=`echo -n admin:$ADMIN_PWD|base64`
cd /tmp
curl -k -H  "authorization: Basic $harbor_api_password" -X POST -H "Content-Type: application/json" "https://$SUPPORT_VIP_DNS/api/v2.0/projects" -d @harbor.json

#### populate harbor with openstack images
#grafana fluentd zun not build
source /tmp/project_config.sh

cat > /etc/docker/daemon.json << EOF
{
 "insecure-registries": ["SUPPORT_VIP_DNS"]
}

EOF

sleep 3
docker login -u admin -p $ADMIN_PWD $SUPPORT_VIP_DNS

#setup repo server
sed -i 's/Listen 80/Listen 8080/' /etc/httpd/conf/httpd.conf
systemctl restart httpd

#setup kolla docker rpm repo for build
mv /tmp/kolla_w_rpm_repo.tar.gz /var/www/html/
cd /var/www/html && tar xf /var/www/html/kolla_w_rpm_repo.tar.gz
echo 'local rpm repo server setup finish!'

docker load < /tmp/centos-binary-base-w.tar
docker load < /tmp/centos-source-kolla-toolbox.tar
docker load < /tmp/centos-source-zun-compute.tar
docker load < /tmp/centos-source-zun-wsproxy.tar
docker load < /tmp/centos-source-zun-api.tar
docker load < /tmp/centos-source-zun-cni-daemon.tar
docker load < /tmp/centos-source-kuryr-libnetwork.tar
docker load < /tmp/centos-binary-fluentd.tar
docker load < /tmp/centos-binary-grafana.tar
docker load < /tmp/centos-binary-elasticsearch-curator.tar

docker tag `docker images |grep centos-source-kolla-toolbox|awk '{print $3}'` $SUPPORT_VIP_DNS/kolla/centos-binary-kolla-toolbox:wallaby

docker tag `docker images |grep centos-binary-fluentd|awk '{print $3}'` $SUPPORT_VIP_DNS/kolla/centos-binary-fluentd:wallaby

docker tag `docker images |grep centos-binary-elasticsearch-curator|awk '{print $3}'` $SUPPORT_VIP_DNS/kolla/centos-binary-elasticsearch-curator:wallaby

docker tag `docker images |grep centos-binary-grafana|awk '{print $3}'` $SUPPORT_VIP_DNS/kolla/centos-binary-grafana:wallaby

docker tag `docker images |grep centos-source-zun-api|awk '{print $3}'` $SUPPORT_VIP_DNS/kolla/centos-source-zun-api:wallaby

docker tag `docker images |grep centos-source-zun-compute|awk '{print $3}'` $SUPPORT_VIP_DNS/kolla/centos-source-zun-compute:wallaby

docker tag `docker images |grep centos-source-zun-wsproxy|awk '{print $3}'` $SUPPORT_VIP_DNS/kolla/centos-source-zun-wsproxy:wallaby

docker tag `docker images |grep centos-source-zun-cni-daemon|awk '{print $3}'` $SUPPORT_VIP_DNS/kolla/centos-source-zun-cni-daemon:wallaby

docker tag `docker images |grep centos-source-kuryr-libnetwork|awk '{print $3}'` $SUPPORT_VIP_DNS/kolla/centos-source-kuryr-libnetwork:wallaby

#setup local repo
cat > /tmp/local.repo <<EOF
[kolla_local]
name=kolla_local
baseurl=http://localhost:8080/kolla_wallaby
enabled=1
gpgcheck=0
EOF

cp /tmp/local.repo /etc/yum.repos.d/
yum install -y openstack-kolla
echo 'install openstack-kolla on local server finish!'

#fix openstack-kolla issue for offline build
sed -i 's/version=.*, //' /usr/lib/python3.6/site-packages/kolla/image/build.py

#kolla docker file custom for offline build

# keystone image
sed -i 's/RUN dnf module/#RUN dnf module/' /usr/share/kolla/docker/keystone/keystone-base/Dockerfile.j2
#neutron image
sed -i 's#kolla_neutron_sudoers #kolla_neutron_sudoers \&\& cp /usr/share/neutron/api-paste.ini /etc/neutron #' /usr/share/kolla/docker/neutron/neutron-base/Dockerfile.j2

#fix centos 8 install issue
sed -i "s/'python3-sqlalchemy-collectd',//" /usr/share/kolla/docker/openstack-base/Dockerfile.j2

#fluentd image
sed -i '105,121s/^/#/' /usr/share/kolla/docker/fluentd/Dockerfile.j2
#grafana image

docker tag localhost/kolla/centos-binary-base:wallaby $SUPPORT_VIP_DNS/kolla/centos-binary-base:wallaby

#kolla build config
kolla-build --base-image localhost/kolla/centos-binary-base --base-tag wallaby -t binary --openstack-release wallaby  --tag wallaby --cache --skip-existing --nopull --registry $SUPPORT_VIP_DNS barbican ceilometer cinder cron designate dnsmasq elasticsearch etcd glance gnocchi grafana hacluster haproxy heat horizon influxdb iscsid  keepalived keystone kibana logstash magnum  manila mariadb memcached multipathd neutron nova octavia openvswitch placement qdrouterd redis rabbitmq swift telegraf trove

#push images to harbor
for i in `docker images |grep $SUPPORT_VIP_DNS|awk '{print $1}'`;do docker push $i:wallaby ;done

######
export etext=`echo -n "admin:{CENTOS_ADMIN_PWD_123456789012}" | base64`
#remove so as to not run again
rm -rf /etc/rc.d/rc.local

cat > /etc/rc.d/rc.local <<EOF
#!/bin/bash

. /tmp/project_config.sh

start() {
SUPPORT_VIP_DNS="$SUPPORT_HOST.$INTERNAL_DOMAIN_NAME"
rm -rf /tmp/harbor-boot.log
exec 1>/tmp/harbor-boot.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

sleep 30

status_code=\$(curl https://$SUPPORT_VIP_DNS/api/v2.0/projects/2 --write-out %{http_code} -k --silent --output /dev/null -H "authorization: Basic $etext")
cd /root/harbor
while [ "\$status_code" -ne 200 ] ; do
  docker-compose down
  sleep 20;
  docker-compose up -d
  sleep 30;
  status_code=\$(curl https://$SUPPORT_VIP_DNS/api/v2.0/projects/2 --write-out %{http_code} -k --silent --output /dev/null -H "authorization: Basic $etext")
done
}

stop() {
    # code to stop app comes here
    # example: killproc program_name
    /bin/true
}

case "\$1" in
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
