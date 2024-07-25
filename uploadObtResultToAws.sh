#!/usr/bin/bash

echo "Start $0"

if [[ "$OBT_ID" =~ "OBT-AWS" ]]
then
    SSH_KEYFILE="~/HPCC-Platform-Smoketest.pem"
    SSH_TARGET="3.99.109.118"   #SmoketestScheduler instance in AWS CA-Central
    SSH_OPTIONS="-oConnectionAttempts=2 -oConnectTimeout=10 -oStrictHostKeyChecking=no"
    SSH_USER="centos"
else
    SSH_KEYFILE="~/hpcc_keypair.pem"
    SSH_OPTIONS="-oConnectionAttempts=5 -oConnectTimeout=20 -oStrictHostKeyChecking=no"
    #SSH_TARGET="10.240.62.177"
    #SSH_TARGET="10.240.62.57"  #OpenStack Region 5
    SSH_TARGET="10.224.20.54"   #OpenStack Region 8 CentOS 7
    SSH_TARGET="10.224.20.53"   #OpenStack Region 8 Rocky 8
    SSH_USER="rocky"
fi

# If any of those SSH_* parameter is overridden in settings.sh then use them
[[ -f ./settings.sh ]] && . ./settings.sh

#rsync -va -e "ssh -i ~/AWSSmoketest.pem"  ~/build/bin/OBT-*.txt ec2-user@ec2-3-133-112-185.us-east-2.compute.amazonaws.com:/home/ec2-user/OBT-009/.
rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/build/bin/OBT-*.txt $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/

date >> ~/diskState.log
df -h | egrep 'Filesys|^/dev/*|common'  >> ~/diskState.log
echo "==============================================" >> ~/diskState.log

#rsync -va -e "ssh -i ~/HPCC-Platform-Smoketest.pem"  ~/diskState.log  centos@ec2-35-183-5-250.ca-central-1.compute.amazonaws.com:/home/ec2-user/OBT-010/.
rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/diskState.log  $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/


if [[ -d ~/Perfstat ]]
then
    # Archive previous month's perfstat files into 'perfstats-YYYY-MM.zip' file
    pushd ~/Perfstat
    
    prevMonth=$(date --date "$today - 1month" +%m)
    prevMonthYear=$(date --date "$today - 1month" +%y)
    prevMonthYearLong=$(date --date "$today - 1month" +%Y)

    find . -iname 'perfstat-*-'$prevMonthYear$prevMonth'*.c*' -type f -print | zip -m perfstats-$prevMonthYearLong-$prevMonth.zip -@
    
    # Same for this month's perfstat files into 'perfstats-YYYY-MM.zip' file
    thisMonth=$(date +%m)
    thisMonthYear=$(date +%y)
    thisMonthYearLong=$(date +%Y)
  
    find . -iname 'perfstat-*-'$thisMonthYear$thisMonth'*.c*' -type f -print | zip -m perfstats-$thisMonthYearLong-$thisMonth.zip -@
    
    popd
    
    rsync -va -e "ssh -i  ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/Perfstat/*  $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/Perfstat/

fi

vcpkgZips=$(find ~/ -maxdepth 1 -iname 'vcpkg_downloads-*[rx].zip' -type f )
if [[ -n "$vcpkgZips" ]]
then
    rsync -va -e "ssh -i  ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/vcpkg_downloads*.zip  $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/Vcpkg_downloads/$OS_ID/
fi

if [[ -f ~/HPCCSystems-log-archive/ml-thor-logs.zip ]]
then
    pushd ~/HPCCSystems-log-archive
    zip -u ml-thor-logs $(find . -iname 'ml-thor-*.zip' -type f)

    rsync -va -e "ssh -i  ${SSH_KEYFILE} ${SSH_OPTIONS}" ml-thor-logs.zip $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/
    popd
fi

