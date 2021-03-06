#!/bin/bash

WriteLog()
(
    IFS=$'\n'
    text=$1
#    set -x
    # Length of the content of text
    if [[ ${#text} -le 32768 ]]
    then
        text="${text//\\n/$'\n'}"
        text="${text//\\t/ $'\t'}"
    else
        #text=$( echo ${text} | sed -e 's/\\\\/\\/g' -e 's/\\t/\t/g' )
        t=''

    fi

    echo "${text}" | while read i
    do
        TIMESTAMP=$( date "+%Y-%m-%d %H:%M:%S")
        printf "%s: %s\n" "${TIMESTAMP}" "$i"
        if [ "$2." == "." ]
        then
            echo ${TIMESTAMP}": ERROR: WriteLog() target log file name is empty! ($0)"
        else 
            echo -e "${TIMESTAMP}: $i" >> $2
        fi
    done
    unset IFS
    #set +x
)
