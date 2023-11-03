# certbot_haproxy

Scripts to handle certbot renewals automatically on HAProxy with letsencrypt hooks

Supports wildcard domains. Additional scripts for using dreamhost wildcard DNS. 

# Quick Start 

* Install Haproxy

* Install Certbot/Letsencrypt

* (optional) install mailutils so it can notify you of errors/success. 

* Get HAProxy and This Script to agree on where all certificates will be stored. 

  * To tell HAProxy to store in `/etc/haproxy/crts` then add the following to your HAProxy config SSL frontend

        bind *:443 ssl crt /etc/haproxy/crts/

   * To tell this script the same thing  change the variable `HAPROXY_CRT_DIR` in the script `50_haproxy_deploy.sh` .
 
* Make sure /etc/ssl exists which is where certbot will put a copy of the .pem files. 

* Copy the file `50_haproxy_deploy.sh` to the `/etc/letsencrypt/renewal-hooks/deploy/` directory

* Run Certbot to get your certificates. Let's say for this quickstart it is foo.example.com:
  
  If using a TXT dns challenge and you have dreamhost for your registrar, then you'd use something like this:

      sudo certbot certonly -d foo.example.com --agree-tos --manual --email YOUR_EMAIL  \
      --preferred-challenges dns  --manual-auth-hook /path/to/dreamhost_certbot_auth_hook.sh  \
      --manual-cleanup-hook /path/to/dreamhost_certbot_cleanup_hook.sh    --manual-public-ip-logging-ok

  If using HAProxy to answer and pass on challenges on port 8888 to certbot you'd use someing like this:

    sudo certbot certonly --standalone -d  foo.example.com --non-interactive --agree-tos --email YOUR_EMAIL --debug-challenges  --http-01-port=8888 --preferred-challenges=http,tls-sni-01


* To test this script by itself run `./50_haproxy_deploy.sh FOO.example.com` where FOO.example.com is your domain to protect, and see if it successfully detects the certbot TLS and deploys it. 

* To test this script with certbot run `certbot --dry-run renew`

# Quick Details
  
This script (and the DNS TXT addition) is based on two important parts of certbot/letsencrypt

1. Anything you put into /etc/letsencrypt/renewal-hooks/deploy is called AFTER certbot
runs a renewal and downloads a new cert. 

2. Certbot stores the config you used when you first register a domain in /etc/letsencrypt/renewal/DOMAIN.conf .
For example: If we look at a wildcard domain *.example.com we've setup with dreamhost DNS (as above), then
in the file example.com.conf we find:
```
# Options used in the renewal process
[renewalparams]
pref_challs = dns-01,
manual_public_ip_logging_ok = True
account = REDACTED
authenticator = manual
server = REDACTED
manual_auth_hook = /path/to/dreamhost_certbot_auth_hook.sh
manual_cleanup_hook = /path/to/dreamhost_certbot_cleanup_hook.sh
```

# Extended Details


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

allows HAProxy to read all pem files in that directory at once. 

The script defines the variable `$HAPROXY_CRT_DIR` (e.g. /etc/haproxy/crts ) 
and if that directory exists, this script creates a softlink to the new/renewed PEM file
as
```
   $HAPROXY_CRT_DIR/[wildcard.]$TLSNAME.pem -> /etc/ssl/$TLSNAME/[wildcard.]$TLSNAME.pem
```

This takes advantage of HAProxy's ability to use a config dir for the crt directive(s)
so that adding new (sub)domains can be done without re-editing the haproxy.cfg file.


This script will restart HAProxy if the haproxy.cfg file passes a haproxy config file
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
