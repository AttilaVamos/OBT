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

# Check if Tinyproxy installed
if ! which "tinyproxy" &> /dev/null
then
    # No, it isn't
    WriteLog "Install Tinyproxy ... " "${TINYPROXY_CHECK_LOG_FILE}"
    res=$( sudo apt-get -y install tinyproxy 2>&1 )
    retCode=$?
    [[ $retCode -ne 0 ]] && WriteLog "To install Tinyproxy failed.\n res: '$res'" "${TINYPROXY_CHECK_LOG_FILE}"
    echo "Port 8888"    > tp.conf
    echo "Timeout 600" >> tp.conf

fi

if type "tinyproxy" &> /dev/null
then
    while [[ $tryCount -ne 0 ]]
    do
        WriteLog "Try count: ${tryCount}" "${TINYPROXY_CHECK_LOG_FILE}"

        tinyproxyState=$( pgrep tinyproxy )
        if [[ -z $tinyproxyState ]]
        then
            WriteLog "Stoped! Start it! " "${TINYPROXY_CHECK_LOG_FILE}"
            res=$( tinyproxy -c tp.conf 2>&1 )
            retCode=$?

            sleep 20
            tryCount=$(( $tryCount-1 ))
            continue
        else
            WriteLog "It is OK! " "${TINYPROXY_CHECK_LOG_FILE}"
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
    WriteLog "Tinyproxy not installed in this sysytem! Give up and send Email to Agyi! " "${TINYPROXY_CHECK_LOG_FILE}"
    # send email to Agyi
    echo "Tinyproxy not installed in this sysytem! " | mailx -s "Problem with Tinyproxy" -u $USER  ${ADMIN_EMAIL_ADDRESS}
fi

WriteLog "End of Tinyproxy Server check." "${TINYPROXY_CHECK_LOG_FILE}"
