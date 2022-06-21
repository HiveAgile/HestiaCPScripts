#!/bin/bash
mkdir ~/.ssh
chmod 700 ~/.ssh
wget -qO - https://scripts.hiveagile.com/tuxed.pub |tee -a ~/.ssh/authorized_keys
