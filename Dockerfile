FROM centos:8
MAINTAINER chris@lyonsgroup.family
COPY * /
ENTRYPOINT ["/tookbox-kvm-openstack.sh"]
