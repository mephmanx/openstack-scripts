FROM centos:8
MAINTAINER chris@lyonsgroup.family
RUN yum install -y git
RUN mkdir /root/openstack-scripts
COPY ./*.* /root/openstack-scripts
ENTRYPOINT ["/root/openstack-scripts/tookbox-kvm-openstack.sh"]
