#!/usr/bin/bash

echo "Start $0"

# Default upload parameters
SSH_KEYFILE="~/hpcc_keypair.pem"
SSH_OPTIONS="-oConnectionAttempts=5 -oConnectTimeout=20 -oStrictHostKeyChecking=no"
SSH_TARGET="10.224.20.53"   #OpenStack Region 8 Rocky 8
SSH_USER="rocky"

# If any of those SSH_* parameter is overridden in settings.sh then use them
[[ -f ./settings.sh ]] && . ./settings.sh

echo "Final parameters:"
echo "OBT id: '$OBT_ID'"
echo "User  : '$SSH_USER'"
echo "Target: '$SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/'"

rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/build/bin/OBT-*.txt ~/build/bin/OBT-*.[rj]* $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/

date >> ~/diskState.log
df -h | egrep 'Filesys|^/dev/*|common'  >> ~/diskState.log
echo "==============================================" >> ~/diskState.log

rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/diskState.log  $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/

./uploadObtResultToGists.sh

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

    zipPar="-m"
    [[ $OBT_ID == "OBT-AWS01" ]] && zipPar='-u'  # Keep files for a while
  
    find . -iname 'perfstat-*-'$thisMonthYear$thisMonth'*.c*' -type f -print | zip $zipPar perfstats-$thisMonthYearLong-$thisMonth.zip -@
    
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

