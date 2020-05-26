#!/bin/bash


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
OBT_BIN_DIR=${BUILD_DIR}/bin
OBT_LOG_FILE=${BUILD_DIR}/bin/obt-${LONG_DATE}.log
TARGET_DIR=${STAGING_DIR}/${SHORT_DATE}/${BUILD_SYSTEM}/${BUILD_TYPE}

#
#------------------------------
#
# Process parameter
#

#echo "param:'"$1"'"

RUN_REGRESSION=1
RUN_COVERAGE=1
RUN_PERFORMANCE=1
BUILD=1
DRY_RUN=0

if [ "$1." != "." ]
then
    param=$1
    upperParam=${param^^}
    echo "Param: ${upperParam}"
    case $upperParam in

        REGR*)  RUN_REGRESSION=1
                RUN_COVERAGE=0
                RUN_PERFORMANCE=0
                BUILD=1
                ;;

        COVER*) RUN_REGRESSION=0
                RUN_COVERAGE=1
                RUN_PERFORMANCE=0
                BUILD=0
                ;;

        PERF*)  RUN_REGRESSION=0
                RUN_COVERAGE=0
                RUN_PERFORMANCE=1
                BUILD=1
                ;;
      
        BUI*)   # Only build
                RUN_REGRESSION=0
                RUN_COVERAGE=0
                RUN_PERFORMANCE=0
                ;;

        *)      # Dry run
                DRY_RUN=1
                RUN_REGRESSION=0
                RUN_COVERAGE=0
                RUN_PERFORMANCE=0
                BUILD=0
                ;;
    esac
fi

#
#------------------------------
#
# there is a bug in GCC 4.8.2 and crash in coverage build

IS_GCC_4_8_2=$( gcc -v 2>&1 | grep '[v]ersion 4.8.2' )

#echo "IS_GCC_4_8_2: ${IS_GCC_4_8_2}, RUN_COVERAGE:${RUN_COVERAGE}"

if [[ ( -n "$IS_GCC_4_8_2" ) && ( ${RUN_COVERAGE} -eq 1 ) ]]
then
    RUN_COVERAGE=0
fi


cd ${OBT_BIN_DIR}

#
#------------------------------
#
# Imports (settings, functions)
#

# Git branch settings

. ./settings.sh

# WriteLog() function

. ./timestampLogger.sh

# UninstallHPCC() fuction

. ./UninstallHPCC.sh

# Git branch cloning

. ./cloneRepo.sh


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
        WriteLog "kill checkdiskspace.sh with pid: ${i}" "${OBT_LOG_FILE}"
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

    ${OBT_BIN_DIR}/archiveLogs.sh obt-exit-cleanup

    if [ "$1." == "$1" ]
    then
        exit -1
    else
        exit $1
    fi
}

#
#----------------------------------------------------
#
# Start Overnight Build and Test process
#

WriteLog "OBT started" "${OBT_LOG_FILE}"

WriteLog "I am $( whoami)" "${OBT_LOG_FILE}"

WriteLog "Trap SIGINT, SIGTERM and SIGKILL signals" "${OBT_LOG_FILE}"
# trap keyboard interrupt (control-c) and SIGTERM signals
trap ControlC SIGINT
trap ControlC SIGTERM
trap ControlC SIGKILL


export PATH=$PATH:/usr/local/bin:/bin:/usr/local/sbin:/sbin:/usr/sbin:/mnt/disk1/home/vamosax/bin:
WriteLog "path:'${PATH}'" "${OBT_LOG_FILE}"

WriteLog "LD_LIBRARY_PATH:'${LD_LIBRARY_PATH}'" "${OBT_LOG_FILE}"


WriteLog "GCC: ${IS_GCC_4_8_2}" "${OBT_LOG_FILE}"

STARTUP_MSG=""

if [[ "$BUILD" -eq 1 ]]
then
    STARTUP_MSG=${STARTUP_MSG}"build"
fi

if [[ "$RUN_REGRESSION" -eq 1 ]]
then
    STARTUP_MSG=${STARTUP_MSG}", Regression"
fi

if [[ "$RUN_COVERAGE" -eq 1 ]]
then
    STARTUP_MSG=${STARTUP_MSG}", Coverage"
fi

if [[ "$RUN_PERFORMANCE" -eq 1 ]]
then
    STARTUP_MSG=${STARTUP_MSG}", Performance"
fi


if [[ -n "$STARTUP_MSG" ]]
then

    WriteLog "In this run of OBT we execute $STARTUP_MSG." "${OBT_LOG_FILE}"

else
    WriteLog "No target selected, this is a dry run." "${OBT_LOG_FILE}"
    #./archiveLogs.sh obt-cleanup
    #exit -1
fi

WriteLog "pwd:$(pwd)" "${OBT_LOG_FILE}"


#
#----------------------------------------------------
#
# Enable core generation
#

WriteLog "Enable core generation." "${OBT_LOG_FILE}"
ulimit -c unlimited

res=$( ulimit -a | grep '[c]ore' )

WriteLog "ulimit: ${res}" "${OBT_LOG_FILE}"


./checkCoreGen.sh >> ${OBT_LOG_FILE} 2>&1

#
#----------------------------------------------------
#
# Start disk/mem space checker
#

KillCheckDiskSpace

WriteLog "Start disk space checker" "${OBT_LOG_FILE}"

./checkDiskSpace.sh &

#
#----------------------------------------------------
#
# Un-install HPCC Systems
#

WriteLog "Un-install HPCC Systems" "${OBT_LOG_FILE}"

UninstallHPCC "${OBT_LOG_FILE}"

# Possible strategy to restart this process is:
# 1. Add schedule into crontab 10-15 minutes later today
# 2. restart the OBT machine
# 3. remove unecessary schedule from crontab (make backup in 1 and restore here)


#
#----------------------------------------------------
#
# Record current diskspace
#

diskSpace=$( df -h . | egrep '^(/dev/)' | awk '{print $1": "$4}' )

WriteLog "Disk space is:${diskSpace}" "${OBT_LOG_FILE}"

#
#----------------------------------------------------
#
# Kill Cassandra if it used too much memory
#

WriteLog "Check memory." "${OBT_LOG_FILE}"

freeMem=$(  free -g | egrep "^(Mem)" | awk '{print $4"GB from "$2"GB" }' )

WriteLog "Free memory is: ${freeMem} " "${OBT_LOG_FILE}"

freeMem=$( free | egrep "^(Mem)" | awk '{ print $4 }' )

# Limit in kByte
MEMORY_LIMIT_GB=3
MEMORY_LIMIT=$(( $MEMORY_LIMIT_GB * (2 ** 20) ))


if [[ $freeMem -lt ${MEMORY_LIMIT} ]]
then
    cassandraPID=$( ps ax  | grep '[c]assandra' | awk '{print $1}' )

    if [[ -n "$cassandraPID" ]]
    then

        WriteLog "Free memory too low, kill Cassandra (pid: ${cassandraPID})" "${OBT_LOG_FILE}"

        sudo kill -9 ${cassandraPID}
        sleep 1m

        freeMem=$( free | egrep "^(Mem)" | awk '{print $4 }' )
        if [[ $freeMem -lt ${MEMORY_LIMIT} ]]
        then
            WriteLog "The free memory (${freeMem} kB) is too low!" "${OBT_LOG_FILE}"
        
            # send email to Agyi
            #echo "After the kill Cassandra the OBT Free memory (${freeMem} kB) is still too low!" | mailx -s "OBT Memory problem" -u root  "attila.vamos@gmail.com"

            #ExitEpilog
        else
            WriteLog "The free memory is (${freeMem} kB)." "${OBT_LOG_FILE}"
        fi
    else
        WriteLog "Cassandra doesn't run but the free memory (${freeMem} kB) is too low!" "${OBT_LOG_FILE}"

        WriteLog "Try to kill Kafka and zookeeper" "${OBT_LOG_FILE}" 
        killKafka=$( ps ax | grep '[K]afka' | awk '{print $1 }' | while read pid; do echo 'kill $pid'; sudo kill -9 $pid; done; )
        WriteLog "${killKafka}" "${OBT_LOG_FILE}"
        sleep 1m

        killZookeeper=$( ps ax | grep '[z]ook' | awk '{print $1 }' | while read pid; do echo 'kill $pid'; sudo kill -9 $pid; done; )
        WriteLog "${killZookeeper}" "${OBT_LOG_FILE}"
        sleep 1m

        freeMem=$( free | egrep "^(Mem)" | awk '{print $4 }' )
        WriteLog "The free memory is (${freeMem} kB)!" "${OBT_LOG_FILE}"
    fi
fi


cassandraPID=$( ps ax  | grep '[c]assandra' | awk '{print $1}' )

if [[ -n "$cassandraPID" ]]
then

    WriteLog "Try to kill Cassandra (pid: ${cassandraPID})" "${OBT_LOG_FILE}"

    sudo kill -9 ${cassandraPID}
    sleep 1m

    freeMem=$( free | egrep "^(Mem)" | awk '{print $4 }' )
    WriteLog "The free memory is (${freeMem} kB)!" "${OBT_LOG_FILE}"
fi

WriteLog "Try to kill Kafka and zookeeper" "${OBT_LOG_FILE}" 
killKafka=$( ps ax | grep '[K]afka' | awk '{print $1 }' | while read pid; do echo "kill Kafka (pid:$pid)"; sudo kill -9 $pid; done; )
WriteLog "Kafka result:${killKafka}" "${OBT_LOG_FILE}"
sleep 1m

killZookeeper=$( ps ax | grep '[z]ook' | awk '{print $1 }' | while read pid; do echo "kill Zookeeper (pid:$pid)"; sudo kill -9 $pid; done; )
WriteLog "Zookeeper result:${killZookeeper}" "${OBT_LOG_FILE}"
sleep 1m

freeMem=$( free | egrep "^(Mem)" | awk '{print $4 }' )
WriteLog "The free memory is (${freeMem} kB)!" "${OBT_LOG_FILE}"

#
#--------------------------------------------------
#
# Build it
#

if [[ $BUILD -eq 1 ]]
then
    #
    #----------------------------------------------------
    #
    # Build phase
    #
    WriteLog "Clean up and prepare..." "${OBT_LOG_FILE}"

    if [ ! -d ${BUILD_DIR}/$BUILD_TYPE ]
    then
        mkdir -p ${BUILD_DIR}/$BUILD_TYPE
    fi

    cd ${BUILD_DIR}/$BUILD_TYPE
    rm -rf build HPCC-Platform

    mkdir build

    #
    #----------------------------------------------------
    #
    # Git repo clone
    #
    
    WriteLog "Git repo clone" "${OBT_LOG_FILE}"
    cRes=$( CloneRepo "https://github.com/hpcc-systems/HPCC-Platform.git" )
    if [[ 0 -ne  $? ]]
    then
        WriteLog "Repo clone failed ! Result is: ${cres}" "${OBT_LOG_FILE}"

        ExitEpilog

    else
        WriteLog "Repo clone success !" "${OBT_LOG_FILE}"
    fi

    #
    #----------------------------------------------------
    #
    # We use branch which is set in settings.sh
    #
    WriteLog "We use branch: ${BRANCH_ID} which is set in settings.sh" "${OBT_LOG_FILE}"

    cd HPCC-Platform

    echo "git branch: ${BRANCH_ID}"  > ${GIT_2DAYS_LOG}

    echo "git checkout ${BRANCH_ID}" >> ${GIT_2DAYS_LOG}    
    WriteLog "git checkout ${BRANCH_ID}" "${OBT_LOG_FILE}"

    res=$( git checkout ${BRANCH_ID} 2>&1 )
    echo $res >> ${GIT_2DAYS_LOG}
    WriteLog "Result:${res}" "${OBT_LOG_FILE}"

    branchDate=$( git log -1 | grep '^Date' ) 
    WriteLog "Branch ${branchDate}" "${OBT_LOG_FILE}"
    echo $branchDate >> ${GIT_2DAYS_LOG}

    branchCrc=$( git log -1 | grep '^commit' )
    WriteLog "Branch ${branchCrc}" "${OBT_LOG_FILE}"
    echo $branchCrc>> ${GIT_2DAYS_LOG}

    echo "git remote -v:"  >> ${GIT_2DAYS_LOG}
    git remote -v  >> ${GIT_2DAYS_LOG}

    echo ""  >> ${GIT_2DAYS_LOG}
    cat ${BUILD_DIR}/bin/gitlog.sh >> ${GIT_2DAYS_LOG}
    ${BUILD_DIR}/bin/gitlog.sh >> ${GIT_2DAYS_LOG}

    #
    #----------------------------------------------------
    #
    # Update submodule
    #

    WriteLog "Update git submodule" "${OBT_LOG_FILE}"

    #subRes=$( SubmoduleUpdate "--init --recursive" )
    subRes=$( SubmoduleUpdate "--init" )
    if [[ 0 -ne  $? ]]
    then
        WriteLog "Submodule update failed ! Result is: ${subRes}" "${OBT_LOG_FILE}"

        #ExitEpilog

    else
        WriteLog "Submodule update success !" "${OBT_LOG_FILE}"
    fi

    #
    #----------------------------------------------------
    #
    # Update BuildNotification.ini and ReportPerfTestResult.ini to use proper branch
    #
    pushd ${OBT_BIN_DIR} > /dev/null

    WriteLog "pwd:$(pwd)" "${OBT_LOG_FILE}"
    WriteLog "Update 'BuildBranch' in BuildNotification.ini" "${OBT_LOG_FILE}"

    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed -e '/# Gen\(.*\)/d' -e '/# Upd\(.*\)/d' -e '/^BuildBranch : \(.*\)/c # Updated by OBT @ '"$( date '+%Y-%m-%d %H:%M:%S' )"' \nBuildBranch : '${BRANCH_ID} ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini

    WriteLog "Update 'BuildBranch' in ReportPerfTestResult.ini" "${OBT_LOG_FILE}"

    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed -e '/# Gen\(.*\)/d' -e '/# Upd\(.*\)/d' -e '/^BuildBranch : \(.*\)/c # Updated by OBT @ '"$( date '+%Y-%m-%d %H:%M:%S' )"' \nBuildBranch : '${BRANCH_ID} ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini

    WriteLog "Update success !" "${OBT_LOG_FILE}"

    popd > /dev/null

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
    #----------------------------------------------------
    #
    # Global Exclusion
    #

    if [ ! -e "${TARGET_DIR}" ] 
    then
        WriteLog "Create ${TARGET_DIR}..." "${OBT_LOG_FILE}"
        mkdir -p  $TARGET_DIR
    fi

    if [ -e "${TARGET_DIR}" ] 
    then
        chmod 777 ${STAGING_DIR}/${SHORT_DATE}
        WriteLog "Create global exclusion file and copy it to ${TARGET_DIR}..." "${OBT_LOG_FILE}"
        echo "Regression:${REGRESSION_EXCLUDE_CLASS}" > ${GLOBAL_EXCLUSION_LOG}
        echo "Performance:${PERFORMANCE_EXCLUDE_CLASS}" >> ${GLOBAL_EXCLUSION_LOG}
        cp ${GLOBAL_EXCLUSION_LOG} $TARGET_DIR/
    else
        WriteLog "$TARGET_DIR doesn't exist or un-reachable" "${OBT_LOG_FILE}"
    fi

    #
    #----------------------------------------------------
    #
    # Build
    #

    WriteLog "Build it..." "${OBT_LOG_FILE}"

    cd ${BUILD_DIR}/$BUILD_TYPE/build
    
    
    CURRENT_DATE=$( date "+%Y-%m-%d %H:%M:%S")
    WriteLog "Start at ${CURRENT_DATE}" "${OBT_LOG_FILE}"
    echo "Start at ${CURRENT_DATE}" > ${BUILD_LOG_FILE} 2>&1
    
    #CMD="make -j 16 package"
    #CMD="make package"
    CMD="make -j ${NUMBER_OF_CPUS} package"

    WriteLog "cmd:'${CMD}'." "${OBT_LOG_FILE}"
    
    ${BUILD_DIR}/bin/build_pf.sh HPCC-Platform >> ${BUILD_LOG_FILE} 2>&1

    ${CMD} >> ${BUILD_LOG_FILE} 2>&1
    
    if [ $? -ne 0 ] 
    then
       echo "Build failed: build has errors " >> ${BUILD_LOG_FILE}
       buildResult=FAILED
    else
       ls -l hpcc*.rpm >/dev/null 2>&1
       if [ $? -ne 0 ] 
       then
          echo "Build failed: no rpm package found " >> ${BUILD_LOG_FILE}
          buildResult=FAILED
       else
          echo "Build succeed" >> ${BUILD_LOG_FILE}
          buildResult=SUCCEED
       fi
    fi
    
    CURRENT_DATE=$( date "+%Y-%m-%d %H:%M:%S")
    WriteLog "Build end at ${CURRENT_DATE}" "${OBT_LOG_FILE}"
    echo "Build end at ${CURRENT_DATE}" >> ${BUILD_LOG_FILE} 2>&1
    
    #if [ ! -e "${TARGET_DIR}" ] 
    #then
    #   WriteLog "Create ${TARGET_DIR}..." "${OBT_LOG_FILE}"
    #   mkdir -p  $TARGET_DIR
    #fi

    if [ -e "${TARGET_DIR}" ] 
    then
        WriteLog "Copy files to ${TARGET_DIR}..." "${OBT_LOG_FILE}"
        #chmod 777 ${STAGING_DIR}/${SHORT_DATE}
        cp ${GIT_2DAYS_LOG}  $TARGET_DIR/
        cp ${BUILD_LOG_FILE}  $TARGET_DIR/
        cp hpcc*.rpm  $TARGET_DIR/
        
    else
        WriteLog "$TARGET_DIR doesn't exist or un-reachable" "${OBT_LOG_FILE}"
    fi

    if [ "$buildResult" = "SUCCEED" ]
    then
       echo "BuildResult:SUCCEED" >   $TARGET_DIR/build_summary
       WriteLog "BuildResult:SUCCEED" "${OBT_LOG_FILE}"

       WriteLog "Archive the package" "${OBT_LOG_FILE}"
       cp hpcc*.rpm  $TARGET_DIR/
     
    else
       echo "BuildResult:FAILED" >   $TARGET_DIR/build_summary
       WriteLog "BuildResult:FAILED" "${OBT_LOG_FILE}"
       
       # Remove old builds
       ${BUILD_DIR}/bin/clean_builds.sh
    
       WriteLog "Send Email notification about build failure" "${OBT_LOG_FILE}"
       
       # Email Notify
       cd ${OBT_BIN_DIR}
       ./BuildNotification.py
    
       ExitEpilog -1
    
    fi

    if [ $RUN_UNITTESTS -ne 1 ]
    then
        # Unit tests doesn't run, so archive build logs now
        cd ${OBT_BIN_DIR}
        ./archiveLogs.sh obt-build
    fi

else
    WriteLog "                            " "${OBT_LOG_FILE}"   
    WriteLog "****************************" "${OBT_LOG_FILE}"
    WriteLog " Skip build HPCC Platform..." "${OBT_LOG_FILE}"
    WriteLog "                            " "${OBT_LOG_FILE}"   
        
fi

if [ $RUN_UNITTESTS -eq 1 ]
then
    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog " Execute Unit tests    " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"
    
    ${SUDO} ${PKG_INST_CMD} ${BUILD_HOME}/hpccsystems-platform?community*.rpm > install.log 2>&1

    cd ${OBT_BIN_DIR}
    ./unittest.sh
    
    if [ ! -e ${TARGET_DIR}/test ]
    then
        WriteLog "Create ${TARGET_DIR}/test directory..." "${OBT_LOG_FILE}"
        mkdir -p ${TARGET_DIR}/test
    fi

    cp ${OBT_LOG_DIR}/unittests*.log   ${TARGET_DIR}/test/
    cp ${OBT_LOG_DIR}/unittests.summary   ${TARGET_DIR}/test/
    
    # Archive build an unit tests logs
    cd ${OBT_BIN_DIR}
    ./archiveLogs.sh obt-build

    WriteLog "Unit tests done" "${OBT_LOG_FILE}"
else
    WriteLog "                            " "${OBT_LOG_FILE}"   
    WriteLog "****************************" "${OBT_LOG_FILE}"
    WriteLog " Skip Unit tests...         " "${OBT_LOG_FILE}"
    WriteLog "                            " "${OBT_LOG_FILE}"
fi

if [ $RUN_REGRESSION -eq 1 ]
then
    #
    #--------------------------------------------------
    #
    # Regression test
    #

    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog "Execute Regression test" "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"
    
    cd ${OBT_BIN_DIR}
    ./regress.sh
    
    # Remove old builds
    ${BUILD_DIR}/bin/clean_builds.sh
    
    WriteLog "Regression test done" "${OBT_LOG_FILE}"


    # -----------------------------------------------------
    # 
    # Uninstall HPCC
    # 
    
    WriteLog "Uninstall HPCC-Platform" "${OBT_LOG_FILE}"
    
    cd ${BUILD_DIR}/${BUILD_TYPE}/build

    
    UninstallHPCC "${OBT_LOG_FILE}"
    
    WriteLog "Copy regression uninstall logs" "${OBT_LOG_FILE}"
    
    [ ! -d ${TARGET_DIR}/test ] && mkdir -p   ${TARGET_DIR}/test
    [ -f uninstall.log ] && cp uninstall.log     ${TARGET_DIR}/test/
    [ -f uninstall.summary ] && cp uninstall.summary ${TARGET_DIR}/test/

    redisMonitors=$( pgrep redis-cli )
    if [ -n "$redisMonitors" ]
    then
        WriteLog "Redis monitor pids: ${redisMonitors}" "${OBT_LOG_FILE}"
        redisMonitorsKill=$( pkill redis-cli 2>&1 )
        WriteLog "Kill Redis monitor result: '${redisMonitorsKill}'" "${OBT_LOG_FILE}"
    fi

else
    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog " Skip Regression test  " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"

        
fi


if [ $RUN_COVERAGE -eq 1 ]
then
    #-----------------------------------------------------------------------------
    #
    # Coverage
    # Placed here to avoid any disturbance to regression test execution and result handling

    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog "Execute Coverage test" "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"

    cd ${OBT_BIN_DIR}

    ./coverage.sh
    cp ~/test/coverage.summary   ${TARGET_DIR}/test/

    cd ${OBT_BIN_DIR}

    WriteLog "Archive coverage testing logs" "${OBT_LOG_FILE}"

    ./archiveLogs.sh coverage

    WriteLog "Coverage test done." "${OBT_LOG_FILE}"

    # -----------------------------------------------------
    # 
    # Uninstall HPCC
    # 
    
    WriteLog "Uninstall HPCC-Platform" "${OBT_LOG_FILE}"
    
    
    cd $TEST_ROOT
    
    UninstallHPCC "${OBT_LOG_FILE}"
    
    WriteLog "Copy regression uninstall logs" "${OBT_LOG_FILE}"
    
    [ ! -d ${TARGET_DIR}/test ] && mkdir -p   ${TARGET_DIR}/test
    [ -f uninstall.log ] && cp uninstall.log     ${TARGET_DIR}/test/
    [ -f uninstall.summary ] && cp uninstall.summary ${TARGET_DIR}/test/


else
    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog "  Skip Coverage test   " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"    
        
fi


if [ $RUN_PERFORMANCE -eq 1 ]
then
    #
    #-----------------------------------------------------------------------------
    #
    # Performance
    # Placed here to avoid any disturbance to regression test execution and result handling

    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog "Execute Performance test" "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"

    cd ${OBT_BIN_DIR}

    ./perftest.sh

    WriteLog "Copy log files to ${TARGET_DIR}/test/perf" "${OBT_LOG_FILE}"

    mkdir -p   ${TARGET_DIR}/test/perf

    cp -uv ~/HPCCSystems-regression/log/*.*   ${TARGET_DIR}/test/perf/

    WriteLog "Send Email notification about Performance test" "${OBT_LOG_FILE}"

    cd ${OBT_BIN_DIR}

    ./ReportPerfTestResult.py >> "${OBT_LOG_FILE}" 2>&1

    WriteLog "Performance test done." "${OBT_LOG_FILE}"

else
    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog " Skip Performance test " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"    

fi


#-----------------------------------------------------------------------------
#
# Stop disk space checker
#

WriteLog "Stop disk space checker" "${OBT_LOG_FILE}"

KillCheckDiskSpace

sleep 10

#-----------------------------------------------------------------------------
#
# End of OBT
#

WriteLog "End of OBT" "${OBT_LOG_FILE}"

cd ${OBT_BIN_DIR}

if [ $DRY_RUN -eq 1 ]
then
    ./archiveLogs.sh obt no
else
    ./archiveLogs.sh obt
fi
