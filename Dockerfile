FROM centos:8
MAINTAINER chris@lyonsgroup.family
RUN yum install -y git
COPY ../openstack-setup/openstack-env.sh /root/openstack-scripts
COPY * /root/openstack-scripts
CMD ["/root/openstack/scripts/tookbox-kvm-openstack.sh /root/openstack-scripts/openstack-env.sh"]
