FROM centos:8
MAINTAINER chris@lyonsgroup.family
RUN yum install -y git
RUN git clone https://github.com/mephmanx/openstack-setup.git /root/openstack-setup
COPY * /root/openstack-scripts
CMD ["/root/openstack/scripts/tookbox-kvm-openstack.sh /root/openstack-setup/openstack-env.sh"]
