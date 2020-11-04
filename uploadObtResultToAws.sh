#!/usr/bin/bash

#rsync -va -e "ssh -i ~/AWSSmoketest.pem"  ~/build/bin/OBT-*.txt ec2-user@ec2-3-133-112-185.us-east-2.compute.amazonaws.com:/home/ec2-user/OBT-009/.
rsync -va -e "ssh -i ~/hpcc_keypair.pem"  ~/build/bin/OBT-*.txt centos@10.240.62.177:/home/centos/${OBT_ID}/

df -h > ~/diskState.log

#rsync -va -e "ssh -i ~/HPCC-Platform-Smoketest.pem"  ~/diskState.log  centos@ec2-35-183-5-250.ca-central-1.compute.amazonaws.com:/home/ec2-user/OBT-010/.
rsync -va -e "ssh -i ~/hpcc_keypair.pem"  ~/diskState.log  centos@10.240.62.177:/home/centos/${OBT_ID}/

[[ -d ~/Perfstat ]] && rsync -va -e "ssh -i ~/hpcc_keypair.pem"  ~/Perfstat/*  centos@10.240.62.177:/home/centos/${OBT_ID}/Perfstat/

