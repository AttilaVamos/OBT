#!/bin/bash
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

set -a

#
#----------------------------------------------------
#
# Get system info 
#

SYSTEM_ID=$( cat /etc/*-release | egrep -i "^PRETTY_NAME" | cut -d= -f2 | tr -d '"' )
if [[ "${SYSTEM_ID}" == "" ]]
then
    SYSTEM_ID=$( cat /etc/*-release | head -1 )
fi

if [[ "$SYSTEM_ID" =~ "Ubuntu" ]]
then
    OS_ID=$(echo $SYSTEM_ID | awk '{ print $1$2 }') 
else
    OS_ID=$(echo $SYSTEM_ID | awk '{ print$1$3 }'  )
fi

SYSTEM_ID=${SYSTEM_ID// (*)/}
SYSTEM_ID=${SYSTEM_ID// /_}
SYSTEM_ID=${SYSTEM_ID//./_}


# A day when we build Debug version
# Use 8 for disable Debug build
DEBUG_BUILD_DAY=0  # Sunday
BUILD_TYPE=RelWithDebInfo

WEEK_DAY=$(date "+%w")

if [[ $WEEK_DAY -eq $DEBUG_BUILD_DAY ]]
then
    BUILD_TYPE=Debug
fi

#
#----------------------------------------------------
# To control the sequence  generation

# A day when we run test in 1 ch and 4 ch Thor slaves
# Use 8 for disable multi channel testing
MULTI_CHANNEL_THOR_SLAVES_TEST_DAY=6 # Saturday
ENABLE_MULTI_CHANNEL_THOR_SLAVES_TEST=0

if [[ $WEEK_DAY -eq $MULTI_CHANNEL_THOR_SLAVES_TEST_DAY ]]
then
    ENABLE_MULTI_CHANNEL_THOR_SLAVES_TEST=1
fi

BRANCH_ID=master
DAYS_FOR_CHECK_COMMITS=2
KEEP_VCPKG_CACHE=0


#
#----------------------------------------------------
#
# Override settings if necessary (generated by the obtSequencer.sh)
#

if [[ -f ./settings.inc ]]
then
    . ./settings.inc
fi

#
#-----------------------------------------------------------
#
# To determine the number of CPUs/Cores to build and parallel execution

NUMBER_OF_CPUS=$(( $( grep 'core\|processor' /proc/cpuinfo | awk '{print $3}' | sort -nru | head -1 ) + 1 ))

SPEED_OF_CPUS=$( grep 'cpu MHz' /proc/cpuinfo | awk '{print $4}' | sort -nru | head -1 | cut -d. -f1 )
SPEED_OF_CPUS_UNIT='MHz'

BOGO_MIPS_OF_CPUS=$( grep 'bogomips' /proc/cpuinfo | awk '{printf "%5.0f\n", $3}' | sort -nru | head -1 | tr -d ' ' )

MEMORY=$(( $( free | grep -i "mem" | awk '{ print $2}' )/ ( 1024 ** 2 ) ))

SETUP_PARALLEL_QUERIES=$(( $NUMBER_OF_CPUS - 1 ))
TEST_PARALLEL_QUERIES=$SETUP_PARALLEL_QUERIES

if [[ $NUMBER_OF_CPUS -ge 20 ]]
then
    SETUP_PARALLEL_QUERIES=20
    TEST_PARALLEL_QUERIES=20
else
    if [[ $NUMBER_OF_CPUS -le 4 ]]
    then
        [[ $NUMBER_OF_CPUS -gt 2 ]] && TEST_PARALLEL_QUERIES=$(( $NUMBER_OF_CPUS - 2 )) || TEST_PARALLEL_QUERIES=1
    fi
fi

#
#-----------------------------------------------------------
# To determine the number of CMake build threads
#

if [[ $NUMBER_OF_CPUS -ge 20 ]]
then
    # We have plenty of cores release the CMake do what it wants
    NUMBER_OF_BUILD_THREADS=
else
    # Use 50% more threads than the number of CPUs you have
    NUMBER_OF_BUILD_THREADS=$(( $NUMBER_OF_CPUS * 3 / 2 )) 
fi


#
#-----------------------------------------------------------
#
# Determine the package manager

IS_NOT_RPM=$( type "rpm" 2>&1 | grep -c "not found" )
PKG_EXT=
PKG_INST_CMD=
PKG_QRY_CMD=
PKG_REM_CMD=

if [[ "$IS_NOT_RPM" -eq 1 ]]
then
    PKG_EXT=".deb"
    PKG_INST_CMD="dpkg -i "
    PKG_QRY_CMD="dpkg -l "
    PKG_REM_CMD="dpkg -r "
else
    PKG_EXT=".rpm"
    PKG_INST_CMD="rpm -i --nodeps "
    PKG_QRY_CMD="rpm -qa "
    PKG_REM_CMD="rpm -e --nodeps "
fi

#
#----------------------------------------------------
#
# Common macros

URL_BASE=http://10.246.32.16/common/nightly_builds/HPCC
RELEASE_BASE=$BRANCH_ID
STAGING_DIR_ROOT=~/common/nightly_builds/HPCC/
STAGING_DIR=${STAGING_DIR_ROOT}/$RELEASE_BASE

SHORT_DATE=$(date "+%Y-%m-%d")

if [ -z $OBT_TIMESTAMP ] 
then 
    OBT_TIMESTAMP=$(date "+%H-%M-%S")
    export OBT_TIMESTAMP
fi

if [ -z $OBT_DATESTAMP ] 
then 
    OBT_DATESTAMP=${SHORT_DATE}
    export OBT_DATESTAMP
fi


SUDO=sudo

if [[ "${SYSTEM_ID}" =~ "Ubuntu" ]]
then
    HPCC_SERVICE="${SUDO} /etc/init.d/hpcc-init"
    DAFILESRV_STOP="${SUDO} /etc/init.d/dafilesrv stop"
else
    HPCC_SERVICE="${SUDO} service hpcc-init"
    DAFILESRV_STOP="${SUDO} service dafilesrv stop"
fi

OBT_MAIN_PARAM="regress"
OBT_SYSTEM=$OBT_ID
OBT_SYSTEM_ENV=AWSTestFarm
OBT_SYSTEM_STACKSIZE=81920
OBT_SYSTEM_NUMBER_OF_PROCESS=524288
OBT_SYSTEM_NUMBER_OF_FILES=524288
OBT_SYSTEM_CORE_SIZE=100

BUILD_SYSTEM=${SYSTEM_ID}
RELEASE_TYPE=CE/platform
TARGET_DIR=${STAGING_DIR}/${OBT_DATESTAMP}/${OBT_SYSTEM}-${BUILD_SYSTEM}/${OBT_TIMESTAMP}/${RELEASE_TYPE}

BUILD_DIR=~/build
OBT_LOG_DIR=${BUILD_DIR}/bin
OBT_BIN_DIR=${BUILD_DIR}/bin
BUILD_HOME=${BUILD_DIR}/${RELEASE_TYPE}/build
SOURCE_HOME=${BUILD_DIR}/${RELEASE_TYPE}/HPCC-Platform
REGRESSION_TEST_ENGINE_HOME=$OBT_BIN_DIR/rte

GIT_2DAYS_LOG=${OBT_LOG_DIR}/git_2days.log
GLOBAL_EXCLUSION_LOG=${OBT_LOG_DIR}/GlobalExclusion.log

TEST_ROOT=${SOURCE_HOME}
TEST_ENGINE_HOME=${TEST_ROOT}/testing/regress

REGRESSION_RESULT_DIR=~/HPCCSystems-regression
TEST_LOG_DIR=$REGRESSION_RESULT_DIR/log
ZAP_DIR=$REGRESSION_RESULT_DIR/zap

LOG_DIR=~/HPCCSystems-regression/log

BIN_HOME=~


TEST_PLUGINS=1
USE_CPPUNIT=1
MAKE_WSSQL=1
USE_LIBMEMCACHED=1
ECLWATCH_BUILD_STRATEGY=IF_MISSING
ENABLE_SPARK=0
SUPPRESS_SPARK=1


# Use complete-uninstall.sh to wipe HPCC
WIPE_OFF_HPCC=0


# ESP Server IP address to customize Regression Test Engine 
# It is used on multinode cluster if the OBT runs different machine than ESP Server
# Default
ESP_IP=127.0.0.1
#
# For our multi node performance cluster:
#ESP_IP=10.241.40.5

LOCAL_IP_STR=$( ip -f inet -o addr | egrep -v 'lo ' | sed -n "s/^.*inet[[:space:]]\([0-9]*\).\([0-9]*\)\.\([0-9]*\)\.\([0-9]*\).*$/\1\.\2\.\3\.\4/p" )

ADMIN_EMAIL_ADDRESS="attila.vamos@gmail.com"

QUICK_SESSION=0  # If non zero then execute standard unittests, else run 'all'


SSH_KEYFILE="~/HPCC-Platform-Smoketest.pem"
SSH_TARGET="10.22.252.118"   #AVamos-test instance in AWS US-east-1l
SSH_OPTIONS="-oConnectionAttempts=2 -oConnectTimeout=10 -oStrictHostKeyChecking=no"

#
#----------------------------------------------------
#
# House keeping
#

# When old 'HPCC-Platform' and 'build' directories exipre
SOURCE_DIR_EXPIRE=1  # days, this is a small VM with 120 GB disk

# usually it is same as EXPIRE, but if we run more than one test a day it can consume ~4GB/test disk space
SOURCE_DIR_MAX_NUMBER=7 # Not implemented yet

BUILD_DIR_EXPIRE=1   # days
BUILD_DIR_MAX_NUMBER=7   # Not implemented yet

# Local log archive
LOG_ARCHIEVE_DIR_EXPIRE=20 # days

# Remote, WEB log archive
WEB_LOG_ARCHIEVE_DIR_EXPIRE=20 # days

# How to create and use build dir.
# If it is 0 then the build create a 'build-<branchid>-<datestamp>' directory for build and create a soft linkt ot is to keep uniform buildin perocess.
# if it is not 0, then it uses 'build' directory to build platform, then at the and of the build process it makes a copy of it to 'build-<branchid>-<datestamp>'
# We nned this because if changes happened in VCPKG stuff then build failed on linked directory.
NEW_BUILD_DIR_STRUCTURE=1

#
#----------------------------------------------------
#
# Monitors
#

PORT_MONITOR_START=0

DISK_SPACE_MONITOR_START=1

MY_INFO_MONITOR_START=1

#
#----------------------------------------------------
#
# Trace generation macro
#

GDB_CMD='gdb --batch --quiet -ex "set interactive-mode off" -ex "echo \nBacktrace for all threads\n==========================" -ex "thread apply all bt" -ex "echo \n Registers:\n==========================\n" -ex "info reg" -ex "echo \n Disas:\n==========================\n" -ex "disas" -ex "quit"'

#
#----------------------------------------------------
#
# Doc build macros
#

BUILD_DOCS=0    # Until I figured out how to do that on CentOS 8

#
#----------------------------------------------------
#
# Supress plugin(s) for a specific build
#

# Default 
SUPRESS_PLUGINS=' -D MAKE_CASSANDRAEMBED=1 -DSUPPRESS_COUCHBASEEMBED=ON -DUSE_AZURE=OFF -DUSE_AWS=OFF -DSUPPRESS_WASMEMBED=ON'

#
#----------------------------------------------------
#
# Regression tests macros
#

# Use complete-uninstall.sh to wipe HPCC
REGRESSION_WIPE_OFF_HPCC=1


# Control to Regression Engine
# 0 - skip Regression Engine execution (dry run to test framework)
# 1 - execute RE to run Regression Suite
EXECUTE_REGRESSION_SUITE=1

REGRESSION_SETUP_PARALLEL_QUERIES=$SETUP_PARALLEL_QUERIES
if [[ "$BUILD_TYPE" == "RelWithDebInfo" ]]
then
    REGRESSION_PARALLEL_QUERIES=$TEST_PARALLEL_QUERIES
else
    # In Debug build sometimes roxie queries are failed with 
    # "Pool memory exhausted" caused by system running out from memory
    # based on a lots of quick queries but slow memory pool reclaim.
    # It will slow down a bit the regression testing, but doesn't impact the cluster times.
    # It happenes in 9.2.x and beyond
    REGRESSION_PARALLEL_QUERIES=$(( $TEST_PARALLEL_QUERIES  * 3 / 4 )) 
fi

REGRESSION_NUMBER_OF_THOR_SLAVES=4

#if not already defined (by the sequencer) then define it
[ -z $REGRESSION_NUMBER_OF_THOR_CHANNELS ] && REGRESSION_NUMBER_OF_THOR_CHANNELS=1

REGRESSION_THOR_LOCAL_THOR_PORT_INC=20

[[ $REGRESSION_NUMBER_OF_THOR_CHANNELS -ne 1 ]] && REGRESSION_THOR_LOCAL_THOR_PORT_INC=20 

REGRESSION_SETUP_TIMEOUT="--timeout 180"
REGRESSION_TIMEOUT="" # Default 720 from ecl-test.json config file
if [[ "$BUILD_TYPE" == "Debug" ]]
then
    REGRESSION_TIMEOUT="--timeout 1800"
    REGRESSION_SETUP_TIMEOUT="--timeout 180"
fi

# Individual timeouts 
#               "testname" "timeout sec"
TEST_1=( "schedule1.ecl" "90" )
TEST_2=( "schedule2.ecl" "150" )
TEST_3=( "workflow_9c.ecl" "90" )
TEST_4=( "workflow_contingency_8.ecl" "60" )
TEST_5=( "stepping7d.ecl" "30" )
TEST_6=( "stepping7e.ecl" "30" )
TEST_7=( "stepping7f.ecl" "30" )
TEST_8=( "supercopy.ecl" "200" )

TIMEOUTS=( 
    TEST_1[@]
    TEST_2[@]
    TEST_3[@]
    TEST_4[@]
    TEST_5[@]
    TEST_6[@]
    TEST_7[@]
    TEST_8[@]
    )


# Enable stack trace generation
REGRESSION_GENERATE_STACK_TRACE="--generateStackTrace"

REGRESSION_EXCLUDE_FILES="--ef wasmembed"

REGRESSION_EXCLUDE_CLASS="-e embedded,3rdparty"
# Exclude spray class from 8.8.x
if [[ "$BRANCH_ID" == "candidate-8.8.x" ]]
then
  REGRESSION_EXCLUDE_CLASS="$REGRESSION_EXCLUDE_CLASS,spray"
fi

PYTHON_PLUGIN=''

# To use local installation
#COUCHBASE_SERVER=$LOCAL_IP_STR
#COUCHBASE_USER=$USER

# Need to add private key into .ssh directory to use remote couchbase server
COUCHBASE_SERVER=10.240.62.177
COUCHBASE_USER=centos

REGRESSION_REPORT_SENDER="\"${OBT_ID,,}\"$USER"
REGRESSION_REPORT_RECEIVERS="attila.vamos@gmail.com,attila.vamos@lexisnexisrisk.com"
REGRESSION_REPORT_RECEIVERS_WHEN_NEW_COMMIT="attila.vamos@lexisnexisrisk.com,attila.vamos@gmail.com"

REGRESSION_PREABORT=""
REGRESSION_PREABORT_SCRIPT=$( find ${HOME}/ -iname 'preAbort.sh' -type f -print | head -n 1)
[[ -n "$REGRESSION_PREABORT_SCRIPT" ]] && REGRESSION_PREABORT="--preAbort ${REGRESSION_PREABORT_SCRIPT}"
REGRESSION_EXTRA_PARAM="-fthorConnectTimeout=36000"
#
#----------------------------------------------------
#
# Build & upload Coverity result
#

# Enable to run Coverity build and upload result
# DO NOT schedule Coverity and Coverity Cloud build on a same day!!!

RUN_COVERITY=1
COVERITY_TEST_BRANCH=master
COVERITY_REPORT_PATH=~/common/nightly_builds/Coverity

COVERITY_TEST_DAY=1    # Monday for BM/VM build
COVERITY_CLOUD_TEST_DAY=3   # Wednesday

#
#----------------------------------------------------
#
# Wutest macros
#

# Enable to run WUtest atfter Regression Suite
# If and only if the Regression Suite execution is enalbled
RUN_WUTEST=1
RUN_WUTEST=$(( $EXECUTE_REGRESSION_SUITE && $RUN_WUTEST ))


WUTEST_HOME=${TEST_ROOT}/testing/esp/wudetails
WUTEST_RESULT_DIR=${TEST_ROOT}/testing/esp/wudetails/results
WUTEST_BIN="wutest.py"
WUTEST_CMD="python3 ${WUTEST_BIN}"
WUTEST_LOG_DIR=${OBT_LOG_DIR}


#
#----------------------------------------------------
#
# Unit tests macros
#

# Enable to run unittests before execute Performance Suite
RUN_UNITTESTS=1
UNITTESTS_PARAM="-all"

if [[ ${QUICK_SESSION} -gt 0 ]]
then
    UNITTESTS_PARAM=""
fi

UNITTESTS_EXCLUDE=" JlibReaderWriterTestTiming AtomicTimingTest "

#
#----------------------------------------------------
#
# WUtool test macros
#

# Enable to run WUtool test before execute any Suite
RUN_WUTOOL_TESTS=1


#
#----------------------------------------------------
#
# Performance tests macros
#

# Enable rebuild HPCC before execute Performance Suite
PERF_BUILD=0
PERF_BUILD_TYPE=RelWithDebInfo

PERF_CONTROL_TBB=1
PERF_USE_TBB=1
PERF_USE_TBBMALLOC=0

# Control the Performance Suite target(s)
PERF_RUN_HTHOR=1
PERF_RUN_THOR=1
PERF_RUN_ROXIE=0

# To controll core generation and logging test
PERF_RUN_CORE_TEST=0

# Control Performance test cluster
PERF_NUM_OF_NODES=1
PERF_IP_OF_NODES=( '127.0.0.1' )

# totalMemoryLimit for Hthor
PERF_HTHOR_MEMSIZE_GB=$(( $MEMORY / 4 + 1 ))
[[ $PERF_HTHOR_MEMSIZE_GB -gt 4 ]] && PERF_HTHOR_MEMSIZE_GB=4

# totalMemoryLimit for Thor
PERF_THOR_MEMSIZE_GB=$(( $MEMORY / 4 + 1 ))
[[ $PERF_THOR_MEMSIZE_GB -gt 4 ]] && PERF_THOR_MEMSIZE_GB=4

PERF_THOR_NUMBER_OF_SLAVES=4
#if not already defined (by the sequencer) then define it
[ -z $PERF_NUMBER_OF_THOR_CHANNELS ] && PERF_NUMBER_OF_THOR_CHANNELS=1

PERF_THOR_LOCAL_THOR_PORT_INC=100

# totalMemoryLimit for Roxie
PERF_ROXIE_MEMSIZE_GB=$(( $MEMORY / 4 + 1 ))
[[ $PERF_ROXIE_MEMSIZE_GB -gt 4 ]] && PERF_ROXIE_MEMSIZE_GB=4

# Control to Regression Engine Setup phase
# 0 - skip Regression Engine setup execution (dry run to test framework)
# 1 - execute RE to run Performance Suite
EXECUTE_PERFORMANCE_SUITE_SETUP=0

# Control to Regression Engine
# 0 - skip Regression Engine execution (dry run to test framework)
# 1 - execute RE to run Performance Suite
EXECUTE_PERFORMANCE_SUITE=1

# timeout in seconds (>0) in Regression Engine
PERF_TIMEOUT=3600

# 0 - HPCC unistalled after Performance Suite finished on hthor
# 1 - performance test doesn't uninstall HPCC after executed tests
PERF_KEEP_HPCC=1

# 0 - HPCC stopped after Performance Suite finished on hthor
# 1 - Keep HPCC alive after executed tests
PERF_KEEP_HPCC_ALIVE=1

# Use complete-uninstall.sh to wipe HPCC
# 0 - HPCC doesn't wipe off
# 1 - HPCC does wipe off
PERF_WIPE_OFF_HPCC=0


PERF_SETUP_PARALLEL_QUERIES=$SETUP_PARALLEL_QUERIES
PERF_TEST_PARALLEL_QUERIES=1

# Example:
#PERF_QUERY_LIST="04ae_* 04cd_* 04cf_* 05bc_* 06bc_*"
PERF_EXCLUDE_CLASS="-e stress"
#PERF_QUERY_LIST="01ag_* 01ah_* 01ak_* 01al_* 02Ca_* 02cb_* 02cc_* 02cd_* 02de_* 02ea_* 02eb_* 04aac_* 04ec_* 11ac_* 12aa_* 80ab_* "
PERF_QUERY_LIST="02bb_sort*"

PERF_FLUSH_DISK_CACHE="" #"--flushDiskCache --flushDiskCachePolicy 1 "
# Dont use this setting (yet)
PERF_RUNCOUNT="" # "--runcount 20"

PERF_TEST_MODE="STD"

if [ -n "$PERF_FLUSH_DISK_CACHE" ]
then
    PERF_TEST_MODE="CDC"
fi

if [ -n "$PERF_RUNCOUNT" ]
then
    loop=$( echo $PERF_RUNCOUNT | awk '{ print $2}' )
    PERF_TEST_MODE=$PERF_TEST_MODE"+${loop}L"
fi

PERF_ENABLE_CALCTREND=0
PERF_CALCTREND_PARAMS=""

#
#----------------------------------------------------
#
# Machine Lerning tests macros
#

# Enable to run ML tests before execute Performance Suite
RUN_ML_TESTS=1

# 0 - HPCC unistalled after Machine Learning finished on hthor
# 1 - Machine Learning test doesn't uninstall HPCC after executed tests
ML_KEEP_HPCC=1

# Use complete-uninstall.sh to wipe HPCC
# 0 - HPCC doesn't wipe off
# 1 - HPCC does wipe off
ML_WIPE_OFF_HPCC=0


# Enable rebuild HPCC before execute Machine Lerning Suite
ML_BUILD=0
ML_BUILD_TYPE=$BUILD_TYPE

# Control the target(s)
ML_RUN_THOR=1
# Use a quarter of the Memory rounded (up to the next GB) but max 4 GB
ML_THOR_MEMSIZE_GB=$(( $MEMORY / 4 + 1 ))
[[ $ML_THOR_MEMSIZE_GB -gt 4 ]] && ML_THOR_MEMSIZE_GB=4

ML_THOR_NUMBER_OF_SLAVES=6

# Control to Regression Engine
# 0 - skip Regression Engine execution (dry run to test framework)
# 1 - execute RE to run Performance Suite
EXECUTE_ML_SUITE=1

# timeout in seconds (>0) in Regression Engine
ML_TIMEOUT=3600
ML_PARALLEL_QUERIES=1
ML_EXCLUDE_FILES="--ef ClassicTestModified.ecl,SVCTest.ecl"
ML_REGRESSION_EXTRA_PARAM="-fthorConnectTimeout=3600"
ML_INSTALL_EXTRA="--verbose"
#
#----------------------------------------------------
#
# Export variables
#

set +a

#
#----------------------------------------------------
#
# Common functions
#

[[ -f ${OBT_BIN_DIR}/utils.sh ]] && . ${OBT_BIN_DIR}/utils.sh

# End of settings.sh
