#!/bin/bash
# 1. Put this script in /etc/letsencrypt/manual-hooks/
# 2. When you run certbot on a domain for the first time call it with 
#    --manual --manual-auth-hook /etc/letsencrypt/manual-hooks/SCRIPTNAME.sh
# 3. When certbot renews it will call with that same argument as saved in /etc/letsencrypt/renewal/$CERTBOT_DOMAIN.conf

API_KEY=YOUR_API_KEY_HERE
API_URL="https://api.dreamhost.com/"

#DOMAIN=$(expr match "$CERTBOT_DOMAIN" '.*\.\(.*\..*\)')
DOMAIN=$(echo "$CERTBOT_DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')

#UUD is for unique_id in the API. If you send the same command twice with the same UUID, only one will be executed
UUID=$(uuidgen)
recordName="_acme-challenge.${CERTBOT_DOMAIN}"
recordValue="${CERTBOT_VALIDATION}"

LINK="${API_URL}?cmd=dns-add_record&type=TXT&value=${recordValue}&comment=ssl-validation&record=${recordName}&key=${API_KEY}&unique_id=${UUID}"

RESPONSE=$(wget -O- -q "$LINK")
if ! (echo "$RESPONSE" | grep -q 'success'); then
  echo "ERROR: $RESPONSE for $DOMAIN"
  exit 1
fi

# Sleep so DNS propagates before letsencrypt validates.
echo "Dreamhost $DOMAIN TXT inserting: Success: $RESPONSE"
echo "Sleeping 30 seconds for DNS propagation"
sleep 30
