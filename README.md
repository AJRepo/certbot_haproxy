# certbot_haproxy
Renewal of TLS certificates using certbot. Supports wildcard domains and dreamhost DNS

Scripts to handle certbot renewals automatically on haproxy with certbot hooks
  
50_haproxy_deploy.sh is called if put in /etc/letsencrypt/renewal-hooks/deploy/

If using manual hooks, create the directory `/etc/letsencrypt/manual-hooks/` and move the manual-hook scripts in this repo there. 

Assumes HAPROXY is looking for certificates in 

`/etc/ssl/"$TLSNAME"/$TLSNAME.pem`

or 

`/etc/ssl/"$TLSNAME"/wildcard.$TLSNAME.pem`

You'd have a line in haproxy.cfg like 

`bind *:443 ssl crt /etc/ssl/example.com/example.pem`
