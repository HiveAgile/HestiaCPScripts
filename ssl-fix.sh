#!/bin/bash
#Define custom functions to use across scripts
source ./functions.sh
get_user_domain $1 $2
#Create Self-Signed certificates
path="/home/$username/web/$domain/ssl-cert"
mkdir $path
crt="$domain.crt"
key="$domain.key"
arg="/countryName=ES/localityName=Madrid/organizationalUnitName=$domain/commonName=$username/emailAddress=spam@$domain"
msg “Creo los certificados”
openssl req -newkey rsa:2048 -x509 -sha256 -days 3650 -nodes -out $path/$crt -keyout $path/$key -subj $arg
ls $path
#Create Self Signed Certificates
msg “Aplico los certificados AUTOFIRMADOS a $domain”
$HESTIA/bin/v-add-web-domain-ssl $username $domain $path
#Force SSL
msg “Fuerzo redirección a https://$domain”
$HESTIA/bin/v-add-web-domain-ssl-force $username $domain
#Try to install Let’s Encrypt as a bonus.
msg “Intento instalar Let’s Encrypt (fallará si el dominio no está publicado)”
$HESTIA/bin/v-add-letsencrypt-domain $username $domain www.$domain
