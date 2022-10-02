#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/project_config.sh

# shellcheck disable=SC2120
start() {
# code to start app comes here
# example: daemon program_name &
exec 1> >(logger --priority user.notice --tag "$(basename "$0")") \
     2> >(logger --priority user.error --tag "$(basename "$0")")

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

SUPPORT_VIP_DNS="$SUPPORT_HOST.$INTERNAL_DOMAIN_NAME"

echo "{CENTOS_ADMIN_PWD_123456789012}" | kinit admin
ipa service-add HTTP/"$(hostname)"
ipa-getcert request \
          -K HTTP/"$(hostname)" \
          -f /tmp/harbor.crt \
          -k /tmp/harbor.key \
          -D "$(hostname)"

mv /tmp/docker-compose-"$DOCKER_COMPOSE_VERSION" /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

cd /root || exit
tar xzvf /tmp/harbor-"$HARBOR_VERSION".tgz
rm -rf /tmp/harbor-"$HARBOR_VERSION".tgz

mv /tmp/harbor.yml /root/harbor/harbor.yml
sed -i "s/{SUPPORT_HOST}/${SUPPORT_VIP_DNS}/g" /root/harbor/harbor.yml
sed -i "s/{SUPPORT_PASSWORD}/{CENTOS_ADMIN_PWD_123456789012}/g" /root/harbor/harbor.yml
sed -i "s/{DATABASE_PASSWORD}/$(generate_random_pwd 31)/g" /root/harbor/harbor.yml
cd /root/harbor || exit
chmod 700 ./*.sh

runuser -l root -c  "cd /root/harbor; ./install.sh --with-notary --with-trivy --with-chartmuseum"

sleep 30

### check for docker login success
## copy loop into startup script to verify start after vm reboot

runuser -l root -c  "cd /root/harbor; docker-compose down"
sleep 30
runuser -l root -c  "cd /root/harbor; ./prepare"
sleep 30

### build config_overwrite_json string to hardcode auth settings
sed -i 's/container_name: harbor-core/container_name: harbor-core\n    environment:\n      - CONFIG_OVERWRITE_JSON={\"ldap_verify_cert\":\"false\", \"auth_mode\":\"ldap_auth\",\"ldap_base_dn\":\"dc=cloud,dc=local\", \"ldap_search_dn\":\"cn=admin,dc=cloud,dc=local\",\"ldap_search_password\":\"{CENTOS_ADMIN_PWD_123456789012}\",\"ldap_url\":\"identity.cloud.local\", \"ldap_scope\":2}/g' /root/harbor/docker-compose.yml

runuser -l root -c  "cd /root/harbor; docker-compose up -d"
sleep 30


runuser -l root -c  "cd /root/harbor; docker-compose down"
sleep 30
runuser -l root -c  "cd /root/harbor; ./prepare"
sleep 30

### build config_overwrite_json string to hardcode auth settings
sed -i 's/container_name: harbor-core/container_name: harbor-core\n    environment:\n      - CONFIG_OVERWRITE_JSON={\"ldap_verify_cert\":\"false\", \"auth_mode\":\"ldap_auth\",\"ldap_base_dn\":\"dc=cloud,dc=local\", \"ldap_search_dn\":\"cn=admin,dc=cloud,dc=local\",\"ldap_search_password\":\"{CENTOS_ADMIN_PWD_123456789012}\",\"ldap_url\":\"identity.cloud.local\", \"ldap_scope\":2}/g' /root/harbor/docker-compose.yml

runuser -l root -c  "cd /root/harbor; docker-compose up -d"
sleep 30
## continue when docker login succeeds

telegram_notify  "Cloudsupport VM starting to process openstack images"
##########################
cat > /tmp/harbor.json << EOF
{"project_name": "kolla","metadata": {"public": "true"}}
EOF

etext=$(echo -n "admin:{CENTOS_ADMIN_PWD_123456789012}" | base64)
curl -k -H  "authorization: Basic $etext" -X POST -H "Content-Type: application/json" "https://$SUPPORT_VIP_DNS/api/v2.0/projects" -d @/tmp/harbor.json

rm -rf /tmp/harbor.json

curl -k --location --request POST "https://$SUPPORT_VIP_DNS/api/v2.0/registries" \
  --header "authorization: Basic $etext" \
  --header 'content-type: application/json' \
  --header "host: $SUPPORT_VIP_DNS" \
  -H 'Accept-Language: en-us' \
  -H 'Accept-Encoding: gzip, deflate, br' \
  -H "Referer: https://$SUPPORT_VIP_DNS/harbor/registries" \
  -H "Origin: https://$SUPPORT_VIP_DNS" \
  -H 'Connection: keep-alive' \
  --data-binary "{\"credential\":{\"type\":\"basic\"},\"description\":\"\",\"insecure\":true,\"name\":\"docker-hub\",\"type\":\"docker-hub\",\"url\":\"https://hub.docker.com\"}"

############  Create new proxy-cache cloudfoundry project
curl -k --location --request POST "https://$SUPPORT_VIP_DNS/api/v2.0/projects" \
  --header "authorization: Basic $etext" \
  --header 'content-type: application/json' \
  --header "host: $SUPPORT_VIP_DNS" \
  --data-binary "{\"project_name\":\"cloudfoundry\",\"registry_id\":1,\"metadata\":{\"public\":\"true\"},\"storage_limit\":-1}"

#### populate harbor with openstack images
#grafana fluentd zun not build

sleep 3
docker login -u admin -p "{CENTOS_ADMIN_PWD_123456789012}" "$SUPPORT_VIP_DNS"

#setup kolla docker rpm repo for build
mv /tmp/kolla_"$OPENSTACK_VERSION"_rpm_repo.tar.gz /var/www/html/
cd /var/www/html && tar xf /var/www/html/kolla_"$OPENSTACK_VERSION"_rpm_repo.tar.gz
rm -rf /var/www/html/kolla_"$OPENSTACK_VERSION"_rpm_repo.tar.gz
echo 'local rpm repo server setup finish!'

docker load < /tmp/centos-binary-base-"$OPENSTACK_VERSION".tar
docker load < /tmp/centos-source-kolla-toolbox.tar
docker load < /tmp/centos-source-zun-compute.tar
docker load < /tmp/centos-source-zun-wsproxy.tar
docker load < /tmp/centos-source-zun-api.tar
docker load < /tmp/centos-source-zun-cni-daemon.tar
docker load < /tmp/centos-source-kuryr-libnetwork.tar
docker load < /tmp/centos-binary-fluentd.tar
docker load < /tmp/centos-binary-grafana.tar
docker load < /tmp/centos-binary-elasticsearch-curator.tar
docker load < /tmp/pypi.tar

docker tag "$(docker images |grep pypi|awk '{print $3}')" "$SUPPORT_VIP_DNS"/library/pypi:latest

docker tag "$(docker images |grep centos-source-kolla-toolbox|awk '{print $3}')" "$SUPPORT_VIP_DNS"/kolla/centos-binary-kolla-toolbox:"$OPENSTACK_VERSION"

docker tag "$(docker images |grep centos-binary-fluentd|awk '{print $3}')" "$SUPPORT_VIP_DNS"/kolla/centos-binary-fluentd:"$OPENSTACK_VERSION"

docker tag "$(docker images |grep centos-binary-elasticsearch-curator|awk '{print $3}')" "$SUPPORT_VIP_DNS"/kolla/centos-binary-elasticsearch-curator:"$OPENSTACK_VERSION"

docker tag "$(docker images |grep centos-binary-grafana|awk '{print $3}')" "$SUPPORT_VIP_DNS"/kolla/centos-binary-grafana:"$OPENSTACK_VERSION"

docker tag "$(docker images |grep centos-source-zun-api|awk '{print $3}')" "$SUPPORT_VIP_DNS"/kolla/centos-source-zun-api:"$OPENSTACK_VERSION"

docker tag "$(docker images |grep centos-source-zun-compute|awk '{print $3}')" "$SUPPORT_VIP_DNS"/kolla/centos-source-zun-compute:"$OPENSTACK_VERSION"

docker tag "$(docker images |grep centos-source-zun-wsproxy|awk '{print $3}')" "$SUPPORT_VIP_DNS"/kolla/centos-source-zun-wsproxy:"$OPENSTACK_VERSION"

docker tag "$(docker images |grep centos-source-zun-cni-daemon|awk '{print $3}')" "$SUPPORT_VIP_DNS"/kolla/centos-source-zun-cni-daemon:"$OPENSTACK_VERSION"

docker tag "$(docker images |grep centos-source-kuryr-libnetwork|awk '{print $3}')" "$SUPPORT_VIP_DNS"/kolla/centos-source-kuryr-libnetwork:"$OPENSTACK_VERSION"

#setup local repo
cat > /tmp/kolla_local.repo <<EOF
[kolla_local]
name=kolla_local
baseurl=http://localhost:8080/kolla_$OPENSTACK_VERSION
enabled=1
gpgcheck=0
cost=100
EOF

mv /tmp/kolla_local.repo /etc/yum.repos.d/
yum install -y openstack-kolla
echo 'install openstack-kolla on local server finish!'

#setup local pypi server for offline pip install, pypi web server port is 9090 on harbor vm. root cache dir is /srv/pypi/.
# put pypi cached .tar.gz or .whl files in the /srv/pypi dir.
# centos-binary-base container image should have been config to use local pip server by /etc/pip.conf . all other images is based on base image.
mkdir -p /srv/pypi
tar -xf /tmp/harbor_python_modules.tar -C /srv/pypi

### remove files from tmp
rm -rf /tmp/*.tar

docker run -itd  --restart unless-stopped -e PYPI_EXTRA="--disable-fallback" -v /srv/pypi:/srv/pypi:rw -p 9090:80 --name pypi "$SUPPORT_VIP_DNS"/library/pypi:latest

#fix openstack-kolla issue for offline build
sed -i 's/version=.*, //' /usr/lib/python3.6/site-packages/kolla/image/build.py

# keystone image
sed -i 's/RUN dnf module/#RUN dnf module/' /usr/share/kolla/docker/keystone/keystone-base/Dockerfile.j2

if [[ $OPENSTACK_VERSION == "wallaby" ]]; then
  #neutron image
  sed -i 's#kolla_neutron_sudoers #kolla_neutron_sudoers \&\& cp /usr/share/neutron/api-paste.ini /etc/neutron #' /usr/share/kolla/docker/neutron/neutron-base/Dockerfile.j2
fi

#fix magnum bug
sed -i 's/USER magnum//' /usr/share/kolla/docker/magnum/magnum-conductor/Dockerfile.j2

cat <<EOF >> /usr/share/kolla/docker/magnum/magnum-conductor/Dockerfile.j2
RUN sed -i '242s|^$|      allowed_cidrs: ["$LB_NETWORK.0/8"]|' /usr/lib/python3.6/site-packages/magnum/drivers/swarm_fedora_atomic_v2/templates/swarmcluster.yaml
RUN sed -i '305s|^$|      allowed_cidrs: ["$LB_NETWORK.0/8"]|' /usr/lib/python3.6/site-packages/magnum/drivers/swarm_fedora_atomic_v1/templates/cluster.yaml

USER magnum
EOF

#fix swift config ring issue
echo "RUN rm -f /etc/swift/swift.conf" >> /usr/share/kolla/docker/swift/swift-base/Dockerfile.j2

#fluentd image
sed -i '105,121s/^/#/' /usr/share/kolla/docker/fluentd/Dockerfile.j2

#prometheus exporter offline fix
sed -i "s/^RUN curl.*$/RUN curl -o \/tmp\/memcached_exporter.tar.gz http:\/\/localhost:8080\/kolla_$OPENSTACK_VERSION\/prometheus_memcached_exporter.tar.gz \\\/" /usr/share/kolla/docker/prometheus/prometheus-memcached-exporter/Dockerfile.j2
sed -i "s/^RUN curl.*$/RUN curl -o \/tmp\/haproxy_exporter.tar.gz http:\/\/localhost:8080\/kolla_$OPENSTACK_VERSION\/prometheus_haproxy_exporter.tar.gz \\\/" /usr/share/kolla/docker/prometheus/prometheus-haproxy-exporter/Dockerfile.j2
sed -i "s/^RUN curl.*$/RUN curl -o \/tmp\/elasticsearch_exporter.tar.gz http:\/\/localhost:8080\/kolla_$OPENSTACK_VERSION\/prometheus_elasticsearch_exporter.tar.gz \\\/" /usr/share/kolla/docker/prometheus/prometheus-elasticsearch-exporter/Dockerfile.j2

docker tag kolla/centos-binary-base:"$OPENSTACK_VERSION" "$SUPPORT_VIP_DNS"/kolla/centos-binary-base:"$OPENSTACK_VERSION"

#kolla build config
if [[ "$OPENSTACK_VERSION" == "xena" ]]; then
  pip3 install --no-index --find-links="/srv/pypi" jinja2==3.0.3
  sed -i 's#centos8-amd64#centos/8/x86_64/#' /usr/share/kolla/docker/base/mariadb.repo
  sed -i "s/https:\/\/src.fedoraproject.org\/rpms\/mariadb\/raw\/\${mariadb_clustercheck_version}\/f\/clustercheck.sh/http:\/\/localhost:8080\/kolla_$OPENSTACK_VERSION\/clustercheck.sh/g" /usr/share/kolla/docker/mariadb/mariadb-base/Dockerfile.j2
fi
kolla-build --base-image kolla/centos-binary-base --base-tag "$OPENSTACK_VERSION" -t binary --openstack-release "$OPENSTACK_VERSION"  --tag "$OPENSTACK_VERSION" --cache --skip-existing --nopull --registry "$SUPPORT_VIP_DNS" barbican ceilometer cinder cron designate dnsmasq elasticsearch etcd glance gnocchi grafana hacluster haproxy heat horizon influxdb iscsid  keepalived keystone kibana logstash magnum  manila mariadb memcached multipathd neutron nova octavia openvswitch placement qdrouterd redis rabbitmq swift telegraf trove murano panko

#push images to harbor
for i in $(docker images |grep "$SUPPORT_VIP_DNS" |awk '{print $1}');do
  docker push "$i":"$(docker images |grep "$i"|head -n 1|awk '{print $2}')" ;
done

######
telegram_notify  "Cloudsupport VM finished processing openstack images, creating kolla vm"

## signaling to hypervisor that cloudsupport is finished
mkdir /tmp/empty_dir
cd /tmp/empty_dir || exit
python3 -m http.server "$CLOUDSUPPORT_SIGNAL" &
########################
#remove so as to not run again
rm -rf /etc/rc.d/rc.local
rm -rf /tmp/*.sh

cat > /etc/rc.d/rc.local <<EOF
#!/bin/bash

start() {

rm -rf /tmp/harbor-boot.log
exec 1>/tmp/harbor-boot.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x                             # tell sh to display commands before execution

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
