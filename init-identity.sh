#!/bin/bash
# chkconfig: 2345 20 80
# description: Description comes here....
# ALWAYS have content in functions otherwise you get syntax errors!

# Source function library.
. /etc/init.d/functions
. /tmp/vm_functions.sh
. /tmp/project_config.sh

start() {
# code to start app comes here
# example: daemon program_name &
exec 1>/root/start-install.log 2>&1 # send stdout and stderr from rc.local to a log file
#set -x                             # tell sh to display commands before execution

########## Add call to the beginning of all rc.local scripts as this wait guarantees network availability
sleep 30
###########################

### system profile
tuned-adm profile virtual-guest
#############

### gen pwd's
DIR_PWD="{DIRECTORY_MGR_PWD_12345678901}"
ADMIN_PWD="{CENTOS_ADMIN_PWD_123456789012}"
##############

DIRECTORY_MANAGER_PASSWORD=$DIR_PWD
REALM_NAME=$(echo "$INTERNAL_DOMAIN_NAME" | tr '[:lower:]' '[:upper:]')
HOSTNAME=identity.$INTERNAL_DOMAIN_NAME

runuser -l root -c "echo '$IDENTITY_VIP $HOSTNAME' >> /etc/hosts"
runuser -l root -c "echo $HOSTNAME > /etc/hostname"
runuser -l root -c "sysctl kernel.hostname=$HOSTNAME"

# Configure freeipa
runuser -l root -c "ipa-server-install -p $DIRECTORY_MANAGER_PASSWORD \
                                        -a $ADMIN_PWD \
                                        -n $INTERNAL_DOMAIN_NAME \
                                        -r $REALM_NAME \
                                        --ip-address $IDENTITY_VIP \
                                        --mkhomedir \
                                        --setup-dns \
                                        --auto-reverse \
                                        --auto-forwarders \
                                        --no-dnssec-validation \
                                        --ntp-server=$GATEWAY_ROUTER_IP -U -q"

runuser -l root -c "ipa-dns-install --auto-forwarders --auto-reverse --no-dnssec-validation -U"
#Create user on ipa WITHOUT A PASSWORD - we don't need one since we'll be using ssh key
#Kinit session
echo $ADMIN_PWD | kinit admin

## run record adds here after kinint for auth
runuser -l root -c "ipa dnszone-mod $INTERNAL_DOMAIN_NAME. --allow-sync-ptr=TRUE"
runuser -l root -c "ipa dnsrecord-add $INTERNAL_DOMAIN_NAME. '*' --a-ip-address=$GATEWAY_ROUTER_IP"
runuser -l root -c "ipa dnsrecord-add $INTERNAL_DOMAIN_NAME. '$APP_INTERNAL_HOSTNAME' --a-ip-address=$INTERNAL_VIP"
runuser -l root -c "ipa dnsrecord-add $INTERNAL_DOMAIN_NAME. '$APP_EXTERNAL_HOSTNAME' --a-ip-address=$EXTERNAL_VIP"
runuser -l root -c "ipa dnsrecord-add $INTERNAL_DOMAIN_NAME. '$SUPPORT_HOST' --a-ip-address=$SUPPORT_VIP"
runuser -l root -c "ipa dnsrecord-add $INTERNAL_DOMAIN_NAME. _ntp._udp --srv-priority=0 --srv-weight=100 --srv-port=123 --srv-target=pfsense.$INTERNAL_DOMAIN_NAME."

#### groups
/usr/bin/ipa group-add cloud-admins
/usr/bin/ipa group-add openstack-admins
/usr/bin/ipa group-add vpn-users

#### users
/usr/bin/ipa user-add --first=Firstname --last=Lastname domain_admin --random

####  send random pwd over telegram
RANDOM_PWD=$(cat </root/start-install.log | grep 'Random password' | awk -F': ' '{print $2}')
telegram_debug_msg  "domain_admin random password is $RANDOM_PWD"

#Add sudo rules
/usr/bin/ipa sudorule-add sysadmin_sudo --hostcat=all --runasusercat=all --runasgroupcat=all --cmdcat=all
/usr/bin/ipa sudorule-add-user sysadmin_sudo --group cloud-admins

##### group memberships
/usr/bin/ipa group-add-member openstack-admins --users=domain_admin
/usr/bin/ipa group-add-member openstack-admins --users=admin
/usr/bin/ipa group-add-member vpn-users --users=domain_admin
/usr/bin/ipa group-add-member cloud-admins --users=domain_admin

# load subordinate CA profile in freeipa
cat > /tmp/subca.profile <<EOF
desc=This certificate profile is for enrolling Subordinate Certificate Authority certificates.
visible=true
enable=true
auth.instance_id=raCertAuth
classId=caEnrollImpl
enableBy=ipara
name=Manual Certificate Manager Subordinate Signing Certificate Enrollment
input.list=i1,i2
input.i1.class_id=certReqInputImpl
input.i2.class_id=submitterInfoInputImpl
output.list=o1
output.o1.class_id=certOutputImpl
policyset.list=caSubCertSet
policyset.caSubCertSet.list=1,2,3,4,5,6,8,9,10
policyset.caSubCertSet.1.constraint.class_id=subjectNameConstraintImpl
policyset.caSubCertSet.1.constraint.name=Subject Name Constraint
policyset.caSubCertSet.1.constraint.params.pattern=.*CN=.+
policyset.caSubCertSet.1.constraint.params.accept=true
policyset.caSubCertSet.1.default.class_id=userSubjectNameDefaultImpl
policyset.caSubCertSet.1.default.name=Subject Name Default
policyset.caSubCertSet.1.default.params.name=
policyset.caSubCertSet.2.constraint.class_id=validityConstraintImpl
policyset.caSubCertSet.2.constraint.name=Validity Constraint
policyset.caSubCertSet.2.constraint.params.range=7305
policyset.caSubCertSet.2.constraint.params.notBeforeCheck=false
policyset.caSubCertSet.2.constraint.params.notAfterCheck=false
policyset.caSubCertSet.2.default.class_id=caValidityDefaultImpl
policyset.caSubCertSet.2.default.name=CA Certificate Validity Default
policyset.caSubCertSet.2.default.params.range=7305
policyset.caSubCertSet.2.default.params.startTime=0
policyset.caSubCertSet.3.constraint.class_id=keyConstraintImpl
policyset.caSubCertSet.3.constraint.name=Key Constraint
policyset.caSubCertSet.3.constraint.params.keyType=-
policyset.caSubCertSet.3.constraint.params.keyParameters=1024,2048,3072,4096,nistp256,nistp384,nistp521
policyset.caSubCertSet.3.default.class_id=userKeyDefaultImpl
policyset.caSubCertSet.3.default.name=Key Default
policyset.caSubCertSet.4.constraint.class_id=noConstraintImpl
policyset.caSubCertSet.4.constraint.name=No Constraint
policyset.caSubCertSet.4.default.class_id=authorityKeyIdentifierExtDefaultImpl
policyset.caSubCertSet.4.default.name=Authority Key Identifier Default
policyset.caSubCertSet.5.constraint.class_id=basicConstraintsExtConstraintImpl
policyset.caSubCertSet.5.constraint.name=Basic Constraint Extension Constraint
policyset.caSubCertSet.5.constraint.params.basicConstraintsCritical=true
policyset.caSubCertSet.5.constraint.params.basicConstraintsIsCA=true
policyset.caSubCertSet.5.constraint.params.basicConstraintsMinPathLen=0
policyset.caSubCertSet.5.constraint.params.basicConstraintsMaxPathLen=0
policyset.caSubCertSet.5.default.class_id=basicConstraintsExtDefaultImpl
policyset.caSubCertSet.5.default.name=Basic Constraints Extension Default
policyset.caSubCertSet.5.default.params.basicConstraintsCritical=true
policyset.caSubCertSet.5.default.params.basicConstraintsIsCA=true
policyset.caSubCertSet.5.default.params.basicConstraintsPathLen=0
policyset.caSubCertSet.6.constraint.class_id=keyUsageExtConstraintImpl
policyset.caSubCertSet.6.constraint.name=Key Usage Extension Constraint
policyset.caSubCertSet.6.constraint.params.keyUsageCritical=true
policyset.caSubCertSet.6.constraint.params.keyUsageDigitalSignature=true
policyset.caSubCertSet.6.constraint.params.keyUsageNonRepudiation=true
policyset.caSubCertSet.6.constraint.params.keyUsageDataEncipherment=false
policyset.caSubCertSet.6.constraint.params.keyUsageKeyEncipherment=false
policyset.caSubCertSet.6.constraint.params.keyUsageKeyAgreement=false
policyset.caSubCertSet.6.constraint.params.keyUsageKeyCertSign=true
policyset.caSubCertSet.6.constraint.params.keyUsageCrlSign=true
policyset.caSubCertSet.6.constraint.params.keyUsageEncipherOnly=false
policyset.caSubCertSet.6.constraint.params.keyUsageDecipherOnly=false
policyset.caSubCertSet.6.default.class_id=keyUsageExtDefaultImpl
policyset.caSubCertSet.6.default.name=Key Usage Default
policyset.caSubCertSet.6.default.params.keyUsageCritical=true
policyset.caSubCertSet.6.default.params.keyUsageDigitalSignature=true
policyset.caSubCertSet.6.default.params.keyUsageNonRepudiation=true
policyset.caSubCertSet.6.default.params.keyUsageDataEncipherment=false
policyset.caSubCertSet.6.default.params.keyUsageKeyEncipherment=false
policyset.caSubCertSet.6.default.params.keyUsageKeyAgreement=false
policyset.caSubCertSet.6.default.params.keyUsageKeyCertSign=true
policyset.caSubCertSet.6.default.params.keyUsageCrlSign=true
policyset.caSubCertSet.6.default.params.keyUsageEncipherOnly=false
policyset.caSubCertSet.6.default.params.keyUsageDecipherOnly=false
policyset.caSubCertSet.8.constraint.class_id=noConstraintImpl
policyset.caSubCertSet.8.constraint.name=No Constraint
policyset.caSubCertSet.8.default.class_id=subjectKeyIdentifierExtDefaultImpl
policyset.caSubCertSet.8.default.name=Subject Key Identifier Extension Default
policyset.caSubCertSet.8.default.params.critical=false
policyset.caSubCertSet.9.constraint.class_id=signingAlgConstraintImpl
policyset.caSubCertSet.9.constraint.name=No Constraint
policyset.caSubCertSet.9.constraint.params.signingAlgsAllowed=SHA1withRSA,SHA256withRSA,SHA512withRSA,SHA1withDSA,SHA1withEC,SHA256withEC,SHA384withEC,SHA512withEC
policyset.caSubCertSet.9.default.class_id=signingAlgDefaultImpl
policyset.caSubCertSet.9.default.name=Signing Alg
policyset.caSubCertSet.9.default.params.signingAlg=-
policyset.caSubCertSet.9.constraint.class_id=noConstraintImpl
policyset.caSubCertSet.9.constraint.name=No Constraint
policyset.caSubCertSet.9.default.class_id=crlDistributionPointsExtDefaultImpl
policyset.caSubCertSet.9.default.name=CRL Distribution Points Extension Default
policyset.caSubCertSet.9.default.params.crlDistPointsCritical=false
policyset.caSubCertSet.9.default.params.crlDistPointsEnable_0=true
policyset.caSubCertSet.9.default.params.crlDistPointsIssuerName_0=CN=Certificate Authority,o=ipaca
policyset.caSubCertSet.9.default.params.crlDistPointsIssuerType_0=DirectoryName
policyset.caSubCertSet.9.default.params.crlDistPointsNum=1
policyset.caSubCertSet.9.default.params.crlDistPointsPointName_0=http://$HOSTNAME/ipa/crl/MasterCRL.bin
policyset.caSubCertSet.9.default.params.crlDistPointsPointType_0=MasterCRL
policyset.caSubCertSet.9.default.params.crlDistPointsReasons_0=
policyset.caSubCertSet.10.constraint.class_id=noConstraintImpl
policyset.caSubCertSet.10.constraint.name=No Constraint
policyset.caSubCertSet.10.default.class_id=authInfoAccessExtDefaultImpl
policyset.caSubCertSet.10.default.name=AIA Extension Default
policyset.caSubCertSet.10.default.params.authInfoAccessADEnable_0=true
policyset.caSubCertSet.10.default.params.authInfoAccessADLocationType_0=URIName
policyset.caSubCertSet.10.default.params.authInfoAccessADLocation_0=
policyset.caSubCertSet.10.default.params.authInfoAccessADMethod_0=1.3.6.1.5.5.7.48.1
policyset.caSubCertSet.10.default.params.authInfoAccessCritical=false
policyset.caSubCertSet.10.default.params.authInfoAccessNumADs=1
profileId=SubCA
EOF

ipa certprofile-import SubCA --store=true --file=/tmp/subca.profile --desc="Enrolling subordinate certificate authority certificates"
ipa host-add --force pfsense.$INTERNAL_DOMAIN_NAME
ipa service-add --force HTTP/pfsense.$INTERNAL_DOMAIN_NAME

# build pfsense CA and wildcard cert
cat > /tmp/sub-ca.cnf <<EOF
HOME			= .
oid_section		= new_oids
[ new_oids ]
tsa_policy1 = 1.2.3.4.1
tsa_policy2 = 1.2.3.4.5.6
tsa_policy3 = 1.2.3.4.5.7
[ ca ]
default_ca	= CA_default		# The default ca section
[ CA_default ]
dir		= /etc/pki/CA		# Where everything is kept
certs		= \$dir/certs		# Where the issued certs are kept
crl_dir		= \$dir/crl		# Where the issued crl are kept
database	= \$dir/index.txt	# database index file.
new_certs_dir	= \$dir/newcerts		# default place for new certs.
certificate	= \$dir/cacert.pem 	# The CA certificate
serial		= \$dir/serial 		# The current serial number
crlnumber	= \$dir/crlnumber	# the current crl number
crl		= \$dir/crl.pem 		# The current CRL
private_key	= \$dir/private/cakey.pem# The private key
RANDFILE	= \$dir/private/.rand	# private random number file
x509_extensions	= usr_cert		# The extentions to add to the cert
name_opt 	= ca_default		# Subject Name options
cert_opt 	= ca_default		# Certificate field options
default_days	= 365			# how long to certify for
default_crl_days= 30			# how long before next CRL
default_md	= sha256		# use SHA-256 by default
preserve	= no			# keep passed DN ordering
policy		= policy_match
[ policy_match ]
countryName		= optional
stateOrProvinceName	= optional
organizationName	= optional
organizationalUnitName	= optional
commonName		= supplied
emailAddress		= optional
[ policy_anything ]
countryName		= optional
stateOrProvinceName	= optional
localityName		= optional
organizationName	= optional
organizationalUnitName	= optional
commonName		= supplied
emailAddress		= optional
[ req ]
default_bits		= 4096
default_md		= sha256
default_keyfile 	= privkey.pem
distinguished_name	= req_distinguished_name
attributes		= req_attributes
x509_extensions	= v3_ca	# The extentions to add to the self signed cert
string_mask = utf8only
req_extensions = v3_req # The extensions to add to a certificate request
prompt = no
[ req_distinguished_name ]
0.organizationName		= $ORGANIZATION
commonName = pfsense.$INTERNAL_DOMAIN_NAME
[ req_attributes ]
[ usr_cert ]
basicConstraints=CA:FALSE
nsComment			= "OpenSSL Generated Certificate"
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
[ v3_req ]
basicConstraints = CA:TRUE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, keyCertSign
subjectAltName = @alt_names
[alt_names]
DNS.1 = pfsense.$INTERNAL_DOMAIN_NAME
[ v3_ca ]
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid:always,issuer
basicConstraints = CA:true
[ crl_ext ]
authorityKeyIdentifier=keyid:always
[ proxy_cert_ext ]
basicConstraints=CA:FALSE
nsComment			= "OpenSSL Generated Certificate"
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
proxyCertInfo=critical,language:id-ppl-anyLanguage,pathlen:3,policy:foo
[ tsa ]
default_tsa = tsa_config1	# the default TSA section
[ tsa_config1 ]
dir		= ./demoCA		# TSA root directory
serial		= \$dir/tsaserial	# The current serial number (mandatory)
crypto_device	= builtin		# OpenSSL engine to use for signing
signer_cert	= \$dir/tsacert.pem 	# The TSA signing certificate
certs		= \$dir/cacert.pem	# Certificate chain to include in reply
signer_key	= \$dir/private/tsakey.pem # The TSA private key (optional)
default_policy	= tsa_policy1		# Policy if request did not specify it
other_policies	= tsa_policy2, tsa_policy3	# acceptable policies (optional)
digests		= sha1, sha256, sha384, sha512	# Acceptable message digests (mandatory)
accuracy	= secs:1, millisecs:500, microsecs:100	# (optional)
clock_precision_digits  = 0	# number of digits after dot. (optional)
ordering		= yes	# Is ordering defined for timestamps?
tsa_name		= yes	# Must the TSA name be included in the reply?
ess_cert_id_chain	= no	# Must the ESS cert id chain be included?
EOF

mkdir /tmp/empty_dir

openssl genrsa -out /tmp/sub-ca.key 4096

file_length_pk=$(wc -c "/tmp/sub-ca.key" | awk -F' ' '{ print $1 }')
file_length_old=3243
while [ "$file_length_pk" != "$file_length_old" ]; do
  runuser -l root -c  "openssl genrsa -out /tmp/sub-ca.key 4096"
  file_length_pk=$(wc -c "/tmp/sub-ca.key" | awk -F' ' '{ print $1 }')
done

openssl rsa -in /tmp/sub-ca.key -out /tmp/empty_dir/sub-ca.key
openssl req -config /tmp/sub-ca.cnf -key /tmp/empty_dir/sub-ca.key -out /tmp/sub-ca.csr -new
runuser -l root -c  "ssh-keygen -f /tmp/empty_dir/sub-ca.key -y > /tmp/empty_dir/sub-ca.pub"

# fulfill the request
ipa cert-request --profile-id=SubCA --principal=HTTP/pfsense.$INTERNAL_DOMAIN_NAME /tmp/sub-ca.csr --certificate-out=/tmp/empty_dir/subca.cert

telegram_notify  "Identity VM ready for use"
## signaling to hypervisor that identity is finished

cd /tmp/empty_dir || exit
python3 -m http.server "$IDENTITY_SIGNAL" &
signal_pid=$!
cat > /tmp/pidfile <<EOF
$signal_pid
EOF

cat > /tmp/server.py <<EOF
#! /usr/bin/python3

import os
from http.server import BaseHTTPRequestHandler, HTTPServer # python3
class HandleRequests(BaseHTTPRequestHandler):
    def _set_headers(self):
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()

    def do_GET(self):
        self._set_headers()

        from os.path import exists
        from cryptography.hazmat.primitives import serialization as crypto_serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.backends import default_backend as crypto_default_backend

        if exists("/tmp/empty_dir/id_rsa") and exists("/tmp/empty_dir/id_rsa"):
          return

        key = rsa.generate_private_key(
          backend=crypto_default_backend(),
          public_exponent=65537,
          key_size=4096
        )

        private_key = key.private_bytes(
          crypto_serialization.Encoding.PEM,
          crypto_serialization.PrivateFormat.TraditionalOpenSSL,
          crypto_serialization.NoEncryption()
        )

        public_key = key.public_key().public_bytes(
          crypto_serialization.Encoding.OpenSSH,
          crypto_serialization.PublicFormat.OpenSSH
        )

        if not exists("/tmp/empty_dir/id_rsa"):
          f = open('/tmp/empty_dir/id_rsa', 'wb')
          f.write(private_key)
          f.close()

        if not exists("/tmp/empty_dir/id_rsa.pub"):
          f = open('/tmp/empty_dir/id_rsa.pub', 'wb')
          f.write(public_key)
          f.close()

    def do_POST(self):
        self._set_headers()
        resp=""
        pids=[]
        with open("/tmp/pidfile") as pidfile:
            for pid in pidfile:
                resp+="killing pid -> " + pid + "\n"
                pids.append(pid)
        self.wfile.write(bytes(resp, "utf-8"))
        os.remove("/tmp/pidfile")
        for pid in pids:
          os.system("kill -KILL  " + pid)

host = ''
port = 22222
HTTPServer((host, port), HandleRequests).serve_forever()
EOF

python3 /tmp/server.py &
echo "$!" >> /tmp/pidfile

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
