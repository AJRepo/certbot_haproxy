#!/bin/bash

# Script to be called after a successful certbot renewal. Currently
# does nothing except send an email notification. Future work is to
# modify .pem files for HaProxy & restart if pre-checks are all ok.

#Assumptions:
#   HAPROXY pem files are stored in /etc/ssl/$TLSNAME/$TLSNAME.pem
#
#Additionally certbot will pass relevant environment variables to some hooks
#  not to all hooks: https://github.com/certbot/certbot/issues/6722
#  Documentation states the following are sent to RENEW hooks
#    CERTBOT_DOMAIN: The domain being authenticated
#    CERTBOT_VALIDATION: The validation string
#    CERTBOT_TOKEN: Resource name part of the HTTP-01 challenge (HTTP-01 only)
#    CERTBOT_REMAINING_CHALLENGES: Number of challenges remaining after the current challenge
#    CERTBOT_ALL_DOMAINS: A comma-separated list of all domains challenged for the current certificate
#  Confirmed DEPLOY Hook Variables
#    RENEWED_LINEAGE
#    RENEWED_DOMAINS (note: could be wildcard. E.g. *.domainname ) 
#  Varables that are NOT passed to deploy hooks
#    CERTBOT_CERT_PATH
#    CERTBOT_KEY_PATH
#    CERTBOT_ALL_DOMAINS
#    CERTBOT_DOMAIN


#Warning: hostname -A adds a space to the end of returned value(s)
FQDN=$(hostname -A | sed -e /\ /s///g)
HOST_DOMAIN=$(hostname -d | sed -e /\ /s///g)
FROM="<HaProxy@$FQDN"
#EMAIL_TO="postmaster@$HOST_DOMAIN"
EMAIL_TO="certbot@$HOST_DOMAIN"
MAIL="/usr/sbin/sendmail"
THIS_SCRIPT=${0}
#X3_FILE=$Z_BASE_DIR/ssl/letsencrypt/lets-encrypt-x3-cross-signed.pem.txt
DATETIME=$(date +%Y%m%d_%H%M%S)

MESSAGE_FILE="/tmp/haproxy_deploy.$(uuidgen).txt"
echo "Starting ${0} deploy hook" > "$MESSAGE_FILE"

THIS_DOMAIN=$(openssl x509 -in "$RENEWED_LINEAGE/cert.pem" -noout -text | grep DNS | awk -F: '{print $2}')
# $THIS_DOMAIN could be a wildcard "*.example.com" ...
THIS_CLEAN_DOMAIN=${THIS_DOMAIN/\*/"wildcard"}

#Make a backup
if mkdir -p "/etc/ssl/$THIS_CLEAN_DOMAIN/backup.$DATETIME"; then
  cp "/etc/ssl/$THIS_CLEAN_DOMAIN/*.pem" /etc/ssl/"$THIS_CLEAN_DOMAIN"/backup."$DATETIME"/
#else
#  echo "Not continuing because backup not made" >> $MESSAGE_FILE
#  exit 1;
fi

# Reload  HAProxy
if haproxy -c -f /etc/haproxy/haproxy.cfg; then 
  service haproxy reload
  echo "HAProxy reloaded" >> "$MESSAGE_FILE"
else
  echo "ERROR: check of haproxy config failed. Not restarting."
  echo "ERROR: check of haproxy config failed. Not restarting." >> "$MESSAGE_FILE"
  exit 1;
fi

########Notify about DEPLOY HOOK being called
echo "Subject: Letsencrypt Renewal on $FQDN
From: <$FROM>

The Letsencrypt Certificate(s) $RENEWED_DOMAINS has(have) been renewed and downloaded
and is(are) about to be deployed at $FQDN
The cert.pem file reports domain $THIS_DOMAIN

Some variables:
LINEAGE=$RENEWED_LINEAGE
RENEWED=$RENEWED_DOMAINS
THIS_DOMAIN=$THIS_DOMAIN
THIS_CLEAN_DOMAIN=$THIS_CLEAN_DOMAIN

This message generated by $THIS_SCRIPT" >> "$MESSAGE_FILE"
$MAIL -s "Letsencrypt Deploy Hook: $RENEWED_DOMAINS" -t "$EMAIL_TO" < "$MESSAGE_FILE"
#####################################
