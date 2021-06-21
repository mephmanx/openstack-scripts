#!/bin/bash

#####  get HPE driver/software repo to pull latest drivers
####  Only if running on HP hardware!
cat > /etc/yum.repos.d/hp.repo <<EOF
[HP-spp]
name=HP Service Pack for ProLiant
baseurl=http://downloads.linux.hpe.com/SDR/repo/spp/RHEL/8.3/x86_64/current/
enabled=1
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/GPG-KEY-ssp

[HP-mcp]
name=HP Management Component Pack for ProLiant
baseurl=http://downloads.linux.hpe.com/SDR/repo/mcp/centos/8.1/x86_64/current/
enabled=1
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/GPG-KEY-mcp

[HP-sum]
name=HP Smart Update Manager
baseurl=http://downloads.linux.hpe.com/repo/hpsum/rhel/8/x86_64/current/
enabled=1
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/GPG-KEY-hpsum
EOF

wget http://downloads.linux.hpe.com/SDR/repo/spp/GPG-KEY-spp -O /etc/pki/rpm-gpg/GPG-KEY-spp
wget http://downloads.linux.hpe.com/SDR/repo/mcp/GPG-KEY-mcp -O /etc/pki/rpm-gpg/GPG-KEY-mcp
wget http://downloads.linux.hpe.com/SDR/repo/hpsum/GPG-KEY-mcp -O /etc/pki/rpm-gpg/GPG-KEY-hpsum

dnf --enablerepo=powertools install libidn-devel
dnf install libnsl
yum install libnsl.i686
yum install libnsl.so.1

yum install hp-health hp-snmp-agents hp-smh-templates hpsmh hponcfg
systemctl enable hp-health
systemctl enable snmpd
systemctl enable hpsmhd
service hp-health start
service snmpd start
service hpsmhd start
###########################

