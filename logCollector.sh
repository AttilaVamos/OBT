#!/bin/bash

echo "Start $0"

if [[ -f ~/build/bin/settings.sh ]] 
then
    echo "source settings.sh..."
    . ~/build/bin/settings.sh
else
    echo "File: '~/build/bin/settings.sh' not found. Exit."
    exit -1
fi
echo "   Done."

if [[ "$OBT_ID" =~ "OBT-AWS" ]]
then
    SSH_KEYFILE="~/HPCC-Platform-Smoketest.pem"
    SSH_TARGET="3.99.109.118"   #SmoketestScheduler instance in AWS CA-Central
    SSH_OPTIONS="-oConnectionAttempts=2 -oConnectTimeout=10 -oStrictHostKeyChecking=no"
else
    SSH_KEYFILE="~/hpcc_keypair.pem"
    SSH_OPTIONS="-oConnectionAttempts=3 -oConnectTimeout=20 -oStrictHostKeyChecking=no"
    SSH_TARGET="10.224.20.54"   #OpenStack Region 8
fi

YM=$(date +%Y-%m)
echo "Current year and month: $YM"

pushd $HOME

if [[ $(find ${STAGING_DIR_ROOT} -iname 'hthor.*.log' -type f -print | egrep -c $YM) -ne 0 ]]
then
    echo "Start Hthor log collection..."
    exec find ${STAGING_DIR_ROOT} -iname 'hthor.*.log' -type f -print | egrep $YM | sort | zip -u HthorLogCollection-$YM -@ > HthorLogCollection-$YM.log &
else
    echo "Hthor log not found,$([ -f HthorLogCollection-$YM.log ] && rm -v HthorLogCollection-$YM.log) skip collection."
fi

if [[ $(find ${STAGING_DIR_ROOT} -iname 'thor.*.log' -type f -print | egrep -c $YM) -ne 0 ]]
then
    echo "Start Thor log collection..."
    exec find ${STAGING_DIR_ROOT} -iname 'thor.*.log' -type f -print | egrep $YM | sort | zip -u ThorLogCollection-$YM -@ > ThorLogCollection-$YM.log &
else
    echo "Thor log not found,$([ -f ThorLogCollection-$YM.log ] && rm -v ThorLogCollection-$YM.log) skip collection."
fi

if [[ $(find ${STAGING_DIR_ROOT} -iname 'roxie.*.log' -type f -print | egrep -c $YM) -ne 0 ]]
then
    echo "Start Roxie log collection..."
    exec find ${STAGING_DIR_ROOT} -iname 'roxie.*.log' -type f -print | egrep $YM | sort | zip -u RoxieLogCollection-$YM -@  > RoxieLogCollection-$YM.log &
else
    echo "Roxie log not found,$([ -f RoxieLogCollection-$YM.log ] && rm -v RoxieLogCollection-$YM.log) skip collection."
fi

if [[ $(find ${STAGING_DIR_ROOT} -iname 'unittest.*.log' -type f -print | egrep -c $YM) -ne 0 ]]
then
    echo "Start Unit test log collection..."
    exec find ${STAGING_DIR_ROOT} -iname 'unittest*.log' -type f -print | egrep $YM | sort | zip -u UnittestsLogCollection-$YM -@  > UnittestsLogCollection-$YM.log &
else
    echo "Unit test log not found,$([ -f UnittestsLogCollection-$YM.log ] && rm -v UnittestsLogCollection-$YM.log) skip collection."
fi

if [[ $(find ${STAGING_DIR_ROOT} -iname 'ml.*.log' -type f -print | egrep -c $YM) -ne 0 ]]
then
    echo "Start ML test log collection..."
    exec find ${STAGING_DIR_ROOT} -iname 'ml*.log' -type f -print | egrep $YM | sort | zip -u MlLogCollection-$YM -@  > MlLogCollection-$YM.log &
else
    echo "ML test log not found,$([ -f MlLogCollection-$YM.log ] && rm -v MlLogCollection-$YM.log) skip collection."
fi

if [[ $(find ${STAGING_DIR_ROOT} -iname 'wutooltest.*.log' -type f -print | egrep -c $YM) -ne 0 ]]
then
    echo "Start WUTool test log collection..."
    exec find ${STAGING_DIR_ROOT} -iname 'wutooltest*.log' -type f -print  | egrep $YM | sort | zip -u WutooltestLogCollection-$YM -@  > WutooltestLogCollection-$YM.log &
else
    echo "WUTool test log not found,$([ -f WutooltestLogCollection-$YM.log ] && rm -v WutooltestLogCollection-$YM.log) skip collection."
fi

if [[ $(find ${STAGING_DIR_ROOT} -iname '*build.*.log' -type f -print | egrep -c $YM) -ne 0 ]]
then
    echo "Start Build log collection..."
    exec find ${STAGING_DIR_ROOT} -iname '*build*.log' -type f -print | egrep $YM | sort | zip -u BuildLogCollection-$YM  -@  > BuildLogCollection-$YM.log &
else
    echo "Build test log not found,$([ -f BuildLogCollection-$YM.log ] && rm -v BuildLogCollection-$YM.log) skip collection."
fi

if [[ $(find ${STAGING_DIR_ROOT} -iname 'report.html' -o -iname 'GlobalExclusion.log' -o -iname 'git_2days.log' -type f -print | egrep -c $YM) -ne 0 ]]
then
    echo "Start Misc (report.htm, GlobalExclusion and git_2days) log collection..."
    exec find ${STAGING_DIR_ROOT} -iname 'report.html' -o -iname 'GlobalExclusion.log' -o -iname 'git_2days.log' -type f | egrep $YM | sort | zip -u MiscLogCollection-$YM  -@  > MiscLogCollection-$YM.log &
else
    echo "Misc (report.htm, GlobalExclusion and git_2days) test log not found,$([ -f MiscLogCollection-$YM.log ] && rm -v MiscLogCollection-$YM.log) skip collection."
fi

echo "......................."
echo "Wait for processes finished."

wait 
echo "......................."
echo "All processes are finished."
popd 
echo "......................."
echo "Upload results.."

rsync -va --min-size=1 -e "ssh -i  ${SSH_KEYFILE} ${SSH_OPTIONS}" ~/*LogCollection-${YM}* centos@${SSH_TARGET}:/home/centos/OBT/${OBT_ID}

echo "Upload done."
echo "......................."
echo "End."

