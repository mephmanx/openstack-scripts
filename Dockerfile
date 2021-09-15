FROM centos:8
MAINTAINER chris@lyonsgroup.family
RUN yum install -y zip sudo
RUN curl -o /tmp/centos8.iso https://vault.centos.org/8.3.2011/isos/x86_64/CentOS-8.3.2011-x86_64-minimal.iso -L
COPY * /tmp/openstack-scripts
WORKDIR /tmp/openstack-scripts
ENTRYPOINT ["/tmp/openstack-scripts/toolbox-kvm-openstack.sh"]
