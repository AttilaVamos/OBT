#!/usr/bin/bash

echo "Start $0"

# Default upload parameters
SSH_KEYFILE="~/hpcc_keypair.pem"
SSH_OPTIONS="-oConnectionAttempts=5 -oConnectTimeout=20 -oStrictHostKeyChecking=no"
SSH_TARGET="10.224.20.53"   #OpenStack Region 8 Rocky 8
SSH_USER="rocky"
DEBUG=0

# If any of those SSH_* parameter is overridden in settings.sh then use them
[[ -f ./settings.sh ]] && . ./settings.sh

echo "Final parameters:"
echo "OBT id: '$OBT_ID'"
echo "User  : '$SSH_USER'"
echo "Target: '$SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/'"

rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}" ~/build/bin/OBT-*.[jrtz]* $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/

[[ -f ~/diagrams.zip ]] && rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/diagrams.zip  $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/

date >> ~/diskState.log
df -h | egrep 'Filesys|^/dev/*|common'  >> ~/diskState.log
echo "==============================================" >> ~/diskState.log

rsync -va -e "ssh -i ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/diskState.log  $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/
./fixJson.sh . > fixJson-$(date "+%Y-%m-%d_%H-%M-%S").log   2>&1
./uploadObtResultToGists.sh >uploadObtResultToGists-$(date "+%Y-%m-%d_%H-%M-%S").log   2>&1

if [[ -d ~/Perfstat ]]
then
    #
    # ZIP all  perfstat-*.c* files into teir corresonding monthly zip file
    #
    pushd ~/Perfstat
    
    FILE_COUNT=0
    echo " "
    echo "Add all perfstat files to monthly zip file."
    while read fileName
    do
        FILE_COUNT=$(( FILE_COUNT + 1 ))
        fName=${fileName#./}                    # Delete leading './' from the fileName but keep the original, need it to zip and git
        dStamp=$(echo "$fName" | awk -F '-' '{ print $3 }' )
        dateStamp="${dStamp:0:2}-${dStamp:2:2}"
        [[ $DEBUG -ne 0 ]] && printf "fName: %-40s, dateStamp: %-10s\n" "$fName" "$dateStamp"

        res=$( zip -u perfstats-${dateStamp}.zip $fileName 2>&1)
        retCode=$?
        [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
        [[ $DEBUG -ne 0 ]] && echo "res: $res"

    done< <( find . -iname 'perfstat-*.c*' -type f -print )
    echo "Done, $FILE_COUNT file(s) archived."
    echo " "
    
    PERFSTAT_DAYS_TO_KEEP=32
    [[ -n $PERF_PERFSTAT_DAYS_TO_KEEP ]] && PERFSTAT_DAYS_TO_KEEP=PERF_PERFSTAT_DAYS_TO_KEEP
    echo "Move file older than $PERFSTAT_DAYS_TO_KEEP into the monthly zip arcive"

    FILE_COUNT=0

    while read fileName
    do
        FILE_COUNT=$(( FILE_COUNT + 1 ))
        fName=${fileName#./}                    # Delete leading './' from the fileName but keep the original, need it to zip and git
        dStamp=$(echo "$fName" | awk -F '-' '{ print $3 }' )
        dateStamp="${dStamp:0:2}-${dStamp:2:2}"
        [[ $DEBUG -ne 0 ]] && printf "fName: %-40s, dateStamp: %-10s\n" "$fName" "$dateStamp"

        res=$( zip -m perfstats-${dateStamp}.zip $fileName 2>&1)
        retCode=$?
        [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
        [[ $DEBUG -ne 0 ]] && echo "res: $res"

    done< <( find . -iname 'perfstat-*.c*' -mtime +${PERFSTAT_DAYS_TO_KEEP} -type f -print )
    echo "Done, $FILE_COUNT file(s) moved."
    echo " "
    popd
    
    rsync -va -e "ssh -i  ${SSH_KEYFILE} ${SSH_OPTIONS}"  ~/Perfstat/*.zip  $SSH_USER@${SSH_TARGET}:/home/$SSH_USER/OBT/${OBT_ID}/Perfstat/

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

#
# ZIP all  archiveLogs-*.log files older than ARCHIVE_LOGS_DAYS_TO_KEEP
#
ARCHIVE_LOGS_DAYS_TO_KEEP=1

while read fileName
do
    fName=${fileName#./}                    # Delete leading './' from the fileName but keep the original, need it to zip and git
    dateStamp=$(echo "$fName" | awk -F '-' '{ print $2"-"$3 }' )
    [[ $DEBUG -ne 0 ]] && printf "%s\n" "$dateStamp"

    res=$( zip -m archiveLogs-${dateStamp}.zip $fileName 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res: $res"

done< <( find . -iname 'arch*.log' -mtime +${ARCHIVE_LOGS_DAYS_TO_KEEP} -type f -print )



#
# ZIP all  *.json files older than JSON_RESULTS_DAYS_TO_KEEP
#
JSON_RESULTS_DAYS_TO_KEEP=1

while read fileName
do
    fName=${fileName#./}                    # Delete leading './' from the fileName but keep the original, need it to zip and git
    fName=${fName//candidate-/}         # Delete 'candidate-' to make filenames uniform
    source=$(echo "$fName" | cut -d'-' -f1,2)
    [[ $DEBUG -ne 0 ]] && printf "%30s, %20s," "$fName" "$source"

    dateStamp=$(echo "$fName" | awk -F '-' '{ print $4"-"$5 }' )
    [[ $DEBUG -ne 0 ]] && printf "%s\n" "$dateStamp"

    res=$( zip -m ${source}-results-${dateStamp}.zip $fileName 2>&1)
    retCode=$?
    [[ $DEBUG -ne 0 ]] && echo "ret code: $retCode"
    [[ $DEBUG -ne 0 ]] && echo "res: $res"

done< <( find . -iname '*.json' -mtime +${JSON_RESULTS_DAYS_TO_KEEP} -type f -print )
