#!/bin/bash

#echo "param:'$1'"

#
#------------------------------
#
# Import settings
#

[[ -f ~/.bash_profile ]] && . ~/.bash_profile


# Git branch

. ./settings.sh

# WriteLog() function

. ./timestampLogger.sh


# UninstallHPCC() fuction

declare -f -F UninstallHPCC > /dev/null
    
if [ $? -ne 0 ]
then
    . ./UninstallHPCC.sh
fi

# CloneRepo()

declare -f -F CloneRepo > /dev/null
    
if [ $? -ne 0 ]
then
    . ~/build/bin/cloneRepo.sh
fi

#
#------------------------------
#
# Check parameter
#

if [ "$1." != "." ]
then
    param=$1
    upperParam=${param^^}
    echo "Param: ${upperParam}"
    case $upperParam in

        HTHOR)  PERF_RUN_HTHOR=1
                PERF_RUN_THOR=0
                PERF_RUN_ROXIE=0
                ;;

        THOR)   PERF_RUN_HTHOR=0
                PERF_RUN_THOR=1
                PERF_RUN_ROXIE=0
                ;;


        ROXIE)  PERF_RUN_HTHOR=0
                PERF_RUN_THOR=0
                PERF_RUN_ROXIE=1
                ;;

        BUILD)  # Only build
                PERF_BUILD=1
                PERF_RUN_HTHOR=0
                PERF_RUN_THOR=0
                PERF_RUN_ROXIE=0
                ;;

        *)      # Dry run
                PERF_RUN_HTHOR=0
                PERF_RUN_THOR=0
                PERF_RUN_ROXIE=0
                PERF_BUILD=0
                ;;
    esac
fi

#
#------------------------------
#
# Constants
#

# ------------------------------------------------
# Defined in settings.sh
#
#BUILD_TYPE=RelWithDebInfo
#LOG_DIR=~/HPCCSystems-regression/log

#BUILD_DIR=~/build
#BUILD_HOME=${BUILD_DIR}/CE/platform/build
#TEST_ROOT=${BUILD_DIR}/CE/platform
#TEST_ENGINE_HOME=${PLATFORM_HOME}/testing/regress
#PERF_TEST_HOME=${PERF_TEST_ROOT}/ecl-bundles/PerformanceTesting
# ------------------------------------------------

BIN_HOME=$OBT_LOG_DIR
PLATFORM_HOME=$SOURCE_HOME

LONG_DATE=$(date "+%Y-%m-%d_%H-%M-%S")

BUILD_LOG_FILE=${BIN_HOME}/"Perf_build_"${LONG_DATE}".log";

PERF_TEST_ROOT=~/perftest

PERF_TEST_HOME=${PERF_TEST_ROOT}/PerformanceTesting/PerformanceTesting
PERF_TEST_LOG=${BIN_HOME}/Perf_test-${LONG_DATE}.log
PERF_TEST_REPO=https://github.com/hpcc-systems/PerformanceTesting.git

#TIMEOUTED_FILE_LISTPATH=${BIN_HOME}
#TIMEOUTED_FILE_LIST_NAME=${TIMEOUTED_FILE_LISTPATH}/PerformanceTimeoutedTests.csv
#TIMEOUT_TAG="//timeout ${PERF_TIMEOUT}"

PARALLEL_QUERIES=0

PERF_RESULT=PASS

#
#----------------------------------------------------
#

ProcessLog()
{ 
    fn=$( find  ${TEST_LOG_DIR}/ -iname $1'.*.log' | sort -r | head -n 1)
    if [[ -n $fn ]]
    then
        total=$(cat $fn | sed -n "s/^[[:space:]]*Queries:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p")
        passed=$(cat $fn | sed -n "s/^[[:space:]]*Passing:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p")
        failed=$(cat $fn | sed -n "s/^[[:space:]]*Failure:[[:space:]]*\([0-9]*\)[[:space:]]*$/\1/p")
        
        WriteLog "TestResult:Total:${total}, passed:${passed}, failed:${failed}" "${PERF_TEST_LOG}"
        
        if [[ $failed -ne 0 ]]
        then
            PERF_RESULT=FAILED
        fi
    else
        WriteLog "Log file related to '$1' not found in '$TEST_LOG_DIR'. " "${PERF_TEST_LOG}"
    fi
}


DeletePackage()
{
    WriteLog "Remove package" "${PERF_TEST_LOG}"

    ${SUDO} ${PKG_QRY_CMD} | grep '[h]pcc' |
    while read hpcc_package
    do
        WriteLog "HPCC package:"${hpcc_package} "${PERF_TEST_LOG}"
        res=$( ${SUDO} ${PKG_REM_CMD} $hpcc_package 2>&1 )
        WriteLog "Res: ${hpcc_package}" "${PERF_TEST_LOG}"

        [ $? -ne 0 ] && WriteLog "HPCC package uninstall failed" "${PERF_TEST_LOG}"

    done
    
    ${SUDO} ${PKG_QRY_CMD} | grep hpcc > /dev/null 2>&1
    if [ $? -eq 0 ]
    then
        WriteLog "Can't remove HPCC package: ${hpcc_package}" "${PERF_TEST_LOG}"
    fi

    WriteLog "Delete package(s)" "${PERF_TEST_LOG}"

    res=$( find ${BUILD_HOME} -maxdepth 1 -name 'hpccsystems-platform-community*' -type f -print -exec rm '{}' \; 2>&1 )
    WriteLog "Res: ${res}" "${PERF_TEST_LOG}"

    query="thor|roxie|d[af][fslu]|ecl[s|c|\s|a][g|c]|sase"
    WriteLog "Check if any hpcc owned process is running (query: ${query})" "${PERF_TEST_LOG}"
    res=$(pgrep -l "${query}" 2>&1)
    if [ -n "$res" ] 
    then
        WriteLog "res:${res}" "${PERF_TEST_LOG}"
        ${SUDO} pkill -9 "${query}"

        # Give it some time
        sleep 1m

        res=$(pgrep -l "${query}" 2>&1)
        WriteLog "After pkill res:${res}" "${PERF_TEST_LOG}"
    else
        WriteLog "Tere is no leftover process" "${PERF_TEST_LOG}"
    fi
}

#
#----------------------------------------------
# Enable TLS/SSl on Roxie
addTlsToRoxie()
{
    pushd $OBT_BIN_DIR

    addFarmProcess=1
    if  [[ -f private.pem ]]
    then 
        WriteLog "Copy private.pem into $HOME." "${PERF_TEST_LOG}"
        res=$(sudo cp -v private.pem ~/ 2>&1 )
        retCode=$?
        if [[ $retCode -eq 0 ]]
        then
            WriteLog "  ret code: $retCode, res:\n  $res" "${PERF_TEST_LOG}"
            WriteLog "  $(ls -l ~/private.pem)" "${PERF_TEST_LOG}"
        else
            WriteLog "  ret code: $retCode, res:\n  $res" "${PERF_TEST_LOG}"
            addFarmProcess=0
        fi
    else
        WriteLog "private.pem not found." "${PERF_TEST_LOG}"
        addFarmProcess=0
    fi

    if [[ -f certificate.crt ]] 
    then 
        WriteLog "Copy 'certificate.crt' into $HOME." "${PERF_TEST_LOG}"
        res=$(sudo cp -v certificate.crt ~/ 2>&1 )
        retCode=$?
        if [[ $retCode -eq 0 ]]
        then
            WriteLog "  ret code: $retCode, res:\n  $res" "${PERF_TEST_LOG}"
            WriteLog "  $(ls -l ~/certificate.crt)" "${PERF_TEST_LOG}"
        else
            WriteLog "  ret code: $retCode, res:\n  $res" "${PERF_TEST_LOG}"
            addFarmProcess=0
        fi            
    else
        WriteLog "'certificate.crt' not found." "${PERF_TEST_LOG}"
        addFarmProcess=0
    fi
    
    if [[ $addFarmProcess -eq 1 ]]
    then
        if [ -n "$(xmlstarlet sel -T -t -v "/Environment/Software/RoxieCluster/RoxieFarmProcess[@name='farmSsl']/@name" /etc/HPCCSystems/environment.xml)" ]; then
          WriteLog "RoxieFarmProcess farmSsl already defined in environment.xml" "${PERF_TEST_LOG}"
        else
          WriteLog "Adding RoxieFarmProcess farmSsl to <RoxieCluster> in environment.xml" "${PERF_TEST_LOG}"
          sudo xmlstarlet ed -P -S -L -s /Environment/Software/RoxieCluster -t elem -n RoxieFarmProcessTMP -v "" \
            -i //RoxieFarmProcessTMP -t attr -n "aclName" -v "" \
            -i //RoxieFarmProcessTMP -t attr -n "listenQueue" -v "200" \
            -i //RoxieFarmProcessTMP -t attr -n "name" -v "farmSsl" \
            -i //RoxieFarmProcessTMP -t attr -n "numThreads" -v "30" \
            -i //RoxieFarmProcessTMP -t attr -n "port" -v "19876" \
            -i //RoxieFarmProcessTMP -t attr -n "protocol" -v "ssl" \
            -i //RoxieFarmProcessTMP -t attr -n "certificateFileName" -v "${HOME}/certificate.crt" \
            -i //RoxieFarmProcessTMP -t attr -n "privateKeyFileName" -v "${HOME}/private.pem" \
            -i //RoxieFarmProcessTMP -t attr -n "passphrase" -v "" \
            -i //RoxieFarmProcessTMP -t attr -n "requestArrayThreads" -v "5" \
            -r //RoxieFarmProcessTMP -v RoxieFarmProcess \
            /etc/HPCCSystems/environment.xml
            WriteLog "  Done. ( $(xmlstarlet sel -T -t -v "/Environment/Software/RoxieCluster/RoxieFarmProcess[@name='farmSsl']/@name" /etc/HPCCSystems/environment.xml) )" "${PERF_TEST_LOG}"
        fi
    else
        WriteLog "Skip to add Roxie farm process, based on something is missing." "${PERF_TEST_LOG}"
    fi

    popd
}

SuppressAnalyserWarnings()
{
    WriteLog "Inject '#onwarning(5820, ignore);' to all performance test." "${PERF_TEST_LOG}"
    pushd ${PERF_TEST_HOME}/ecl

    while read file
    do
        WriteLog "  File:${file}" "${PERF_TEST_LOG}"

        patched=$( egrep -H '#onwarning' $file | egrep -c '5820' )

        if [[ ${patched} -eq 0 ]]
        then
            WriteLog "    Patching..." "${PERF_TEST_LOG}"
            (echo "#onwarning(5820, ignore); // Suppress analyser warning" ; cat $file) >${file}.new
            mv ${file}.new $file
            WriteLog "      Done: $(egrep -H '#onwarning' $file | egrep -c '5820' )" "${PERF_TEST_LOG}"
        else
            WriteLog "    Already has '#onwarning(5820, ignore)'." "${PERF_TEST_LOG}"
        fi
    done < <(ls -1 *.ecl )

    popd
    
    WriteLog "  Done." "${PERF_TEST_LOG}"
}


#
#-----------------------------------------------------
# Patch Performance suite tests if they needed to prevent extra long execuion tme
InjectTimeout()
{
    if [[ -n $PERF_TIMEOUTS ]]
    then
        WriteLog "Inject/update '//timeout <value>' to all performance test stored in 'PERF_TIMEOUTS' array." "${PERF_TEST_LOG}"
        COUNT=${#PERF_TIMEOUTS[@]}
        WriteLog "There is $COUNT test case need individual timeout setting" "${PERF_TEST_LOG}"
        pushd ${PERF_TEST_HOME}/ecl

        for((testIndex=0; testIndex<$COUNT; testIndex++))
        do
            TEST=(${!PERF_TIMEOUTS[$testIndex]})
            WriteLog "\tPatch ${TEST[0]} with ${TEST[1]} sec timeout" "${PERF_TEST_LOG}"
            file="${TEST[0]}"
            if [[ -f ${file} ]]
            then
                timeout=${TEST[1]}
                # Check if test already has '//timeout' tag
                if [[ $( egrep -c '\/\/timeout' $file ) -eq 0 ]]
                then
                    # it has not, add one at the beginning of the file
                    mv -fv $file $file-back
                    echo "// Patched by the perftest.sh on $( date '+%Y.%m.%d %H:%M:%S')" > $file
                    echo "//timeout $timeout" >> $file
                    cat $file-back >> $file
                else
                    # yes it has, change it
                    cp -fv $file $file-back
                    sed -e 's/^\/\/timeout \(.*\).*$/\/\/ Patched by the Smoketest on '"$( date '+%Y.%m.%d %H:%M:%S')"'\n\/\/timeout '"$timeout"'/g' $file > $file-patched && mv -f $file-patched $file
                fi
                WriteLog "$(egrep -H -B1 -A1 '//timeout ' $file)" "${PERF_TEST_LOG}"
                WriteLog "\t\tDone.\n" "${PERF_TEST_LOG}"
            else
                WriteLog "\t\t${file} file not exists, skip patching." "${PERF_TEST_LOG}"
            fi
        done
        WriteLog "  Done." "${PERF_TEST_LOG}"
        popd
    else
        WriteLog "No file to patch." "${PERF_TEST_LOG}"
    fi
}

#
#----------------------------------------------------
#
# Start Performance Test process
#

WriteLog "Performance Test started" "${PERF_TEST_LOG}"

STARTUP_MSG=""

if [[ "$PERF_BUILD" -eq 1 ]]
then
    STARTUP_MSG=${STARTUP_MSG}"build, "
fi

if [[ "$PERF_RUN_HTHOR" -eq 1 ]]
then
    STARTUP_MSG=${STARTUP_MSG}"hthor, "
fi

if [[ "$PERF_RUN_THOR" -eq 1 ]]
then
    STARTUP_MSG=${STARTUP_MSG}"thor, "
fi

if [[ "$PERF_RUN_ROXIE" -eq 1 ]]
then
    STARTUP_MSG=${STARTUP_MSG}"roxie "
fi

if [[ -n "$STARTUP_MSG" ]]
then
    WriteLog "Execute performance suite on ${STARTUP_MSG}" "${PERF_TEST_LOG}"
else
    WriteLog "No target selected. This is a dry run." "${PERF_TEST_LOG}"
fi

CORE_LIMIT='unlimited' #$(( 256 * 1024 ))   # 256 MB (256kb * 1024b [blocksize])
WriteLog "Set core file size to  ${CORE_LIMIT} blocks." "${PERF_TEST_LOG}"
[[ "${CORE_LIMIT}" != 'unlimited' ]] && WriteLog "It is enough to stack trace and \ncore file(s) doesn't consume the entirely disk space if something went wrong." "${PERF_TEST_LOG}"
ulimit -c ${CORE_LIMIT}
WriteLog "$(ulimit -a)" "${PERF_TEST_LOG}"

#
#---------------------------
#
# Determine the package manager

WriteLog "packageExt: '${PKG_EXT}', installCMD: '${PKG_INST_CMD}'." "${PERF_TEST_LOG}"

#
#---------------------------
#
# Clean system
#

WriteLog "Clean system" "${PERF_TEST_LOG}"

[ ! -e $PERF_TEST_ROOT ] && mkdir -p $PERF_TEST_ROOT

rm -rf ${PERF_TEST_ROOT}/*
cd  ${PERF_TEST_ROOT}
 
#
#---------------------------
#
# Uninstall HPCC to free as much disk space as can
#

if [[ ${PERF_KEEP_HPCC} -eq 0 ]]
then
    WriteLog "Uninstall HPCC to free as much disk space as can" "${PERF_TEST_LOG}"
    
    WriteLog "Uninstall HPCC-Platform" "${PERF_TEST_LOG}"
    
    UninstallHPCC "${PERF_TEST_LOG}" "${PERF_WIPE_OFF_HPCC}"
else
    WriteLog "Skip Uninstall HPCC on ${TARGET_PLATFORM} but stop it!" "${PERF_TEST_LOG}"
    StopHpcc "${PERF_TEST_LOG}"
    DeletePackage
fi

# Get RTE
WriteLog "Get the latest Regression Test Engine..." "${PERF_TEST_LOG}"
[[ -d $REGRESSION_TEST_ENGINE_HOME ]] && rm -rf $REGRESSION_TEST_ENGINE_HOME
    
cres=$( CloneRepo "https://github.com/AttilaVamos/RTE.git" "$REGRESSION_TEST_ENGINE_HOME" )

if [[ 0 -ne  $? ]]
then
    WriteLog "RTE clone failed ! Result is: ${cres}" "${PERF_TEST_LOG}"
    cd ${OBT_BIN_DIR}
    ./archiveLogs.sh obt-build timestamp=${OBT_TIMESTAMP}
    ExitEpilog "${PERF_TEST_LOG}" "build.sh" "RTE clone failed ! Result is: ${cres}"
else
    WriteLog "RTE clone success !" "${PERF_TEST_LOG}"
fi

#
#--------------------------------------------------
#
# Build it
#

if [[ $PERF_BUILD -eq 1 ]]
then
    WriteLog "                                           " "${PERF_TEST_LOG}"
    WriteLog "*******************************************" "${PERF_TEST_LOG}"
    WriteLog " Build HPCC Platform from ${BUILD_HOME} ..." "${PERF_TEST_LOG}"
    WriteLog "                                           " "${PERF_TEST_LOG}"

    #
    #-------------------------------------------------------------------------------------
    # Build HPCC
    #
    WriteLog "Build started ($0)" "${PERF_TEST_LOG}"

    WriteLog "Clean up and prepare..." "${PERF_TEST_LOG}"

    if [ ! -d ${BUILD_DIR}/$RELEASE_TYPE ]
    then
        mkdir -p ${BUILD_DIR}/$RELEASE_TYPE
    fi

    WriteLog "PWD: $(pwd)" "${PERF_TEST_LOG}"

    cd ${BUILD_DIR}/$RELEASE_TYPE

    buildTarget=build-${BRANCH_ID}-${LONG_DATE}

    if [[ $NEW_BUILD_DIR_STRUCTURE -ne 0 ]]
    then
        if [[ -d build ]]
        then 
            WriteLog "$BUILD_TYPE build remove build dir." "${PERF_TEST_LOG}"
            res=$( rm -rf build )
            [[ $? -ne 0 ]] && WriteLog " 'rm -rf build' return with ${res}" "${PERF_TEST_LOG}"
        fi
        if [[ -f build ]]
        then
            WriteLog "$BUILD_TYPE build remove link to build dir." "${PERF_TEST_LOG}"
            res=$( rm build )
            [[ $? -ne 0 ]] && WriteLog " 'rm build' return with ${res}" "${PERF_TEST_LOG}"
        fi
        mkdir build
        [[ -d build ]] && WriteLog " 'build' directory created." "${PERF_TEST_LOG}"

    else
       # Use the old linked build directory structure
        WriteLog "$BUILD_TYPE build remove build dir." "${PERF_TEST_LOG}"
        
        res=$( rm  build )
        [[ $? -ne 0 ]] && WriteLog " 'rm build' return with ${res}" "${PERF_TEST_LOG}"
        
        WriteLog "Create symlink for build to ${buildTarget}." "${PERF_TEST_LOG}"
        mkdir ${buildTarget}
        
        ln -s ${buildTarget} build
    fi

    # Remove all build-* directory older than a week (?)
    #
    WriteLog "Remove all build-* directory older than ${BUILD_DIR_EXPIRE} days." "${PERF_TEST_LOG}"
    res=$( find . -maxdepth 1 -type d -mtime +${BUILD_DIR_EXPIRE} -iname 'build-*' -print -exec rm -rf '{}' \; 2>&1 )

    WriteLog "res:${res}" "${PERF_TEST_LOG}"
    WriteLog "Done." "${PERF_TEST_LOG}"


    # ------------------------------------
    # Git repo clone
    #


    WriteLog "Git repo clone" "${PERF_TEST_LOG}"

    target=HPCC-Platform-${BRANCH_ID}-${LONG_DATE}
    cRes=$( CloneRepo "https://github.com/hpcc-systems/HPCC-Platform.git" "${target}" )

    if [[ 0 -ne  $? ]]
    then
        #WriteLog "Repo clone failed ! Result is: ${cres}" "${PERF_TEST_LOG}"
        #ExitEpilog "${PERF_TEST_LOG}"

        WriteLog "Repo clone failed ! Result is: ${cres}" "${PERF_TEST_LOG}"

        buildResult=FAILED
        export buildResult

        exit -2

    else
        WriteLog "Repo clone success !" "${PERF_TEST_LOG}"
    
        WriteLog "Create symlink for HPCC-Platform to ${target}." "${PERF_TEST_LOG}"
       
        [[ -h HPCC-Platform ]] && rm HPCC-Platform || ( [[ -d HPCC-Platform ]] && rm -rf HPCC-Platform)

        ln -s ${target} HPCC-Platform

        WriteLog "Done." "${PERF_TEST_LOG}"
   
        # Remove all HPCC-Platform-* directory older than a week (?)
        #
        WriteLog "Remove all HPCC-Platform-* directory older than ${SOURCE_DIR_EXPIRE} days." "${PERF_TEST_LOG}"
        res=$( find . -maxdepth 1 -type d -mtime +${SOURCE_DIR_EXPIRE} -iname 'HPCC-Platform-*' -print -exec rm -rf '{}' \; 2>&1 )

        WriteLog "res:${res}" "${PERF_TEST_LOG}"
        WriteLog "Done." "${PERF_TEST_LOG}"
    fi

    # -----------------------------------------
    # We use branch which is set in settings.sh
    #
    WriteLog "We use branch: ${BRANCH_ID} which is set in settings.sh" "${PERF_TEST_LOG}"

    cd ${PLATFORM_HOME}

    echo "git branch: ${BRANCH_ID}"  > ${GIT_2DAYS_LOG}

    echo "git checkout ${BRANCH_ID}" >> ${GIT_2DAYS_LOG}    
    WriteLog "git checkout ${BRANCH_ID}" "${PERF_TEST_LOG}"

    res=$( git checkout ${BRANCH_ID} 2>&1 )
    echo $res >> ${GIT_2DAYS_LOG}
    WriteLog "Result:${res}" "${PERF_TEST_LOG}"
    
    if [[ -n "$SHA" ]]
    then
        res=$( git checkout ${SHA} 2>&1 )
        WriteLog "Result:${res}" "${PERF_TEST_LOG}"
        COMMIT_ID=$SHA
    else
    COMMIT_ID=$( git log -1 | grep '^commit' | cut -d' ' -f 2 )
        COMMIT_ID=${COMMIT_ID:0:8}
    fi

    branchDate=$( git log -1 | grep '^Date' ) 
    WriteLog "Branch ${branchDate}" "${PERF_TEST_LOG}"
    echo $branchDate >> ${GIT_2DAYS_LOG}

    branchCrc=$( git log -1 | grep '^commit' )
    WriteLog "Branch ${branchCrc}" "${PERF_TEST_LOG}"
    echo $branchCrc>> ${GIT_2DAYS_LOG}

    export COMMIT_ID

    echo "git remote -v:"  >> ${GIT_2DAYS_LOG}
    git remote -v  >> ${GIT_2DAYS_LOG}

    echo ""  >> ${GIT_2DAYS_LOG}
    cat ${BUILD_DIR}/bin/gitlog.sh >> ${GIT_2DAYS_LOG}
    ${BUILD_DIR}/bin/gitlog.sh >> ${GIT_2DAYS_LOG}

    #
    # Update submodule
    #

    WriteLog "Update git submodule" "${PERF_TEST_LOG}"

    subRes=$( SubmoduleUpdate "--init --recursive" )
    if [[ 0 -ne  $? ]]
    then
        WriteLog "Submodule update failed ! Result is: ${subRes}" "${PERF_TEST_LOG}"
        exit -3

    else
        WriteLog "Submodule update success !" "${PERF_TEST_LOG}"
    fi
    
    #
    #----------------------------------------------------
    #
    # Check and cache boost package into $HOME directory and 
    # copy it into ${BUILD_HOME}/downloads/ directory to avoid on-fly download attempt in build
    #
    # Should get these information from HPCC-Platform/cmake_modules/buildBOOST_REGEX.cmake:
    #       URL https://dl.bintray.com/boostorg/release/1.71.0/source/boost_1_71_0.tar.gz
    #
    #BOOST_URL="https://dl.bintray.com/boostorg/release/1.71.0/source/$BOOST_PKG"
    BOOST_URL=$( egrep 'URL ' $SOURCE_HOME/cmake_modules/buildBOOST_REGEX.cmake| awk '{print $2}')

    #BOOST_PKG="boost_1_71_0.tar.gz"
    BOOST_PKG=${BOOST_URL##*/}; 

    WriteLog "Check if $BOOST_PKG cached" "${PERF_TEST_LOG}"
    if [[ ! -f $HOME/$BOOST_PKG ]]
    then
        WriteLog "It is not, download it." "${PERF_TEST_LOG}"
        BOOST_DOWNLOAD_TRY_COUNT=5
        BOOST_DOWNLOAD_TRY_DELAY=2m

        while [[ $BOOST_DOWNLOAD_TRY_COUNT -gt 0 ]]
        do 
            WriteLog "Try count: $BOOST_DOWNLOAD_TRY_COUNT" "${PERF_TEST_LOG}"
            BOOST_DOWNLOAD_TRY_COUNT=$(( $BOOST_DOWNLOAD_TRY_COUNT - 1 ))

            download_res=$( wget -v  -O  $HOME/$BOOST_PKG  $BOOST_URL 2>&1 )
            retCode=$?
            if [[  $retCode -ne 0 ]]
            then 
                WriteLog "Error: $retCode '${download_res}'. Wait ${BOOST_DOWNLOAD_TRY_DELAY} for retry." "${PERF_TEST_LOG}"
                sleep ${BOOST_DOWNLOAD_TRY_DELAY}
                [[ -f $HOME/$BOOST_PKG ]] && rm $HOME/$BOOST_PKG
            else
                WriteLog "The $BOOST_PKG downloaded." "${PERF_TEST_LOG}"
                WriteLog "Ping: ${download_res}" "${PERF_TEST_LOG}"

                DOWNL=$( echo "$download_res" | tail -nhead -n 2)
                WriteLog "${DOWNL}" "${OBT_LOG_DIR}/$BOOST_PKG.download"
                break
            fi
        done
    fi

    if [[ ! -f $HOME/$BOOST_PKG ]]
    then
        WriteLog "The $BOOST_PKG download attempts were unsuccessful." "${PERF_TEST_LOG}"
    else
        WriteLog "The $BOOST_PKG downloaded, copy it into the source tree." "${PERF_TEST_LOG}"
        mkdir -p ${BUILD_HOME}/downloads
        res=$( cp -v  $HOME/$BOOST_PKG ${BUILD_HOME}/downloads/  2>&1 )
        WriteLog "res: ${res}" "${PERF_TEST_LOG}"
    fi

    removeLog4j=$( find $SOURCE_HOME/ -iname '*log4j*' -type f -exec rm -fv {} \; )
    WriteLog "Remove LOG4J items result:\n${removeLog4j}" "${PERF_TEST_LOG}"

    removeCommonsText=$( find $SOURCE_HOME/ -iname 'commons-text-*.jar' -type f -exec rm -fv {} \; )
    WriteLog "Remove 'commons-text-*.jar' items result:\n${removeCommonsText}" "${PERF_TEST_LOG}"

    #
    # Prepare to build
    #

    cd ${BUILD_HOME}
    
    if [[ $PERF_SKIP_VCPKG_HANDLING -ne 1 ]]
    then 
        BASE_VERSION=${BRANCH_ID#candidate-}
        BASE_VERSION=${BASE_VERSION%.*}
        [[ "$BASE_VERSION" != "master" ]] && BASE_VERSION=$BASE_VERSION.x
        VCPKG_DOWNLOAD_ARCHIVE=~/vcpkg_downloads-${BASE_VERSION}.zip
        WriteLog "BRANCH_ID: $BRANCH_ID, BASE_VERSION: $BASE_VERSION, VCPKG_DOWNLOAD_ARCHIVE: $VCPKG_DOWNLOAD_ARCHIVE" "$PERF_TEST_LOG"

        if [[ -f  $VCPKG_DOWNLOAD_ARCHIVE ]]
        then
            WriteLog "Extract $VCPKG_DOWNLOAD_ARCHIVE into build directory" "$PERF_TEST_LOG"
            
            res=$( unzip $VCPKG_DOWNLOAD_ARCHIVE 2>&1 )
            retCode=$?
            
            [[ $retCode -ne 0 ]] && WriteLog "retCode: ${retCode}\nRes: $res" "$PERF_TEST_LOG"
            WriteLog "   Done."  "$PERF_TEST_LOG"
        else
            WriteLog "The $VCPKG_DOWNLOAD_ARCHIVE not found." "$PERF_TEST_LOG"
        fi
    else
        WriteLog "Skip vcpkg handling." "$PERF_TEST_LOG"
    fi

    date=$( date "+%Y-%m-%d %H:%M:%S")
    WriteLog "Start build at ${date}" "${PERF_TEST_LOG}"

    WriteLog "Create makefiles $(date +%Y-%m-%d_%H-%M-%S)" "${PERF_TEST_LOG}"
    CMAKE_CMD=$'cmake'
    CMAKE_CMD+=$' -D CMAKE_BUILD_TYPE='$PERF_BUILD_TYPE
    CMAKE_CMD+=$' -D CMAKE_EXE_LINKER_FLAGS=-lrt'
    CMAKE_CMD+=${PERF_SUPRESS_PLUGINS}
    CMAKE_CMD+=$' -D USE_CPPUNIT=1'
    CMAKE_CMD+=$' -D USE_LIBMEMCACHED=1'
    CMAKE_CMD+=$' -D CMAKE_EXPORT_COMPILE_COMMANDS=ON'
    CMAKE_CMD+=$' -D VCPKG_ECLBLAS_DYNAMIC_ARCH=OFF'
    CMAKE_CMD+=$' -D USE_NATIVE_LIBRARIES=ON'
    CMAKE_CMD+=$' -D WSSQL_SERVICE=1'
    CMAKE_CMD+=$' -D USE_LIBXSLT=ON'
    CMAKE_CMD+=$' -D XALAN_LIBRARIES='
    CMAKE_CMD+=$' ../HPCC-Platform'

    WriteLog "CMAKE_CMD:'${CMAKE_CMD}'\\n" "${PERF_TEST_LOG}"

    res=$( eval ${CMAKE_CMD} 2>&1 )

    WriteLog "${res[*]}" "${PERF_TEST_LOG}"

    # Control TBB and TBBMALLOC stuff

    if [[ $PERF_CONTROL_TBB -eq 1 ]]
    then
        C_CMD="cmake -D USE_TBB=$PERF_USE_TBB -DUSE_TBBMALLOC=$PERF_USE_TBBMALLOC ../HPCC-Platform"
        WriteLog "${C_CMD}" "${PERF_TEST_LOG}"

        res=( "$(${C_CMD} 2>&1)" )
        echo "${res[*]}" > ${BUILD_LOG_FILE}
    fi


    # Let's build
    CMD="make -j ${NUMBER_OF_BUILD_THREADS} package"
    WriteLog "cmd: ${CMD}" "${PERF_TEST_LOG}"

    ${CMD} >> ${BUILD_LOG_FILE} 2>&1

    if [ $? -ne 0 ] 
    then
        WriteLog "Build failed: build has errors " "${PERF_TEST_LOG}"
        buildResult=FAILED
        export buildResult
        exit 1
    else
        ls -l hpcc*${PKG_EXT} >/dev/null 2>&1
        if [ $? -ne 0 ] 
        then
            WriteLog "Build failed: no rpm package found " "${PERF_TEST_LOG}"
            buildResult=FAILED
            exit 2
        else
            WriteLog "Build succeed" "${PERF_TEST_LOG}"
            buildResult=SUCCEED
            if [[ $NEW_BUILD_DIR_STRUCTURE -ne 0 ]]
            then
                pushd ${BUILD_DIR}/$RELEASE_TYPE
                WriteLog "Move 'build' to '$buildTarget' (PWD:$(pwd))." "${PERF_TEST_LOG}"
                mv build $buildTarget
                WriteLog "Create link as 'build'" "${PERF_TEST_LOG}"
                ln -s ${buildTarget} build
                WriteLog "  Done. (retCode: $?)'. " "${PERF_TEST_LOG}"
                popd
            fi
            
            if [[ $PERF_SKIP_VCPKG_HANDLING -ne 1 ]]
            then 
                if [[ -d ${BUILD_HOME}/vcpkg_installed  ]]
                then
                    BASE_VERSION=${BRANCH_ID#candidate-}
                    BASE_VERSION=${BASE_VERSION%.*}
                    [[ "$BASE_VERSION" != "master" ]] && BASE_VERSION=$BASE_VERSION.x
                    WriteLog "Check the content of vcpkg_downloads-${BASE_VERSION}.zip file" "${PERF_TEST_LOG}"
                    # We need relative paths to use this archive in Smoketest as well
                    pushd ${BUILD_HOME}
                    rm -rf vcpkg_downloads/tools vcpkg_downloads/temp
                    [[ -f vcpkg_installed/vcpkg/compiler-file-hash-cache.json ]] && rm -rf  vcpkg_installed/vcpkg

                    changesInInstalled=1
                    changesInDownloads=1
                    if [[ -f ~/vcpkg_downloads-${BASE_VERSION}.zip ]]
                    then
                        cp -fv ~/vcpkg_downloads-${BASE_VERSION}.zip .
                        changesInInstalled=$( zip -ru vcpkg_downloads-${BASE_VERSION}.zip vcpkg_installed/* )
                        WriteLog "Changes in installed: '$changesInInstalled'." "${PERF_TEST_LOG}"
                                        
                        changesInDownloads=$( zip -u vcpkg_downloads-${BASE_VERSION}.zip vcpkg_downloads/* )
                        WriteLog "Changes in downloads: '$changesInDownloads'." "${PERF_TEST_LOG}"
                    fi

                    if [[ -n "$changesInInstalled" || -n "$changesInDownloads" ]]
                    then
                        # Don't use the local vcpkg_downloads-${BASE_VERSION}.zip  file updated above,
                        # because it can contain older version of components along with the new one and
                        # its size can grows more than necessary.
                        WriteLog "Something changed, generate a new '~/vcpkg_downloads-${BASE_VERSION}.zip'." "${PERF_TEST_LOG}"
                        [[ -f ~/vcpkg_downloads-${BASE_VERSION}.zip ]] && WriteLog "Clean-up: $(rm -v ~/vcpkg_downloads-${BASE_VERSION}.zip) 2>&1)." "${PERF_TEST_LOG}"

                        res=$(zip -r ~/vcpkg_downloads-${BASE_VERSION}.zip vcpkg_installed/* vcpkg_downloads/*  2>&1)
                        retCode=$?
                        [[ $retCode -ne 0 ]] && WriteLog "retCode: ${retCode}\nRes: $res" "${PERF_TEST_LOG}"
                        WriteLog "  Done." "${PERF_TEST_LOG}"
                    else
                        WriteLog "Nothing changed neither in vcpkg_installed nor in vcpkg_dowloads,\nso, keep the original '~/vcpkg_downloads-${BASE_VERSION}.zip'." "${PERF_TEST_LOG}"
                    fi
                    [[ -f ./vcpkg_downloads-${BASE_VERSION}.zip ]] && WriteLog "Clean-up: $(rm -v ./vcpkg_downloads-${BASE_VERSION}.zip) 2>&1)." "${PERF_TEST_LOG}"
                else
                    WriteLog "Skip vcpkg handling." "$PERF_TEST_LOG"
                fi
                
                WriteLog "Clean-up 'build/vcpkg_*', '_CPack_Packages' and 'esp' '$RELEASE_TYPE' directories to save disk space." "${PERF_TEST_LOG}"
                WriteLog "Before: $(df -h . | egrep -v 'Files')" "${PERF_TEST_LOG}"
                for d in vcpkg_downloads vcpkg_installed _CPack_Packages esp $RELEASE_TYPE
                do
                    WriteLog "rm -rf $d" "${PERF_TEST_LOG}"
                    rm -rf $d
                    WriteLog "Res: $?" "${PERF_TEST_LOG}"
                done
                WriteLog  "After: $(df -h . | egrep -v 'Files')" "${PERF_TEST_LOG}"
                WriteLog "  Done." "${PERF_TEST_LOG}"
            fi
        fi
    fi

    date=$( date "+%Y-%m-%d %H:%M:%S")
    WriteLog "Build end at ${date}" "${PERF_TEST_LOG}"

    HPCC_PACKAGE=$( find . -maxdepth 1 -name 'hpccsystems-platform-community*' -type f )
    
    WriteLog " Default package: '${HPCC_PACKAGE}'." "${PERF_TEST_LOG}"
    WriteLog "                                           " "${PERF_TEST_LOG}"      

else
    WriteLog "                                           " "${PERF_TEST_LOG}"
    WriteLog "*******************************************" "${PERF_TEST_LOG}"
    WriteLog " Skip build HPCC Platform...               " "${PERF_TEST_LOG}"
    WriteLog "                                           " "${PERF_TEST_LOG}"      

    cd ${BUILD_HOME}
    HPCC_PACKAGE=$( find . -maxdepth 1 -name 'hpccsystems-platform-community*' -type f )    
    WriteLog " Default package: '${HPCC_PACKAGE}' ." "${PERF_TEST_LOG}"
    WriteLog "                                           " "${PERF_TEST_LOG}"      

fi


TARGET_PLATFORM="hthor"

if [[ "$PERF_RUN_HTHOR" -eq 1 ]]
then
    #***************************************************************
    #
    #           HTHOR test
    #
    #***************************************************************
    
    WriteLog "                                " "${PERF_TEST_LOG}"
    WriteLog "********************************" "${PERF_TEST_LOG}"
    WriteLog " Start ${TARGET_PLATFORM} test. " "${PERF_TEST_LOG}"
    WriteLog "                                " "${PERF_TEST_LOG}"
    
    #
    # --------------------------------------------------------------
    # Install HPCC
    #
#    if [[ ${PERF_KEEP_HPCC} -eq 0 ]]
#    then
#        WriteLog "Remove environment.xml to ensure clean, out-of-box environmnet." "${PERF_TEST_LOG}"
#        sudo rm /etc/HPCCSystems/environment.xml
#
#        WriteLog "Install HPCC Platform ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
#    
#        ${SUDO} ${PKG_INST_CMD} ${BUILD_HOME}/${HPCC_PACKAGE}
#    
#        if [ $? -ne 0 ]
#        then
#            WriteLog "Error in install! ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
#            exit
#        fi
#    else
#        WriteLog "Start HPCC Platform ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
#        ${SUDO} /etc/init.d/hpcc-init start
#    fi
    #
    # --------------------------------------------------------------
    # Install HPCC
    #
    if [ -f /etc/HPCCSystems/environment.xml ]
    then
        WriteLog "Remove environment.xml to ensure clean, out-of-box environmnet." "${PERF_TEST_LOG}"
        sudo rm /etc/HPCCSystems/environment.xml
    fi

    WriteLog "Install HPCC Platform ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    ${SUDO} ${PKG_INST_CMD} ${BUILD_HOME}/${HPCC_PACKAGE}
    
    if [ $? -ne 0 ]
    then
        WriteLog "Error in install! ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
        exit 1
    fi

    # Add Write permission to /var/lib/HPCCSystems and its subdiretories

    ${SUDO} chmod -R 0777 /var/lib/HPCCSystems


    #
    #---------------------------
    #
    # Patch environment.xml to use diferent size Memory
    #

    MEMSIZE=$(( $PERF_HTHOR_MEMSIZE_GB * (2 ** 30) ))

    # for hthor we should change 'defaultMemoryLimitMB' as well 

    MEMSIZE_MB=$(( $PERF_HTHOR_MEMSIZE_GB * (2 ** 10) ))

    
    WriteLog "Patch environment.xml to use ${PERF_HTHOR_MEMSIZE_GB}GB Memory for test on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    ${SUDO} cp /etc/HPCCSystems/environment.xml /etc/HPCCSystems/environment.xml.bak
    ${SUDO} sed -e 's/totalMemoryLimit="1073741824"/totalMemoryLimit="'${MEMSIZE}'"/g' -e 's/defaultMemoryLimitMB="300"/defaultMemoryLimitMB="'${MEMSIZE_MB}'"/g' "/etc/HPCCSystems/environment.xml" > temp.xml && ${SUDO} mv -f temp.xml "/etc/HPCCSystems/environment.xml"

    WriteLog "Patch environment.xml to use ${PERF_THOR_NUMBER_OF_SLAVES} slaves for Thor" "${PERF_TEST_LOG}"
    WriteLog "Patch environment.xml to use ${PERF_THOR_LOCAL_THOR_PORT_INC} for localThorPortInc for Thor" "${PERF_TEST_LOG}"
    
    #${SUDO} cp /etc/HPCCSystems/environment.xml /etc/HPCCSystems/environment.xml.bak
    ${SUDO} sed -e 's/slavesPerNode="\(.*\)"/slavesPerNode="'${PERF_THOR_NUMBER_OF_SLAVES}'"/g' \
                -e 's/localThorPortInc="\(.*\)"/localThorPortInc="'${PERF_THOR_LOCAL_THOR_PORT_INC}'"/g' \
                   "/etc/HPCCSystems/environment.xml" > temp.xml && ${SUDO} mv -f temp.xml "/etc/HPCCSystems/environment.xml"

    WriteLog "Add 'farmSsl' Roxie Farm Process to environment.xml" "${PERF_TEST_LOG}"
    addTlsToRoxie
    
    #
    #----------------------------------------------------
    #
    # Kill Cassandra if it used too much memory
    #
    WriteLog "Check memory on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    freeMem=$( free | egrep "^(Mem)" | awk '{print $4 }' )

    WriteLog "Free memory is: ${freeMem} kB on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    if [[ "$freeMem" -lt 3777356 ]]
    then
        WriteLog "Free memory too low on ${TARGET_PLATFORM}!" "${PERF_TEST_LOG}"

        cassandraPID=$( ps ax  | grep '[c]assandra' | awk '{print $1}' )
    
        if [ -n "$cassandraPID" ]
        then
            WriteLog "Kill Cassandra (pid: ${cassandraPID})  on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
        
            kill -9 ${cassandraPID}
            sleep 5
    
            freeMem=$( free | egrep "^(Mem)" | awk '{print $4 }' )
            if [[ "$freeMem" -lt 3777356 ]]
            then
                WriteLog "The free memory (${freeMem} kB) is still too low! Cannot start HPCC Systems!! Give it up on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
        
                # send email to Agyi
                echo "After the kill Cassandra the Performance test free memory (${freeMem} kB) is still too low on ${TARGET_PLATFORM}! Performance test stopped!" | mailx -s "OBT Memory problem" -u $USER  ${ADMIN_EMAIL_ADDRESS}
        
                #exit -1
            fi
        fi
    fi

    WriteLog "Free memory is: ${freeMem} kB on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    #
    #---------------------------
    #
    # Check HPCC Systems
    #
    WriteLog "Check HPCC Systems on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

    NUMBER_OF_HPCC_COMPONENTS=$( /opt/HPCCSystems/sbin/configgen -env /etc/HPCCSystems/environment.xml -list | egrep -i -v 'eclagent' | wc -l )
    
    hpccRunning=$( ${SUDO} /etc/init.d/hpcc-init status | grep -c "running")

    if [[ "$hpccRunning" -ne ${NUMBER_OF_HPCC_COMPONENTS} ]]
    then
        WriteLog "Start HPCC System on ${TARGET_PLATFORM}..." "${PERF_TEST_LOG}"
        ${SUDO} /etc/init.d/hpcc-init start
    fi
    
    # give it some time
    sleep 5
    
    hpccRunning=$( ${SUDO} /etc/init.d/hpcc-init status | grep -c "running")
    if [[ "$hpccRunning" -ne ${NUMBER_OF_HPCC_COMPONENTS} ]]
    then
        WriteLog "Unable start HPCC system!! Only ${hpccRunning} component is up on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
        exit -2
    fi
    
    #
    #----------------------------------------------------
    #
    # Check if HPCC can generate core with execute ECL code
    #
    
    if [[ ${PERF_RUN_CORE_TEST} -eq 1 ]]
    then
        cd ${BIN_HOME}

        WriteLog "Check ECL core generation." "${PERF_TEST_LOG}"

        res=$( ulimit -a | grep '[c]ore' )

        WriteLog "ulimit: ${res}" "${PERF_TEST_LOG}"

        ./checkCoreGen.sh ecl >> "${PERF_TEST_LOG}" 2>&1

        cd ${REGRESSION_TEST_ENGINE_HOME}

        # Add Write permission to /var/lib/HPCCSystems and its subdiretories
        ${SUDO} chmod -R 0777 /var/lib/HPCCSystems

        WriteLog "Check ECL core generation with Regression Test Engine." "${PERF_TEST_LOG}"

        CMD="./ecl-test run --suiteDir ${BIN_HOME} --timeout 15 -fthorConnectTimeout=36000 -t all"

        WriteLog "CMD: '${CMD}'" "${PERF_TEST_LOG}"
    
        ${CMD} >> ${PERF_TEST_LOG} 2>&1
        
        retCode=$( echo $? )
        WriteLog "retcode: ${retCode}" "${PERF_TEST_LOG}"
    
        cores=( $( find /var/lib/HPCCSystems/ -name 'core_*' -type f ) )

        if [ ${#cores[@]} -ne 0 ]
        then
            WriteLog "There is/are ${#cores[@]} core file(s) '${cores[*]}'" "${PERF_TEST_LOG}"
            if [ ${#cores[@]} -eq 3 ]
            then
                WriteLog "Core generation is OK!" "${PERF_TEST_LOG}"
            else
                WriteLog "Core generation failed on some platform(s)!" "${PERF_TEST_LOG}"
            fi
            WriteLog "Clean up." "${PERF_TEST_LOG}"

            ${SUDO} rm -f ${cores[*]}
            rm eclcc.log
        else
            WriteLog "Problem with Core generation!" "${PERF_TEST_LOG}"
        fi

        rm -rf ${LOG_DIR}/*
    else
        WriteLog "Check core generation skipped." "${PERF_TEST_LOG}"
    fi
    
    #
    #---------------------------
    #
    # Get test from github
    #
    WriteLog "Get Performance Test Boundle from github on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    cd  ${PERF_TEST_ROOT}

    WriteLog "Pwd: ${myPwd} $TARGET_PLATFORM" "${PERF_TEST_LOG}"

    WriteLog "Get test from github ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

    cRes=$( CloneRepo "${PERF_TEST_REPO}" )
    if [[ 0 -ne  $? ]]
    then
        WriteLog "Repo clone failed ! Result is: ${cres}" "${PERF_TEST_LOG}"
        exit -3
    else
        WriteLog "Repo clone success !" "${PERF_TEST_LOG}"
    fi
    
    SuppressAnalyserWarnings
    InjectTimeout
    
    cd ${REGRESSION_TEST_ENGINE_HOME}
    

    #
    #----------------------------------------------------
    #
    # Patch testcase(s) which previously run timeout if any

    #echo "Patch testcases which previously run timeout if any ${TARGET_PLATFORM}"
    #WriteLog "Patch testcases which previously run timeout if any ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

    #if [ -f ${TIMEOUTED_FILE_LIST_NAME} ]
    #then
    #    echo "There is some timeouted testcases"
    #    WriteLog "There is some timeouted testcases" "${PERF_TEST_LOG}"
    #    myPwd=$( pwd )    
    #    cd ${PERF_TEST_HOME}/ecl
    #    
    #    while read fileName
    #    do
    #        echo "File:${fileName}"
    #        WriteLog "File:${fileName}" "${PERF_TEST_LOG}"
    #        
    #        patched=$( grep '//timeout' ${fileName}.ecl )
    #    
    #        if [[ -z ${patched} ]]
    #        then
    #            echo "Patching..."
    #            WriteLog "Patching..." "${PERF_TEST_LOG}"
    #            $(echo ${TIMEOUT_TAG}; cat ${fileName}".ecl") >${fileName}.new
    #            mv ${fileName}{.new,.ecl}
    #        else
    #            echo "Already has //timeout tag !"
    #            WriteLog "Already has //timeout tag !" "${PERF_TEST_LOG}"
    #        fi
    #    done < "${TIMEOUTED_FILE_LIST_NAME}"
    #    
    #    cd ${myPwd}
    #fi
    

    #
    #----------------------------------------------------
    #
    # Exclude doesn't implement sort algos from Hthor
    #
    cd  ${PERF_TEST_HOME}

    excludeAlgos=('insertionsort' 'tbbstableqsort')
    
    for i in ${excludeAlgos[@]}
    do
        WriteLog "i: ${i}" "${PERF_TEST_LOG}"
        isExists=$( grep -l '${i}$' ecl/*.ecl )
        WriteLog "isExists: ${isExists}" "${PERF_TEST_LOG}"
        
        if [[ -n ${isExists} ]]
        then
            for f in ${isExists[@]}
            do
                WriteLog "f: ${f}" "${PERF_TEST_LOG}"
                msg="Exclude ${f}(algo='${i}')"
                WriteLog "${msg} on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

                cp ${f} ${f}.bak
                sed 's/\/\/version algo=\x27'${i}'\x27$/\/\/version algo=\x27'${i}'\x27,no'${TARGET_PLATFORM}'/g' "${f}" > ./temp.ecl 
                mv -f ./temp.ecl ${f}
            done
        else
            WriteLog "It seems the ${i} on ${TARGET_PLATFORM} is already fixed." "${PERF_TEST_LOG}"
        fi
    done
    
    #
    #----------------------------------------------------
    # 
    # Till it is not fixed change
    #   export indexName := prefix + 'index';
    # to
    #   export indexName := thorprefix + 'index';
    # in ecl/perform/files.ecl
    #
    #
    #cd  ${PERF_TEST_HOME}
    #
    #isExists=$( grep -l 'indexName := prefix' ecl/perform/files.ecl )
    #WriteLog "isExists: ${isExists}" "${PERF_TEST_LOG}"
    #if [[ -n ${isExists} ]]
    #then
    #    WriteLog "Replace 'prefix' to 'thorprefix'." "${PERF_TEST_LOG}"
    #    sed 's/indexName := prefix/indexName := thorprefix/g' "ecl/perform/files.ecl" > ./temp.ecl 
    #    mv -f ./temp.ecl ecl/perform/files.ecl
    #else
    #    WriteLog "It seems the 'export indexName:=...' in 'ecl/perform/files.ecl' is already fixed." "${PERF_TEST_LOG}"
    #fi
    #

    #
    #------------------------------------------------------------
    # Start sar monitor if it is enabled
    pushd $OBT_BIN_DIR

    if [[ ${PERF_SAR_MONITOR_START} -eq 1 ]]
    then
        WriteLog "Start System Resource monitor (sar) " "${PERF_TEST_LOG}"

        sar -r 1 > sar-${TARGET_PLATFORM}-$(date +%Y-%m-%d_%H-%M%S).log 2>&1 &
        echo $! > sarMonitor.pid
        WriteLog "  pid: $(cat sarMonitor.pid)" "${PERF_TEST_LOG}"
    fi

    popd

    #
    #---------------------------
    #
    # Run performance tests setup
    #
    WriteLog "Run performance tests setup on all platforms pwd:${myPwd}" "${PERF_TEST_LOG}"
    
    cd ${REGRESSION_TEST_ENGINE_HOME}    

    WriteLog "PERF_TEST_HOME  : ${PERF_TEST_HOME}" "${PERF_TEST_LOG}"
    WriteLog "TEST_ENGINE_HOME: ${REGRESSION_TEST_ENGINE_HOME}" "${PERF_TEST_LOG}"
    
    CMD="./ecl-test setup --suiteDir ${PERF_TEST_HOME} --timeout ${PERF_TIMEOUT} -fthorConnectTimeout=36000 --pq ${PERF_SETUP_PARALLEL_QUERIES} ${JOB_NAME_SUFFIX}"

    WriteLog "CMD: '${CMD}'" "${PERF_TEST_LOG}"
    
    NUMBER_OF_PUBLISHED=0
    if [ ${EXECUTE_PERFORMANCE_SUITE_SETUP} -ne 0 ]
    then
        ${CMD} >> ${PERF_TEST_LOG} 2>&1
        
        retCode=$( echo $? )
        WriteLog "retcode: ${retCode}" "${PERF_TEST_LOG}"
    
        if [ ${retCode} -ne 0 ] 
        then
            WriteLog "Performance tests on ${TARGET_PLATFORM} returns with ${retCode}" "${PERF_TEST_LOG}"
            exit -1
        else 
            ProcessLog "setup_hthor"
            ProcessLog "setup_thor"
            ProcessLog "setup_roxie"
        fi
    else
        WriteLog "Skip performance test setup execution!" "${PERF_TEST_LOG}"
        WriteLog "                                      " "${PERF_TEST_LOG}"        
    fi

    #
    #---------------------------
    #
    # Run performance tests
    #
    WriteLog "Run performance tests on ${TARGET_PLATFORM} pwd:${myPwd}" "${PERF_TEST_LOG}"
    
    cd ${REGRESSION_TEST_ENGINE_HOME}    

    WriteLog "PERF_TEST_HOME  : ${PERF_TEST_HOME}" "${PERF_TEST_LOG}"
    WriteLog "TEST_ENGINE_HOME: ${REGRESSION_TEST_ENGINE_HOME}" "${PERF_TEST_LOG}"
    
    if [[ -n "$PERF_QUERY_LIST" ]]
    then
        CMD="./ecl-test query --suiteDir ${PERF_TEST_HOME} --timeout ${PERF_TIMEOUT} -fthorConnectTimeout=36000 -t ${TARGET_PLATFORM} ${PERF_EXCLUDE_CLASS} --pq ${PERF_TEST_PARALLEL_QUERIES} ${PERF_FLUSH_DISK_CACHE} ${PERF_RUNCOUNT} ${PERF_QUERY_LIST} ${JOB_NAME_SUFFIX}"
    else
        CMD="./ecl-test run --suiteDir ${PERF_TEST_HOME} --timeout ${PERF_TIMEOUT} -fthorConnectTimeout=36000 -t ${TARGET_PLATFORM} ${PERF_EXCLUDE_CLASS} --pq ${PERF_TEST_PARALLEL_QUERIES} ${PERF_FLUSH_DISK_CACHE} ${PERF_RUNCOUNT} ${JOB_NAME_SUFFIX}"
    fi

    WriteLog "CMD: '${CMD}'" "${PERF_TEST_LOG}"
    
    if [ ${EXECUTE_PERFORMANCE_SUITE} -eq 1 ]
    then
        ${CMD} >> ${PERF_TEST_LOG} 2>&1
        
        retCode=$( echo $? )
        WriteLog "retcode: ${retCode}" "${PERF_TEST_LOG}"
    
        if [ ${retCode} -ne 0 ] 
        then
            WriteLog "Performance tests on ${TARGET_PLATFORM} returns with ${retCode}" "${PERF_TEST_LOG}"
            exit -1
        else 
            ProcessLog "${TARGET_PLATFORM}"
        fi
    else
        WriteLog "Skip performance test suite execution!" "${PERF_TEST_LOG}"
        WriteLog "                                      " "${PERF_TEST_LOG}"        
    fi


    #
    #--------------------------
    #
    pushd $OBT_BIN_DIR

    if [[ -f ./sarMonitor.pid ]]
    then
        WriteLog "Stop sarMonitor (pid: $(cat ./sarMonitor.pid)" "${PERF_TEST_LOG}"
        res=$(sudo kill $( cat ./sarMonitor.pid ) 2>&1 )
        retCode=$?
        WriteLog "retCode:$retCode\nres:$res" "${PERF_TEST_LOG}"

        res=$( rm -v ./sarMonitor.pid )
        retCode=$?
        WriteLog "retCode:$retCode\nres:$res" "${PERF_TEST_LOG}"

    fi

    #
    #---------------------------
    #
    # Archive hthor performance logs
    #
    
    WriteLog "Archive ${TARGET_PLATFORM} performance logs" "${PERF_TEST_LOG}"
    
    ${BIN_HOME}/archiveLogs.sh performance-${TARGET_PLATFORM} timestamp=${OBT_TIMESTAMP}
    
    #
    #---------------------------
    #
    # Uninstall HPCC to free as much disk space as can
    #

    if [[ ${PERF_KEEP_HPCC} -eq 0 ]]
    then
        WriteLog "Uninstall HPCC to free as much disk space as can on ${TARGET_PLATFORM}!" "${PERF_TEST_LOG}"
    
        WriteLog "Uninstall HPCC-Platform" "${PERF_TEST_LOG}"
    
        UninstallHPCC "${PERF_TEST_LOG}" "${PERF_WIPE_OFF_HPCC}"
    else
        WriteLog "Skip Uninstall HPCC on ${TARGET_PLATFORM} but stop it!" "${PERF_TEST_LOG}"
        StopHpcc "${PERF_TEST_LOG}"
    fi

    #
    #----------------------------
    #
    # Remove ECL-Bundles
    #
    WriteLog "Remove ECL-Bundles" "${PERF_TEST_LOG}"
    
    rm -rf ${PERF_TEST_ROOT}/PerformanceTesting
    
    WriteLog "                                " "${PERF_TEST_LOG}"
    WriteLog "********************************" "${PERF_TEST_LOG}"
    WriteLog " End of ${TARGET_PLATFORM} test." "${PERF_TEST_LOG}"
    WriteLog "                                " "${PERF_TEST_LOG}"
    
else
    WriteLog "                                " "${PERF_TEST_LOG}"
    WriteLog "********************************" "${PERF_TEST_LOG}"
    WriteLog " Skip ${TARGET_PLATFORM} test.  " "${PERF_TEST_LOG}"
    WriteLog "                                " "${PERF_TEST_LOG}"

fi


TARGET_PLATFORM="thor"

if [[ "$PERF_RUN_THOR" -eq 1 ]]
then

    #***************************************************************
    #
    #           THOR test
    #
    #***************************************************************
    
    WriteLog "                                " "${PERF_TEST_LOG}"
    WriteLog "********************************" "${PERF_TEST_LOG}"
    WriteLog " Start ${TARGET_PLATFORM} test. " "${PERF_TEST_LOG}"
    WriteLog "                                " "${PERF_TEST_LOG}"
    
    #
    # --------------------------------------------------------------
    # Install HPCC
    #
    if [ -f /etc/HPCCSystems/environment.xml ]
    then
        WriteLog "Remove environment.xml to ensure clean, out-of-box environmnet." "${PERF_TEST_LOG}"
        sudo rm /etc/HPCCSystems/environment.xml
    fi

    WriteLog "Install HPCC Platform ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    # TO-DO Should check if it is already installed
    ${SUDO} ${PKG_INST_CMD} ${BUILD_HOME}/${HPCC_PACKAGE}
    
    if [ $? -ne 0 ]
    then
        WriteLog "Error in install! ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
        exit 1
    fi
        
    # Add Write permission to /var/lib/HPCCSystems and its subdiretories

    ${SUDO} chmod -R 0777 /var/lib/HPCCSystems

    #
    #----------------------------------------------------
    #
    # Check free memory
    #
    
    WriteLog "Check memory. ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    freeMem=$( free | egrep "^(Mem)" | awk '{print $4 }' )
    
    WriteLog "Free memory is: ${freeMem} kB ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

    #
    #---------------------------
    # Check if it run on multinode system
    #
    if [[ $PERF_NUM_OF_NODES -gt 1 ]]
    then
       WriteLog "Multinode cluster is enabled." "${PERF_TEST_LOG}"
    
        if [ -f ${OBT_BIN_DIR}/multinode_perf_cluster.xml ]
        then
            WriteLog "Copy multinode environment file:multinode_perf_cluster.xml into /etc/HPCCSystems directory" "${PERF_TEST_LOG}"
            sudo cp ${OBT_BIN_DIR}/multinode_perf_cluster.xml /etc/HPCCSystems/environment.xml
        else
            PERF_NUM_OF_NODES=1
            WriteLog "Multinode environment file not found. Fall back to single node." "${PERF_TEST_LOG}"
        fi
    else
        WriteLog "Multinode cluster is not enabled." "${PERF_TEST_LOG}"
    fi
     
    WriteLog "Cluster size is: $PERF_NUM_OF_NODES node(s)." "${PERF_TEST_LOG}"

    #
    #---------------------------
    #
    # Patch environment.xml to use diferent size Memory
    #

    MEMSIZE=$(( $PERF_THOR_MEMSIZE_GB * (2 ** 30) ))

    WriteLog "Patch environment.xml to use ${PERF_THOR_MEMSIZE_GB}GB Memory for ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    WriteLog "Patch environment.xml to use ${PERF_THOR_NUMBER_OF_SLAVES} slaves for ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    WriteLog "Patch environment.xml to use ${PERF_THOR_LOCAL_THOR_PORT_INC} for localThorPortInc for ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    ${SUDO} cp /etc/HPCCSystems/environment.xml /etc/HPCCSystems/environment.xml.bak
    ${SUDO} sed -e 's/totalMemoryLimit="\(.*\)"/totalMemoryLimit="'${MEMSIZE}'"/g' \
                -e 's/slavesPerNode="\(.*\)"/slavesPerNode="'${PERF_THOR_NUMBER_OF_SLAVES}'"/g' \
                -e 's/localThorPortInc="\(.*\)"/localThorPortInc="'${PERF_THOR_LOCAL_THOR_PORT_INC}'"/g' \
                   "/etc/HPCCSystems/environment.xml" > temp.xml && ${SUDO} mv -f temp.xml "/etc/HPCCSystems/environment.xml"

    
    WriteLog "Add 'farmSsl' Roxie Farm Process to environment.xml" "${PERF_TEST_LOG}"
    addTlsToRoxie

    #
    #---------------------------
    #
    # Set HPCC core size
    #
    isHpccInLimits=$( egrep -c 'hpcc [sh].* core ' /etc/security/limits.conf)
    if [[ $isHpccInLimits -eq 0 ]]
    then
        WriteLog "Patch /etc/security/limits.conf to set hpcc core size to  ${CORE_LIMIT}" "${PERF_TEST_LOG}"
        echo "# Patched by OBT Performance test" | sudo tee -a /etc/security/limits.conf
        echo "hpcc soft core  ${CORE_LIMIT}" | sudo tee -a /etc/security/limits.conf
        echo "hpcc hard core  ${CORE_LIMIT}" | sudo tee -a /etc/security/limits.conf
    else
        WriteLog "hpcc core settings are already exists in '/etc/security/limits.conf', change them to  ${CORE_LIMIT}." "${PERF_TEST_LOG}"
        sudo sed -i 's/hpcc \([sh].*\) core \(.*\)/hpcc \1 core '" ${CORE_LIMIT}"'/g' /etc/security/limits.conf
    fi
    WriteLog "  Done\n$(egrep 'hpcc [sh].* core' /etc/security/limits.conf)" "${PERF_TEST_LOG}"        
    
    isHpccComonCoreUnlimited=$(egrep -c  'MIN_Hc_core="unlimited"' /opt/HPCCSystems/etc/init.d/hpcc_common 2>&1 )
    if [[ ${isHpccComonCoreUnlimited} -eq 1 ]]
    then
        sudo sed -i 's/MIN_Hc_core="\(.*\)"/MIN_Hc_core="0"/g' /opt/HPCCSystems/etc/init.d/hpcc_common
    else
        WriteLog "The '/opt/HPCCSystems/etc/init.d/hpcc_common' is already patched." "${PERF_TEST_LOG}"
    fi
    WriteLog "  Done\n$(egrep 'MIN_Hc_core=' /opt/HPCCSystems/etc/init.d/hpcc_common)" "${PERF_TEST_LOG}" 

    WriteLog "Core dump filter: $(sudo cat /proc/self/coredump_filter)" "${PERF_TEST_LOG}"
    res=$( echo 0x13 | sudo tee /proc/self/coredump_filter 2>&1)
    retCode=$?
    WriteLog "retCode:${retCode}\nres:$res" "${PERF_TEST_LOG}"
    WriteLog "Core dump filter: $(sudo cat /proc/self/coredump_filter)" "${PERF_TEST_LOG}"

    #
    #---------------------------
    #
    # Check HPCC Systems
    #
    
    WriteLog "Check HPCC Systems ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

    NUMBER_OF_HPCC_COMPONENTS=$( /opt/HPCCSystems/sbin/configgen -env /etc/HPCCSystems/environment.xml -list | egrep -i -v 'eclagent' | wc -l )

    WriteLog "Number of HPCC components is: ${NUMBER_OF_HPCC_COMPONENTS} ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

    
    if [[ $PERF_NUM_OF_NODES -gt 1  &&  -f ${OBT_BIN_DIR}/multinode_perf_cluster.xml ]]
    then
        WriteLog "Multinode cluster is enabled." "${PERF_TEST_LOG}"

        # Push config file
        WriteLog "Push config file... ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
        sudo /opt/HPCCSystems/sbin/hpcc-push.sh -s ${OBT_BIN_DIR}/multinode_perf_cluster.xml.work -t /etc/HPCCSystems/environment.xml

        WriteLog "Start HPCC System... ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
        # install  package to the nodes
        sudo /opt/HPCCSystems/sbin/install-cluster.sh ${BUILD_HOME}/${HPCC_PACKAGE}

        # Start the cluster
        sudo /opt/HPCCSystems/sbin/hpcc-run.sh -a hpcc-init start -n $PERF_NUM_OF_NODES

    else
        
        hpccRunning=$( ${SUDO} /etc/init.d/hpcc-init status | grep -c "running")
        if [ $hpccRunning -ne ${NUMBER_OF_HPCC_COMPONENTS} ]
        then
            WriteLog "$hpccRunning componenets are running, start HPCC System... ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
            ${SUDO} /etc/init.d/hpcc-init start
        fi
    
        # give it some time
        sleep 5
    
        hpccRunning=$( ${SUDO} /etc/init.d/hpcc-init status | grep -c "running")
        if [[ "$hpccRunning" -ne "${NUMBER_OF_HPCC_COMPONENTS}" ]]
        then
            WriteLog "Unable start HPCC system!! Only ${hpccRunning} component from $NUMBER_OF_HPCC_COMPONENTS is up. ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

            msg=$(  ${SUDO} netstat -tulnap | egrep ":20000*" )

            WriteLog "Msg netstat: ${msg} ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

            msg=$( ${SUDO} /etc/init.d/hpcc-init status )
            WriteLog "Msg hpcc status:\n${msg} ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

            exit -2
        fi

        WriteLog "Roxie core settings:\n$(sudo cat /proc/$(pidof roxie)/limits | egrep 'Limit|core')" "${PERF_TEST_LOG}"
        WriteLog "  limits.conf:\n$(egrep 'hpcc [sh].* core' /etc/security/limits.conf)" "${PERF_TEST_LOG}"   
        WriteLog "  hpcc_common:\n$(egrep 'MIN_Hc_core=' /opt/HPCCSystems/etc/init.d/hpcc_common)" "${PERF_TEST_LOG}" 
        WriteLog "  Core dump filter: $(sudo cat /proc/$(pidof roxie)/coredump_filter)" "${PERF_TEST_LOG}"
    
    fi
    #
    #---------------------------
    #
    # Get test from github
    #
    
    if true
    then
        WriteLog "Get Performance Test Boundle from github ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
        cd  ${PERF_TEST_ROOT}
    
        WriteLog "Pwd: ${myPwd}" "${PERF_TEST_LOG}"
        
        cRes=$( CloneRepo "${PERF_TEST_REPO}" )
        if [[ 0 -ne  $? ]]
        then
           WriteLog "Repo clone failed ! Result is: ${cres}" "${PERF_TEST_LOG}"
           exit -3
        else
            WriteLog "Repo clone success !" "${PERF_TEST_LOG}"
        fi
    fi
    
    SuppressAnalyserWarnings
    InjectTimeout
    
    cd ${REGRESSION_TEST_ENGINE_HOME}
    
    #
    #----------------------------------------------------
    #
    # Patch testcase(s) which previously run timeout if any

#    WriteLog "Patch testcase(s) which previously run timeout if any ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
#
#    if [ -f ${TIMEOUTED_FILE_LIST_NAME} ]
#    then
#        WriteLog "There is some timeouted testcases ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
#        myPwd=$( pwd )
#
#        cd ${PERF_TEST_HOME}/ecl
#
#        while read file
#        do
#            WriteLog "File:${file}" "${PERF_TEST_LOG}"
#
#            patched=$( grep '//timeout' ${file}.ecl )
#
#            if [[ -z ${patched} ]]
#            then
#                WriteLog "Patching..." "${PERF_TEST_LOG}"
#                (echo ${TIMEOUT_TAG}; cat ${file}'.ecl') >${file}.new
#                mv ${file}{.new,.ecl}
#            else
#                WriteLog "Already has //timeout tag !" "${PERF_TEST_LOG}"
#            fi
#        done < "${TIMEOUTED_FILE_LIST_NAME}"
#
#        cd ${myPwd}
#    fi

    #
    #----------------------------------------------------
    #
    # Update Regression Test Engine config (ecl-test.json)
    #
    
    ORIG_ESP_IP=$( egrep 'espIp' ${REGRESSION_TEST_ENGINE_HOME}/ecl-test.json | tr -d '":,' | awk '{ print $2 }' )

    if [[ -n ${ESP_IP} && ${ESP_IP} != "127.0.0.1" ]]
    then
        WriteLog "Replace original Regression Test Engine ESP IP ${ORIG_ESP_IP} with ${ESP_IP}" "${PERF_TEST_LOG}"

        cp ${REGRESSION_TEST_ENGINE_HOME}/ecl-test.json ${REGRESSION_TEST_ENGINE_HOME}/ecl-test.json.bak

        sed -r -e 's/(\s*)"espIp"\s*:\s*"([0-9\.]*)",/\1"espIp" : "'${ESP_IP}'",/g' ${REGRESSION_TEST_ENGINE_HOME}/ecl-test.json > temp.json && mv -f temp.json ${REGRESSION_TEST_ENGINE_HOME}/ecl-test.json

    else
        WriteLog "Keep original Regression Test Engine ESP IP ${ORIG_ESP_IP}" "${PERF_TEST_LOG}"

    fi

    if [[ -n $PERF_MAX_ATTEMPT_COUNT ]]
    then
        WriteLog "Replace original Regression Test Engine maxAttemptCount value with ${PERF_MAX_ATTEMPT_COUNT}" "${PERF_TEST_LOG}"

        cp ${REGRESSION_TEST_ENGINE_HOME}/ecl-test.json ${REGRESSION_TEST_ENGINE_HOME}/ecl-test.json.bak

        sed -r -e 's/(\s*)"maxAttemptCount"\s*:\s*"([0-9]*)",/\1"maxAttemptCount" : "'${PERF_MAX_ATTEMPT_COUNT}'",/g' ${REGRESSION_TEST_ENGINE_HOME}/ecl-test.json > temp.json && mv -f temp.json ${REGRESSION_TEST_ENGINE_HOME}/ecl-test.json

    else
        WriteLog "Keep original Regression Test Engine maxAttemptCount" "${PERF_TEST_LOG}"

    fi
    
    #
    #----------------------------------------------------
    #
    # Till it is not fixed change
    #   export indexName := prefix + 'index';
    # to
    #   export indexName := thorprefix + 'index';
    # in ecl/perform/files.ecl
    #
    #
    #cd  ${PERF_TEST_HOME}
    #
    #isExists=$( grep -l 'indexName := prefix' ecl/perform/files.ecl )
    #WriteLog "isExists: ${isExists}" "${PERF_TEST_LOG}"
    #if [[ -n ${isExists} ]]
    #then
    #    WriteLog "Replace 'prefix' to 'thorprefix'." "${PERF_TEST_LOG}"
    #    sed 's/indexName := prefix/indexName := thorprefix/g' "ecl/perform/files.ecl" > ./temp.ecl 
    #    mv -f ./temp.ecl ecl/perform/files.ecl
    #else
    #    WriteLog "It seems the 'export indexName:=...' in 'ecl/perform/files.ecl' is already fixed." "${PERF_TEST_LOG}"
    #fi
    #


    #
    #------------------------------------------------------------
    # Start sar monitor if it is enabled
    pushd $OBT_BIN_DIR

    if [[ ${PERF_SAR_MONITOR_START} -eq 1 ]]
    then
        WriteLog "Start System Resource monitor (sar) " "${PERF_TEST_LOG}"

        sar -r 1 > sar-${TARGET_PLATFORM}-$(date +%Y-%m-%d_%H-%M%S).log 2>&1 &
        echo $! > sarMonitor.pid
        WriteLog "  pid: $(cat sarMonitor.pid)" "${PERF_TEST_LOG}"
    fi

    popd

    #
    #---------------------------
    #
    # Run performance tests setup
    #
    WriteLog "Run performance tests setup on all platforms pwd:${myPwd}" "${PERF_TEST_LOG}"
    
    cd ${REGRESSION_TEST_ENGINE_HOME}    

    WriteLog "PERF_TEST_HOME  : ${PERF_TEST_HOME}" "${PERF_TEST_LOG}"
    WriteLog "TEST_ENGINE_HOME: ${REGRESSION_TEST_ENGINE_HOME}" "${PERF_TEST_LOG}"
    
    CMD="./ecl-test setup --suiteDir ${PERF_TEST_HOME} --timeout ${PERF_TIMEOUT} -fthorConnectTimeout=36000 -t thor,roxie --pq ${PERF_SETUP_PARALLEL_QUERIES} ${JOB_NAME_SUFFIX}"

    WriteLog "CMD: '${CMD}'" "${PERF_TEST_LOG}"
    
    if [[ ${EXECUTE_PERFORMANCE_SUITE_SETUP} -ne 0 && ${PERF_RUN_HTHOR} -eq 0 ]]
    then
        ${CMD} >> ${PERF_TEST_LOG} 2>&1
        
        retCode=$( echo $? )
        WriteLog "retcode: ${retCode}" "${PERF_TEST_LOG}"
    
        if [ ${retCode} -ne 0 ] 
        then
            WriteLog "Performance tests on ${TARGET_PLATFORM} returns with ${retCode}" "${PERF_TEST_LOG}"
            exit -1
        else 
            ProcessLog "setup_thor"
            ProcessLog "setup_roxie"
        fi
    else
        WriteLog "Skip performance test setup execution!" "${PERF_TEST_LOG}"

        WriteLog "                                      " "${PERF_TEST_LOG}"        
    fi


    #
    #---------------------------
    #
    # Run performance tests 
    #
    
    WriteLog "Run performance tests on ${TARGET_PLATFORM} (pwd:${myPwd})" "${PERF_TEST_LOG}"
    
    cd ${REGRESSION_TEST_ENGINE_HOME}

    if [[ -n "$PERF_QUERY_LIST" ]]
    then
        CMD="./ecl-test query --suiteDir ${PERF_TEST_HOME} --timeout ${PERF_TIMEOUT} -fthorConnectTimeout=36000 -t ${TARGET_PLATFORM} ${PERF_EXCLUDE_CLASS} --pq ${PERF_TEST_PARALLEL_QUERIES} ${PERF_FLUSH_DISK_CACHE} ${PERF_RUNCOUNT} ${PERF_QUERY_LIST} ${JOB_NAME_SUFFIX}"
    else
        CMD="./ecl-test run --suiteDir ${PERF_TEST_HOME} --timeout ${PERF_TIMEOUT} -fthorConnectTimeout=36000 -t ${TARGET_PLATFORM} ${PERF_EXCLUDE_CLASS} --pq ${PERF_TEST_PARALLEL_QUERIES} ${PERF_FLUSH_DISK_CACHE} ${PERF_RUNCOUNT} ${JOB_NAME_SUFFIX}"
    fi

    WriteLog "${CMD}" "${PERF_TEST_LOG}"
    
    if [ ${EXECUTE_PERFORMANCE_SUITE} -ne 0 ]
    then
        ${CMD} >> ${PERF_TEST_LOG} 2>&1
        
        retCode=$( echo $? )
        WriteLog "retcode: ${retCode}" "${PERF_TEST_LOG}"
        
        if [ ${retCode} -ne 0 ] 
        then
            WriteLog "Performance tests on ${TARGET_PLATFORM} returns with "${retCode} "${PERF_TEST_LOG}"
            exit -1
        else 
            ProcessLog "${TARGET_PLATFORM}"
        fi
    else
        WriteLog "Skip performance test suite execution!" "${PERF_TEST_LOG}"
    fi
    

    #
    #--------------------------
    #
    pushd $OBT_BIN_DIR

    if [[ -f ./sarMonitor.pid ]]
    then
        WriteLog "Stop sarMonitor (pid: $(cat ./sarMonitor.pid)" "${PERF_TEST_LOG}"
        res=$(sudo kill $( cat ./sarMonitor.pid ) 2>&1 )
        retCode=$?
        WriteLog "retCode:$retCode\nres:$res" "${PERF_TEST_LOG}"

        res=$( rm -v ./sarMonitor.pid )
        retCode=$?
        WriteLog "retCode:$retCode\nres:$res" "${PERF_TEST_LOG}"

    fi

    #
    #---------------------------
    #
    # Archive thor performance logs
    #
    
    WriteLog "Archive ${TARGET_PLATFORM} performance logs ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    ${BIN_HOME}/archiveLogs.sh performance-${TARGET_PLATFORM} timestamp=${OBT_TIMESTAMP}
    
    #
    #---------------------------
    #
    # Uninstall HPCC to free as much disk space as can
    #
    
    if [[ ${PERF_KEEP_HPCC} -eq 0 ]]
    then
        WriteLog "Uninstall HPCC to free as much disk space as can on ${TARGET_PLATFORM}!" "${PERF_TEST_LOG}"
    
        WriteLog "Uninstall HPCC-Platform" "${PERF_TEST_LOG}"
    
        UninstallHPCC "${PERF_TEST_LOG}" "${PERF_WIPE_OFF_HPCC}"
    else
        WriteLog "Skip Uninstall HPCC on ${TARGET_PLATFORM} but stop it!" "${PERF_TEST_LOG}"
        StopHpcc "${PERF_TEST_LOG}"
    fi

    #
    #----------------------------
    #
    # Remove ECL-Bundles
    #
    WriteLog "Remove ECL-Bundles" "${PERF_TEST_LOG}"
    
    rm -rf ${PERF_TEST_ROOT}/PerformanceTesting

    WriteLog "                                " "${PERF_TEST_LOG}"
    WriteLog "********************************" "${PERF_TEST_LOG}"
    WriteLog " End of ${TARGET_PLATFORM} test." "${PERF_TEST_LOG}"
    WriteLog "                                " "${PERF_TEST_LOG}"
    
else
    WriteLog "                                " "${PERF_TEST_LOG}"
    WriteLog "********************************" "${PERF_TEST_LOG}"
    WriteLog " Skip ${TARGET_PLATFORM} test.  " "${PERF_TEST_LOG}"
    WriteLog "                                " "${PERF_TEST_LOG}"
fi


TARGET_PLATFORM="roxie"

if [[ "$PERF_RUN_ROXIE" -eq 1 ]]
then
    
    #***************************************************************
    #
    #           ROXIE test
    #
    #***************************************************************
    
    WriteLog "                                " "${PERF_TEST_LOG}"
    WriteLog "********************************" "${PERF_TEST_LOG}"
    WriteLog " Start ${TARGET_PLATFORM} test. " "${PERF_TEST_LOG}"
    WriteLog "                                " "${PERF_TEST_LOG}"
    
    #
    # --------------------------------------------------------------
    # Install HPCC
    #
    
    if [[ ${PERF_KEEP_HPCC} -eq 0 ]]
    then
        if [ -f /etc/HPCCSystems/environment.xml]
        then
            WriteLog "Remove environment.xml to ensure clean, out-of-box environmnet." "${PERF_TEST_LOG}"
            sudo rm /etc/HPCCSystems/environment.xml
        fi


        WriteLog "Install HPCC Platform ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
        ${SUDO} ${PKG_INST_CMD} ${BUILD_HOME}/${HPCC_PACKAGE}
    
        if [ $? -ne 0 ]
        then
            WriteLog "Error in install! ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
            exit 1
        fi
#    else
#        WriteLog "Start HPCC Platform ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
#        ${SUDO} /etc/init.d/hpcc-init start
    fi

    # Add Write permission to /var/lib/HPCCSystems and its subdiretories

    ${SUDO} chmod -R 0777 /var/lib/HPCCSystems

    #
    #----------------------------------------------------
    #
    # Check free memory
    #
    
    WriteLog "Check memory. ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    freeMem=$( free | egrep "^(Mem)" | awk '{print $4 }' )
    
    WriteLog "Free memory is: ${freeMem} kB ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

    #
    #---------------------------
    #
    # Patch environment.xml to use more memory than the default
    #
    
    MEMSIZE=$(( $PERF_ROXIE_MEMSIZE_GB * (2 ** 30) ))

    # for Roxie "totalMemoryLimit" but you also need to set "defaultMemoryLimit" 
    
    WriteLog "Patch environment.xml to use ${PERF_ROXIE_MEMSIZE_GB}GB Memory for ${TARGET_PLATFORM} test" "${PERF_TEST_LOG}"
    
    ${SUDO} cp /etc/HPCCSystems/environment.xml /etc/HPCCSystems/environment.xml.bak
    ${SUDO} sed -e 's/totalMemoryLimit="1073741824"/totalMemoryLimit="'${MEMSIZE}'"/g' -e 's/defaultMemoryLimit="0"/defaultMemoryLimit="'${MEMSIZE}'"/g' "/etc/HPCCSystems/environment.xml" > temp.xml && ${SUDO} mv -f temp.xml "/etc/HPCCSystems/environment.xml"
    
    WriteLog "Add 'farmSsl' Roxie Farm Process to environment.xml" "${PERF_TEST_LOG}"
    addTlsToRoxie

    #
    #---------------------------
    #
    # Check HPCC Systems
    #
    
    WriteLog "Check HPCC Systems ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

    NUMBER_OF_HPCC_COMPONENTS=$( /opt/HPCCSystems/sbin/configgen -env /etc/HPCCSystems/environment.xml -list | egrep -i -v 'eclagent' | wc -l )

    WriteLog "Number of HPCC components is: ${NUMBER_OF_HPCC_COMPONENTS} ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

    
    hpccRunning=$( ${SUDO} /etc/init.d/hpcc-init status | grep -c "running")
    if [[ $hpccRunning -ne ${NUMBER_OF_HPCC_COMPONENTS} ]]
    then
        WriteLog "$hpccRunning componenets are running, start HPCC System... ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
        ${SUDO} /etc/init.d/hpcc-init start
    fi
    
    # give it some time
    sleep 5
    
    hpccRunning=$( ${SUDO} /etc/init.d/hpcc-init status | grep -c "running")
    if [[ ${hpccRunning} -ne ${NUMBER_OF_HPCC_COMPONENTS} ]]
    then
        WriteLog "Unable start HPCC system!! Only ${hpccRunning} component from $NUMBER_OF_HPCC_COMPONENTS is up. ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

        msg=$(  ${SUDO} netstat -tulnap | egrep ":20000*" )
        WriteLog "Msg netstat: ${msg} ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

        msg=$( ${SUDO} /etc/init.d/hpcc-init status )
        WriteLog "Msg hpcc status: ${msg} ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"

        exit -2
    fi
    
    #
    #---------------------------
    #
    # Patch Performance tests to use 1GB RAM in ROXIE tests
    #
    
    if false
    then 
        WriteLog "Patch ecl-bundles/PerformanceTesting/ecl/perform/config.ecl to use 1GB Memory" "${PERF_TEST_LOG}"
    
        cp /root/perftest/ecl-bundles/PerformanceTesting/ecl/perform/config.ecl /root/perftest/ecl-bundles/PerformanceTesting/ecl/perform/config.ecl.bak
    
        sed 's/memoryPerSlave := 0x100000000; \/\/ 4Gb is fairly standard memory configuration/memoryPerSlave := 0x40000000; \/\/ 1Gb to reach clean result in OBT/g' "/root/perftest/ecl-bundles/PerformanceTesting/ecl/perform/config.ecl" > temp.ecl && mv -f temp.ecl "/root/perftest/ecl-bundles/PerformanceTesting/ecl/perform/config.ecl"
    fi
    
    #
    #---------------------------
    #
    # Get test from github
    #
    
    WriteLog "Get Performance Test Boundle from github ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    cd  ${PERF_TEST_ROOT}
    
    WriteLog "Pwd: ${myPwd} ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    WriteLog "Get test from github ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    cRes=$( CloneRepo "${PERF_TEST_REPO}" )
    if [[ 0 -ne  $? ]]
    then
        WriteLog "Repo clone failed ! Result is: ${cres}" "${PERF_TEST_LOG}"
        exit -3
    else
        WriteLog "Repo clone success !" "${PERF_TEST_LOG}"
    fi
    
    SuppressAnalyserWarnings
    InjectTimeout
    cd ${REGRESSION_TEST_ENGINE_HOME}


    #
    #----------------------------------------------------
    #
    # Till it is not fixed change
    #   export indexName := prefix + 'index';
    # to
    #   export indexName := thorprefix + 'index';
    # in ecl/perform/files.ecl
    #
    #
    #cd  ${PERF_TEST_HOME}
    #
    #isExists=$( grep -l 'indexName := prefix' ecl/perform/files.ecl )
    #WriteLog "isExists: ${isExists}" "${PERF_TEST_LOG}"
    #if [[ -n ${isExists} ]]
    #then
    #    WriteLog "Replace 'prefix' to 'thorprefix'." "${PERF_TEST_LOG}"
    #    sed 's/indexName := prefix/indexName := thorprefix/g' "ecl/perform/files.ecl" > ./temp.ecl 
    #    mv -f ./temp.ecl ecl/perform/files.ecl
    #else
    #    WriteLog "It seems the 'export indexName:=...' in 'ecl/perform/files.ecl' is already fixed." "${PERF_TEST_LOG}"
    #fi
    #
    #

    #
    #------------------------------------------------------------
    # Start sar monitor if it is enabled
    pushd $OBT_BIN_DIR

    if [[ ${PERF_SAR_MONITOR_START} -eq 1 ]]
    then
        WriteLog "Start System Resource monitor (sar) " "${PERF_TEST_LOG}"

        sar -r 1 > sar-${TARGET_PLATFORM}-$(date +%Y-%m-%d_%H-%M%S).log 2>&1 &
        echo $! > sarMonitor.pid
        WriteLog "  pid: $(cat sarMonitor.pid)" "${PERF_TEST_LOG}"
    fi

    popd

    #
    #---------------------------
    #
    # Run performance tests on roxie
    #
    
    WriteLog "Run performance tests on ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    cd ${REGRESSION_TEST_ENGINE_HOME}

    TIMEOUT=900
    
    if [[ -n "$PERF_QUERY_LIST" ]]
    then
        CMD="./ecl-test query --suiteDir ${PERF_TEST_HOME} --timeout ${PERF_TIMEOUT} -fthorConnectTimeout=36000 -t ${TARGET_PLATFORM} ${PERF_EXCLUDE_CLASS} --pq ${PERF_TEST_PARALLEL_QUERIES} ${PERF_FLUSH_DISK_CACHE} ${PERF_RUNCOUNT} ${PERF_QUERY_LIST} ${JOB_NAME_SUFFIX}"
    else
        CMD="./ecl-test run --suiteDir ${PERF_TEST_HOME} --timeout ${PERF_TIMEOUT} -fthorConnectTimeout=36000 -t ${TARGET_PLATFORM} ${PERF_EXCLUDE_CLASS} --pq ${PERF_TEST_PARALLEL_QUERIES} ${PERF_FLUSH_DISK_CACHE} ${PERF_RUNCOUNT} ${JOB_NAME_SUFFIX}"
    fi

    WriteLog "${CMD}" "${PERF_TEST_LOG}"
    
    if [ ${EXECUTE_PERFORMANCE_SUITE} -ne 0 ]
    then
        ${CMD} >> ${PERF_TEST_LOG} 2>&1
        
        retCode=$( echo $? )
        WriteLog "retcode: ${retCode}"  "${PERF_TEST_LOG}"
        
        if [ ${retCode} -ne 0 ] 
        then
            WriteLog "Performance tests on ${TARGET_PLATFORM} returns with ${retCode} ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
            exit -1
        else 
            ProcessLog "${TARGET_PLATFORM}"
        fi
    else
        WriteLog "Skip performance test suite execution!" "${PERF_TEST_LOG}"
    fi
 
    #
    #--------------------------
    #
    pushd $OBT_BIN_DIR

    if [[ -f ./sarMonitor.pid ]]
    then
        WriteLog "Stop sarMonitor (pid: $(cat ./sarMonitor.pid)" "${PERF_TEST_LOG}"
        res=$(sudo kill $( cat ./sarMonitor.pid ) 2>&1 )
        retCode=$?
        WriteLog "retCode:$retCode\nres:$res" "${PERF_TEST_LOG}"

        res=$( rm -v ./sarMonitor.pid )
        retCode=$?
        WriteLog "retCode:$retCode\nres:$res" "${PERF_TEST_LOG}"

    fi

    #
    #---------------------------
    #
    # Archive roxie performance logs
    #
    
    WriteLog "Archive ${TARGET_PLATFORM} performance logs ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    
    ${BIN_HOME}/archiveLogs.sh performance-${TARGET_PLATFORM} timestamp=${OBT_TIMESTAMP}
    

    WriteLog "                                " "${PERF_TEST_LOG}"
    WriteLog "********************************" "${PERF_TEST_LOG}"
    WriteLog " End of ${TARGET_PLATFORM} test." "${PERF_TEST_LOG}"
    WriteLog "                                " "${PERF_TEST_LOG}"
    
else

    WriteLog "                                " "${PERF_TEST_LOG}"
    WriteLog "********************************" "${PERF_TEST_LOG}"
    WriteLog " Skip ${TARGET_PLATFORM} test.  " "${PERF_TEST_LOG}"
    WriteLog "                                " "${PERF_TEST_LOG}"

fi

#
#-----------------------------------------------------------------------------
#
# End of Performance test
#

if [ ! -e ${TARGET_DIR}/test/ZAP ]
then
    WriteLog "Create ${TARGET_DIR}/test/ZAP directory..." "${PERF_TEST_LOG}"
    mkdir -p ${TARGET_DIR}/test/ZAP
fi

cp ${ZAP_DIR}/* ${TARGET_DIR}/test/ZAP/

#
#---------------------------
#
# Collect Performance test results
#

cd ${OBT_BIN_DIR}
#if [[ "$PERF_RESULT" == "PASS" ]]
if [[ true ]]
then
    WriteLog "Check HPCC Systems ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    NUMBER_OF_HPCC_COMPONENTS=$( /opt/HPCCSystems/sbin/configgen -env /etc/HPCCSystems/environment.xml -list | egrep -i -v 'eclagent' | wc -l )
    WriteLog "Number of HPCC components is: ${NUMBER_OF_HPCC_COMPONENTS} ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
    hpccRunning=$( ${SUDO} /etc/init.d/hpcc-init status | grep -c "running")
    if [[ $hpccRunning -ne ${NUMBER_OF_HPCC_COMPONENTS} ]]
    then
        WriteLog "$hpccRunning componenets are running, start HPCC System... ${TARGET_PLATFORM}" "${PERF_TEST_LOG}"
        ${SUDO} /etc/init.d/hpcc-init start
    fi
    
    # give it some time
    sleep 5
    
    QUERY_STAT2_EXTRA='-v --timestamp'
    [[ ( -n  ${JOB_NAME_SUFFIX}) && ( -n ${PERF_TEST_DATE} ) ]] &&  QUERY_STAT2_EXTRA=" ${JOB_NAME_SUFFIX} --dateTransform ${PERF_TEST_DATE}"
    WriteLog "Collect Performance Test results" "${PERF_TEST_LOG}"
    CMD="./QueryStat2.py -p ${HOME}/Perfstat/ -d '' --buildType $PERF_BUILD_TYPE ${QUERY_STAT2_EXTRA}" 
    WriteLog "  CMD: '${CMD}'" "${PERF_TEST_LOG}"

    ${CMD} >> ${PERF_TEST_LOG} 2>&1
        
    retCode=$( echo $? )
    WriteLog "retcode: ${retCode}"  "${PERF_TEST_LOG}"


    ARCH_CMD=archivePerfStat.sh
    if [[ -f ../../Perfstat/${ARCH_CMD} ]]
    then
        pushd  ../../Perfstat 
        cmd="./${ARCH_CMD}"
    WriteLog "Arcieve old stat files: ${cmd}" "${PERF_TEST_LOG}"
        res=$( ${cmd} 2>&1 )
    popd
    WriteLog "res: ${res}" "${PERF_TEST_LOG}" 
    fi
    
    coreFiles=$(find /var/lib/HPCCSystems/ /opt/HPCCSystems/ -iname 'core_*.[0-9]*' -type f -print )
    echo "Number of core files found: ${#coreFiles[@]}" > coreFiles.summary 2>&1
    [[ ${#coreFiles[@]} -gt 0 ]] && echo "${coreFiles[@]}" >>  coreFiles.summary

    WriteLog "Copy coreFiles.summary " "${PERF_TEST_LOG}"
    res=$(cp -v coreFiles.summary  ${TARGET_DIR}/test/  2>&1)
    retCode=$?
    WriteLog "$res\nretCode: $retCode" "${PERF_TEST_LOG}"

else
    WriteLog "Performance Test failed, skip collecting results" "${PERF_TEST_LOG}"
fi

#
#---------------------------
#
# Stop HPCC Systems
#

if [ ${PERF_KEEP_HPCC_ALIVE} -eq 0 ]
then
    WriteLog "Stop HPCC Systems." "${PERF_TEST_LOG}"
    StopHpcc "${PERF_TEST_LOG}"
else
    WriteLog "Keep HPCC Systems alive." "${PERF_TEST_LOG}"

fi

WriteLog "End of Performance test" "${PERF_TEST_LOG}"

