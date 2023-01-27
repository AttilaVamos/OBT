#!/usr/bin/bash

SSH_KEYFILE="~/hpcc_keypair.pem"
SSH_OPTIONS="-oConnectionAttempts=5 -oConnectTimeout=100 -oStrictHostKeyChecking=no"
#SSH_TARGET="10.240.62.177"
#SSH_TARGET="10.240.62.57"  #OpenStack Region 5
SSH_TARGET="10.224.20.54"   #OpenStack Region 8

#rsync -va -e "ssh -i ~/AWSSmoketest.pem"  ~/build/bin/OBT-*.txt ec2-user@ec2-3-133-112-185.us-east-2.compute.amazonaws.com:/home/ec2-user/OBT-009/.
rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/build/bin/OBT-*.txt centos@${SSH_TARGET}:/home/centos/OBT/${OBT_ID}/

date >> ~/diskState.log
df -h | egrep 'Filesys|^/dev/*|common'  >> ~/diskState.log
echo "==============================================" >> ~/diskState.log

#rsync -va -e "ssh -i ~/HPCC-Platform-Smoketest.pem"  ~/diskState.log  centos@ec2-35-183-5-250.ca-central-1.compute.amazonaws.com:/home/ec2-user/OBT-010/.
rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/diskState.log  centos@${SSH_TARGET}:/home/centos/OBT/${OBT_ID}/


if [[ -d ~/Perfstat ]]
then
    # Archive previous month perfstat files into 'perfstats-YYYY-MM.zip' file
    pushd ~/Perfstat
    
    prevMonth=$(date --date "$today - 1month" +%m)
    prevMonthYear=$(date --date "$today - 1month" +%y)
    prevMonthYearLong=$(date --date "$today - 1month" +%Y)

    find . -iname 'perfstat-*-'$prevMonthYear$prevMonth'*.c*' -type f -print | zip -m perfstats-prevMonthYearLong-$prevMonth.zip -@
    popd
    
    rsync -va -e "ssh -i  ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/Perfstat/*  centos@${SSH_TARGET}:/home/centos/OBT/${OBT_ID}/Perfstat/

fi
