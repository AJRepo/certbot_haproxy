# certbot_haproxy

Scripts to handle certbot renewals automatically on haproxy with letsencrypt hooks

Supports wildcard domains. Additional scripts for using dreamhost wildcard DNS. 
  
50_haproxy_deploy.sh is called automatically on successful creation/renewal of a
certificate (e.g. `certbot renew`) if put in /etc/letsencrypt/renewal-hooks/deploy/

Can also be called directly with the domain name as first argument 
(e.g. 50_haproxy_deploy.sh foo.example.com )

The script 50_haproxy_deploy creates PEM files in 
```
   /etc/ssl/$TLSNAME/[wildcard.]$TLSNAME.pem
```
and creates backups in 
```
   /etc/ssl/$TLSNAME/backup.YYYYMMDD.HHMMSS/
```
where `wildcard.` is used to replace the '\*' character if the script detects your certificate is a wildcard cert (e.g. \*.example.com) 

If you have more than one certificate, having the following in the haproxy.cfg file

   `bind *:443 ssl crt /etc/haproxy/crts/`

allows HA-Proxy to read all pem files in that directory at once. 

The script 50_haproxy_deploy defines the variable $HAPROXY_CRT_DIR (e.g. /etc/haproxy/crts ) 
and if that directory exists, this script creates a softlink to the new/renewed PEM file
as
```
   $HAPROXY_CRT_DIR/[wildcard.]$TLSNAME.pem -> /etc/ssl/$TLSNAME/[wildcard.]$TLSNAME.pem
```
This takes advantage of HA-Proxy's ability to use a config dir for the crt directive(s)
so that adding new (sub)domains can be done without re-editing the haproxy.cfg file.   


This script will not restart HA-Proxy unless the haproxy.cfg file passes the haproxy
check (`haproxy -c -f /etc/haproxy/haproxy.cfg`) 


The Dreamhost DNS/certbot hooks are setup as manual hooks. E.g. 

`certbot certonly -d foo.example.com --agree-tos --manual --email $EMAIL  --preferred-challenges dns  --manual-auth-hook dreamhost_certbot_auth_hook.sh   --manual-cleanup-hook dreamhost_certbot_cleanup_hook.sh    --manual-public-ip-logging-ok` 

and if put in 

   `/etc/letsencrypt/manual-hooks/` 

can be called automatically as part of the script update_cert_haproxy.sh
for wildcard certificate renewals. 


Note:
These scripts call `/usr/bin/mail` for sending e-mails which is often provided by GNU Mailutils. GNU Mailutils changed how the -t/--to flag operates recently. 
GNU Mailutils Version >=3.4 (Ubuntu 18.04 and up) -t flag functionality is 
```
   read recipients from the message header (e.g. To: <foo@example.com> )
```
GNU Mailutils Version 2.99.99 (Ubuntu 16.04 and up) -t flag functionality is 
```
   precede message by a list of addresses (e.g. foo@example.com )
```
so messages generated by these scripts have some redundancy in formatting for backwards compatibility. 
