FROM centos:8
MAINTAINER chris@lyonsgroup.family
RUN dnf update -y
RUN dnf install -y yum-utils createrepo syslinux genisoimage isomd5sum bzip2 curl file git wget unzip zip sudo
RUN curl -L -o /CentOS-Stream.iso http://isoredirect.centos.org/centos/8-stream/isos/x86_64/CentOS-Stream-8-x86_64-latest-boot.iso

RUN git clone https://github.com/mephmanx/centos-8-minimal.git /centos-build/
RUN cp /CentOS-Stream.iso /centos-build/
RUN chmod +x /centos-build/create_iso_in_container.sh && cd /centos-build/; ./create_iso_in_container.sh

ARG ENVFILE
COPY * /tmp/openstack-scripts/
RUN echo "$ENVFILE" > /root/openstack-env.sh
WORKDIR /tmp/openstack-scripts
ENTRYPOINT exec /tmp/openstack-scripts/toolbox-kvm-openstack.sh /root/openstack-env.sh
