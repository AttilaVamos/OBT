#!/usr/bin/bash

SSH_KEYFILE="~/hpcc_keypair.pem"
SSH_OPTIONS="-oConnectionAttempts=5 -oConnectTimeout=100 -oStrictHostKeyChecking=no"
SSH_TARGET="10.240.62.177"

#rsync -va -e "ssh -i ~/AWSSmoketest.pem"  ~/build/bin/OBT-*.txt ec2-user@ec2-3-133-112-185.us-east-2.compute.amazonaws.com:/home/ec2-user/OBT-009/.
rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/build/bin/OBT-*.txt centos@${SSH_TARGET}:/home/centos/${OBT_ID}/

df -h > ~/diskState.log

#rsync -va -e "ssh -i ~/HPCC-Platform-Smoketest.pem"  ~/diskState.log  centos@ec2-35-183-5-250.ca-central-1.compute.amazonaws.com:/home/ec2-user/OBT-010/.
rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/diskState.log  centos@${SSH_TARGET}:/home/centos/${OBT_ID}/

[[ -d ~/Perfstat ]] && rsync -va -e "ssh -i  ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/Perfstat/*  centos@${SSH_TARGET}:/home/centos/${OBT_ID}/Perfstat/

