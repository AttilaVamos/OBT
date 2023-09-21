#!/bin/bash

PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }' 
#set -x

#------------------------------
#
# Imports (settings, functions)
#

# remove old settings.inc if exists

[[ -f ./settings.inc ]] && rm ./settings.inc

# Git branch settings

. ./settings.sh


if [[ -f ./obtSequence.inc ]]
then
    . ./obtSequence.inc
fi

#
#------------------------------
#

CheckIfNoSessionIsRunning()
{
    checkCount=0
    timeStamp="date +%H:%M:%S"
    echo "$($timeStamp): Check if no session is running"
    
    while [[ -f /tmp/build.log ]]
    do  
        echo "$($timeStamp): A previous session is still running."
        
        # Check GDB and kill it if it is running longer than the value of gdbTimeOut in sec.
        echo "$($timeStamp): Check if any gdb stuck in stack trace generation."
        gdbTimeOut=300 # sec
        pgrep -f gdb | while read pid
        do 
            procTime=$(ps -o etimes= -p $pid )
            printf "%s: GDB pid: %7d, run time: %4d sec. "  "$($timeStamp)" "$pid" "${procTime}"
            [[ ${procTime} -gt ${gdbTimeOut} ]]  && (echo " -> Running longer than $gdbTimeOut sec, kill"; sudo kill -KILL $pid) || echo " "
        done
        echo "$($timeStamp): Gdb check finished."
        
        # Check git and kill it if it is running longer than the value of gitTimeOut in sec.
        echo "$($timeStamp): Check if any git command stuck in clone/fetch/etc operation."
        gitTimeOut=600 # sec
        pgrep -f git | while read pid
        do 
            procTime=$(ps -o etimes= -p $pid )
            printf "%s: git pid: %7d, run time: %4d sec. "  "$($timeStamp)" "$pid" "${procTime}"
            [[ ${procTime} -gt ${gitTimeOut} ]]  && (echo " -> Running longer than $gitTimeOut sec, kill"; sudo kill -KILL $pid) || echo " "
        done
        echo "$($timeStamp): Git check finished."
        
        echo "$($timeStamp): Wait for the current session is finished."

        checkCount=$(( $checkCount + 1 ))
        if [[ $(( $checkCount % 12 )) -eq 0 ]]
        then
            echo "At $(date "+%Y.%m.%d %H:%M:%S") the previous OBT session is still running on ${OBT_SYSTEM}!" | mailx -s "Overlapped sessions on ${OBT_SYSTEM}" -u $USER  ${ADMIN_EMAIL_ADDRESS}
        fi

        # Give it some time to finish
        sleep 5m
    done

    echo "$($timeStamp): Session is finished."
    echo "----------------------------------------------------"
    echo ""
}


RunObt()
{
    # Execute OBT
    cmd="./obtMain.sh regress"
    echo "cmd:${cmd}"
    echo "----------------------------------------------------"
    echo ""

    ${cmd} > /tmp/build.log 2>&1
}

#
# -----------------------------
#
# Main

echo "Start $0."

# To avoid overlapping if a session is stil running 
# and cron kicked off a new one.

CheckIfNoSessionIsRunning

DRY_RUN=0

CWD=$( pwd ) 
targetFile="${PWD}/settings.inc"

if [ -z $RUN_ARRAY ]
then
    if [ -z $BRANCHES_TO_TEST ]
    then
        echo "No sequence defined, execute OBT with default values".
        RunObt
        
    else
        
        echo "Without versioning"
        for branch in  ${BRANCHES_TO_TEST[@]}
        do
            echo "Branch : $branch"
            LONG_DATE=$(date "+%Y-%m-%d_%H-%M-%S")
            echo "# Generated by $0 on ${LONG_DATE}" > ${targetFile}
            echo "BRANCH_ID=$branch" >> ${targetFile}
            echo "export BRANCH_ID=$branch" >> ${targetFile}
            
            echo "----------------------------------------------------"
            cat ${targetFile}
            echo "----------------------------------------------------"
            
            PARAMSTR=( 'BRANCH_ID' )
            RunObt
            
        done
    fi
else
    echo "With versioning"

    # Loop and print it.  Using offset and length to extract values
    NUMBER_OF_SESSIONS=${#RUN_ARRAY[@]}
    echo "Number of session is: $NUMBER_OF_SESSIONS"
    echo "----------------------------------------------------"

    for ((i=0; i<$NUMBER_OF_SESSIONS; i++))
    do
        SESSION_PARAMS=(${!RUN_ARRAY[$i]})
        echo "Session-$(( $i + 1)) parameter(s): ${SESSION_PARAMS[@]}"

        SIZE=${#SESSION_PARAMS[@]}
        echo "Number of parameters: $SIZE"

        LONG_DATE=$(date "+%Y-%m-%d_%H-%M-%S")
        echo "# Generated by $0 on ${LONG_DATE}" > ${targetFile}
        
        PARAMSTR=()
        for((item=0; item<$SIZE; item++))
        do
            SETTINGS=${SESSION_PARAMS[item]}
            
            PARAMNAME=$(  echo "$SETTINGS" | cut -d\= -f1)
            PARAMVALUE=$( echo "$SETTINGS" | cut -d\= -f2)
            echo -e "\tParameter-$(( $item + 1)) name: '$PARAMNAME'"
            echo -e "\t\tcurrent value : '${!PARAMNAME}'\n\t\tin new session: '$PARAMVALUE'"
            
            # Write it into settings.inc
            echo "$SETTINGS" >> ${targetFile}
            echo "export $SETTINGS" >> ${targetFile}
            
            PARAMSTR+=( "${PARAMNAME}" )
        done
        
        echo "OBT_PARAMS='${PARAMSTR[@]}'" >> ${targetFile}
        echo "export OBT_PARAMS='"${PARAMSTR[@]}"'" >> ${targetFile}

        echo ""
        echo "Content of $targetFile:"
        echo "------------------------"
        cat ${targetFile}
        echo "----------------------------------------------------"

        if [[ $DRY_RUN -eq 0 ]]
        then
            RunObt
        else
            continue
            #break
        fi
        
        echo ""
        echo "=================================================================="
        
    done
fi

if [[ "$OBT_ID" == "OBT-AWS02" ]]
then
    SmoketestSchedulerIp='10.20.0.14'  # It is in same region, so use local IP

    # Run regressMinikube.sh
    echo "Start regressMinikube.sh..."
    if [[ -f obt-values.yaml  && -f ecl-test-minikube.json ]]
    then
        [ ! -f rte/ecl-test-minikube.json ] && cp -v ecl-test-minikube.json rte/
        
        ./regressMinikube.sh 

        echo "Upload Perfstat-Minikube to SmoketestScheduler (CA - $SmoketestSchedulerIp) ..."
        rsync -va -e "ssh -i ~/HPCC-Platform-Smoketest.pem" /home/centos/Perfstat-Minikube centos@$SmoketestSchedulerIp:/home/centos/AWS-Minikube/

        echo "Upload regressMinikube-*.log as well ..."
        rsync -va -e "ssh -i ~/HPCC-Platform-Smoketest.pem" /home/centos/build/bin/regressMinikube-*.log centos@$SmoketestSchedulerIp:/home/centos/AWS-Minikube/
        zip -m RegressMinkubeLogs-$(date "+%Y-%m") regressMinikube-*.log
        
        pushd ~/
        zip -r HPCCSystems-regression-Minikube-$(date "+%Y-%m-%d") HPCCSystems-regression/
        popd
    else
        echo "Missing 'obt-values.yaml' and/or 'ecl-test-minikube.json' file, skip Minikube testing."
    fi
    echo "    End."
    
    echo "Upload PkgCache to SmoketestScheduler (CA - $SmoketestSchedulerIp) ..."
    rsync -va -e "ssh -i ~/HPCC-Platform-Smoketest.pem" /home/centos/build/bin/PkgCache centos@$SmoketestSchedulerIp:/home/centos/
    echo "    End."
fi

# Clean-up to prevent the next session stalls on an existing build*.log file.
rm -v /tmp/build*

# Clean-up package cache
[[ -d $OBT_BIN_DIR/PkgCache ]] && rm -rf $OBT_BIN_DIR/PkgCache/*

echo "End."

