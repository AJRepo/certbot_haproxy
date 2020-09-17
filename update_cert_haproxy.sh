#!/usr/bin/env bash

#Assumes fully specified HAPROXY pem files are stored in $HAPROXY_CRT_DIR/$TLSNAME/$TLSNAME.pem
#Assumes wildcard HAPROXY pem files are stored in $HAPROXY_CRT_DIR/$TLSNAME/wildcard.$TLSNAME.pem
#Assumes certbot manual hooks are in /etc/letsencrypt/manual-hooks/

#Success -> /etc/letsencrypt/renewal-hooks/deploy/50_haproxy.sh

#Permissions Required:
# * write permissions to $HAPROXY_CRT_DIR/$TLSNAME
# * certbot (write permissions to /etc/letsencrypt/live)
# * restart haproxy service

TLSNAME=""
FQDN=$(hostname -A | sed -e /\ /s///g)
HOST_DOMAIN=$(hostname -d | sed -e /\ /s///g)
FROM="<HaProxy@$FQDN"
#REPLACE WITH YOUR EMAIL
#EMAIL_TO="certbot@example.com"
EMAIL_TO="certbot@$HOST_DOMAIN"
HAPROXY_CRT_DIR="/etc/ssl"
MAIL="/usr/bin/mail"
WILDCARD=0
DATETIME=$(date +%Y%m%d_%H%M%S)

MESSAGE_FILE="/tmp/haproxy_deploy.$(uuidgen).txt"

########Notify about script being called ##############
echo "Subject: Letsencrypt Renewal on $HOST_DOMAIN site
From: <$FROM>

Renewal Script Called from Cron

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

TOP=$(echo "$TLSNAME" | awk -F. '{print $1}')
if [[ "$TOP" == '*' ]]; then
  WILDCARD=1
  PEM_FILE="$HAPROXY_CRT_DIR/$TLSNAME/wildcard.$TLSNAME.pem"
else
  WILDCARD=0
  PEM_FILE="$HAPROXY_CRT_DIR/$TLSNAME/$TLSNAME.pem"
fi

if [ -d $HAPROXY_CRT_DIR/"$TLSNAME" ]; then
  HAPROXY_CRT_DIR_EXISTS=true
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
  HAPROXY_CRT_DIR_EXISTS=false
  HAPROXY_CRT_FILE_EXISTS=false
  if [ ! -w  $HAPROXY_CRT_DIR ]; then
    echo "This script must be run as a user with rights to write to haproxy certificate dir: $HAPROXY_CRT_DIR" 1>&2
    exit 1
  fi
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
    $MAIL -t "$EMAIL_TO" < "$MESSAGE_FILE"
    exit 1;
  fi
else
  if ! CERTBOT_REPLY=$(certbot certonly --standalone -d "$TLSNAME" --non-interactive --agree-tos --email "$EMAIL_TO" --http-01-port=8888  --preferred-challenges=$PREFERRED_CHALLENGE) ; then
    echo "ERROR: http standalone renewal failed";
    echo "ERROR: http standalone renewal failed" >> "$MESSAGE_FILE"
    $MAIL -t "$EMAIL_TO" < "$MESSAGE_FILE"
    exit 1;
  fi
fi

#RESPONSES
#- - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - Certificate not yet due for renewal; no action taken. - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
if echo "$CERTBOT_REPLY" | grep "no action"; then
  echo "Certbot reports 'no action taken' - not due for renewal"
  echo "Certbot reports 'no action taken' - not due for renewal" >> "$MESSAGE_FILE"
  if $HAPROXY_CRT_DIR_EXISTS && $HAPROXY_CRT_FILE_EXISTS; then
    echo "HaProxy file exists. no copying needed"
    echo "HaProxy file exists. no copying needed" >> "$MESSAGE_FILE"
    $MAIL -t "$EMAIL_TO" < "$MESSAGE_FILE"
    exit 0;
  else
    echo "HaProxy CRT file does not exist. $PEM_FILE to be created."
    echo "HaProxy CRT file does not exist. $PEM_FILE to be created." >> "$MESSAGE_FILE"
  fi
fi

#TODO: Move the following into 50_haproxy_deploy.sh

#Make a backup
if $HAPROXY_CRT_FILE_EXISTS && mkdir -p "$HAPROXY_CRT_DIR/$TLSNAME/backup.$DATETIME"; then
  cp $HAPROXY_CRT_DIR/"$TLSNAME"/*.pem $HAPROXY_CRT_DIR/"$TLSNAME"/backup."$DATETIME"/
fi

# Concatenate new cert files
# NOTE: If you TLS certs for a wildcard AND a base DNS domain with the same base name
# e.g. *.EXAMPLE.ORG and EXAMPLE.ORG
# then certbot will create the directories
# /etc/letsencrypt/live/EXAMPLE.ORG
# and
# /etc/letsencrypt/live/EXAMPLE.ORG-0001
# which means assuming the path = /etc/letsencrypt/live/$TLSNAME won't work
# and all of this needs to be moved into a deploy hook that has the pathname.
#
##Check Permissions
#$ sudo certbot certificates -d example.net
#  Certificate Name: example.net
#    Domains: example.net
#    Expiry Date: 2020-12-15 20:03:02+00:00 (VALID: 89 days)
#    Certificate Path: /etc/letsencrypt/live/example.net/fullchain.pem
#    Private Key Path: /etc/letsencrypt/live/example.net/privkey.pem
CRT_PATH=$(certbot certificates -d "$TLSNAME" | grep "Certificate Path" | awk -F : '{print $2}' | sed -e /\ /s///)
KEY_PATH=$(certbot certificates -d "$TLSNAME" | grep "Private Key Path" | awk -F : '{print $2}' | sed -e /\ /s///)

#echo "DEBUG: $CRT_PATH, $KEY_PATH, $PEM_FILE"

# TODO: move to tee to allow for being called from sudo
if [[ $WILDCARD == 0 ]]; then
  cat "$CRT_PATH" "$KEY_PATH" > "$PEM_FILE"
else
  cat "$CRT_PATH" "$KEY_PATH" > "$PEM_FILE"
fi

#shellcheck disable=SC2181
if [[ $? != 0 ]]; then
  echo "unable to copy pem files to $TLSNAME dir"
  exit 1
fi

# Reload  HAProxy
if haproxy -c -f /etc/haproxy/haproxy.cfg; then
  if systemctl --no-ask-password reload haproxy.service; then
    echo "$TLSNAME: systemctl reload haproxy.service" >> "$MESSAGE_FILE"
    $MAIL -t "$EMAIL_TO" < "$MESSAGE_FILE"
  else
    echo "ERROR: systemctl reload haproxy.service failed"
    exit 1
  fi
else
  echo "ERROR: check of haproxy config failed. Not restarting.";
  exit 1;
fi
