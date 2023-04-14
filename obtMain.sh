#!/bin/bash

# For bash debug
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }' 

#
#------------------------------
#
# Imports (settings, functions)
#

#. ~/.bash_profile


# To ensure the TIMESTAMP is obtMain execution related.
unset OBT_TIMESTAMP
unset OBT_DATESTAMP

# Git branch settings

. ./settings.sh

# WriteLog() function

. ./timestampLogger.sh

# UninstallHPCC() fuction

. ./UninstallHPCC.sh

# Git branch cloning

. ./cloneRepo.sh

#
#------------------------------
#
# Constants 
#

# ------------------------------------------------
# Defined in settings.sh
#
#SHORT_DATE=$(date "+%Y-%m-%d")
#BUILD_DIR=~/build
#RELEASE_BASE=5.0
#STAGING_DIR=/tmount/data2/nightly_builds/HPCC/$RELEASE_BASE
#BUILD_SYSTEM=centos_6_x86_64
#BUILD_TYPE=CE/platform
#TARGET_DIR=${STAGING_DIR}/${SHORT_DATE}/${BUILD_SYSTEM}/${BUILD_TYPE}

#OBT_LOG_DIR=${BUILD_DIR}/bin
#OBT_BIN_DIR=${BUILD_DIR}/bin
# ------------------------------------------------

LONG_DATE=$(date "+%Y-%m-%d_%H-%M-%S")
OBT_LOG_FILE=${BUILD_DIR}/bin/obt-${LONG_DATE}.log

#
#------------------------------
#
# Function
#

ControlC()
# run if user hits control-c or process receives SIGTERM signal
{

    WriteLog "User break (Ctrl-c)!" "${OBT_LOG_FILE}"

    exitCode=$( echo $? )

    ExitEpilog "${OBT_LOG_FILE}" "exitCode"

}


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
                BUILD=0
                ;;
        ML*) 
                RUN_REGRESSION=0
                RUN_COVERAGE=0
                RUN_PERFORMANCE=0
                RUN_ML_TESTS=1
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


#
#----------------------------------------------------
#
# Start Overnight Build and Test process
#

WriteLog "OBT started ($0)" "${OBT_LOG_FILE}"

WriteLog "I am $( whoami)" "${OBT_LOG_FILE}"

WriteLog "Trap SIGINT, SIGTERM and SIGKILL signals" "${OBT_LOG_FILE}"
# trap keyboard interrupt (control-c) and SIGTERM signals
trap ControlC SIGINT
trap ControlC SIGTERM
trap ControlC SIGKILL


export PATH=$PATH:/usr/local/bin:/bin:/usr/local/sbin:/sbin:/usr/sbin:/mnt/disk1/home/vamosax/bin:
WriteLog "path:'${PATH}'" "${OBT_LOG_FILE}"

WriteLog "LD_LIBRARY_PATH:'${LD_LIBRARY_PATH}'" "${OBT_LOG_FILE}"
WriteLog "GCC: $(gcc --version | head -n 1)" "${OBT_LOG_FILE}"
WriteLog "CMake: $( /usr/local/bin/cmake --version | head -n 1)" "${OBT_LOG_FILE}"
WriteLog "Python: $(python --version )" "${OBT_LOG_FILE}"
WriteLog "Python2: $(python2 --version )" "${OBT_LOG_FILE}"
WriteLog "Python3: $(python3 --version )" "${OBT_LOG_FILE}"

STARTUP_MSG=""

if [[ "$BUILD" -eq 1 ]]
then
    STARTUP_MSG=${STARTUP_MSG}"build ($BUILD_TYPE)"
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
    #./archiveLogs.sh obt-cleanup timestamp=${OBT_TIMESTAMP}
    #exit -1
fi

WriteLog "pwd:$(pwd)" "${OBT_LOG_FILE}"


#
#---------------------------------------------------
#
# Increase number of user process
#

WriteLog "Increase stack size to ${OBT_SYSTEM_STACKSIZE}." "${OBT_LOG_FILE}"
ulimit -s ${OBT_SYSTEM_STACKSIZE}

WriteLog "Increase number of user process to ${OBT_SYSTEM_NUMBER_OF_PROCESS}." "${OBT_LOG_FILE}"
ulimit -u ${OBT_SYSTEM_NUMBER_OF_PROCESS}

WriteLog "Increase number of open files to ${OBT_SYSTEM_NUMBER_OF_FILES}." "${OBT_LOG_FILE}"
ulimit -n ${OBT_SYSTEM_NUMBER_OF_FILES}

res=$( ulimit -a | egrep '[pr]ocesses|open|stack' )

WriteLog "${res}" "${OBT_LOG_FILE}"

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

if [[ ${DISK_SPACE_MONITOR_START} -eq 1 ]]
then
   KillCheckDiskSpace "${OBT_LOG_FILE}"
   
   WriteLog "Start disk space checker" "${OBT_LOG_FILE}"
   
   ./checkDiskSpace.sh &
   echo $! > checkdiskspace.pid
fi


if [[ ${MY_INFO_MONITOR_START} -eq 1 ]]
then
    WriteLog "Start myInfo" "${OBT_LOG_FILE}"
    
    ./myInfo.sh &
    echo $! > myinfo.pid
fi

if [[ ${PORT_MONITOR_START} -eq 1 ]]
then
    WriteLog "Start port monitor" "${OBT_LOG_FILE}"

    (fn="myPortUsage-"$( date "+%Y-%m-%d_%H-%M-%S" )".log"; while true; do echo $( date "+%Y.%m.%d %H:%M:%S" ) >> ${fn}; sudo netstat -anp >> ${fn}; echo -e "---------------------------------\n" >> ${fn}; sleep 1; done ) &
    #(fn="myPortUsage-"$( date "+%Y-%m-%d_%H-%M-%S" )".log"; while true; do echo $( date "+%y.%m.%d %H:%M:%S" ) >> ${fn}; sudo ss -antp4 >> ${fn}; echo -e "------------------------------------------\n" >> ${fn}; sleep 1; done ) &
    
    echo $! > portlog.pid
fi

if [[ ${HTHOR_STACK_MONITOR_START} -eq 1 ]]
then
    WriteLog "Hthor start stack monitor" "${OBT_LOG_FILE}"

    (fn="HthorStackUsage-"$( date "+%Y-%m-%d_%H-%M-%S" )".log"; while true; do echo $( date "+%Y.%m.%d %H:%M:%S" ) >> ${fn}; sudo netstat -anp >> ${fn}; echo -e "---------------------------------\n" >> ${fn}; sleep 1; done ) &
    #(fn="myPortUsage-"$( date "+%Y-%m-%d_%H-%M-%S" )".log"; while true; do echo $( date "+%y.%m.%d %H:%M:%S" ) >>$

    echo $! > hthorStackMonitorLog.pid
fi


#
#----------------------------------------------------
#
# Un-install HPCC Systems
#

WriteLog "Un-install HPCC Systems" "${OBT_LOG_FILE}"

#cd $TEST_ROOT

if [[ "$RUN_REGRESSION" -eq 1 ]]
then
    UninstallHPCC "${OBT_LOG_FILE}" "${REGRESSION_WIPE_OFF_HPCC}"
fi

if [[ "$RUN_PERFORMANCE" -eq 1 ]]
then
    UninstallHPCC "${OBT_LOG_FILE}" "${PERF_WIPE_OFF_HPCC}"
fi


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

WriteLog "Free memory is: $( GetFreeMemGB )" "${OBT_LOG_FILE}"

freeMem=$( GetFreeMem )

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
        sleep 20

        freeMem=$( GetFreeMem )

        if [[ $freeMem -lt ${MEMORY_LIMIT} ]]
        then
            WriteLog "The free memory $( GetFreeMemGB ) is too low!" "${OBT_LOG_FILE}"
        
            # send email to Agyi
            #echo "After the kill Cassandra the OBT Free memory $( GetFreeMemGB ) is still too low!" | mailx -s "OBT Memory problem" -u $USER  ${ADMIN_EMAIL_ADDRESS}

            #ExitEpilog
        else
            WriteLog "The free memory is $( GetFreeMemGB )." "${OBT_LOG_FILE}"
        fi
    else
        WriteLog "Cassandra doesn't run but the free memory ($( GetFreeMemGB )) is too low!" "${OBT_LOG_FILE}"

        WriteLog "Try to kill Kafka and zookeeper" "${OBT_LOG_FILE}" 
        killKafka=$( ps ax | grep '[K]afka' | awk '{print $1 }' | while read pid; do echo "kill $pid"; sudo kill -9 $pid; done; )
        WriteLog "${killKafka}" "${OBT_LOG_FILE}"
        sleep 20

        killZookeeper=$( ps ax | grep '[z]ook' | awk '{print $1 }' | while read pid; do echo "kill $pid"; sudo kill -9 $pid; done; )
        WriteLog "${killZookeeper}" "${OBT_LOG_FILE}"
        sleep 20

        rm -fr /tmp/zookeeper /tmp/kafka-log

        WriteLog "The free memory is $( GetFreeMemGB )!" "${OBT_LOG_FILE}"
    fi

    clearOsCache=$( free; sudo sync; echo 3 | sudo tee /proc/sys/vm/drop_caches; free )
    WriteLog "Clear Os cache result:\n${clearOsCache}" "${OBT_LOG_FILE}"

    WriteLog "The free memory is $( GetFreeMemGB )!" "${OBT_LOG_FILE}"

fi


cassandraPID=$( ps ax  | grep '[c]assandra' | awk '{print $1}' )

if [[ -n "$cassandraPID" ]]
then

    WriteLog "Try to kill Cassandra (pid: ${cassandraPID})" "${OBT_LOG_FILE}"

    sudo kill -9 ${cassandraPID}
    sleep 20

    WriteLog "The free memory is $( GetFreeMemGB )!" "${OBT_LOG_FILE}"
fi

WriteLog "Try to kill Kafka and zookeeper" "${OBT_LOG_FILE}" 
killKafka=$( ps ax | grep '[K]afka' | awk '{print $1 }' | while read pid; do echo "kill Kafka (pid:$pid)"; sudo kill -9 $pid; done; )
WriteLog "Kafka result:${killKafka}" "${OBT_LOG_FILE}"
sleep 20

killZookeeper=$( ps ax | grep '[z]ook' | awk '{print $1 }' | while read pid; do echo "kill Zookeeper (pid:$pid)"; sudo kill -9 $pid; done; )
WriteLog "Zookeeper result:${killZookeeper}" "${OBT_LOG_FILE}"
sleep 20

KillJava "${OBT_LOG_FILE}"

WriteLog "Check Couchbase state" "${OBT_LOG_FILE}"

if [ -f /opt/couchbase/bin/couchbase-server ]
then
    # It is not as resurce hungry beast as Cassandra and Kafka, so leave it alone
    #WriteLog "Try to kill Couchbase" "${OBT_LOG_FILE}" 
    #killCouchbase=$( sudo /opt/couchbase/bin/couchbase-server -k )
    #WriteLog "Couchbase result:${killCouchbase}" "${OBT_LOG_FILE}"

    couchbaseState=$(  ps aux | egrep -ic 'couchbase-server' )
    if [[ ${couchbaseState} -ne 0 ]]
    then
        WriteLog "Couchbase is up." "${OBT_LOG_FILE}"
    else
        WriteLog "Couchbase is down." "${OBT_LOG_FILE}"
    fi
else
    WriteLog "It is not exist, skip it." "${OBT_LOG_FILE}"
fi

#
#----------------------------------------------------
#
# Update BuildNotification.ini and ReportPerfTestResult.ini to use proper branch, build system id ans for old OBT IP of mounted log server
#
    pushd ${OBT_BIN_DIR} > /dev/null

    WriteLog "pwd:$(pwd)" "${OBT_LOG_FILE}"
    WriteLog "Update 'BuildBranch' in BuildNotification.ini" "${OBT_LOG_FILE}"

    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed -e '/# Gen\(.*\)/d' -e '/# Upd\(.*\)/d' -e '/^BuildBranch : \(.*\)/c # Updated by OBT @ '"$( date '+%Y-%m-%d %H:%M:%S' )"' \nBuildBranch : '${BRANCH_ID} ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini

    # Get build branch
    WriteLog "Build branch is: '${BRANCH_ID}'" "${OBT_LOG_FILE}"

    WriteLog "Update 'BuildBranch' in ReportPerfTestResult.ini" "${OBT_LOG_FILE}"

    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed -e '/# Gen\(.*\)/d' -e '/# Upd\(.*\)/d' -e '/^BuildBranch : \(.*\)/c # Updated by OBT @ '"$( date '+%Y-%m-%d %H:%M:%S' )"' \nBuildBranch : '${BRANCH_ID} ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini

    # Get system info 
    WriteLog "System ID is: '${SYSTEM_ID}'" "${OBT_LOG_FILE}"

    WriteLog "Update 'BuildSystem' in BuildNotification.ini" "${OBT_LOG_FILE}"

    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed 's/^BuildSystem\(.*\)/BuildSystem : '"${SYSTEM_ID}"'/g' ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini

    WriteLog "Update 'BuildSystem' in ReportPerfTestResult.ini" "${OBT_LOG_FILE}"

    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed 's/^BuildSystem\(.*\)/BuildSystem : '"${SYSTEM_ID}"'/g' ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini

    # Get BUILD TYPE info 
    WriteLog "BuildType is: '${BUILD_TYPE}'" "${OBT_LOG_FILE}"

    WriteLog "Update 'BuildType' in BuildNotification.ini" "${OBT_LOG_FILE}"
    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed  -e '/^BuildType : \(.*\)/c BuildType : '${BUILD_TYPE} ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini

    WriteLog "Update 'BuildType' in ReportPerfTestResult.ini" "${OBT_LOG_FILE}"
    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed  -e '/^BuildType : \(.*\)/c BuildType : '${PERF_BUILD_TYPE} ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini
    
    
    WriteLog "Update 'ThorSlaves' in BuildNotification.ini to ${REGRESSION_NUMBER_OF_THOR_SLAVES}" "${OBT_LOG_FILE}"
    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed  -e '/^ThorSlaves : \(.*\)/c ThorSlaves : '${REGRESSION_NUMBER_OF_THOR_SLAVES} ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini
    
    
    WriteLog "Update 'ThorSlaves' in ReportPerfTestResult.ini to ${PERF_THOR_NUMBER_OF_SLAVES}" "${OBT_LOG_FILE}"
    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed  -e '/^ThorSlaves : \(.*\)/c ThorSlaves : '${PERF_THOR_NUMBER_OF_SLAVES} ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini
    

    WriteLog "Update 'ThorChannelsPerSlave ' in BuildNotification.ini to ${REGRESSION_NUMBER_OF_THOR_CHANNELS}" "${OBT_LOG_FILE}"
    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed  -e '/^ThorChannelsPerSlave : \(.*\)/c ThorChannelsPerSlave : '${REGRESSION_NUMBER_OF_THOR_CHANNELS} ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini
    
    
    WriteLog "Update 'ThorChannelsPerSlave ' in ReportPerfTestResult.ini to ${PERF_NUMBER_OF_THOR_CHANNELS}" "${OBT_LOG_FILE}"
    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed  -e '/^ThorChannelsPerSlave : \(.*\)/c ThorChannelsPerSlave : '${PERF_NUMBER_OF_THOR_CHANNELS} ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini
 

    WriteLog "Update 'urlBase ' in BuildNotification.ini to ${URL_BASE}" "${OBT_LOG_FILE}"
    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed  -e '/^urlBase : \(.*\)/c urlBase : '${URL_BASE} ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini
    
    
    WriteLog "Update 'shareBase ' in BuildNotification.ini to ${STAGING_DIR_ROOT}" "${OBT_LOG_FILE}"
    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed  -e '/^shareBase : \(.*\)/c shareBase : '${STAGING_DIR_ROOT} ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini
    
    

    WriteLog "Update 'ObtSystem' in BuildNotification.ini to ${OBT_SYSTEM}" "${OBT_LOG_FILE}"
    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed  -e '/^ObtSystem : \(.*\)/c ObtSystem : '${OBT_SYSTEM} ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini
    
    
    WriteLog "Update 'ObtSystem' in ReportPerfTestResult.ini to ${OBT_SYSTEM}" "${OBT_LOG_FILE}"
    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed  -e '/^ObtSystem : \(.*\)/c ObtSystem : '${OBT_SYSTEM} ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini
    
    
    WriteLog "Update 'ObtSystemEnv ' in BuildNotification.ini to ${OBT_SYSTEM_ENV}" "${OBT_LOG_FILE}"
    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed  -e '/^ObtSystemEnv : \(.*\)/c ObtSystemEnv : '${OBT_SYSTEM_ENV} ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini
    
    
    WriteLog "Update 'ObtSystemEnv ' in ReportPerfTestResult.ini to ${OBT_SYSTEM_ENV}" "${OBT_LOG_FILE}"
    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed  -e '/^ObtSystemEnv : \(.*\)/c ObtSystemEnv : '${OBT_SYSTEM_ENV} ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini


    WriteLog "Update 'ObtSystemHw in BuildNotification.ini to CPU/Cores: ${NUMBER_OF_CPUS}, RAM: ${MEMORY} GB" "${OBT_LOG_FILE}"
    cp -f ./BuildNotification.ini ./BuildNotification.bak
    sed  -e '/^ObtSystemHw : \(.*\)/c ObtSystemHw : "'"CPU/Cores: ${NUMBER_OF_CPUS}, RAM: ${MEMORY} GB"'"' ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini
    
    
    WriteLog "Update 'ObtSystemHw' in ReportPerfTestResult.ini to CPU/Cores: ${NUMBER_OF_CPUS}, RAM: ${MEMORY} GB" "${OBT_LOG_FILE}"
    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed  -e '/^ObtSystemHw : \(.*\)/c ObtSystemHw : "'"CPU/Cores: ${NUMBER_OF_CPUS}, RAM: ${MEMORY} GB"'"' ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini


    WriteLog "Update 'TestMode' in ReportPerfTestResult.ini to TestMode: ${PERF_TEST_MODE}" "${OBT_LOG_FILE}"
    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed  -e '/^TestMode : \(.*\)/c TestMode : '${PERF_TEST_MODE} ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini


    WriteLog "Update 'ObtLogDir' in ReportPerfTestResult.ini to ObtLogDir : ${OBT_LOG_DIR}" "${OBT_LOG_FILE}"
    cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
    sed  -e '/^ObtLogDir : \(.*\)/c ObtLogDir : '${OBT_LOG_DIR} ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini 

    if [ -n "$OBT_ID" ]
    then
        sender=$REGRESSION_REPORT_SENDER
        [[ -z "$sender" ]] && sender="testfarm.${OBT_ID,,}@lexisnexisrisk.com"
        
        WriteLog "Update 'Sender' in BuildNotification.ini to Sender : $sender" "${OBT_LOG_FILE}"
        cp -f ./BuildNotification.ini ./BuildNotification.bak
        sed  -e '/^Sender : \(.*\)/c Sender : '"$sender" ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini 
    
        WriteLog "Update 'Sender' in ReportPerfTestResult.ini to Sender : $sender" "${OBT_LOG_FILE}"
        cp -f ./ReportPerfTestResult.ini ./ReportPerfTestResult.bak
        sed  -e '/^Sender : \(.*\)/c Sender : '"$sender" ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini
    fi
    
    if [[ -n "$REGRESSION_REPORT_RECEIVERS" ]]
    then
        WriteLog "Update 'Receivers' in BuildNotification.ini to Receivers : ${REGRESSION_REPORT_RECEIVERS}" "${OBT_LOG_FILE}"
        cp -f ./BuildNotification.ini ./BuildNotification.bak
        sed  -e '/^Receivers : \(.*\)/c Receivers : '"${REGRESSION_REPORT_RECEIVERS}" ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini 
    else
        WriteLog "The 'REGRESSION_REPORT_RECEIVERS' not defined in settings.sh keep the original value" "${OBT_LOG_FILE}"
    fi
    
    if [[ -n "$REGRESSION_REPORT_RECEIVERS_WHEN_NEW_COMMIT" ]]
    then
        WriteLog "Update 'ReceiversWhenNewCommit' in BuildNotification.ini to ReceiversWhenNewCommit : ${REGRESSION_REPORT_RECEIVERS_WHEN_NEW_COMMIT}" "${OBT_LOG_FILE}"
        cp -f ./BuildNotification.ini ./BuildNotification.bak
        sed  -e '/^ReceiversWhenNewCommit : \(.*\)/c ReceiversWhenNewCommit : '"${REGRESSION_REPORT_RECEIVERS_WHEN_NEW_COMMIT}" ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini 
    else
        WriteLog "The 'REGRESSION_REPORT_RECEIVERS_WHEN_NEW_COMMIT' not defined in settings.sh keep the original value" "${OBT_LOG_FILE}"
    fi
    
    # Check if it is an old OBT system with 'urlBase : http://<IP>/data2/...'
    isOldOBT=$(  cat BuildNotification.ini | grep -c -i 'data2' )

    if [[ $isOldOBT -ne 0 ]]
    then
        # Get Log Server ip from mount 
        # (The logserver directory mounted as a share, it can read from the output of mount)

        logServerIP=$(  mount | grep -i 'data2' | cut -d: -f1 )
        WriteLog "Log server IP ($logServerIP) " "${OBT_LOG_FILE}"

        WriteLog "Update log server IP of 'urlBase' in BuildNotification.ini" "${OBT_LOG_FILE}"
        sed -e '/^urlBase : \(.*\)/c # Updated by OBT @ '"$( date '+%Y-%m-%d %H:%M:%S' )"' \nurlBase : http:\/\/'"${logServerIP}"'\/data2\/nightly_builds\/HPCC' ./BuildNotification.ini > ./BuildNotification.tmp && mv -f ./BuildNotification.tmp ./BuildNotification.ini

        WriteLog "Update log server IP of 'urlBase' in ReportPerfTestResult.ini" "${OBT_LOG_FILE}"
        sed -e '/^urlBase : \(.*\)/c # Updated by OBT @ '"$( date '+%Y-%m-%d %H:%M:%S' )"' \nurlBase : http:\/\/'"${logServerIP}"'\/data2\/nightly_builds\/HPCC' ./ReportPerfTestResult.ini > ./ReportPerfTestResult.tmp && mv -f ./ReportPerfTestResult.tmp ./ReportPerfTestResult.ini
    fi

    WriteLog "Update success !" "${OBT_LOG_FILE}"
    popd > /dev/null

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
    
    ./build.sh

    if [[ 0 -ne  $? ]]
    then
        ExitEpilog "${OBT_LOG_FILE}" "-1"
    fi


    KillJava "${OBT_LOG_FILE}"
    
    #if [ $RUN_UNITTESTS -ne 1 ]
    #then
        # Unit tests doesn't run, so archive build logs now
        cd ${OBT_BIN_DIR}
        ./archiveLogs.sh obt-build timestamp=${OBT_TIMESTAMP}
    #fi

else
    WriteLog "                            " "${OBT_LOG_FILE}"   
    WriteLog "****************************" "${OBT_LOG_FILE}"
    WriteLog " Skip build HPCC Platform..." "${OBT_LOG_FILE}"
    WriteLog "                            " "${OBT_LOG_FILE}"   
fi


#
#--------------------------------------------------
#
# Run coverity 
#

if [ $RUN_COVERITY -eq 1 ]
then
    WriteLog "                       " "${OBT_LOG_FILE}"
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog "     Run coverity      " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"

    res=$( ./runCoverity.sh 2>&1 )

    WriteLog "Result is: ${res}" "${OBT_LOG_FILE}"
else
    WriteLog "                            " "${OBT_LOG_FILE}"   
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog "   Skip Coverity...    " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"   
        
fi



#
#--------------------------------------------------
#
# Unit and wutool tests
#

if [ $RUN_UNITTESTS -eq 1 ]
then
    WriteLog "                       " "${OBT_LOG_FILE}"
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog " Execute Unit tests    " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"

    res=$( ${SUDO} ${PKG_INST_CMD} ${BUILD_HOME}/hpccsystems-platform?community*.rpm 2>&1 )

    echo "${res}" > install.log
    WriteLog "Install result is:\n${res}" "${OBT_LOG_FILE}"

    cd ${OBT_BIN_DIR}

    WriteLog "Unittests param: '${UNITTESTS_PARAM}'" "${OBT_LOG_FILE}"
    ./unittest.sh ${UNITTESTS_PARAM}
    
    if [ ! -e ${TARGET_DIR}/test ]
    then
        WriteLog "Create ${TARGET_DIR}/test directory..." "${OBT_LOG_FILE}"
        mkdir -p ${TARGET_DIR}/test
    fi

    WriteLog "Copy unittest result files to ${TARGET_DIR}..." "${OBT_LOG_FILE}"
    cp ${OBT_LOG_DIR}/unittest*.log   ${TARGET_DIR}/test/
    cp ${OBT_LOG_DIR}/unittests.summary   ${TARGET_DIR}/test/
    
    # Archive build an unit tests logs
    cd ${OBT_BIN_DIR}
    ./archiveLogs.sh intern-unitt timestamp=${OBT_TIMESTAMP}

    WriteLog "Unit tests done" "${OBT_LOG_FILE}"
else
    WriteLog "                            " "${OBT_LOG_FILE}"   
    WriteLog "****************************" "${OBT_LOG_FILE}"
    WriteLog " Skip Unit tests...         " "${OBT_LOG_FILE}"
    WriteLog "                            " "${OBT_LOG_FILE}"
fi

if [ $RUN_WUTOOL_TESTS -eq 1 ]
then
    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog " Execute WUtool tests  " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"
    
    # Check if the HPCC System installed
    if [[ ! -f /etc/init.d/hpcc-init ]]
    then
        WriteLog "Install HPCC Systems" "${OBT_LOG_FILE}"

        ${SUDO} ${PKG_INST_CMD} ${BUILD_HOME}/hpccsystems-platform?community*.rpm > install.log 2>&1
    fi

    cd ${OBT_BIN_DIR}
    ./wutoolTest.sh
    
    if [ ! -e ${TARGET_DIR}/test ]
    then
        WriteLog "Create ${TARGET_DIR}/test directory..." "${OBT_LOG_FILE}"
        mkdir -p ${TARGET_DIR}/test
    fi

    WriteLog "Copy wutool result files to ${TARGET_DIR}..." "${OBT_LOG_FILE}"
    cp ${OBT_LOG_DIR}/wutoolTests.log   ${TARGET_DIR}/test/wutooltests.log
    cp ${OBT_LOG_DIR}/wutoolTest*.summary   ${TARGET_DIR}/test/wutooltests.summary
    
    # Archive build an unit tests logs
    cd ${OBT_BIN_DIR}
    ./archiveLogs.sh intern-wutool timestamp=${OBT_TIMESTAMP}

    WriteLog "WUtool tests done" "${OBT_LOG_FILE}"
else
    WriteLog "                            " "${OBT_LOG_FILE}"   
    WriteLog "****************************" "${OBT_LOG_FILE}"
    WriteLog " Skip WUtool tests...         " "${OBT_LOG_FILE}"
    WriteLog "                            " "${OBT_LOG_FILE}"
fi



if [ $RUN_ML_TESTS -eq 1 ]
then
    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog "   Execute ML tests    " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"
    
    # Check if the HPCC System installed
    if [[ ! -f /etc/init.d/hpcc-init ]]
    then
        WriteLog "Install HPCC Systems" "${OBT_LOG_FILE}"
        ${SUDO} ${PKG_INST_CMD} ${BUILD_HOME}/hpccsystems-platform?community*.rpm > install.log 2>&1
    fi

    cd ${OBT_BIN_DIR}
    #./mltest.sh
    ./bundleTest.sh
    

    cd ${OBT_BIN_DIR}

#    if [ ! -e ${TARGET_DIR}/test/ML ]
#    then
#        WriteLog "Create ${TARGET_DIR}/test/ML directory..." "${OBT_LOG_FILE}"
#        mkdir -p ${TARGET_DIR}/test/ML
#    fi

#    # Copy test summary to Wiki
#    WriteLog "Copy ML test result files from ${LOG_DIR} to ${TARGET_DIR}..." "${OBT_LOG_FILE}"
#
#    WriteLog "--->${LOG_DIR}/ml-....log" "${OBT_LOG_FILE}"
#    WriteLog "--->$(ls -l ${LOG_DIR}/ )" "${OBT_LOG_FILE}"
#    res=$( cp -v ${LOG_DIR}/ml-*.log ${TARGET_DIR}/test/  2>&1 )
#    WriteLog "---->res:${res}" "${OBT_LOG_FILE}"
#
#    WriteLog "--_>mltests.summary" "${OBT_LOG_FILE}"
#    res=$( cp -v mltests.summary ${TARGET_DIR}/test/mltests.summary 2>&1 )
#    WriteLog "---->res:${res}" "${OBT_LOG_FILE}"
#    
    # To-DO Should check it there is any ZAP file
    #WriteLog "  ZAP file(s)" "${OBT_LOG_FILE}"
    #cp ${ZAP_DIR}/* ${TARGET_DIR}/test/ZAP/

    # Archive  logs
    WriteLog "Archive ${TARGET_PLATFORM} ML logs" "${OBT_LOG_FILE}"
    
    ./archiveLogs.sh ml-${TARGET_PLATFORM} timestamp=${OBT_TIMESTAMP}

    WriteLog "ML tests done" "${OBT_LOG_FILE}"
else
    WriteLog "                            " "${OBT_LOG_FILE}"   
    WriteLog "****************************" "${OBT_LOG_FILE}"
    WriteLog " Skip ML tests...           " "${OBT_LOG_FILE}"
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
    #${BUILD_DIR}/bin/clean_builds.sh
    
    WriteLog "Regression test done" "${OBT_LOG_FILE}"


    if [ $RUN_WUTEST -eq 0 ]
    then
        # -----------------------------------------------------
        # 
        # Uninstall HPCC
        # 
    
        WriteLog "Uninstall HPCC-Platform" "${OBT_LOG_FILE}"

        [ -d ${BUILD_DIR}/${BUILD_TYPE}/build ] && cd ${BUILD_DIR}/${BUILD_TYPE}/build

        UninstallHPCC "${OBT_LOG_FILE}" "${REGRESSION_WIPE_OFF_HPCC}"
    
        WriteLog "Copy regression uninstall logs" "${OBT_LOG_FILE}"
    
        [ ! -d ${TARGET_DIR}/test ] && mkdir -p   ${TARGET_DIR}/test
        [ -f uninstall.log ] && cp uninstall.log     ${TARGET_DIR}/test/
        [ -f uninstall.summary ] && cp uninstall.summary ${TARGET_DIR}/test/
    fi

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


if [ $RUN_WUTEST -eq 1 ]
then
    #-----------------------------------------------------------------------------
    #
    # wutest
    #

    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog "   Execute wutest.py   " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"

    if [[ -d "${WUTEST_HOME}" && -f "${WUTEST_HOME}/wutest.py" ]]
    then
        cd ${WUTEST_HOME}
        WriteLog "Execute: ${WUTEST_BIN} " "${OBT_LOG_FILE}"
        set -x

        LOG_DATE=$(date "+%Y-%m-%d_%H-%M-%S")
        WUTEST_LOG_FILE="${WUTEST_LOG_DIR}/wutest-${LOG_DATE}.log"
        WUTEST_SUMMARY_FILE=${WUTEST_LOG_DIR}/wutest.summary

        ${WUTEST_CMD} >> $WUTEST_LOG_FILE 2>&1

        WriteLog "Archieve wutest results directory: '${WUTEST_RESULT_DIR}' " "${OBT_LOG_FILE}"
        # Pack the result directory into ${WUTEST_LOG_DIR}
        zip ${WUTEST_LOG_DIR}/wutest-result-${LOG_DATE} ${WUTEST_RESULT_DIR}/*

        # Create wutest.summary file
        # [INFO] Success count: 22
        # [INFO] Failure count: 24
        INFO=$( egrep -i '\[INFO\] (succ|fail)' ${WUTEST_LOG_FILE} )

        if [ -n "$INFO" ]
        then
            success=0
            failure=0

            success=$( echo $INFO | sed -n "s/^\(.*\)Success count\:[[:space:]]*\([0-9]*\).*$/\2/p" )

            failure=$( echo $INFO | sed -n "s/^\(.*\)Failure count\:[[:space:]]*\([0-9]*\).*$/\2/p" )

            total=$(( $success + $failure ))

            WriteLog "TestResult:wutest:total :${total} passed:${success} failed:${failure}"  "${OBT_LOG_FILE}"    
            echo "TestResult:wutest:total:${total} passed:${success} failed:${failure}" >> $WUTEST_SUMMARY_FILE   
        else
            WriteLog "Wrong result generated." "${OBT_LOG_FILE}"
        fi
         
        set +x

        cd ${OBT_BIN_DIR}

        # -----------------------------------------------------
        # 
        # Uninstall HPCC
        # 
    
        WriteLog "Uninstall HPCC-Platform" "${OBT_LOG_FILE}"

        [ -d ${BUILD_DIR}/${BUILD_TYPE}/build ] && cd ${BUILD_DIR}/${BUILD_TYPE}/build

        UninstallHPCC "${OBT_LOG_FILE}" "${REGRESSION_WIPE_OFF_HPCC}"
    
        WriteLog "Copy regression uninstall logs" "${OBT_LOG_FILE}"
    
        [ ! -d ${TARGET_DIR}/test ] && mkdir -p   ${TARGET_DIR}/test
        [ -f uninstall.log ] && cp uninstall.log     ${TARGET_DIR}/test/
        [ -f uninstall.summary ] && cp uninstall.summary ${TARGET_DIR}/test/
    else
        WriteLog "wutest not found." "${OBT_LOG_FILE}"
    fi

    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog "     Wutest done.      " "${OBT_LOG_FILE}"
    WriteLog "                       " "${OBT_LOG_FILE}"
else
    WriteLog "                       " "${OBT_LOG_FILE}"    
    WriteLog "***********************" "${OBT_LOG_FILE}"
    WriteLog "   Skip wutest test    " "${OBT_LOG_FILE}"
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

    ./archiveLogs.sh coverage timestamp=${OBT_TIMESTAMP}

    WriteLog "Coverage test done." "${OBT_LOG_FILE}"

    # -----------------------------------------------------
    # 
    # Uninstall HPCC
    # 
    
    WriteLog "Uninstall HPCC-Platform" "${OBT_LOG_FILE}"
    
    cd $TEST_ROOT
    
    UninstallHPCC "${OBT_LOG_FILE}" "${REGRESSION_WIPE_OFF_HPCC}"
    
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

    if [[ 0 -eq  $? ]]
    then
        WriteLog "Copy log files to ${TARGET_DIR}/test/perf" "${OBT_LOG_FILE}"

        mkdir -p   ${TARGET_DIR}/test/perf

        cp -uv ~/HPCCSystems-regression/log/*.*   ${TARGET_DIR}/test/perf/

        if [ $PERF_ENABLE_CALCTREND -eq 1 ]
        then
            WriteLog "Calculate and report results" "${OBT_LOG_FILE}"

            WriteLog "python3 ./calcTrend2.py3 -d ../../Perfstat/ ${PERF_CALCTREND_PARAMS}" "${OBT_LOG_FILE}"
            #./calcTrend2.py -d ../../Perfstat/ ${PERF_CALCTREND_PARAMS} >> "${OBT_LOG_FILE}" 2>&1
            python3 ./calcTrend2.py3 -d ../../Perfstat/ ${PERF_CALCTREND_PARAMS} >> "${OBT_LOG_FILE}" 2>&1

            WriteLog "Copy diagrams to ${TARGET_DIR}/test/diagrams" "${OBT_LOG_FILE}"

            mkdir -p   ${TARGET_DIR}/test/diagrams
            mkdir -p   ${TARGET_DIR}/test/diagrams/hthor
            mkdir -p   ${TARGET_DIR}/test/diagrams/thor
            mkdir -p   ${TARGET_DIR}/test/diagrams/roxie

            cp perftest*.png ${TARGET_DIR}/test/diagrams/
            cp *-hthor-*.png ${TARGET_DIR}/test/diagrams/hthor/
            cp *-thor-*.png ${TARGET_DIR}/test/diagrams/thor/
            cp *-roxie-*.png ${TARGET_DIR}/test/diagrams/roxie/
        else
             WriteLog "Calculate and report results skiped" "${OBT_LOG_FILE}"
        fi

        cp ./perftest*.summary ./perftest.summary

        WriteLog "Send Email notification about Performance test" "${OBT_LOG_FILE}"

        ./ReportPerfTestResult.py -d ${OBT_DATESTAMP} -t ${OBT_TIMESTAMP} >> "${OBT_LOG_FILE}" 2>&1
    else
        WriteLog "Build for performane test is failed." "${OBT_LOG_FILE}"
    fi
    WriteLog "Performance test done." "${OBT_LOG_FILE}"

    # send email to Agyi to schedule tuning suite test
    echo "Standard performanc test done. You can schedule a tuning test!" | mailx -s "Ready for tuning test" -u $USER  ${ADMIN_EMAIL_ADDRESS}

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

KillCheckDiskSpace "${OBT_LOG_FILE}"

sleep 10

#-----------------------------------------------------------------------------
#
# House keeping
#


#
# Remove old remote/WEB logs
#

WriteLog "Number of directories in ${STAGING_DIR_ROOT}:" "${OBT_LOG_FILE}"
NEW_DIRS=$(find ${STAGING_DIR_ROOT} -maxdepth 1 -type d | egrep 'candi|master' | while read p; do n=$( find $p -maxdepth 1 -type d | wc -l); echo "$p: $n"; done)
WriteLog "${NEW_DIRS}"  "${OBT_LOG_FILE}"

OLD_DIRS_COUNT=$( find ${STAGING_DIR_ROOT} -maxdepth 2 -mtime +${WEB_LOG_ARCHIEVE_DIR_EXPIRE} -iname '*20??*' -type d  | wc -l) 

if [[  $OLD_DIRS_COUNT -ge 1 ]]
then
    WriteLog "Remove all log archive directory older than ${WEB_LOG_ARCHIEVE_DIR_EXPIRE} days from ${STAGING_DIR_ROOT}." "${OBT_LOG_FILE}"
    OLD_DIRS=( $( find ${STAGING_DIR_ROOT} -maxdepth 2 -mtime +${WEB_LOG_ARCHIEVE_DIR_EXPIRE} -iname '*20??*' -type d ) )

    WriteLog "${#OLD_DIRS[@]} old directory found and to be removed." "${OBT_LOG_FILE}"
    WriteLog "${OLD_DIRS[@]}" "${OBT_LOG_FILE}"
    
    #TO-DO  Something wrong with this command. It removed all directory in ${STAGING_DIR_ROOT} (not only the oldest one)
    res=$( find ${STAGING_DIR_ROOT} -maxdepth 2 -mtime +${WEB_LOG_ARCHIEVE_DIR_EXPIRE} -iname '*20??*' -type d -print -exec rm -rf '{}' \; 2>&1 )
    #res=$( find ${STAGING_DIR_ROOT} -maxdepth 2 -mtime +${WEB_LOG_ARCHIEVE_DIR_EXPIRE} -type d -print 2>&1 )

    WriteLog "res:${res}" "${OBT_LOG_FILE}"
    # send email to Agyi
    (echo "On $OBT_DATESTAMP $OBT_TIMESTAMP in $OBT_SYSTEM (branch: $BRANCH_ID, WEB_LOG_ARCHIEVE_DIR_EXPIRE is:${WEB_LOG_ARCHIEVE_DIR_EXPIRE}) ${#OLD_DIRS[@]} old directory found."; echo "${res}"; echo "Number of directories in ${STAGING_DIR_ROOT}:"; echo "${NEW_DIRS}" ) | mailx -s "OBT WEB archive clean up" -u $USER  ${ADMIN_EMAIL_ADDRESS}
    
else
    WriteLog "There is no old directory in ${STAGING_DIR_ROOT} area." "${OBT_LOG_FILE}"
    
    # send email to Agyi
    #echo "On $OBT_DATESTAMP $OBT_TIMESTAMP the value of WEB_LOG_ARCHIEVE_DIR_EXPIRE is:${WEB_LOG_ARCHIEVE_DIR_EXPIRE} is smaller than the expected on $OBT_SYSTEM ($BRANCH_ID)" | mailx -s "OBT WEB_LOG_ARCHIEVE_DIR_EXPIRE problem" -u $USER  ${ADMIN_EMAIL_ADDRESS}
fi

WriteLog "\tdone." "${OBT_LOG_FILE}"

#
# Clean up in /tmp/ directory
#

WriteLog "Remove files and direrctories from /tmp/ drirectory older than 3 days" "${OBT_LOG_FILE}"

dirCount=$( sudo find /tmp/ -mtime +2 -type d -print | wc -L )

sudo find /tmp/ -mtime +2 -type d -print -exec rm -rf '{}' \;

fileCount=$( sudo find /tmp/ -mtime +2 -type f -print | wc -l )

sudo find /tmp/ -mtime +2 -type f -print -exec rm  '{}' \;

WriteLog "${dirCount} directories and ${fileCount} files are removed." "${OBT_LOG_FILE}"

WriteLog "End of cleanup." "${OBT_LOG_FILE}"


#-----------------------------------------------------------------------------
#
# End of OBT
#

cd ${OBT_BIN_DIR}

if [ $DRY_RUN -eq 1 ]
then
    ./archiveLogs.sh obt-exit timestamp=${OBT_TIMESTAMP} nopub
else
    ./archiveLogs.sh obt-exit timestamp=${OBT_TIMESTAMP}
fi

#
# Delete the generated settings.inc
#

WriteLog "Delete the generated settings.inc" "${OBT_LOG_FILE}"

[ -f settings.inc ] && rm -f settings.inc

WriteLog "End of OBT." "${OBT_LOG_FILE}"

