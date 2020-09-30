#!/bin/bash

PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

echo "Update start..."
cw=$(pwd)
OBT_DIR="$HOME/build/bin"

[ ! -d $OBT_DIR/update ] && mkdir -p $OBT_DIR/update

logFile="$OBT_DIR/update/update-"$( date "+%Y-%m-%d" )".log"
LONG_DATE=$( date "+%Y-%m-%d %H:%M:%S" )

echo "Update started @ ${LONG_DATE}" >> ${logFile}

if [ ! -d ~/OBT ]
then
   echo "Cloning ..." >> ${logFile}
   echo "Cloning ..." 
   pushd ~/
   git clone https://github.com/AttilaVamos/OBT.git >> ${logFile} 2>&1
   popd
   echo "Cloned."
   echo "Cloned." >> ${logFile}
fi

if [ -d ~/OBT ]
then
    pushd ~/OBT

    res=$( git pull 2>&1 )
    echo "${res}"  >> ${logFile}
    echo "${res}"

    cp -u -v * $OBT_DIR/  >> ${logFile} 2>&1

    if [ -n "$OBT_ID" ]
    then
    	cp -v $OBT_ID/settings.sh $OBT_DIR/settings.sh  >> ${logFile} 2>&1
    else
	echo "OBT_ID is not defined, using default settings.sh." >> ${logFile} 2>&1
        echo "OBT_ID is not defined, using default settings.sh." 
    fi

    popd
    echo "Update finished." >> ${logFile} 2>&1
    echo "Update finished."
else
    echo "Update failed, ~/OBT directory not exists."  >> ${logFile} 2>&1
    echo "Update failed, ~/OBT directory not exists."
fi

echo "End @ "$( date "+%Y-%m-%d %H:%M:%S" )"."   >> ${logFile} 2>&1
echo "------------------------------------------" >> ${logFile} 2>&1
echo ""   >> ${logFile} 2>&1
