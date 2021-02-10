#!/bin/bash
# A quick script to show wildcard renewal via dreamhost api DNS for
# those people who don't want to read the documentation. 
# Use update_cert_haproxy.sh for a more general script
# Don't forget to set API_KEY


EMAIL="certbot@example.com"
TLSNAME="*.example.com"
PREFERRED_CHALLENGE="dns"

certbot certonly -d "$TLSNAME" --agree-tos --manual \
--email $EMAIL \
--preferred-challenges $PREFERRED_CHALLENGE \
--manual-auth-hook ./manual-hooks/dreamhost_certbot_auth_hook.sh \
--manual-cleanup-hook ./manual-hooks/dreamhost_certbot_cleanup_hook.sh \
--manual-public-ip-logging-ok
