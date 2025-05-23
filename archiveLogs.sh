#!/bin/bash

PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

#
#------------------------------
#
# Import settings
#
# Git branch, common macros, etc

. ~/build/bin/settings.sh

# WriteLog() function

. ~/build/bin/timestampLogger.sh

#
#------------------------------
#
# Constants
#
#

if [ -n $OBT_TIMESTAMP ] 
then 
    TIMESTAMP=${OBT_TIMESTAMP}
else
    TIMESTAMP=$(date "+%H-%M-%S")
fi

if [ -n $OBT_DATESTAMP ] 
then 
    DATE_SHORT=${OBT_DATESTAMP}
else
    
    DATE_SHORT=$(date "+%Y-%m-%d") 
fi

#DATE="${DATE_SHORT}_$TIMESTAMP{}"
DATE=$(date "+%Y-%m-%d_%H-%M-%S") 


HPCC_LOG_DIR=/var/log/HPCCSystems
HPCC_BINARY_DIR=/var/lib/HPCCSystems
DALI_DIR=/var/lib/HPCCSystems/mydali
HPCC_BUILD_DIR=~/build/CE/platform/build
OBT_LOG_DIR=~/build/bin
TEST_LOG_DIR=~/HPCCSystems-regression
COVERAGE_LOG_DIR=~/coverage
ECLCC_DIR=/var/lib/HPCCSystems/myeclccserver


ARCHIVE_TARGET_DIR=~/HPCCSystems-log-archive
ARCHIVE_LOG_DIR=${OBT_LOG_DIR}/archiveLogs-${DATE}.log

TEST_LOG_SUBDIRS=('log' 'archives' 'results' 'zap')
MOVE_TO_ZIP_FLAG=''
MOVE_LOG_TO_ZIP_FLAG=-m
MOVE_OBT_CONSOLE_LOG_TO_ZIP_FLAG=''

IS_COVERAGE=
DO_ARCHIVE=1


#
#---------------------------------------
#
# Functions
#
CheckAndZip()
{
    #set -x

    flags=$1
    target=$2
    sourceDir=$3
    source=$4
    log=$5
 
    if [ -d "${sourceDir}" ]
    then
        res=$(find "${sourceDir}"/ -maxdepth 1 -name "$source" -print -quit)
    
        if test -n "$res"
        then
            zip ${flags} ${target} ${sourceDir}/${source} >> ${log}
    
        fi
    
        set +x
    fi
}

#clear

if [ ! -d $ARCHIVE_TARGET_DIR ]
then
    mkdir $ARCHIVE_TARGET_DIR
fi


ARCHIVE_NAME='Logs-archive'

while [ $# -gt 0 ]
do
    #ARCHIVE_NAME=$1
    param=$1
    #param=${param//-/}
    param=${param,,}
    WriteLog "param:${param}" "${ARCHIVE_LOG_DIR}"

    case $param in
        obt-build)  WriteLog "mode:OBT-build (log files move into archive)" "${ARCHIVE_LOG_DIR}"
                    ARCHIVE_NAME=$param
                    ;;

        obt-exit*)  WriteLog "mode:OBT-exit-cleanup (log files move into archive, skip copy to wiki)" "${ARCHIVE_LOG_DIR}"
                    ARCHIVE_NAME=$param
                    MOVE_TO_ZIP_FLAG=-m
                    DO_ARCHIVE=1
                    MOVE_OBT_CONSOLE_LOG_TO_ZIP_FLAG=-m
                    ARCHIVE_NAME=obt-exit-cleanup
                    ;;

        *clean*)    WriteLog "mode:OBT-cleanup (log files move into archive, skip copy to wiki)" "${ARCHIVE_LOG_DIR}"
                    ARCHIVE_NAME=$param
                    MOVE_TO_ZIP_FLAG=-m
                    DO_ARCHIVE=0
                    MOVE_OBT_CONSOLE_LOG_TO_ZIP_FLAG=-m
                    ARCHIVE_NAME=obt-cleanup
                    ;;

        intern*)    WriteLog "mode:Internal testing (unit, wutool,  files move into archive)" "${ARCHIVE_LOG_DIR}"
                    ARCHIVE_NAME=$param
                    #ARCHIVE_NAME=internal
                    ;;


        obt*)       WriteLog "mode:OBT (files move into archive)" "${ARCHIVE_LOG_DIR}"
                    ARCHIVE_NAME=$param
                    MOVE_TO_ZIP_FLAG=-m
                    #MOVE_OBT_CONSOLE_LOG_TO_ZIP_FLAG=-m
                    ;;

        regr*)      WriteLog "mode:Regression (move test log files move into archive)" "${ARCHIVE_LOG_DIR}"
                    ARCHIVE_NAME=$param
                    ;;
            

        perf*)      WriteLog "mode:Performance (log files copy into archive)" "${ARCHIVE_LOG_DIR}"
                    ARCHIVE_NAME=$param
                    MOVE_LOG_TO_ZIP_FLAG=''
                    ;;

        coverage)   WriteLog "mode:Coverage (log files move into archive)" "${ARCHIVE_LOG_DIR}"
                    ARCHIVE_NAME=$param
                    IS_COVERAGE=1
                    ;;

        ml*)        WriteLog "mode:ML (files move into archive)" "${ARCHIVE_LOG_DIR}"
                    ARCHIVE_NAME=$param
                    #MOVE_TO_ZIP_FLAG=-m
                    ;;


        time*)      TIMESTAMP=${param//time*=/}
                    WriteLog "Archive timestamp is: '${TIMESTAMP}'" "${ARCHIVE_LOG_DIR}"
                    ;;

        nopub*)     WriteLog "Do not publish archive." "${ARCHIVE_LOG_DIR}"
                    DO_ARCHIVE=0
                    ;;

        *)          MOVE_LOG_TO_ZIP_FLAG=''
                    ;;
    esac
    
    shift
done

FULL_ARCHIVE_TARGET_DIR=${ARCHIVE_TARGET_DIR}/$DATE_SHORT/${BRANCH_ID}/${TIMESTAMP}


WriteLog "Archive log dir: $FULL_ARCHIVE_TARGET_DIR" "${ARCHIVE_LOG_DIR}"

if [ ! -d $FULL_ARCHIVE_TARGET_DIR ]
then
    mkdir -p $FULL_ARCHIVE_TARGET_DIR
fi



ARCHIVE_NAME=${ARCHIVE_NAME}'-'${DATE}
WriteLog "Archive: $ARCHIVE_NAME" "${ARCHIVE_LOG_DIR}"

ARCHIVE_TARGET="${FULL_ARCHIVE_TARGET_DIR}/${ARCHIVE_NAME}"
WriteLog "Archive target: $ARCHIVE_TARGET" "${ARCHIVE_LOG_DIR}"

#
# --------------------------------
# Archive /tmp/build.log if exists
#

if [ -f /tmp/build.log ]
then
    WriteLog "Archive content of /tmp/build.log" "${ARCHIVE_LOG_DIR}"
    echo 'Archive content of /tmp/build.log' >> $ARCHIVE_TARGET.log
    echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
    zip ${MOVE_OBT_CONSOLE_LOG_TO_ZIP_FLAG} $ARCHIVE_TARGET /tmp/build.log >> $ARCHIVE_TARGET.log
    echo '' >> $ARCHIVE_TARGET.log
fi

if [ -f /tmp/build_sequencer.log ]
then
    WriteLog "Archive content of /tmp/build_sequencer.log" "${ARCHIVE_LOG_DIR}"
    echo 'Archive content of /tmp/build_sequencer.log' >> $ARCHIVE_TARGET.log
    echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
    zip -u $ARCHIVE_TARGET /tmp/build_sequencer.log >> $ARCHIVE_TARGET.log
    echo '' >> $ARCHIVE_TARGET.log
fi

#
# --------------------------------
# Archive /etc/HPCCSystems/environment.xml and .conf if exists
#

CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "/etc/HPCCSystems" "environment.*" "$ARCHIVE_TARGET.log"


#
# --------------------------------
# Archive logs from OBT_LOG_DIR (/root/build/bin)
#
WriteLog "Archive content of ${OBT_LOG_DIR}" "${ARCHIVE_LOG_DIR}"
echo 'Archive content of '${OBT_LOG_DIR} >> $ARCHIVE_TARGET.log
echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "obt-*.log" "$ARCHIVE_TARGET.log"

CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "simple-*.log" "$ARCHIVE_TARGET.log""$ARCHIVE_TARGET.log"

CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "perftest-*.log"                "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "diskspace-*.log"               "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "memspace-*.log"                "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "redis*.out"                    "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "check*.log"                    "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "Check*.log"                    "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "Perf_*.log"                    "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "uninst*.*"                     "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "Core-gen-test-*.log"           "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "CloneRepo-*.log"               "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "SubmoduleUpdate-*.log"         "$ARCHIVE_TARGET.log"
CheckAndZip " "                                   "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "*KnownProblems.csv"            "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "unittest-*"                    "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "unittests*.log"                 "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "core_unittests*"               "$ARCHIVE_TARGET.log"

CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "wutool*.log"                   "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "wutool*.summary"               "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "unittest-*.log"                "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "WatchDog*.log"                 "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${HPCC_BUILD_DIR}/CMakeFiles" "CMakeOutput.log" "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${HPCC_BUILD_DIR}/CMakeFiles" "CMakeError.log"  "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "usedPort.summary"              "$ARCHIVE_TARGET.log"

CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "regress-*.log"                 "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "Regression-*.csv"              "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "Regression-*.txt"              "$ARCHIVE_TARGET.log"
CheckAndZip " "                                   "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "git_2days.log"                 "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "GlobalExclusion.log"           "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "setup_*.log"                    "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "*.summary"                     "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "hthor*.log"                    "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "thor*.log"                     "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "roxie*.log"                    "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "environment*"                  "$ARCHIVE_TARGET.log"
CheckAndZip " "                                   "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "BuildNotification.ini"         "$ARCHIVE_TARGET.log"
CheckAndZip " "                                   "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "settings.*"                    "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "perfstat-*"                    "$ARCHIVE_TARGET.log"
CheckAndZip " "                                   "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "obtSequence.inc"               "$ARCHIVE_TARGET.log"

CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "perftest*.summary"             "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "perfreport-*.csv"              "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "PerformanceTest*.pdf"          "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "perftest-*"                    "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "*.png"                         "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "results-thor-6.5.0.csv"        "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "results-roxie-6.5.0.csv"       "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "PerformanceIssues-1*.csv"      "$ARCHIVE_TARGET.log"
CheckAndZip " "                                   "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "PerformanceIssues.csv"         "$ARCHIVE_TARGET.log"

CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "ML_*.log"                      "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "mltests.summary"               "$ARCHIVE_TARGET.log"

CheckAndZip "-m"                                 "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "build-*.log"                   "$ARCHIVE_TARGET.log"
CheckAndZip "-m"                                 "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "install*.log"                  "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "myInfo-*.log"                  "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "myPortUsage-*.log"             "$ARCHIVE_TARGET.log"

CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "wutest*.log"                   "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "wutest.summary"                "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "wutest*.zip"                   "$ARCHIVE_TARGET.log"

CheckAndZip "-m"                                 "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "tinyproxy.conf"                   "$ARCHIVE_TARGET.log"

CheckAndZip "-m"                                 "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "uploadObtResultToGists-*.log" "$ARCHIVE_TARGET.log"
CheckAndZip "-m"                                 "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "fixJson-*.log"                        "$ARCHIVE_TARGET.log"
CheckAndZip "${MOVE_TO_ZIP_FLAG}" "$ARCHIVE_TARGET" "${OBT_LOG_DIR}" "sar-*.log"                             "$ARCHIVE_TARGET.log"


echo '' >> $ARCHIVE_TARGET.log


#
# --------------------------------
# Archive logs from COVERAGE_LOG_DIR (~/coverage)
#
if [ -n "$IS_COVERAGE" ]
then
    WriteLog "Archive content of ${COVERAGE_LOG_DIR}" "${ARCHIVE_LOG_DIR}"
    echo 'Archive content of '${COVERAGE_LOG_DIR} >> $ARCHIVE_TARGET.log
    echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
    CheckAndZip "-m" "$ARCHIVE_TARGET" "${COVERAGE_LOG_DIR}" "*.summary" "$ARCHIVE_TARGET.log"
    CheckAndZip "-m" "$ARCHIVE_TARGET" "${COVERAGE_LOG_DIR}" "*.log"     "$ARCHIVE_TARGET.log"
    CheckAndZip "-m" "$ARCHIVE_TARGET" "${COVERAGE_LOG_DIR}" "*.lcov"    "$ARCHIVE_TARGET.log"
    CheckAndZip "-m" "$ARCHIVE_TARGET" "${COVERAGE_LOG_DIR}" "*_log"     "$ARCHIVE_TARGET.log"
    echo '' >> $ARCHIVE_TARGET.log
fi



#
# --------------------------------
# Archive logs from HPCC_BUILD_DIR (/root/build/CE/platform/build)
#
WriteLog "Archive content of ${HPCC_BUILD_DIR}" "${ARCHIVE_LOG_DIR}"
echo 'Archive content of '${HPCC_BUILD_DIR} >> $ARCHIVE_TARGET.log
echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
CheckAndZip "-m" "$ARCHIVE_TARGET" "${HPCC_BUILD_DIR}" "*.summary" "$ARCHIVE_TARGET.log"
echo '' >> $ARCHIVE_TARGET.log

#
# --------------------------------
# Archive logs from HPCC_LOG_DIR (/var/log/HPCCSystems)
#
WriteLog "Archive content of ${HPCC_LOG_DIR}" "${ARCHIVE_LOG_DIR}"
echo 'Archive content of '${HPCC_LOG_DIR} >> $ARCHIVE_TARGET.log
echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
#zip $ARCHIVE_TARGET ${HPCC_LOG_DIR} >> $ARCHIVE_TARGET.log

if [ -d /var/log/HPCCSystems/ ] 
then
    find /var/log/HPCCSystems/ -name '*'$(date "+%Y_%m_%d")'*.log' -type f -exec \
         zip $ARCHIVE_TARGET'{}' \; >> $ARCHIVE_TARGET.log
    
    # If there is any log from yesterday (overlappeds session case) add it to archive
    # (It can happen only in overlapped case, because otherwise the OBT cleans up everything at the end of a session.)
    find /var/log/HPCCSystems/ -name '*'$(date -d '-1 day'  "+%Y_%m_%d")'*.log' -type f -exec \
         zip $ARCHIVE_TARGET'{}' \; >> $ARCHIVE_TARGET.log
    
    echo '' >> $ARCHIVE_TARGET.log
fi


#
# --------------------------------
# Archive content of TEST_LOG_DIR (/root/HPCCSystems-regression)
#
WriteLog "Archive content of ${TEST_LOG_DIR}" "${ARCHIVE_LOG_DIR}"
echo 'Archive content of '${TEST_LOG_DIR} >> $ARCHIVE_TARGET.log
echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
echo '' >> $ARCHIVE_TARGET.log


for i in ${TEST_LOG_SUBDIRS[@]}
do 
    WriteLog "Archive content of ${TEST_LOG_DIR}/$i" "${ARCHIVE_LOG_DIR}"
    echo "  Archive content of :"$i >> $ARCHIVE_TARGET.log
    echo "  ------------------------------------" >> $ARCHIVE_TARGET.log

    zip ${MOVE_LOG_TO_ZIP_FLAG} $ARCHIVE_TARGET ${TEST_LOG_DIR}/$i/ >> $ARCHIVE_TARGET.log
    echo '' >> $ARCHIVE_TARGET.log

done


#
# --------------------------------
# Archive core files if generated
#

if [ -d ${HPCC_BINARY_DIR} ] 
then

    cores=($(find ${HPCC_BINARY_DIR}/ -type f -regextype sed -regex '.*/core_.*\.[0-9]*$'))
    maxNumberOfCoresStored=3
    if [ ${#cores[@]} -ne 0 ]
    then
        WriteLog "Archive '${#cores[*]}' core file(s) from ${HPCC_BINARY_DIR}" "${ARCHIVE_LOG_DIR}" 
        echo 'Archive '${#cores[*]}' core file(s) from '${HPCC_BINARY_DIR} >> $ARCHIVE_TARGET.log
        echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
        echo '' >> $ARCHIVE_TARGET.log
     
        coreIndex=1
        for core in ${cores[@]}
        do 
            sudo chmod 0755 $core

            coreSize=$( ls -l $core | awk '{ print $5}' )
            coreSizeHuman=$( ls -lh $core | awk '{ print $5}' )

            WriteLog "$( printf %3d $coreIndex ). Generate backtrace for $core." "${ARCHIVE_LOG_DIR}"
            #base=$( dirname $core )
            #lastSubdir=${base##*/}
            #comp=${lastSubdir##my}

            corename=${core##*/}; 
            comp=$( echo $corename | tr '_.' ' ' | awk '{print $2 }' ); 
            compnamepart=$( find /opt/HPCCSystems/bin/ -iname "$comp*" -type f -print | head -n 1); 
            compname=${compnamepart##*/}

            WriteLog "corename: ${corename}, comp: ${comp}, compnamepart: ${compnamepart}, component name: ${compname}" "${ARCHIVE_LOG_DIR}"
            eval ${GDB_CMD} "/opt/HPCCSystems/bin/${compname}" $core | sudo tee "$core.trace"

            zip $ARCHIVE_TARGET$core.trace >> $ARCHIVE_TARGET.log
            zip $ARCHIVE_TARGET"/opt/HPCCSystems/bin/${comp}" >> $ARCHIVE_TARGET.log


            if [[ (${coreIndex} -le $maxNumberOfCoresStored) && (${coreSize} -lt 1073741824) ]]      # <1GB
            then
                WriteLog "Add $core (${coreSizeHuman}) to archive" "${ARCHIVE_LOG_DIR}"
                zip $ARCHIVE_TARGET$core >> $ARCHIVE_TARGET.log
            else
                WriteLog "Skip to add $core (${coreSizeHuman}) to archive" "${ARCHIVE_LOG_DIR}"
            fi
            
            coreIndex=$(( $coreIndex + 1 ))
            sudo rm $core $core.trace
    
        done
        
        echo 'Done.' >> $ARCHIVE_TARGET.log

        # send email to Agyi about core files
        echo "During to process ${ARCHIVE_NAME} there are ${#cores[*]} core file(s) found in ${HPCC_BINARY_DIR} generated in ${OBT_SYSTEM} on ${BRANCH_ID} branch at ${OBT_TIMESTAMP//-/:}. You should check them." | mailx -s "Core files generated" -u $USER  ${ADMIN_EMAIL_ADDRESS}


    else
        WriteLog "There is no core file in '${HPCC_BINARY_DIR}" "${ARCHIVE_LOG_DIR}"
        echo 'There is no core file in '${HPCC_BINARY_DIR} >> $ARCHIVE_TARGET.log
        echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
        echo '' >> $ARCHIVE_TARGET.log
    fi
else
    WriteLog "There is no directory ${HPCC_BINARY_DIR}" "${ARCHIVE_LOG_DIR}"
    echo 'There is no directory '${HPCC_BINARY_DIR} >> $ARCHIVE_TARGET.log
    echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
    echo '' >> $ARCHIVE_TARGET.log
fi


#
# --------------------------------
# Archive logs from DALI_DIR (/var/log/HPCCSystems/mydali)
#
WriteLog "Archive content of ${DALI_DIR}" "${ARCHIVE_LOG_DIR}"
echo 'Archive content of '${DALI_DIR} >> $ARCHIVE_TARGET.log
echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
zip $ARCHIVE_TARGET-r ${DALI_DIR} >> $ARCHIVE_TARGET.log
echo '' >> $ARCHIVE_TARGET.log


#
# --------------------------------
# Archive logs from ECLCC_DIR (/var/log/HPCCSystems/myeclccserver)
#
WriteLog "Archive content of ${ECLCC_DIR}" "${ARCHIVE_LOG_DIR}"
echo 'Archive content of '${ECLCC_DIR} >> $ARCHIVE_TARGET.log
echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
zip $ARCHIVE_TARGET-r ${ECLCC_DIR}/*.log >> $ARCHIVE_TARGET.log
echo '' >> $ARCHIVE_TARGET.log



#
# --------------------------------
# End of archiving process
#

echo '' >> $ARCHIVE_TARGET.log
echo 'End of archive' >> $ARCHIVE_TARGET.log
echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log


#
# --------------------------------
# Move Unittest core file(s)archive to log archieve
#

unittest_cores=( $(find ${OBT_LOG_DIR}/ -iname 'unittest-core*zip' -type f) )
    
if [ ${#unittest_cores[@]} -ne 0 ]
then
    WriteLog "Archive '${#unittest_cores[*]}' core file(s) from ${OBT_LOG_DIR}" "${ARCHIVE_LOG_DIR}" 
    echo 'Archive '${#unittest_cores[*]}' core file(s) from '${OBT_LOG_DIR} >> $ARCHIVE_TARGET.log
    echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
    echo '' >> $ARCHIVE_TARGET.log
     
    for c in ${unittest_cores[@]}
    do 
        WriteLog "Move $c to archive" "${ARCHIVE_LOG_DIR}"

        mv $c   ${FULL_ARCHIVE_TARGET_DIR}/.

    done
        
    echo 'Done.' >> $ARCHIVE_TARGET.log
else
    WriteLog "There is no core file in '${OBT_LOG_DIR}" "${ARCHIVE_LOG_DIR}"
    echo 'There is no core file in '${OBT_LOG_DIR} >> $ARCHIVE_TARGET.log
    echo '-----------------------------------------------------------' >> $ARCHIVE_TARGET.log
    echo '' >> $ARCHIVE_TARGET.log
fi




#
# --------------------------------
# Copy archive to Wiki area
#

if [ $DO_ARCHIVE -eq 1 ]
then
    REMOTE_ARCHIVE_TARGET_DIR=${TARGET_DIR}/log-archive
    
    WriteLog "Copy archive into wiki ( ${REMOTE_ARCHIVE_TARGET_DIR} )." "${ARCHIVE_LOG_DIR}"
    
    if [ ! -d ${REMOTE_ARCHIVE_TARGET_DIR} ]
    then
        mkdir $REMOTE_ARCHIVE_TARGET_DIR
    fi

    if [ -d ${REMOTE_ARCHIVE_TARGET_DIR} ]
    then
        WriteLog "cp $ARCHIVE_TARGET* ${REMOTE_ARCHIVE_TARGET_DIR}/" "${ARCHIVE_LOG_DIR}"
        cp $ARCHIVE_TARGET* ${REMOTE_ARCHIVE_TARGET_DIR}/
    else
        WriteLog "${REMOTE_ARCHIVE_TARGET_DIR} doesn't exist! Skip copy files to wiki!" "${ARCHIVE_LOG_DIR}"
    fi
else
    WriteLog "Skip copy files to wiki!" "${ARCHIVE_LOG_DIR}"
fi

#
# --------------------------------
# End of archiving process
#

WriteLog "End of archiveLogs.sh" "${ARCHIVE_LOG_DIR}"
WriteLog "" "${ARCHIVE_LOG_DIR}"


#
# --------------------------------
# House keeping
#

WriteLog "Remove all log archive directory older than ${LOG_ARCHIEVE_DIR_EXPIRE} days from ${ARCHIVE_TARGET_DIR}." "${ARCHIVE_LOG_DIR}"
echo "Remove all log archive directory older than ${LOG_ARCHIEVE_DIR_EXPIRE} days from ${ARCHIVE_TARGET_DIR}." >> $ARCHIVE_TARGET.log

OLD_DIRS=( $( find ${ARCHIVE_TARGET_DIR}/ -maxdepth 1 -mtime +${LOG_ARCHIEVE_DIR_EXPIRE} -type d ) )

WriteLog "${#OLD_DIRS[@]} old directory found." "${ARCHIVE_LOG_DIR}"
echo "${#OLD_DIRS[@]} old directory found." >> $ARCHIVE_TARGET.log

res=$( find ${ARCHIVE_TARGET_DIR}/ -maxdepth 1 -mtime +${LOG_ARCHIEVE_DIR_EXPIRE} -type d -print -exec rm -rf '{}' \; 2>&1 )

WriteLog "res:${res}" "${ARCHIVE_LOG_DIR}"
echo "res:${res}" >> $ARCHIVE_TARGET.log

WriteLog "End of cleanup." "${ARCHIVE_LOG_DIR}"
echo "End of cleanup." >> $ARCHIVE_TARGET.log
echo " " >> $ARCHIVE_TARGET.log

#
# ------------------------------
#
# Done
#

zip -m $ARCHIVE_TARGET${OBT_LOG_DIR}/archiveLogs*.log >> $ARCHIVE_TARGET.log

echo "Done" >> $ARCHIVE_TARGET.log
