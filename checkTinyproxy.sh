#!/bin/bash

#
#------------------------------
#
# Import settings
#
# Git branch

. ./settings.sh

# WriteLog() function

. ./timestampLogger.sh

#
#------------------------------
#
# Constants
#

#BUILD_HOME=~/build/CE/platform/build
LONG_DATE=$(date "+%Y-%m-%d_%H-%M-%S")
TINYPROXY_CHECK_LOG_FILE=${OBT_LOG_DIR}/CheckTinyProxy-${LONG_DATE}.log

tryCount=2

#
#------------------------------
#
# Check the state of Tinyproxy
#

WriteLog "Start Tinyproxy Server check..." "${TINYPROXY_CHECK_LOG_FILE}"

goodToGo=1
# Check if Tinyproxy installed
if ! which "tinyproxy" &> /dev/null
then
    # No, it isn't
    WriteLog "Install Tinyproxy ... " "${TINYPROXY_CHECK_LOG_FILE}"
    if [[ "$OS_ID" =~ "Ubuntu" ]]
    then
        res=$( sudo apt-get -y install tinyproxy 2>&1 )
        retCode=$?
    else
        res=$( sudo yum -y install tinyproxy 2>&1 )
        retCode=$?   
    fi
    if [[ $retCode -ne 0 ]] 
    then 
        WriteLog "To install Tinyproxy failed.\n res: '$res'" "${TINYPROXY_CHECK_LOG_FILE}"
        goodToGo=0
    else
        WriteLog "  Done." "${TINYPROXY_CHECK_LOG_FILE}"
    fi
else
    WriteLog "Tinyproxy is installed." "${TINYPROXY_CHECK_LOG_FILE}"
fi

if [[ ! -f tinyproxy.conf ]]
then
    WriteLog "Tinyproxy config file is missing, create it." "${TINYPROXY_CHECK_LOG_FILE}"
    echo "Port 8888"    > tinyproxy.conf
    echo "Timeout 600" >> tinyproxy.conf
    echo "StartServers 5" >> tinyproxy.conf
    echo "MaxClients 5" >> tinyproxy.conf
    echo "DisableViaHeader yes" >> tinyproxy.conf
    echo "#SysLog On" >> tinyproxy.conf
    WriteLog "  Done." "${TINYPROXY_CHECK_LOG_FILE}"
else
    WriteLog "Tinyproxy config is found." "${TINYPROXY_CHECK_LOG_FILE}"
fi 

if [[ $goodToGo -eq 1 ]]
then
    WriteLog "Start tinyproxy ...(max attempt count is: $tryCount)" "${TINYPROXY_CHECK_LOG_FILE}"
    while [[ $tryCount -ne 0 ]]
    do
        tinyproxyState=$( pgrep tinyproxy )
        if [[ -z $tinyproxyState ]]
        then
            WriteLog "Stoped! Start it! " "${TINYPROXY_CHECK_LOG_FILE}"
            res=$( sudo tinyproxy -c tinyproxy.conf 2>&1 )
            retCode=$?
            if [[ $retCode -ne 0 ]]
            then
                WriteLog "Error at start: $retCode" "${TINYPROXY_CHECK_LOG_FILE}"
                WriteLog "res:$res" "${TINYPROXY_CHECK_LOG_FILE}"
            fi
            sleep 20
            tryCount=$(( $tryCount-1 ))
            WriteLog "Try count: ${tryCount}" "${TINYPROXY_CHECK_LOG_FILE}"
            continue
        else
            WriteLog "It is running." "${TINYPROXY_CHECK_LOG_FILE}"
            WriteLog "PID(s): $(pgrep tinyproxy)" "${TINYPROXY_CHECK_LOG_FILE}"
            break
        fi
    done
    
    if [[ $tryCount -eq 0 ]]
    then
        WriteLog "Tinyproxy won't start! Give up and send Email to Agyi! " "${TINYPROXY_CHECK_LOG_FILE}"
        # send email to Agyi
        echo "Tinyproxy won't start! " | mailx -s "Problem with Tinyproxy" -u $USER  ${ADMIN_EMAIL_ADDRESS}
    fi
else
    WriteLog "Tinyproxy not installed in this system! Give up and send Email to Agyi! " "${TINYPROXY_CHECK_LOG_FILE}"
    # send email to Agyi
    echo "Tinyproxy not installed in this system! " | mailx -s "Problem with Tinyproxy" -u $USER  ${ADMIN_EMAIL_ADDRESS}
fi

WriteLog "End of Tinyproxy Server check." "${TINYPROXY_CHECK_LOG_FILE}"
