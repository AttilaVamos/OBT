#!/bin/bash -x

echo "param:'"$1"'"

if [ "$1." = "." ]
then
    REGRESSION_ONLY=
else
    REGRESSION_ONLY=1
fi

#echo "Regression only:"$REGRESSION_ONLY

echo "Start..."
cd ~/build/bin
echo "pwd:$(pwd)"


#
#------------------------------
#
# Imports (settings, functions)
#

# Git branch settings

. ./settings.sh

# Git branch cloning

. ./cloneRepo.sh

# WriteLog() function

. ./timestampLogger.sh

#
#------------------------------
#
# Constants
#

SHORT_DATE=$(date "+%Y-%m-%d")
LONG_DATE=$(date "+%Y-%m-%d_%H-%M-%S") 
BUILD_DIR=~/build
RELEASE_BASE=5.0
RELEASE=
STAGING_DIR=/tmount/data2/nightly_builds/HPCC/$RELEASE_BASE
BUILD_SYSTEM=centos_6_x86_64
BUILD_TYPE=CE/platform
OBT_LOG_DIR=${BUILD_DIR}/bin
OBT_LOG_FILE=${BUILD_DIR}/bin/obt-${LONG_DATE}.log

#
#-----------------------------------------
#
# Functions


KillCheckDiskSpace()
{
   WriteLog "KillCheckDiskSpace()" "${OBT_LOG_FILE}"
   pids=$( ps ax | grep "[c]heckDiskSpace.sh" | awk '{print $1}' )

    for i in $pids
    do 
    WriteLog "kill pid:"${i} "${OBT_LOG_FILE}"
    echo 'kill: '$i
    kill -9 $i
    sleep 1
    done;

    sleep 1
}


ControlC()
# run if user hits control-c or process receives SIGTERM signal
{

    WriteLog "User break (Ctrl-c)!" "${OBT_LOG_FILE}"

    exitCode=$( echo $? )

    ExitEpilog "exitCode"

}

ExitEpilog()
{
    WriteLog "Stop disk space checker" "${OBT_LOG_FILE}"
    echo "Stop disk space checker"

    KillCheckDiskSpace

    sleep 10

    WriteLog "End of OBT" "${OBT_LOG_FILE}"
    echo "End of OBT"

    ~/build/bin/archiveLogs.sh obt

    exit $1
}

#
#----------------------------------------------------
#
# Start Overnight Build and Test process
#

WriteLog "OBT started" "${OBT_LOG_FILE}"

# trap keyboard interrupt (control-c) and SIGTERM signals
trap ControlC SIGINT
trap ControlC SIGTERM


if [ -z "$REGRESSION_ONLY" ]
then
    echo "Execute regression, coverage, performance thor and performance roxie tests."
    WriteLog "Execute regression, coverage, performance thor and performance roxie tests." "${OBT_LOG_FILE}"

else
    echo "Execute regression test only."
    WriteLog "Execute regression test only." "${OBT_LOG_FILE}"

fi

#
#----------------------------------------------------
#
# Enable core generation
#

WriteLog "Enable core generation." "${OBT_LOG_FILE}"
#ulimit -c unlimited

res=$( ulimit -a | grep '[c]ore' )

WriteLog "ulimit: ${res}" "${OBT_LOG_FILE}"


#
#----------------------------------------------------
#
# Start disk/mem space checker
#
WriteLog "Start disk space checker" "${OBT_LOG_FILE}"

./checkDiskSpace.sh &

#
#----------------------------------------------------
#
# Un-install HPCC Systems
#

WriteLog "Un-install HPCC Systems" "${OBT_LOG_FILE}"

if [ -f /opt/HPCCSystems/sbin/complete-uninstall.sh ]
then
    sudo /opt/HPCCSystems/sbin/complete-uninstall.sh 
else
    WriteLog "HPCC Systems isn't istalled." "${OBT_LOG_FILE}"
fi

diskSpace=$( df -h | grep 'dev/[sv]da1' | awk '{print $1": "$4}')

WriteLog "Disk space is:${diskSpace}" "${OBT_LOG_FILE}"


#
#----------------------------------------------------
#
# Kill Cassandra if it used too much memory
#

WriteLog "Check memory." "${OBT_LOG_FILE}"

freeMem=$( free | egrep "^(Mem)" | awk '{print $4 }' )

WriteLog "Free memory is: "${freeMem}" kB" "${OBT_LOG_FILE}"

# Limit in kByte
MEMORY_LIMIT_GB=3
MEMORY_LIMIT=$(( $MEMORY_LIMIT_GB * (2 ** 20) ))


if [[ $freeMem -lt ${MEMORY_LIMIT} ]]
then
    cassandraPID=$( ps ax  | grep '[c]assandra' | awk '{print $1}' )

    WriteLog "Free memory too low, kill Cassandra (pid: "${cassandraPID}" )" "${OBT_LOG_FILE}"

    kill -9 ${cassandraPID}
    sleep 1m

    freeMem=$( free | egrep "^(Mem)" | awk '{print $4 }' )
    if [[ $freeMem -lt ${MEMORY_LIMIT} ]]
    then
        WriteLog "The free memory ("${freeMem}" kB) is too low! Can't start HPCC Systems!! Give it up!" "${OBT_LOG_FILE}"
        
        # send email to Agyi
        echo "After the kill Cassandra the OBT Free memory ("${freeMem}" kB) is still too low! OBT stopped!" | mailx -s "OBT Memory problem" -u root  "attila.vamos@gmail.com"

        #ExitEpilog
    fi
fi

#
#----------------------------------------------------
#
# Clean-up, git repo clone and git submodule
#

WriteLog "Clean-up, git repo clone and git submodule" "${OBT_LOG_FILE}"

cd ${BUILD_DIR}/$BUILD_TYPE
rm -rf build HPCC-Platform


#git clone https://github.com/hpcc-systems/HPCC-Platform.git

cRes=$( CloneRepo "https://github.com/hpcc-systems/HPCC-Platform.git" )
if [[ 0 -ne  $? ]]
then
    echo "Repo clone failed ! Result is:"$cres
    WriteLog "Repo clone failed ! Result is:"${cres} "${OBT_LOG_FILE}"

    ExitEpilog

else
    echo "Repo clone success !"
    WriteLog "Repo clone success !" "${OBT_LOG_FILE}"
fi


mkdir build
cd HPCC-Platform
git submodule update --init --recursive


#
#----------------------------------------------------
#
# We use branch which is set in settings.sh
#
WriteLog "We use branch which is set in settings.sh branch:${BRANCH_ID}" "${OBT_LOG_FILE}"


echo "git branch: "${BRANCH_ID}  > ../build/git_2days.log

echo "git checkout "${BRANCH_ID} >> ../build/git_2days.log
echo "git checkout "${BRANCH_ID}
res=$( git checkout ${BRANCH_ID} 2>&1 )
echo $res
echo $res >> ../build/git_2days.log
WriteLog "Result:${res}" "${OBT_LOG_FILE}"

branchDate=$( git log -1 | grep '^Date' ) 
WriteLog "Branch ${branchDate}" "${OBT_LOG_FILE}"
echo $branchDate >> ../build/git_2days.log

branchCrc=$( git log -1 | grep '^commit' )
WriteLog "Branch ${branchCrc}" "${OBT_LOG_FILE}"
echo $branchCrc>> ../build/git_2days.log

echo "git remote -v:"  >> ../build/git_2days.log
git remote -v  >> ../build/git_2days.log

echo ""  >> ../build/git_2days.log
cat ${BUILD_DIR}/bin/gitlog.sh >> ../build/git_2days.log
${BUILD_DIR}/bin/gitlog.sh >> ../build/git_2days.log

#
#----------------------------------------------------
#
# Patch plugins/cassandra/CMakeLists.txt

WriteLog "Patch plugins/cassandra/CMakeLists.txt to avoid usage of lib64" "${OBT_LOG_FILE}"


res=$(  grep 'FIND_LIBRARY_USE_LIB64_PATHS' ~/build/CE/platform/HPCC-Platform/plugins/cassandra/CMakeLists.txt )
if [ -z "$res" ]
then
    
    sudo cp ~/build/CE/platform/HPCC-Platform/plugins/cassandra/CMakeLists.txt ~/build/CE/platform/HPCC-Platform/plugins/cassandra/CMakeLists.txt.bak

    sudo sed -i '/option(CASS_BUILD_EXAMPLES "Build examples" OFF)/a    set_property(GLOBAL PROPERTY FIND_LIBRARY_USE_LIB64_PATHS FALSE)' "/root/build/CE/platform/HPCC-Platform/plugins/cassandra/CMakeLists.txt" > temp.xml && sudo mv -f temp.xml "~/build/CE/platform/HPCC-Platform/plugins/cassandra/CMakeLists.txt"

fi
#WriteLog "Copy regress.py" "${REGRESS_LOG_FILE}"
#cp /root/build/bin/regress.py /root/test/HPCC-Platform/testing/regress/hpcc/regression/

#WriteLog "Copy suite.py" "${REGRESS_LOG_FILE}"
#cp /root/build/bin/suite.py /root/test/HPCC-Platform/testing/regress/hpcc/regression/


#
#--------------------------------------------------
#
# Build it
#
WriteLog "Build it..." "${OBT_LOG_FILE}"

cd ../build


CURRENT_DATE=$( date +%Y-%m-%d_%H-%M-%S)
echo "Start at "${CURRENT_DATE}
echo "Start at "${CURRENT_DATE} > build.log 2>&1


${BUILD_DIR}/bin/build_pf.sh HPCC-Platform >> build.log 2>&1


make -j 8 package >> build.log 2>&1
if [ $? -ne 0 ] 
then
   echo "Build failed: build has errors " >> build.log
   buildResult=FAILED
else
   ls -l hpcc*.rpm >/dev/null 2>&1
   if [ $? -ne 0 ] 
   then
      echo "Build failed: no rpm package found " >> build.log
      buildResult=FAILED
   else
      echo "Build succeed" >> build.log
      buildResult=SUCCEED
   fi
fi

CURRENT_DATE=$( date +%Y-%m-%d_%H-%M-%S)
echo "Build end at "${CURRENT_DATE}
echo "Build end at "${CURRENT_DATE} >> build.log 2>&1

TARGET_DIR=${STAGING_DIR}/${SHORT_DATE}/${BUILD_SYSTEM}/${BUILD_TYPE}

if [ ! -e "${TARGET_DIR}" ] 
then
   mkdir -p  $TARGET_DIR
   chmod 777 ${STAGING_DIR}/${SHORT_DATE}
fi

cp git_2days.log  $TARGET_DIR/
cp build.log  $TARGET_DIR/
cp hpcc*.rpm  $TARGET_DIR/
if [ "$buildResult" = "SUCCEED" ]
then
   echo "BuildResult:SUCCEED" >   $TARGET_DIR/build_summary
   WriteLog "BuildResult:SUCCEED" "${OBT_LOG_FILE}"
 
else
   echo "BuildResult:FAILED" >   $TARGET_DIR/build_summary
   WriteLog "BuildResult:FAILED" "${OBT_LOG_FILE}"
   
   # Remove old builds
   ${BUILD_DIR}/bin/clean_builds.sh

   WriteLog "Send Email notification about Regression test" "${OBT_LOG_FILE}"
   echo "Send Email notification about Regression test"

   # Email Notify
   cd ~/build/bin
   ./BuildNotification.py

   ExitEpilog -1

fi


#
#--------------------------------------------------
#
# Regression test
#

WriteLog "Execute Regression test" "${OBT_LOG_FILE}"
echo "Execute Regression test"

cd ~/build/bin
./regress.sh

WriteLog "Copy regression test logs" "${OBT_LOG_FILE}"
echo "Copy regression test logs"

mkdir -p   ${TARGET_DIR}/test
cp ~/test/*.log   ${TARGET_DIR}/test/
cp ~/test/*.summary   ${TARGET_DIR}/test/


# Remove old builds
${BUILD_DIR}/bin/clean_builds.sh

WriteLog "Send Email notification about Regression test" "${OBT_LOG_FILE}"
echo "Send Email notification about Regression test"

# Email Notify
./BuildNotification.py

WriteLog "Archive regression testing logs" "${OBT_LOG_FILE}"
echo "Archive regression testing logs"

./archiveLogs.sh regress

WriteLog "Regression test done" "${OBT_LOG_FILE}"
echo "Regression test done"


#-----------------------------------------------------------------------------
#
# Coverage
# Placed here to avoid any disturbance to regression test execution and result handling

if [ -z "$REGRESSION_ONLY" ]
then

    WriteLog "Execute Coverage test" "${OBT_LOG_FILE}"
    echo "Execute Coverage test"


    cd ~/build/bin

    ./coverage.sh
    cp ~/test/coverage.summary   ${TARGET_DIR}/test/

    WriteLog "Archive coverage testing logs" "${OBT_LOG_FILE}"
    echo "Archive coverage testing logs"

    ./archiveLogs.sh coverage

    WriteLog "Coverage test done." "${OBT_LOG_FILE}"
    echo "Coverage test done."
fi

#
#-----------------------------------------------------------------------------
#
# Performance
# Placed here to avoid any disturbance to regression test execution and result handling

if [ -z "$REGRESSION_ONLY" ]
then
    WriteLog "Execute Performance test" "${OBT_LOG_FILE}"
    echo "Execute Performance test"

    cd ~/build/bin

    ./perftest.sh

    WriteLog "Copy log files to ${TARGET_DIR}/test/perf" "${OBT_LOG_FILE}"
    echo "Copy log files to ${TARGET_DIR}/test/perf"

    mkdir -p   ${TARGET_DIR}/test/perf

    cp -uv ~/HPCCSystems-regression/log/*.*   ${TARGET_DIR}/test/perf/


    WriteLog "Send Email notification about Performance test" "${OBT_LOG_FILE}"
    echo "Send Email notification about Performance test"

    cd ~/build/bin

    ./ReportPerfTestResult.py

    WriteLog "Performance test done." "${OBT_LOG_FILE}"
    echo "Performance test done."


fi

#-----------------------------------------------------------------------------
#
# Stop disk space checker
#

WriteLog "Stop disk space checker" "${OBT_LOG_FILE}"
echo "Stop disk space checker"

KillCheckDiskSpace

sleep 10

#-----------------------------------------------------------------------------
#
# End of OBT
#

WriteLog "End of OBT" "${OBT_LOG_FILE}"
echo "End of OBT"

./archiveLogs.sh obt
