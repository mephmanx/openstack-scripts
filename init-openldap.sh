#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/project_config.sh
. /tmp/openstack-env.sh

start() {
# code to start app comes here
# example: daemon program_name &
exec 1>/root/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

### cleanup from previous boot
rm -rf /tmp/eth*
########

## enable auto updates if selected
if [[ $LINUX_AUTOUPDATE == 1 ]]; then
  systemctl enable --now dnf-automatic.timer
fi

#### add hypervisor host key to authorized keys
## this allows the hypervisor to ssh without password to openstack vms
runuser -l root -c 'cat /tmp/id_rsa.pub >> /root/.ssh/authorized_keys'
######

runuser -l root -c 'cp /tmp/id_rsa.key /root/.ssh/id_rsa'
runuser -l root -c 'cp /tmp/id_rsa.pub /root/.ssh/id_rsa.pub'

runuser -l root -c 'chmod 600 /root/.ssh/id_rsa'
runuser -l root -c 'chmod 600 /root/.ssh/id_rsa.pub'
runuser -l root -c 'chmod 600 /root/.ssh/authorized_keys'

dnf update -y

dnf install -y cyrus-sasl-devel make libtool autoconf libtool-ltdl-devel openssl-devel libdb-devel tar gcc perl perl-devel wget vim rsyslog

useradd -r -M -d /var/lib/openldap -u 55 -s /usr/sbin/nologin ldap

tar xzf /tmp/openldap.tgz -C /tmp
mkdir /tmp/openldap
mv /tmp/openldap*/* /tmp/openldap
cd /tmp/openldap

./configure --prefix=/usr --sysconfdir=/etc --disable-static \
    --enable-debug --with-tls=openssl --with-cyrus-sasl --enable-dynamic \
    --enable-crypt --enable-spasswd --enable-slapd --enable-modules \
    --enable-rlookups --enable-backends=mod --disable-ndb --disable-sql \
    --disable-shell --disable-bdb --disable-hdb --enable-overlays=mod --enable-wt=no

make depend

make

make install

mkdir /var/lib/openldap /etc/openldap/slapd.d
chown -R ldap:ldap /var/lib/openldap
chown root:ldap /etc/openldap/slapd.conf
chmod 640 /etc/openldap/slapd.conf

cat > /etc/systemd/system/slapd.service <<EOF
[Unit]
Description=OpenLDAP Server Daemon
After=syslog.target network-online.target
Documentation=man:slapd
Documentation=man:slapd-mdb

[Service]
Type=forking
PIDFile=/var/lib/openldap/slapd.pid
ExecStart=/usr/libexec/slapd -u ldap -g ldap -h 'ldap:/// ldapi:/// ldaps:///' -F /etc/openldap/slapd.d

[Install]
WantedBy=multi-user.target
EOF

cat > /var/run/slapd.pid <<EOF

EOF

cat > /var/run/slapd.args <<EOF

EOF

chown -R ldap:ldap /var/run/slapd.pid
chown -R ldap:ldap /var/run/slapd.args

cp /usr/share/doc/sudo/schema.OpenLDAP  /etc/openldap/schema/sudo.schema

cat << 'EOL' > /etc/openldap/schema/sudo.ldif
dn: cn=sudo,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: sudo
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.1 NAME 'sudoUser' DESC 'User(s) who may  run sudo' EQUALITY caseExactIA5Match SUBSTR caseExactIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.2 NAME 'sudoHost' DESC 'Host(s) who may run sudo' EQUALITY caseExactIA5Match SUBSTR caseExactIA5SubstringsMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.3 NAME 'sudoCommand' DESC 'Command(s) to be executed by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.4 NAME 'sudoRunAs' DESC 'User(s) impersonated by sudo (deprecated)' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.5 NAME 'sudoOption' DESC 'Options(s) followed by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.6 NAME 'sudoRunAsUser' DESC 'User(s) impersonated by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcAttributeTypes: ( 1.3.6.1.4.1.15953.9.1.7 NAME 'sudoRunAsGroup' DESC 'Group(s) impersonated by sudo' EQUALITY caseExactIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 )
olcObjectClasses: ( 1.3.6.1.4.1.15953.9.2.1 NAME 'sudoRole' SUP top STRUCTURAL DESC 'Sudoer Entries' MUST ( cn ) MAY ( sudoUser $ sudoHost $ sudoCommand $ sudoRunAs $ sudoRunAsUser $ sudoRunAsGroup $ sudoOption $ description ) )
EOL

cat > /etc/openldap/schema/ppolicy.ldif <<EOF
dn: cn=ppolicy,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: ppolicy
olcAttributeTypes: {0}( 1.3.6.1.4.1.42.2.27.8.1.1 NAME 'pwdAttribute' EQUALITY
  objectIdentifierMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.38 )
olcAttributeTypes: {1}( 1.3.6.1.4.1.42.2.27.8.1.2 NAME 'pwdMinAge' EQUALITY in
 tegerMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
olcAttributeTypes: {2}( 1.3.6.1.4.1.42.2.27.8.1.3 NAME 'pwdMaxAge' EQUALITY in
 tegerMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
olcAttributeTypes: {3}( 1.3.6.1.4.1.42.2.27.8.1.4 NAME 'pwdInHistory' EQUALITY
  integerMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
olcAttributeTypes: {4}( 1.3.6.1.4.1.42.2.27.8.1.5 NAME 'pwdCheckQuality' EQUAL
 ITY integerMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
olcAttributeTypes: {5}( 1.3.6.1.4.1.42.2.27.8.1.6 NAME 'pwdMinLength' EQUALITY
  integerMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
olcAttributeTypes: {6}( 1.3.6.1.4.1.42.2.27.8.1.7 NAME 'pwdExpireWarning' EQUA
 LITY integerMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
olcAttributeTypes: {7}( 1.3.6.1.4.1.42.2.27.8.1.8 NAME 'pwdGraceAuthNLimit' EQ
 UALITY integerMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
olcAttributeTypes: {8}( 1.3.6.1.4.1.42.2.27.8.1.9 NAME 'pwdLockout' EQUALITY b
 ooleanMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.7 SINGLE-VALUE )
olcAttributeTypes: {9}( 1.3.6.1.4.1.42.2.27.8.1.10 NAME 'pwdLockoutDuration' E
 QUALITY integerMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
olcAttributeTypes: {10}( 1.3.6.1.4.1.42.2.27.8.1.11 NAME 'pwdMaxFailure' EQUAL
 ITY integerMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE )
olcAttributeTypes: {11}( 1.3.6.1.4.1.42.2.27.8.1.12 NAME 'pwdFailureCountInter
 val' EQUALITY integerMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.27 SINGLE-VALUE
 )
olcAttributeTypes: {12}( 1.3.6.1.4.1.42.2.27.8.1.13 NAME 'pwdMustChange' EQUAL
 ITY booleanMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.7 SINGLE-VALUE )
olcAttributeTypes: {13}( 1.3.6.1.4.1.42.2.27.8.1.14 NAME 'pwdAllowUserChange'
 EQUALITY booleanMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.7 SINGLE-VALUE )
olcAttributeTypes: {14}( 1.3.6.1.4.1.42.2.27.8.1.15 NAME 'pwdSafeModify' EQUAL
 ITY booleanMatch SYNTAX 1.3.6.1.4.1.1466.115.121.1.7 SINGLE-VALUE )
olcAttributeTypes: {15}( 1.3.6.1.4.1.4754.1.99.1 NAME 'pwdCheckModule' DESC 'L
 oadable module that instantiates "check_password() function' EQUALITY caseExa
 ctIA5Match SYNTAX 1.3.6.1.4.1.1466.115.121.1.26 SINGLE-VALUE )
olcObjectClasses: {0}( 1.3.6.1.4.1.4754.2.99.1 NAME 'pwdPolicyChecker' SUP top
  AUXILIARY MAY pwdCheckModule )
olcObjectClasses: {1}( 1.3.6.1.4.1.42.2.27.8.2.1 NAME 'pwdPolicy' SUP top AUXI
 LIARY MUST pwdAttribute MAY ( pwdMinAge $ pwdMaxAge $ pwdInHistory $ pwdCheck
 Quality $ pwdMinLength $ pwdExpireWarning $ pwdGraceAuthNLimit $ pwdLockout $
  pwdLockoutDuration $ pwdMaxFailure $ pwdFailureCountInterval $ pwdMustChange
  $ pwdAllowUserChange $ pwdSafeModify ) )
EOF

slapadd -n 0 -F /etc/openldap/slapd.d -l /etc/openldap/slapd.ldif

chown -R ldap:ldap /etc/openldap/slapd.d
systemctl daemon-reload
systemctl enable --now slapd

cat > /tmp/enable-ldap-log.ldif <<EOF
dn: cn=config
changeType: modify
replace: olcLogLevel
olcLogLevel: stats
EOF

ldapmodify -Y external -H ldapi:/// -f /tmp/enable-ldap-log.ldif
ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config "(objectClass=olcGlobal)" olcLogLevel -LLL -Q
echo "local4.* /var/log/slapd.log" >> /etc/rsyslog.conf
systemctl restart rsyslog

echo `slappasswd -g` > /tmp/passwd.txt
chmod 600 /tmp/passwd.txt
PWD=`slappasswd -T /tmp/passwd.txt`

cat > /tmp/rootdn.ldif <<EOF
dn: olcDatabase=mdb,cn=config
objectClass: olcDatabaseConfig
objectClass: olcMdbConfig
olcDatabase: mdb
olcDbMaxSize: 42949672960
olcDbDirectory: /var/lib/openldap
olcSuffix: dc=ldapmaster,dc=lyonsgroup,dc=family
olcRootDN: cn=admin,dc=ldapmaster,dc=lyonsgroup,dc=family
olcRootPW: $PWD
olcDbIndex: uid pres,eq
olcDbIndex: cn,sn pres,eq,approx,sub
olcDbIndex: mail pres,eq,sub
olcDbIndex: objectClass pres,eq
olcDbIndex: loginShell pres,eq
olcDbIndex: sudoUser,sudoHost pres,eq
olcAccess: to attrs=userPassword,shadowLastChange,shadowExpire
  by self write
  by anonymous auth
  by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by dn.subtree="ou=system,dc=ldapmaster,dc=lyonsgroup,dc=family" read
  by * none
olcAccess: to dn.subtree="ou=system,dc=ldapmaster,dc=lyonsgroup,dc=family" by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by * none
olcAccess: to dn.subtree="dc=ldapmaster,dc=lyonsgroup,dc=family" by dn.subtree="gidNumber=0+uidNumber=0,cn=peercred,cn=external,cn=auth" manage
  by users read
  by * none
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/rootdn.ldif

cp /tmp/id_rsa.crt /etc/pki/tls/ldapserver.crt
cp /tmp/id_rsa.key /etc/pki/tls/ldapserver.key
chown ldap:ldap /etc/pki/tls/{ldapserver.crt,ldapserver.key}

cat > /tmp/add-tls.ldif <<EOF
dn: cn=config
changetype: modify
add: olcTLSCACertificateFile
olcTLSCACertificateFile: /etc/pki/tls/ldapserver.crt
-
add: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/pki/tls/ldapserver.key
-
add: olcTLSCertificateFile
olcTLSCertificateFile: /etc/pki/tls/ldapserver.crt
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/add-tls.ldif
echo "TLS_CACERT     /etc/pki/tls/ldapserver.crt" >> /etc/openldap/ldap.conf

cat > /tmp/basedn.ldif <<EOF
dn: dc=ldapmaster,dc=lyonsgroup,dc=family
objectClass: dcObject
objectClass: organization
objectClass: top
o: lyonsgroup
dc: ldapmaster

dn: ou=groups,dc=ldapmaster,dc=lyonsgroup,dc=family
objectClass: organizationalUnit
objectClass: top
ou: groups

dn: ou=people,dc=ldapmaster,dc=lyonsgroup,dc=family
objectClass: organizationalUnit
objectClass: top
ou: people
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/basedn.ldif

cat > /tmp/users.ldif <<EOF
dn: uid=pfsense,ou=people,dc=ldapmaster,dc=lyonsgroup,dc=family
objectClass: inetOrgPerson
objectClass: posixAccount
objectClass: shadowAccount
uid: pfsense
cn: pfsense
sn: pfsense
loginShell: /bin/bash
uidNumber: 10000
gidNumber: 10000
homeDirectory: /home/pfsense
shadowMax: 60
shadowMin: 1
shadowWarning: 7
shadowInactive: 7
shadowLastChange: 0

dn: cn=pfsense,ou=groups,dc=ldapmaster,dc=lyonsgroup,dc=family
objectClass: posixGroup
cn: pfsense
gidNumber: 10000
memberUid: pfsense
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/users.ldif

echo `slappasswd -g` > /tmp/pfsense.txt
chmod 600 /tmp/pfsense.txt

ldappasswd -H ldapi:/// -Y EXTERNAL -S "uid=pfsense,ou=people,dc=ldapmaster,dc=lyonsgroup,dc=family" -T /tmp/pfsense.txt

echo `slappasswd -g` > /tmp/bind.txt
chmod 600 /tmp/bind.txt
BIND_PWD=`slappasswd -T /tmp/bind.txt`

cat > /tmp/bindDNuser.ldif <<EOF
dn: ou=system,dc=ldapmaster,dc=lyonsgroup,dc=family
objectClass: organizationalUnit
objectClass: top
ou: system

dn: cn=readonly,ou=system,dc=ldapmaster,dc=lyonsgroup,dc=family
objectClass: organizationalRole
objectClass: simpleSecurityObject
cn: readonly
userPassword: $BIND_PWD
description: Bind DN user for LDAP Operations
EOF

ldapadd -Y EXTERNAL -H ldapi:/// -f /tmp/bindDNuser.ldif

dnf install -y php php-cgi php-mbstring php-common php-pear php-{gd,json,zip} php-ldap git
git clone https://github.com/breisig/phpLDAPadmin.git /usr/share/phpldapadmin
cp /usr/share/phpldapadmin/config/config.php{.example,}

chown -R apache:apache /usr/share/phpldapadmin

cat > /etc/httpd/conf.d/phpldapadmin.conf <<EOF
Alias /phpldapadmin /usr/share/phpldapadmin/htdocs

<Directory /usr/share/phpldapadmin/htdocs>
  <IfModule mod_authz_core.c>
    Require all granted
  </IfModule>
</Directory>
EOF

setsebool -P httpd_can_network_connect 1
setsebool -P httpd_can_connect_ldap 1
setsebool -P authlogin_nsswitch_use_ldap 1
setsebool -P nis_enabled 1

systemctl enable --now httpd

telegram_notify $TELEGRAM_API $TELEGRAM_CHAT_ID "Openldap VM ready for use"
##########################
#remove so as to not run again
rm -rf /etc/rc.d/rc.local

}

stop() {
    # code to stop app comes here 
    # example: killproc program_name
    /bin/true
}

case "$1" in 
    start)
       start
       ;;
    stop)
        /bin/true
       stop
       ;;
    restart)
       stop
       start
       ;;
    status)
        /bin/true
       # code to check status of app comes here 
       # example: status program_name
       ;;
    *)
       echo "Usage: $0 {start|stop|status|restart}"
esac

exit 0 
