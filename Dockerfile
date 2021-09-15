FROM centos:8
MAINTAINER chris@lyonsgroup.family
COPY * /
ENTRYPOINT ["/toolbox-kvm-openstack.sh"]
