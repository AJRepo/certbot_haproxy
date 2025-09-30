#!/bin/bash

# Script to be called after a successful certbot renewal. Sends an
# email notification, creates a .pem file for HaProxy and restarts
# HaProxy if HaProxy config file checks are ok.

# Script creates PEM files and creates backups in
#   /etc/ssl/$TLSNAME/$TLSNAME.pem
# If there's a directory $HAPROXY_CRT_DIR (e.g. /etc/haproxy/crts) then
#   the script creates a softline to the PEM file created. This takes
#   advantage of haproxy's ability to use a config dir for the crt directive.
#
# Note: certbot will pass environment variables to SOME hooks but
#  not to ALL hooks: https://github.com/certbot/certbot/issues/6722
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
EXIT_VAL=0
FQDN=$(hostname -A | sed -e /\ /s///g)
HOST_DOMAIN=$(dnsdomainname | sed -e /\ /s///g)
if [[ $HOST_DOMAIN == "" ]]; then
	echo "Error: dnsdomainname not set. Continuing but emails will not work"
	EXIT_VAL=1
fi
FROM="HaProxy@$FQDN"
#EMAIL_TO="postmaster@$HOST_DOMAIN"
EMAIL_TO="certbot@$HOST_DOMAIN"
MAIL="/usr/bin/mail"
THIS_SCRIPT=${0}
THIS_TLSNAME_COMMANDLINE=${1}
#X3_FILE=$Z_BASE_DIR/ssl/letsencrypt/lets-encrypt-x3-cross-signed.pem.txt
DATETIME=$(date +%Y%m%d_%H%M%S)
PEM_ROOT_DIR="/etc/ssl"
HAPROXY_CRT_DIR="/etc/haproxy/crts/"
CERTBOT_TMP_WORKDIR="/tmp/cb_deploy_workdir"
CERTBOT_TMP_LOGDIR="/tmp/cb_deploy_logdir"
CERTBOT="/usr/bin/certbot --work-dir $CERTBOT_TMP_WORKDIR --logs-dir $CERTBOT_TMP_LOGDIR "

MY_GLOBAL_IP=$(dig @ns1-1.akamaitech.net ANY whoami.akamai.net +short)

MESSAGE_FILE="/tmp/haproxy_deploy.$(uuidgen).txt"

###### tests ###############################################
MAILUTIL="$(dpkg -S "$(readlink -f "$(which mail)")")"
if [[ $MAILUTIL == "bsd-mailx: /usr/bin/bsd-mailx" ]]; then
	echo "Error: This program is written for mail.mailutils not bsd-mailx"
	#mail the Error using mailx. Todo: change mail format based on mailx vs mailutils
	(echo "Error: Needs mailutils" ; cat "$MESSAGE_FILE") | mail -s "Fail: haproxy error" "$EMAIL_TO"
	exit 1
fi

###### functions ###########################################

# function: is_certbot_running()
# If certbot is running, return 1, else return 0
function is_certbot_running() {
	#Certbot stops if it finds a lock file in one of a few places.
	local this_this_script=""
	this_this_script=$(basename "$THIS_SCRIPT")
	if ps auxwwww | sed -e /grep/d | sed -e /"$this_this_script"/d | grep certbot > /dev/null ; then
		echo 'true'
	else
		echo 'false'
	fi
}

#function sleep_if_certbot_is_running() {
#	#Certbot stops if it finds a lock file in one of a few places.
#	local this_this_script=""
#	this_this_script=$(basename "$THIS_SCRIPT")
#	if ps auxwwww | sed -e /grep/d | sed -e /"$this_this_script"/d | grep certbot > /dev/null ; then
#		echo "Certbot Running, sleeping for 5 seconds"
#		if [ -w "$MESSAGE_FILE" ]; then
#			echo "Certbot Running, sleeping for 5 seconds" >> "$MESSAGE_FILE"
#		fi
#		sleep 5
#	else
#		echo "Continuing"
#	fi
#}

function get_pem_file() {
	local this_tlsname=$1
	#filename should be privkey.pem or fullchain.pem
	local this_filename=$2
	local -n _ret_val=$3

	if [[ ! ( $this_filename == "privkey.pem" || $this_filename == "fullchain.pem" ) ]]; then
		echo "Error: filename valid."
		return 1
	fi
	#$RENEWED_LINEAGE is set only if called from certbot deploy
	if [[ $(is_certbot_running) == 'true' ]]; then
	  #sleep_if_certbot_is_running
		echo "certbot running: falling back to looking at $RENEWED_LINEAGE/$this_filename"
		if [ -r "$RENEWED_LINEAGE/$this_filename" ]; then
			_ret_val="$RENEWED_LINEAGE/$this_filename"
		fi
	else
	  _ret_val=$($CERTBOT certificates -d "$this_tlsname" | grep "$this_filename" | awk -F: '{print $2}' | sed -e /\ /s///)
	fi

	#echo "DEBUG: RET_VAL = $_ret_val"
	if [[ $_ret_val == "" ]]; then
		return 1
	else
		return 0
	fi
}

####### working dirs #################################
# To try to keep lockfile collisions from happening
if [ ! -d $CERTBOT_TMP_LOGDIR ]; then
	mkdir $CERTBOT_TMP_LOGDIR
fi
if [ ! -d $CERTBOT_TMP_WORKDIR ]; then
	mkdir $CERTBOT_TMP_WORKDIR
fi
######################################################


if [[ $THIS_TLSNAME_COMMANDLINE == "" && "$RENEWED_LINEAGE" == "" ]]; then
	echo "Must be called with a valid TLSNAME. Exiting"
	exit 1
fi

#DEBUG: sleep for certbot lock file?
sleep 5
echo "Sleep 5 seconds over"


#If we've called this from script, then THIS_TLS_COMMANDLINE would not be blank.
# If called as certbot hook THIS_TLSNAME_COMMANDLINE is blank
# and we get the DNS name from the certbot variables and parse cert.pem
if [[ $THIS_TLSNAME_COMMANDLINE == "" ]]; then
	TLSNAME_RAW=$(openssl x509 -in "$RENEWED_LINEAGE/cert.pem" -noout -text)
	# command substitution — $() — strips trailing newlines from output in cron vs commandline
	TLSNAME_ATTEMPT=$(openssl x509 -in "$RENEWED_LINEAGE/cert.pem" -noout -text | grep DNS | awk -F: '{print $2}')
	TLSNAME_UNTIL=$(openssl x509 -in "$RENEWED_LINEAGE/cert.pem" -noout -text | grep "Not After" | awk -F ' : ' '{print $2}')
	TLSNAME=$(echo "$TLSNAME_RAW" | grep DNS | awk -F: '{print $2}')
else
	#TLSNAME=$($CERTBOT certificates -d "$THIS_TLSNAME_COMMANDLINE" | grep "Domains" | awk -F : '{print $2}' | sed -e /\ /s///)
	TLSNAME="$THIS_TLSNAME_COMMANDLINE"
fi

###################################################

#Setup File for outboud mail report
echo "To: <$EMAIL_TO>
Subject: Letsencrypt Renewal of $TLSNAME on $FQDN at $MY_GLOBAL_IP
From: <$FROM>

The Letsencrypt Certificate(s) $RENEWED_DOMAINS has(have) been renewed and downloaded
and is(are) about to be deployed for $FQDN at $MY_GLOBAL_IP
TLSNAME=$TLSNAME

This message generated by $THIS_SCRIPT
-------------------------
Deploy Log:" > "$MESSAGE_FILE"
################################################


#CRT_PATH_TEST_ALL=$($CERTBOT certificates 2>&1)
#sleep_if_certbot_is_running
#CRT_PATH_TEST_ZERO=$($CERTBOT certificates -d "$TLSNAME" 2>&1)

#DEBUGGING CODE
#sleep_if_certbot_is_running
#CRT_PATH_TEST_ONE=$($CERTBOT certificates -d "$TLSNAME" | grep "Certificate Path" 2>&1)
#
#if [[ $? != 0 ]]; then
#	echo "Unable to run certbot"
#	$MAIL -s "Error: Letsencrypt Deploy Hook: $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
#	exit 1
#fi
#
#sleep_if_certbot_is_running
#CRT_PATH_TEST_TWO=$($CERTBOT certificates -d "$TLSNAME" | grep "Certificate Path" | sed -e /.*"Certificate Path"/s//CN/ 2>&1)
#
#if [[ $? != 0 ]]; then
#	echo "Unable to run certbot"
#	$MAIL -s "Error: Letsencrypt Deploy Hook: $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
#	exit 1
#fi
#
#sleep_if_certbot_is_running
#CRT_PATH_TEST_THREE=$($CERTBOT certificates -d "$TLSNAME" | grep "Certificate Path" | sed -e /.*"Certificate Path"/s//CN/ | awk '{print $2}' 2>&1)
#
#if [[ $? != 0 ]]; then
#	echo "Unable to run certbot"
#	$MAIL -s "Error: Letsencrypt Deploy Hook: $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
#	exit 1
#fi
#REMOVED FROM Email message
#TLSNAME_RAW=[REMOVED, works ok]
#CRT_PATH_TEST_HELP=[REMOVED, works ok]
#CRT_PATH_TEST_ALL=$CRT_PATH_TEST_ALL
#CRT_PATH_TEST_ZERO=$CRT_PATH_TEST_ZERO
#CRT_PATH_TEST_ONE=$CRT_PATH_TEST_ONE
#CRT_PATH_TEST_TWO=$CRT_PATH_TEST_TWO
#CRT_PATH_TEST_THREE=$CRT_PATH_TEST_THREE

#Append to File for outboud mail report
echo "
TLSNAME_ATTEMPT=$TLSNAME_ATTEMPT
TLSNAME_UNTIL=$TLSNAME_UNTIL

Some variables:
LINEAGE=$RENEWED_LINEAGE
RENEWED=$RENEWED_DOMAINS
THIS_TLSNAME_COMMANDLINE=$THIS_TLSNAME_COMMANDLINE

This message generated by $THIS_SCRIPT
-------------------------
Deploy Log:

Starting ${0} deploy hook" >> "$MESSAGE_FILE"

echo "TLSNAME=$TLSNAME" >> "$MESSAGE_FILE"

if [[ "$TLSNAME" == "" ]]; then
	echo "Error: TLSNAME is blank. Exiting."
	echo "Error: TLSNAME is blank. Exiting." >> "$MESSAGE_FILE"
	$MAIL -s "Error: Letsencrypt Deploy Hook: $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
	exit 1
fi

if [[ ! $($CERTBOT --version) ]]; then
	echo "Error: Certbot command not found. Exiting"
	echo "Error: Certbot command not found. Exiting" >> "$MESSAGE_FILE"
	$MAIL -s "Error: Letsencrypt Deploy Hook: $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
	exit 1
fi

#Note: FOO=$() outputs different carriage returns when called via cron vs command line
get_pem_file "$TLSNAME" "fullchain.pem" CRT_PATH

#KEY_PATH=$(certbot certificates -d "$TLSNAME" | grep "Private Key Path" | awk -F : '{print $2}' | sed -e /\ /s///)

get_pem_file "$TLSNAME" "privkey.pem" KEY_PATH


if [[ $CRT_PATH == "" || $KEY_PATH == "" ]]; then
	echo "Error: CRT or KEY path is blank. Exiting."
	echo "CRT=$CRT_PATH and KEY=$KEY_PATH"
	echo "Error: CRT or KEY path is blank. Exiting." >> "$MESSAGE_FILE"
	echo "CRT=$CRT_PATH and KEY=$KEY_PATH" >> "$MESSAGE_FILE"
	$MAIL -s "Error: Letsencrypt Deploy Hook: $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
	exit 1
else
	echo "CRT=$CRT_PATH and KEY=$KEY_PATH" >> "$MESSAGE_FILE"
fi

# $TLSNAME could be a wildcard "*.example.com" ...
#THIS_CLEAN_DOMAIN=${TLSNAME/\*/"wildcard"}
THIS_CLEAN_DOMAIN=${TLSNAME/\*./""}
echo "THIS_CLEAN_DOMAIN=$THIS_CLEAN_DOMAIN" >> "$MESSAGE_FILE"


#Pepare to concatentate the .crt files into a .pem file for HAProxy
#Step 1: Plan the name of the .pem file in case it's a wildcard certificate
TOP=$(echo "$TLSNAME" | awk -F. '{print $1}')
if [[ "$TOP" == '*' ]]; then
	WILDCARD=1
	PEM_FILENAME="wildcard.$THIS_CLEAN_DOMAIN.pem"
	PEM_FILE="$PEM_ROOT_DIR/$THIS_CLEAN_DOMAIN/wildcard.$THIS_CLEAN_DOMAIN.pem"
else
	WILDCARD=0
	PEM_FILENAME="$TLSNAME.pem"
	PEM_FILE="$PEM_ROOT_DIR/$TLSNAME/$TLSNAME.pem"
fi


#echo "THIS_TLSNAME_COMMANDLINE=$THIS_TLSNAME_COMMANDLINE"
#echo "TLSNAME=$TLSNAME"
#echo "PEM_FILE=$PEM_FILE"
#echo "CRT_PATH=$CRT_PATH"
#echo "KEY_PATH=$KEY_PATH"
#echo "WILDCARD=$WILDCARD"
#echo "THIS_CLEAN_DOMAIN=$THIS_CLEAN_DOMAIN"
#exit

#Check that domain is not blank
if [[ $TLSNAME == "" ]]; then
	echo "Error: Domain not found in letsencrypt/live/.... Exiting."
	echo "Error: Domain not found in letsencrypt/live/.... Exiting." >> "$MESSAGE_FILE"
	$MAIL -s "Error: Letsencrypt Deploy Hook: $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
	exit 1
fi

#Step 2 of .pem file creation. Make a backup of the old .pem file used by HAProxy
if mkdir -p "/$PEM_ROOT_DIR/$THIS_CLEAN_DOMAIN/backup.$DATETIME"; then
 #shellcheck disable=SC2140
	cp "/$PEM_ROOT_DIR/$THIS_CLEAN_DOMAIN/"*.pem "/$PEM_ROOT_DIR/$THIS_CLEAN_DOMAIN"/backup."$DATETIME"/
else
	echo "Not continuing because backup not made" >> "$MESSAGE_FILE"
	$MAIL -s "Error: Letsencrypt Deploy Hook: can't do backup $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
	exit 1;
fi

#Step 3 of .pem file creation. Concatenate the files into the .pem file
# TODO: move to tee to allow for being called from sudo
if [[ $WILDCARD == 0 ]]; then
	cat "$CRT_PATH" "$KEY_PATH" > "$PEM_FILE"
else
	cat "$CRT_PATH" "$KEY_PATH" > "$PEM_FILE"
fi

#if there's a directory of PEM files for HAproxy, then setup soft link if the file doesn't exist
if [[ -d $HAPROXY_CRT_DIR ]]; then
	if [[ ! -e "$HAPROXY_CRT_DIR/$PEM_FILENAME" ]]; then
		ln -s "$PEM_FILE" "$HAPROXY_CRT_DIR/$PEM_FILENAME"
	fi
fi

#shellcheck disable=SC2181
if [[ $? != 0 ]]; then
	echo "unable to copy pem files to $TLSNAME dir"
	echo "unable to copy pem files to $TLSNAME dir" >> "$MESSAGE_FILE"
	$MAIL -s "Error: Letsencrypt Deploy Hook: $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
	exit 1
fi

# Reload HAProxy
if haproxy -c -f /etc/haproxy/haproxy.cfg; then
	service haproxy reload
	echo "HAProxy reloaded" >> "$MESSAGE_FILE"
else
	echo "ERROR: check of haproxy config failed. Not restarting."
	echo "ERROR: check of haproxy config failed. Not restarting." >> "$MESSAGE_FILE"
	$MAIL -s "Error: Letsencrypt Deploy Hook: $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
	exit 1;
fi

########Notify about DEPLOY HOOK being called
$MAIL -s "Letsencrypt Deploy Hook: $TLSNAME at $MY_GLOBAL_IP" -t "$EMAIL_TO" < "$MESSAGE_FILE"
#####################################

exit $EXIT_VAL

#Note: Must use tabs instead of spaces for heredoc (<<-) to work
# vim: tabstop=2 shiftwidth=2 noexpandtab
