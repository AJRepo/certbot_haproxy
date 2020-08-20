#!/bin/bash

API_KEY=YOUR_API_KEY_HERE
API_URL="https://api.dreamhost.com/"

#DOMAIN=$(expr match "$CERTBOT_DOMAIN" '.*\.\(.*\..*\)')
DOMAIN=$(echo "$CERTBOT_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')

UUID=$(uuidgen)
recordName="_acme-challenge.${CERTBOT_DOMAIN}"
recordValue="${CERTBOT_VALIDATION}"

LINK="${API_URL}?cmd=dns-remove_record&type=TXT&value=${recordValue}&record=${recordName}&key=${API_KEY}&unique_id=${UUID}"

RESPONSE=$(wget -O- -q "$LINK")
if ! (echo "$RESPONSE" | grep -q 'success'); then
  echo "ERROR: $RESPONSE"
  exit 1
fi

echo "Dreamhost $DOMAIN TXT removal Success: $RESPONSE"
