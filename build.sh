#!/bin/bash


#
#------------------------------
#
# Constants 
#

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


# ------------------------------------------------
# Defined in settings.sh
#
#BUILD_DIR=~/build
#OBT_LOG_DIR=${BUILD_DIR}/bin
#OBT_BIN_DIR=${BUILD_DIR}/bin

#RELEASE_BASE=5.0
#RELEASE=
#STAGING_DIR=/tmount/data2/nightly_builds/HPCC/$RELEASE_BASE
#BUILD_SYSTEM=centos_6_x86_64
#BUILD_TYPE=CE/platform
#TARGET_DIR=${STAGING_DIR}/${SHORT_DATE}/${BUILD_SYSTEM}/${BUILD_TYPE}
# ---------------------------------------------

SHORT_DATE=$(date "+%Y-%m-%d")
LONG_DATE=$(date "+%Y-%m-%d_%H-%M-%S") 
OBT_BUILD_LOG_FILE=${OBT_LOG_DIR}/obt-build-${LONG_DATE}.log
BUILD_LOG_FILE=${OBT_LOG_DIR}/build-${LONG_DATE}.log


#
#----------------------------------------------------
#
# Build phase
#
WriteLog "Build started ($0)" "${OBT_BUILD_LOG_FILE}"

WriteLog "Clean up and prepare..." "${OBT_BUILD_LOG_FILE}"

if [ ! -d ${BUILD_DIR}/$RELEASE_TYPE ]
then
    mkdir -p ${BUILD_DIR}/$RELEASE_TYPE
fi

WriteLog "PWD: $(pwd)" "${OBT_BUILD_LOG_FILE}"

cd ${BUILD_DIR}/$RELEASE_TYPE

WriteLog "$BUILD_TYPE build remove build dir." "${OBT_BUILD_LOG_FILE}"

res=$( rm  build )
[[ $? -ne 0 ]] && WriteLog " 'rm build' return with ${res}" "${OBT_BUILD_LOG_FILE}"

buildTarget=build-${BRANCH_ID}-${LONG_DATE}

WriteLog "Create symlink for build to ${buildTarget}." "${OBT_BUILD_LOG_FILE}"
mkdir ${buildTarget}

ln -s ${buildTarget} build

WriteLog "Done." "${OBT_BUILD_LOG_FILE}"

# Remove all build-* directory older than a week (?)
#
WriteLog "Before:" "${OBT_BUILD_LOG_FILE}"
WriteLog "$( df -h . )\n" "${OBT_BUILD_LOG_FILE}"
WriteLog "$( du -ksch build-* HPCC-Platform-* )" "${OBT_BUILD_LOG_FILE}"
WriteLog "---------------------------------" "${OBT_BUILD_LOG_FILE}"

WriteLog "Remove all build-* directory older than ${BUILD_DIR_EXPIRE} days." "${OBT_BUILD_LOG_FILE}"
res=$( find . -maxdepth 1 -daystart -type d -mtime +${BUILD_DIR_EXPIRE} -iname 'build-*' -print -exec rm -rf '{}' \; 2>&1 )
WriteLog "res:${res}" "${OBT_BUILD_LOG_FILE}"

WriteLog "Done." "${OBT_BUILD_LOG_FILE}"


WriteLog "LD_LIBRARY_PATH=$LD_LIBRARY_PATH" "${OBT_BUILD_LOG_FILE}"


#
#----------------------------------------------------
#
# Git repo clone
#

WriteLog "Git repo clone" "${OBT_BUILD_LOG_FILE}"
target=HPCC-Platform-${BRANCH_ID}-${LONG_DATE}
cRes=$( CloneRepo "https://github.com/hpcc-systems/HPCC-Platform.git" "${target}" )
if [[ 0 -ne  $? ]]
then
    WriteLog "Repo clone failed ! Result is: ${cres}" "${OBT_BUILD_LOG_FILE}"

    ExitEpilog "${OBT_BUILD_LOG_FILE}" "build.sh" "Repo clone failed ! Result is: ${cres}"

else
    WriteLog "Repo clone success !" "${OBT_BUILD_LOG_FILE}"
    
    WriteLog "Create symlink for HPCC-Platform to ${target}." "${OBT_BUILD_LOG_FILE}"
    rm HPCC-Platform

    ln -s ${target} HPCC-Platform
    WriteLog "Done." "${OBT_BUILD_LOG_FILE}"
   
    # Remove all HPCC-Platform-* directory older than a week (?)
    #

    WriteLog "Remove all HPCC-Platform-* directory older than ${SOURCE_DIR_EXPIRE} days." "${OBT_BUILD_LOG_FILE}"
    res=$( find . -maxdepth 1 -daystart -type d -mtime +${SOURCE_DIR_EXPIRE} -iname 'HPCC-Platform-*' -print -exec rm -rf '{}' \; 2>&1 )
    WriteLog "res:${res}" "${OBT_BUILD_LOG_FILE}"

    WriteLog "---------------------------------" "${OBT_BUILD_LOG_FILE}"
    WriteLog "After:" "${OBT_BUILD_LOG_FILE}"
    WriteLog "$( df -h . )\n" "${OBT_BUILD_LOG_FILE}"
    WriteLog "$( du -ksch build-* HPCC-Platform-* )" "${OBT_BUILD_LOG_FILE}"

    WriteLog "Done." "${OBT_BUILD_LOG_FILE}"
    
fi

#
#----------------------------------------------------
#
# We use branch which is set in settings.sh
#
WriteLog "We use branch: ${BRANCH_ID} which is set in settings.sh" "${OBT_BUILD_LOG_FILE}"

cd HPCC-Platform

echo "git branch: ${BRANCH_ID}"  > ${GIT_2DAYS_LOG}

echo "git checkout ${BRANCH_ID}" >> ${GIT_2DAYS_LOG}    
    WriteLog "git checkout ${BRANCH_ID}" "${OBT_BUILD_LOG_FILE}"

res=$( git checkout ${BRANCH_ID} 2>&1 )
echo $res >> ${GIT_2DAYS_LOG}
WriteLog "Result:${res}" "${OBT_BUILD_LOG_FILE}"

branchDate=$( git log -1 | grep '^Date' ) 
WriteLog "Branch ${branchDate}" "${OBT_BUILD_LOG_FILE}"
echo $branchDate >> ${GIT_2DAYS_LOG}

branchCrc=$( git log -1 | grep '^commit' )
WriteLog "Branch ${branchCrc}" "${OBT_BUILD_LOG_FILE}"
echo $branchCrc>> ${GIT_2DAYS_LOG}

numberOfCommitsInLast24Hours=$( git log --pretty=format:"%h%x09%an%x09%ad%x09%s" --since="1 day" | wc -l )
WriteLog "Number of commits in last 24 hours ${numberOfCommitsInLast24Hours}" "${OBT_BUILD_LOG_FILE}"
echo "numberOfCommitsInLast24Hours: $numberOfCommitsInLast24Hours" >> ${GIT_2DAYS_LOG}

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

WriteLog "Update git submodule" "${OBT_BUILD_LOG_FILE}"

subRes=$( SubmoduleUpdate "--init --recursive" )
#subRes=$( SubmoduleUpdate "--init" )
if [[ 0 -ne  $? ]]
then
    WriteLog "Submodule update failed ! Result is: ${subRes}" "${OBT_BUILD_LOG_FILE}"

    ExitEpilog "${OBT_BUILD_LOG_FILE}" "build.sh" "Submodule update failed ! Result is: ${subRes}"

else
    WriteLog "Submodule update success !" "${OBT_BUILD_LOG_FILE}"
fi

#
#----------------------------------------------------
#
# Patch/hack before build

# Patch plugins/couchbase/libcouchbase/cmake/Modules/DonwloadLcbDep.cmake

res=$(  egrep "\-\-retry" $SOURCE_HOME/plugins/couchbase/libcouchbase/cmake/Modules/DownloadLcbDep.cmake )
if [ -z "$res" ]
then
    WriteLog "Patch plugins/couchbase/libcouchbase/cmake/Modules/DownloadLcbDep.cmake to retry download 20 times before give it up" "${OBT_BUILD_LOG_FILE}"
    
    sudo cp $SOURCE_HOME/plugins/couchbase/libcouchbase/cmake/Modules/DownloadLcbDep.cmake $SOURCE_HOME/plugins/couchbase/libcouchbase/cmake/Modules/DownloadLcbDep.cmake.bak

    sudo sed -e 's/EXECUTE_PROCESS(COMMAND "${CURL}" \(.*\)$/EXECUTE_PROCESS(COMMAND "${CURL}" --retry 20 \1/' $SOURCE_HOME/plugins/couchbase/libcouchbase/cmake/Modules/DownloadLcbDep.cmake > temp.txt && sudo mv -f temp.txt $SOURCE_HOME/plugins/couchbase/libcouchbase/cmake/Modules/DownloadLcbDep.cmake

    WriteLog "curl params: $( sed -n 's/EXECUTE_PROCESS(COMMAND "${CURL}" \(.*\)$/\1/p' $SOURCE_HOME/plugins/couchbase/libcouchbase/cmake/Modules/DownloadLcbDep.cmake ) " "${OBT_BUILD_LOG_FILE}"

else
    WriteLog "No pathch neccessary." "${OBT_BUILD_LOG_FILE}"

fi

# jcomp.cpp hack
if [[ -f ${OBT_BIN_DIR}/jcomp.cpp ]]
then
    WriteLog "Copy jcomp.cpp" "${OBT_BUILD_LOG_FILE}"
    cp ${OBT_BIN_DIR}/jcomp.cpp $SOURCE_HOME/system/jlib/
fi

#
#----------------------------------------------------
#
# Global Exclusion
#

if [ ! -e "${TARGET_DIR}" ] 
then
    WriteLog "Create ${TARGET_DIR}..." "${OBT_BUILD_LOG_FILE}"
    mkdir -p  $TARGET_DIR
fi

if [ -e "${TARGET_DIR}" ] 
    then
        chmod 777 ${STAGING_DIR}/${SHORT_DATE}
        WriteLog "Create global exclusion file and copy it to ${TARGET_DIR}..." "${OBT_BUILD_LOG_FILE}"

        # Should check the content(lentgh) of REGRESSION_EXCLUDE_CLASS and REGRESSION_EXCLUDE_FILES
        # to avoid orphan ',' char in "Regression:" line.
        #echo "Regression:${REGRESSION_EXCLUDE_CLASS}, ${REGRESSION_EXCLUDE_FILES}" > ${GLOBAL_EXCLUSION_LOG}

        [[ -n "$SUPRESS_PLUGINS" ]] && echo "Build:${SUPRESS_PLUGINS}" > ${GLOBAL_EXCLUSION_LOG}

        [[ -n "$UNITTESTS_EXCLUDE" ]] && echo "Unittests:${UNITTESTS_EXCLUDE[@]}" >> ${GLOBAL_EXCLUSION_LOG}

        [[ -n "$PERFORMANCE_EXCLUDE_CLASS" ]] && echo "Performance:${PERFORMANCE_EXCLUDE_CLASS}" >> ${GLOBAL_EXCLUSION_LOG}

        [[ ${BUILD_DOCS} -eq 0 ]] && BUILD_DOCS_STR=No || BUILD_DOCS_STR=Yes
        echo "Documentation: ${BUILD_DOCS_STR}" >> ${GLOBAL_EXCLUSION_LOG}


        echo "# Generated by OBT @ $( date '+%Y-%m-%d %H:%M:%S' )" >> ${GLOBAL_EXCLUSION_LOG}
        echo "# for build and testing ${BRANCH_ID}" >> ${GLOBAL_EXCLUSION_LOG}
        echo "# on ${OBT_SYSTEM} ${OBT_SYSTEM_ENV}, OS: ${SYSTEM_ID}" >> ${GLOBAL_EXCLUSION_LOG}


        #WriteLog "Regression exclusion:${REGRESSION_EXCLUDE_CLASS} (class), ${REGRESSION_EXCLUDE_FILES} (file)" "${OBT_BUILD_LOG_FILE}"
        cp ${GLOBAL_EXCLUSION_LOG} $TARGET_DIR/
else
        WriteLog "$TARGET_DIR doesn't exist or un-reachable" "${OBT_BUILD_LOG_FILE}"
fi


#
#----------------------------------------------------
#
# Check on-fly download for Couchbase
#

WriteLog "Check whether 'packages.couchbase.com' is resolvable" "${OBT_BUILD_LOG_FILE}"

PING_TRY_COUNT=5
PING_TRY_DELAY=2m

while [[ $PING_TRY_COUNT -gt 0 ]]
do 
    WriteLog "Try count: $PING_TRY_COUNT" "${OBT_BUILD_LOG_FILE}"
    PING_TRY_COUNT=$(( $PING_TRY_COUNT - 1 ))

    ping_res=$( ping -c 1 packages.couchbase.com 2>&1 )
    if [[ "${ping_res}" =~ "unknown" ]]
    then 
        WriteLog "Error: '${ping_res}'. Wait ${PING_TRY_DELAY} for retry." "${OBT_BUILD_LOG_FILE}"
        sleep ${PING_TRY_DELAY}
    else
        WriteLog "The 'packages.couchbase.com' is accessible" "${OBT_BUILD_LOG_FILE}"
        WriteLog "Ping: ${ping_res}" "${OBT_BUILD_LOG_FILE}"

        PING_1=$( echo "$ping_res" | head -n 1)
        WriteLog "${PING_1}\n" "${OBT_LOG_DIR}/packages_couchbase_com.ping"
        break
    fi
done



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

WriteLog "Check if $BOOST_PKG cached" "${OBT_BUILD_LOG_FILE}"
if [[ ! -f $HOME/$BOOST_PKG ]]
then
    WriteLog "It is not, download it." "${OBT_BUILD_LOG_FILE}"
    BOOST_DOWNLOAD_TRY_COUNT=5
    BOOST_DOWNLOAD_TRY_DELAY=2m

    while [[ $BOOST_DOWNLOAD_TRY_COUNT -gt 0 ]]
    do 
        WriteLog "Try count: $BOOST_DOWNLOAD_TRY_COUNT" "${OBT_BUILD_LOG_FILE}"
        BOOST_DOWNLOAD_TRY_COUNT=$(( $BOOST_DOWNLOAD_TRY_COUNT - 1 ))

        download_res=$( wget -v  -O  $HOME/$BOOST_PKG  $BOOST_URL 2>&1 )
        retCode=$?
        if [[  $retCode -ne 0 ]]
        then 
            WriteLog "Error: $retCode '${download_res}'. Wait ${BOOST_DOWNLOAD_TRY_DELAY} for retry." "${OBT_BUILD_LOG_FILE}"
            sleep ${BOOST_DOWNLOAD_TRY_DELAY}
            [[ -f $HOME/$BOOST_PKG ]] && rm $HOME/$BOOST_PKG
        else
            WriteLog "The $BOOST_PKG downloaded." "${OBT_BUILD_LOG_FILE}"
            WriteLog "Ping: ${download_res}" "${OBT_BUILD_LOG_FILE}"

            DOWNL=$( echo "$download_res" | tail -nhead -n 2)
            WriteLog "${DOWNL}" "${OBT_LOG_DIR}/$BOOST_PKG.download"
            break
        fi
    done
fi

if [[ ! -f $HOME/$BOOST_PKG ]]
then
    WriteLog "The $BOOST_PKG download attempts were unsuccessful." "${OBT_BUILD_LOG_FILE}"
else
    WriteLog "The $BOOST_PKG downloaded, copy it into the source tree." "${OBT_BUILD_LOG_FILE}"
    mkdir -p ${BUILD_HOME}/downloads
    res=$( cp -v  $HOME/$BOOST_PKG ${BUILD_HOME}/downloads/  2>&1 )
    WriteLog "res: ${res}" "${OBT_BUILD_LOG_FILE}"
fi

#
#----------------------------------------------------
#
# Build
#

cd ${BUILD_HOME}

WriteLog "Build it...( $( pwd ) )" "${OBT_BUILD_LOG_FILE}"

CURRENT_DATE=$( date "+%Y-%m-%d %H:%M:%S")
WriteLog "Start at ${CURRENT_DATE}" "${OBT_BUILD_LOG_FILE}"
echo "Start at ${CURRENT_DATE}" > ${BUILD_LOG_FILE} 2>&1

WriteLog "Generate makefiles ( $( pwd ) )" "${OBT_BUILD_LOG_FILE}"
WriteLog "Build docs: ${BUILD_DOCS}" "${OBT_BUILD_LOG_FILE}"
export BUILD_DOCS
${OBT_BIN_DIR}/build_pf.sh HPCC-Platform ${BUILD_TYPE} >> ${BUILD_LOG_FILE} 2>&1

WriteLog "Build it...( $( pwd ) )" "${OBT_BUILD_LOG_FILE}"

TIME_STAMP=$(date +%s)

CMD="make -j ${NUMBER_OF_BUILD_THREADS} package"

WriteLog "cmd:'${CMD}'." "${OBT_BUILD_LOG_FILE}"

${CMD} >> ${BUILD_LOG_FILE} 2>&1

BUILD_TIME=$(( $(date +%s) - $TIME_STAMP ))

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
echo "Elaps:$( SecToTimeStr ${BUILD_TIME} )" >> ${BUILD_LOG_FILE}

CURRENT_DATE=$( date "+%Y-%m-%d %H:%M:%S")
WriteLog "Build end at ${CURRENT_DATE}" "${OBT_BUILD_LOG_FILE}"
echo "Build end at ${CURRENT_DATE}" >> ${BUILD_LOG_FILE} 2>&1

if [ ! -e "${TARGET_DIR}" ] 
then
   WriteLog "Create ${TARGET_DIR}..." "${OBT_BUILD_LOG_FILE}"
   mkdir -p  $TARGET_DIR
fi

if [ -e "${TARGET_DIR}" ] 
then
    WriteLog "Copy files to ${TARGET_DIR}..." "${OBT_BUILD_LOG_FILE}"
    #chmod 777 ${STAGING_DIR}/${SHORT_DATE}
    cp ${GIT_2DAYS_LOG}  $TARGET_DIR/
    cp ${BUILD_LOG_FILE}  $TARGET_DIR/build.log

    cp usedPort.summary $TARGET_DIR/

else
    WriteLog "$TARGET_DIR doesn't exist or un-reachable" "${OBT_BUILD_LOG_FILE}"
fi

if [ "$buildResult" = "SUCCEED" ]
then
    echo "BuildResult:SUCCEED" >   $TARGET_DIR/build_summary
    echo "Elaps:${BUILD_TIME} sec" >> $TARGET_DIR/build_summary

    WriteLog "BuildResult:SUCCEED" "${OBT_BUILD_LOG_FILE}"
    WriteLog "Elaps:${BUILD_TIME} sec" "${OBT_BUILD_LOG_FILE}"

    cp $TARGET_DIR/build_summary ${OBT_BIN_DIR}

    hpcc_package=$( find . -maxdepth 1 -iname 'hpcc*'${PKG_EXT} -type f -print)
    if [ -f "$hpcc_package" ]
    then    
        WriteLog "Archive the package" "${OBT_BUILD_LOG_FILE}"

        cp $hpcc_package  $TARGET_DIR/
        res=$( ${SUDO} ${PKG_INST_CMD} ${BUILD_HOME}/$hpcc_package 2>&1 )

        WriteLog "Install package" "${OBT_BUILD_LOG_FILE}"

        echo "${res}" > install.log
        WriteLog "Install result is:\n${res}" "${OBT_BUILD_LOG_FILE}"

    else
        WriteLog "Install package don't found." "${OBT_BUILD_LOG_FILE}"
        ExitEpilog "${OBT_LOG_FILE}" "-1"
    fi

    WriteLog "Patch /etc/HPCCSystems/environment.xml to enable ESP starts without WS_SQL" "${OBT_BUILD_LOG_FILE}"

    sudo mv -f /etc/HPCCSystems/environment.xml /etc/HPCCSystems/environment.bak

    if [[ $MAKE_WSSQL -eq 0 ]]
    then
    
        sudo xmlstarlet ed -r '//Environment/Software/EspProcess/EspBinding[@service="ws_sql"]' -v "InactiveEspBinding" \
                           -r '//Environment/Software/EspService[@name="ws_sql"]' -v "InactiveEspService" \
                           /etc/HPCCSystems/environment.bak | sudo tee /etc/HPCCSystems/environment.xml 1>/dev/null

    else
        WriteLog "Remove patch from /etc/HPCCSystems/environment.xml to enable ESP starts with WS_SQL" "${OBT_BUILD_LOG_FILE}"

        sudo xmlstarlet ed -r '//Environment/Software/EspProcess/InactiveEspBinding[@service="ws_sql"]' -v "EspBinding" \
                           -r '//Environment/Software/InactiveEspService[@name="ws_sql"]' -v "EspService" \
                           /etc/HPCCSystems/environment.bak | sudo tee /etc/HPCCSystems/environment.xml 1>/dev/null
 
    fi

    if [ -f /etc/HPCCSystems/environment.xml ]
    then
        WriteLog "The /etc/HPCCSystems/environment.xml is patched to enable ESP starts without WS_SQL" "${OBT_BUILD_LOG_FILE}"

    else
        sudo mv -f /etc/HPCCSystems/environment.bak /etc/HPCCSystems/environment.xml
        WriteLog "Something whent wrong and the /etc/HPCCSystems/environment.xml doesn't patched.\nThe original environment.xml restored." "${OBT_BUILD_LOG_FILE}"
       
    fi
    
    if [[ -d "/opt/HPCCSystems/lib64" ]]
    then
        WriteLog "There is an unwanted lib64 directory, copy its contents into lib" "${OBT_BUILD_LOG_FILE}"
        sudo cp -v /opt/HPCCSystems/lib64/* /opt/HPCCSystems/lib/
    fi
 
else
   echo "BuildResult:FAILED" >   $TARGET_DIR/build_summary
   WriteLog "BuildResult:FAILED" "${OBT_BUILD_LOG_FILE}"
   cp $TARGET_DIR/build_summary ${OBT_BIN_DIR}

   # Remove old builds
   ${BUILD_DIR}/bin/clean_builds.sh

   WriteLog "Send Email notification about build failure" "${OBT_BUILD_LOG_FILE}"
   
   # Email Notify
   cd ${OBT_BIN_DIR}
   ./BuildNotification.py -d ${OBT_DATESTAMP} -t ${OBT_TIMESTAMP} >> "${OBT_BUILD_LOG_FILE}" 2>&1


   ExitEpilog "${OBT_BUILD_LOG_FILE}" "-1"

fi
