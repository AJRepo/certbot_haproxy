#!/usr/bin/env bash

# This script is mostly obsolete. It was originally written to call certbot and 
# then deploy the .pem files for HaProxy. Now most of the functionality is in the
# deploy script 50_haproxy_deploy.sh . When put in /etc/letsencrypt/renewa-hooks/deploy/
# 50_haproxy_deploy.sh runs automatically when certbot registers/renews certs.
# 
# The one part that isn't obsolete is the wildcard DNS renewal for dreamhost. 
# A sample file now exists named: sample_wildcard_dreamhost_renew.sh 
##########################################################################
#Assumes HAPROXY pem files are stored in $HAPROXY_CRT_DIR/$TLSNAME/$TLSNAME.pem
#Assumes wildcard pem files are stored in $HAPROXY_CRT_DIR/$TLSNAME/wildcard.$TLSNAME.pem
#Assumes certbot manual hooks are in /etc/letsencrypt/manual-hooks/

#Success -> /etc/letsencrypt/renewal-hooks/deploy/50_haproxy.sh

#Permissions Required:
# * write permissions to $HAPROXY_CRT_DIR/$TLSNAME
# * certbot (write permissions to /etc/letsencrypt/live)
# * restart haproxy service

TLSNAME=""
FQDN=$(hostname -A | sed -e /\ /s///g)
HOST_DOMAIN=$(dnsdomainname | sed -e /\ /s///g)
FROM="HaProxy@$FQDN"
#REPLACE WITH YOUR EMAIL
#EMAIL_TO="certbot@example.com"
EMAIL_TO="certbot@$HOST_DOMAIN"
HAPROXY_CRT_DIR="/etc/ssl"
DEPLOY_SCRIPT="50_haproxy_deploy.sh"
MAIL="/usr/bin/mail"
WILDCARD=0
DATETIME=$(date +%Y%m%d_%H%M%S)

MESSAGE_FILE="/tmp/haproxy_deploy.$(uuidgen).txt"

########Notify about script being called ##############
echo "Subject: Letsencrypt Renewal on $HOST_DOMAIN site
From: <$FROM>
To: <$EMAIL_TO>

Renewal Script Called from Cron at $DATETIME

This message generated by $THIS_SCRIPT" > "$MESSAGE_FILE"

#Check Usage and Permissions
#####################################

if [ "$1" == "" ] || [[ ! "$1" = *.* ]]; then
  echo "Domain name blank or missing a dot "
  echo "Valid domain name is required as first argument:"
  echo "Usage: $0 SSL_certificate_name"
  exit
else
  TLSNAME=$1
  echo "About to renew $TLSNAME"
  echo "About to renew $TLSNAME" >> "$MESSAGE_FILE"
fi

#Must be run as a user with rights to certbot files and commands
if ! certbot certificates; then
  echo "This script must be run as a user with rights to certbot certificates" 1>&2
  exit 1
fi

#Must be run as a user with rights to haproxy files and commands
if ! systemctl --no-ask-password reload haproxy.service; then
  echo "This script must be run as a user with rights to haproxy reload." 1>&2
  exit 1
fi

if [ "$(dnsdomainname)" == "" ]; then
  echo "Error: dnsdomainname returns blank. Check /etc/hosts file for proper configuration"
  exit 1
fi

TOP=$(echo "$TLSNAME" | awk -F. '{print $1}')
if [[ "$TOP" == '*' ]]; then
  WILDCARD=1
  PEM_FILE="$HAPROXY_CRT_DIR/$TLSNAME/wildcard.$TLSNAME.pem"
else
  WILDCARD=0
  PEM_FILE="$HAPROXY_CRT_DIR/$TLSNAME/$TLSNAME.pem"
fi

if [ -d $HAPROXY_CRT_DIR/"$TLSNAME" ]; then
  if [ ! -w  $HAPROXY_CRT_DIR/"$TLSNAME" ]; then
    echo "This script must be run as a user with rights to write to haproxy certificate dir: $HAPROXY_CRT_DIR/$TLSNAME" 1>&2
    exit 1
  fi
  if [ ! -f "$PEM_FILE" ]; then
    HAPROXY_CRT_FILE_EXISTS=false
  else
    HAPROXY_CRT_FILE_EXISTS=true
    if [ ! -w "$PEM_FILE" ]; then
      echo "This script must be run as a user with rights to overwrite: $PEM_FILE" 1>&2
      exit 1
    fi
  fi
else
  HAPROXY_CRT_FILE_EXISTS=false
  if [ ! -w  $HAPROXY_CRT_DIR ]; then
    echo "This script must be run as a user with rights to write to haproxy certificate dir: $HAPROXY_CRT_DIR" 1>&2
    exit 1
  else
    mkdir -p "$HAPROXY_CRT_DIR/$TLSNAME"
  fi
fi

##Check CRT and KEY
# Example output of "sudo certbot certificates -d example.net"
#  Certificate Name: example.net
#    Domains: example.net
#    Expiry Date: 2020-12-15 20:03:02+00:00 (VALID: 89 days)
#    Certificate Path: /etc/letsencrypt/live/example.net/fullchain.pem
#    Private Key Path: /etc/letsencrypt/live/example.net/privkey.pem
CRT_PATH=$(certbot certificates -d "$TLSNAME" | grep "Certificate Path" | awk -F : '{print $2}' | sed -e /\ /s///)
KEY_PATH=$(certbot certificates -d "$TLSNAME" | grep "Private Key Path" | awk -F : '{print $2}' | sed -e /\ /s///)

if [[ $CRT_PATH == "" || $KEY_PATH == "" ]]; then
  echo "Error: CRT or KEY path is blank. Exiting."
  echo "Error: CRT or KEY path is blank. Exiting." >> "$MESSAGE_FILE"
  $MAIL -s "Error: Letsencrypt Deploy Hook: $RENEWED_DOMAINS" -t "$EMAIL_TO" < "$MESSAGE_FILE"
  exit 1
fi


##################################


if [[ $WILDCARD == 1 ]]; then
  PREFERRED_CHALLENGE="dns"
  #TODO: lookup NS record and set DNS provider apropriately
  DNS_PROVIDER="dreamhost"
else
  PREFERRED_CHALLENGE="http"
fi



# Renew the certificate
#certbot renew --force-renewal --tls-sni-01-port=8888

# If you are manually renewing all of your certificates, the --force-renewal flag may be helpful;
# it causes the expiration time of the certificate(s) to be ignored when considering renewal,
# and attempts to renew each and every installed certificate regardless of its age. (This form
# is not appropriate to run daily because each certificate will be renewed every day,
# which will quickly run into the certificate authority rate limit.)

#certbot -q certonly --standalone -d $TLSNAME --non-interactive --agree-tos --email $EMAIL_TO --http-01-port=8888  --preferred-challenges=$PREFERRED_CHALLENGE --force-renewal

if [[ $PREFERRED_CHALLENGE == "dns" ]]; then
  if ! CERTBOT_REPLY=$(certbot certonly -d "$TLSNAME" --agree-tos --manual \
      --email "$EMAIL_TO" \
      --preferred-challenges $PREFERRED_CHALLENGE \
      --manual-auth-hook /etc/letsencrypt/manual-hooks/${DNS_PROVIDER}_certbot_auth_hook.sh \
      --manual-cleanup-hook /etc/letsencrypt/manual-hooks/${DNS_PROVIDER}_certbot_cleanup_hook.sh \
      --manual-public-ip-logging-ok); then
    echo "ERROR: wildcard $PREFERRED_CHALLENGE at $DNS_PROVIDER renewal failed";
    echo "ERROR: wildcard $PREFERRED_CHALLENGE at $DNS_PROVIDER renewal failed" >> "$MESSAGE_FILE"
    $MAIL -s "Error: certbot renew" -t "$EMAIL_TO" < "$MESSAGE_FILE"
    exit 1;
  fi
else
  if ! CERTBOT_REPLY=$(certbot certonly --standalone -d "$TLSNAME" --non-interactive --agree-tos --email "$EMAIL_TO" --http-01-port=8888  --preferred-challenges=$PREFERRED_CHALLENGE) ; then
    echo "ERROR: http standalone renewal failed";
    echo "ERROR: http standalone renewal failed" >> "$MESSAGE_FILE"
    $MAIL -s "Error: certbot renew" -t "$EMAIL_TO" < "$MESSAGE_FILE"
    exit 1;
  fi
fi

#RESPONSES
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - Certificate not yet due for renewal; no action taken. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
if echo "$CERTBOT_REPLY" | grep "no action"; then
  echo "Certbot reports 'no action taken' - not due for renewal"
  echo "Certbot reports 'no action taken' - not due for renewal" >> "$MESSAGE_FILE"
  if $HAPROXY_CRT_FILE_EXISTS; then
    echo "No Cerbot renew and HaProxy file exists. no copying needed"
    echo "No Cerbot renew and HaProxy file exists. no copying needed" >> "$MESSAGE_FILE"
    $MAIL -s "Letsencrypt Renewal on $HOST_DOMAIN. no action " -t "$EMAIL_TO" < "$MESSAGE_FILE"
    exit 0;
  else
    echo "HaProxy CRT file does not exist. $PEM_FILE to be created."
    echo "HaProxy CRT file does not exist. $PEM_FILE to be created." >> "$MESSAGE_FILE"
  fi
fi

#Deploy a successfully renewed certificate
echo "Now call '$DEPLOY_SCRIPT $TLSNAME' or put $DEPLOY_SCRIPT in renewal-hooks"
echo "Renewed: Now call '$DEPLOY_SCRIPT $TLSNAME' or put $DEPLOY_SCRIPT in renewal-hooks" >> "$MESSAGE_FILE"

$MAIL -s "Letsencrypt Renewal on $HOST_DOMAIN. Success" -t "$EMAIL_TO" < "$MESSAGE_FILE"
