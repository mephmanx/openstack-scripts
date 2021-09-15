FROM centos:8
MAINTAINER chris@lyonsgroup.family
RUN yum install -y zip
COPY * /tmp/openstack-scripts
RUN cd /tmp/openstack-scripts
ENTRYPOINT ["/tmp/openstack-scripts/toolbox-kvm-openstack.sh"]
