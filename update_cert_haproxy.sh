#!/usr/bin/env bash

#Assumes fully specified HAPROXY pem files are stored in /etc/ssl/$TLSNAME/$TLSNAME.pem
#Assumes wildcard HAPROXY pem files are stored in /etc/ssl/$TLSNAME/wildcard.$TLSNAME.pem
#Assumes certbot manual hooks are in /etc/letsencrypt/manual-hooks/

#Success -> /etc/letsencrypt/renewal-hooks/deploy/50_haproxy.sh

#Permissions Required: 
# * write permissions to /etc/ssl/$TLSNAME
# * certbot (write permissions to /etc/letsencrypt/live)
# * restart haproxy service

TLSNAME=""
#REPLACE WITH YOUR EMAIL
EMAIL="certbot@example.com"
WILDCARD=0
DATETIME=$(date +%Y%m%d_%H%M%S)

#Must be run as a root user
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

if [ "$1" == "" ]; then
   echo "Domain name argument is required:"
   echo "Usage: update_cert fqdn"
   exit
else
   TLSNAME=$1
   echo "About to renew $TLSNAME"
fi

PREFERRED_CHALLENGE="http"

TOP=$(echo "$TLSNAME" | awk -F. '{print $1}')
if [[ "$TOP" == '*' ]]; then
  PREFERRED_CHALLENGE="dns"
  #TODO: lookup NS record and set DNS provider apropriately
  DNS_PROVIDER="dreamhost"
  WILDCARD=1
fi

# Renew the certificate
#certbot renew --force-renewal --tls-sni-01-port=8888

# If you are manually renewing all of your certificates, the --force-renewal flag may be helpful;
# it causes the expiration time of the certificate(s) to be ignored when considering renewal,
# and attempts to renew each and every installed certificate regardless of its age. (This form 
# is not appropriate to run daily because each certificate will be renewed every day,
# which will quickly run into the certificate authority rate limit.)

#certbot -q certonly --standalone -d $TLSNAME --non-interactive --agree-tos --email $EMAIL --http-01-port=8888  --preferred-challenges=$PREFERRED_CHALLENGE --force-renewal

if [[ $PREFERRED_CHALLENGE == "dns" ]]; then
  if ! CERTBOT_REPLY=$(certbot certonly -d "$TLSNAME" --agree-tos --manual \
      --email $EMAIL \
      --preferred-challenges $PREFERRED_CHALLENGE \
      --manual-auth-hook /etc/letsencrypt/manual-hooks/${DNS_PROVIDER}_certbot_auth_hook.sh \
      --manual-cleanup-hook /etc/letsencrypt/manual-hooks/${DNS_PROVIDER}_certbot_cleanup_hook.sh \
      --manual-public-ip-logging-ok); then
    echo "ERROR: wildcard $PREFERRED_CHALLENGE at $DNS_PROVIDER renewal failed";
    exit 1;
  fi
else
  if ! CERTBOT_REPLY=$(certbot certonly --standalone -d "$TLSNAME" --non-interactive --agree-tos --email $EMAIL --http-01-port=8888  --preferred-challenges=$PREFERRED_CHALLENGE) ; then
    echo "ERROR: http standalone renewal failed";
    exit 1;
  fi
fi

#RESPONSES
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - Certificate not yet due for renewal; no action taken. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
if echo "$CERTBOT_REPLY" | grep "no action"; then
  echo "Certbot reports 'no action taken' - not due for renewal"
  exit 0;
fi

#TODO: Move the following into 50_haproxy_deploy.sh

#Make a backup
mkdir -p "/etc/ssl/$TLSNAME/backup.$DATETIME"
cp /etc/ssl/"$TLSNAME"/*.pem /etc/ssl/"$TLSNAME"/backup."$DATETIME"/

# Concatenate new cert files
# TODO: move to tee to allow for being called from sudo
if [[ $WILDCARD == 0 ]]; then
  cat "/etc/letsencrypt/live/$TLSNAME/fullchain.pem" "/etc/letsencrypt/live/$TLSNAME/privkey.pem" > "/etc/ssl/$TLSNAME/$TLSNAME.pem"
else
  cat "/etc/letsencrypt/live/$TLSNAME/fullchain.pem" "/etc/letsencrypt/live/$TLSNAME/privkey.pem" > "/etc/ssl/$TLSNAME/wildcard.$TLSNAME.pem"
fi

#shellcheck disable=SC2181
if [[ $? != 0 ]]; then
  echo "unable to copy pem files to $TLSNAME dir"
  exit 1
fi

# Reload  HAProxy
if haproxy -c -f /etc/haproxy/haproxy.cfg; then 
  service haproxy reload
else
  echo "ERROR: check of haproxy config failed. Not restarting.";
  exit 1;
fi
