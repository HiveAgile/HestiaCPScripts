#!/bin/bash

/bin/bash -c "$(curl -fsSL https://get.docker.com)"
systemctl enable docker
systemctl start docker

sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

wget -q -O /tmp/docker-hestia.tgz  https://scripts.hiveagile.com/template.tgz
tar xvfz /tmp/docker-hestia.tgz -C /
sleep 3; cd /root/containers/hestia-proxy/
docker network create web
docker-compose up -d 
