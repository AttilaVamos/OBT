#!/usr/bin/bash

rsync -va -e "ssh -i ~/AWSSmoketest.pem"  ~/build/bin/OBT-010.txt ec2-user@ec2-3-133-112-185.us-east-2.compute.amazonaws.com:/home/ec2-user/OBT-010/.

df -h > ~/diskState.log

rsync -va -e "ssh -i ~/AWSSmoketest.pem"  ~/diskState.log ec2-user@ec2-3-133-112-185.us-east-2.compute.amazonaws.com:/home/ec2-user/OBT-010/.

