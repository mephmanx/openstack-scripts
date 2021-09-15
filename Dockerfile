FROM centos:8
MAINTAINER chris@lyonsgroup.family
RUN yum install -y git
COPY * /root/openstack-scripts
ENTRYPOINT ["/root/openstack/scripts/tookbox-kvm-openstack.sh"]
