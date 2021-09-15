FROM centos:8
MAINTAINER chris@lyonsgroup.family
RUN yum install -y zip
COPY * /tmp/openstack-scripts
COPY openstack-setup.sh /tmp/openstack-env.sh
ENTRYPOINT ["/tmp/openstack-scripts/toolbox-kvm-openstack.sh"]
