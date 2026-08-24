#!/bin/bash
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

# Git branch settings
. ./settings.sh

[[ "$OBT_ID" =~ "OBT-" ]] && IN_OBT=1 || IN_OBT=0

CLEAN_UP=1
[[ "$1" == "-no-cleanup" ]] && CLEAN_UP=0

[[ -z $COVERITY_BUILD_PATH ]] && COVERITY_BUILD_PATH=$BUILD_HOME
[[ -z $COVERITY_SOURCE_PATH ]] && COVERITY_SOURCE_PATH=$SOURCE_HOME
VCPKG_ARCHIVE="vcpkg_downloads-$BRANCH_ID-coverity.zip"

# Strictly for debug, because it will be so sloow
# Default value set in settings.sh
#NUMBER_OF_BUILD_THREADS=1

# Comment-out and/or update if VCPKG fails to download/build a package
#CMAKE_EXTRA_PARAM=" -D USE_LIBMEMCACHED=OFF -D SUPPRESS_LIBMEMCACHED=ON"

# If it is 1 (default) then upload the result
DO_UPLOAD=1

[ ! -d ${COVERITY_REPORT_PATH} ] && mkdir -p ${COVERITY_REPORT_PATH}
RECEIVERS=attila.vamos@lexisnexisrisk.com,attila.vamos@gmail.com

SHORT_DATE=$(date "+%Y-%m-%d")

CONTAINERIZED=0
WEEK_DAY=$(date "+%w")

if [[  (-n $COVERITY_CLOUD_TEST_DAY) && ( $WEEK_DAY -eq $COVERITY_CLOUD_TEST_DAY )  ]] 
then
    CONTAINERIZED=1
    COVERITY_TEST_DAY=$COVERITY_CLOUD_TEST_DAY
fi

WEEK_DAY_NAME=$(date -d "${WEEK_DAY}" '+%A')
#COVERITY_BIN_DIR=~/cov-analysis-linux64-2023.6.2/bin
#COVERITY_BIN_DIR=~/cov-analysis-linux64-2024.6.1/bin
COVERITY_BIN_DIR=~/cov-analysis-linux64-2024.12.1/bin

# Set it to 1 if you want to test runCoverity.sh without execute Coverity build and upload.
DRY_RUN=0

NEXT_TEST_DAY=$(date -d "next Sunday +$COVERITY_TEST_DAY days")
NEXT_TEST_DAY_NAME=$(date -d "next Sunday +$COVERITY_TEST_DAY days" '+%A')

echo "Start Coverity analysis."
echo "Test day is      : $NEXT_TEST_DAY_NAME"
echo "Today is         : $WEEK_DAY_NAME"
echo "Test branch is   : $COVERITY_TEST_BRANCH"
echo "Current branch is: $BRANCH_ID"
echo "CONTAINERIZED is : $CONTAINERIZED"
echo "Build is in OBT  : $IN_OBT"
echo "Source path      : $COVERITY_SOURCE_PATH"
echo "Build path       : $COVERITY_BUILD_PATH"
echo "VCPKG archive    : $VCPKG_ARCHIVE"


if [[ ( $WEEK_DAY -eq $COVERITY_TEST_DAY ) && ( $BRANCH_ID -eq $COVERITY_TEST_BRANCH ) ]]
then
    if [[ $CONTAINERIZED -eq 0 ]]
    then
        PROJECT_ID=1115
        REPORT_FILE_NAME=hpcc-$SHORT_DATE.tgz
        if [ -f coverityToken.dat ]
        then
            echo "Get Coverity upload token."
            COVERITY_TOKEN=$(cat coverityToken.dat)
            echo "Done."
        else
            echo "Send Email to ${RECEIVERS} about missing 'coverityToken'."
            echo -e "Hi,\n\nCoverity analysis at ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} failed on missing coverityToken.\n\nThanks\n\nOBT" | mailx -s "Missing coverityToken" -u root  ${RECEIVERS}
            exit -1
        fi
        COVERITY_PROJECT_NAME=HPCC-Platform
    else
        PROJECT_ID=29342
        REPORT_FILE_NAME=hpcc-cloud-$SHORT_DATE.tgz
        if [ -f coverityTokenCloud.dat ]
        then
            echo "Get Coverity Cloud upload token."
            COVERITY_TOKEN=$(cat coverityTokenCloud.dat)
            echo "Done."
        else
            echo "Send Email to ${RECEIVERS} about missing 'coverityTokenCloud.dat'."
            echo -e "Hi,\n\nCoverity analysis at ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} failed on missing coverityCloudToken.\n\nThanks\n\nOBT" | mailx -s "Missing coverityCloudToken" -u root  ${RECEIVERS}
            exit -1
        fi
        COVERITY_PROJECT_NAME=HPCC-Platform-Cloud
    fi

    echo "Today is $WEEK_DAY_NAME and current branch is $BRANCH_ID. Perform $([[ $CONTAINERIZED -eq 1 ]] && echo "Containerized/cloud" || echo "Bare Metal") Coverity analysis."

    if [[ -f ${COVERITY_BIN_DIR}/cov-build ]]
    then
        if [[ -f ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} ]]
        then
            echo "Coverity analysis already done. Skip it."
        else
        
            export VCPKG_BINARY_SOURCES="clear;nuget,GitHub,readwrite"
            export VCPKG_NUGET_REPOSITORY=https://github.com/hpcc-systems/vcpkg
            
            if [[ $DRY_RUN -ne 1 ]]
            then
                echo "Create/clean-up build directory ($COVERITY_BUILD_PATH)."
                if [ ! -d $COVERITY_BUILD_PATH ]
                then
                    mkdir -p $COVERITY_BUILD_PATH
                else
                    [[ $CLEAN_UP -eq 1 ]] && rm -rf $COVERITY_BUILD_PATH/*
                fi

                pushd $COVERITY_BUILD_PATH
                echo "Delete cov-int directory."
                [ -d cov-int ] && rm -r cov-int

                echo "Delete .ccfxprep files."
                find . -name '*.ccfxprep' -delete

                if [[ $CLEAN_UP -eq 1 ]]
                then
                    echo "make clean"
                    make clean -j
                fi

                if [[ -f ~/$VCPKG_ARCHIVE && ($CLEAN_UP -eq 1) ]]
                then
                    echo "delete vcpkg_*"
                    rm -rf vcpkg_*

                    echo "extract $VCPKG_ARCHIVE"
                    res=$( unzip ~/vcpkg_downloads-$BRANCH_ID.zip 2>&1 )
                    [[ $? -ne 0 ]] && myEcho "$res"
                fi

                echo "cmake ..."
                cmake -D CMAKE_BUILD_TYPE=RelWithDebInfo -DCONTAINERIZED=$CONTAINERIZED $CMAKE_EXTRA_PARAM ../HPCC-Platform

                echo "Build with ${NUMBER_OF_BUILD_THREADS} threads ..."
                ${COVERITY_BIN_DIR}/cov-build   --dir cov-int make -j ${NUMBER_OF_BUILD_THREADS}
                retCode=$?
                echo "RetCode: $retCode"
                if [[ $retCode -ne 0 ]]
                then
                    echo "Build failed with $retCode"
                    echo "Exit."
                    exit -1
                else
                    echo "  done"
                fi

                if [[ $CLEAN_UP -eq 1 ]]
                then
                    echo "make clean"
                    make clean -j

                    echo "delete vcpkg_*"
                    rm -rf vcpkg_*
                fi

                echo "Generating report file..."
                tar czvf ${REPORT_FILE_NAME} cov-int
                find . -name *.ccfxprep -delete
                mv -v ${REPORT_FILE_NAME} ${COVERITY_REPORT_PATH}/.
                echo "  Done."

                echo "Looking for annotation*.csv file:"
                res=$(find . -iname '*annotation*.csv' -type f  -exec  cp -v  {}  ${COVERITY_REPORT_PATH}/  \; 2>&1)
                echo "  res: $res"

                # To upload
                # When you upload the build can you also include the commit SHA in the version (Gavin)
                #
                echo "Get ${COVERITY_TEST_BRANCH} branch SHA"
                # Need to use the correct path which is PCC-Platform-master-<timestamp>
                branchDir=$(find ~/build/CE/platform/ -iname 'HPCC-Platform-'$COVERITY_TEST_BRANCH'*' -type d )
                if [[ -d $branchDir ]]
                then
                    pushd $branchDir
                    branchCrc=$( git log -1 | grep '^commit' | cut -s -d' ' -f 2)
                    popd
                else
                    pushd $COVERITY_SOURCE_PATH
                    branchCrc=$( git log -1 | grep '^commit' | cut -s -d' ' -f 2)
                    popd
                fi

                echo "Commit ID: ${branchCrc}"

                echo "Send Email to ${RECEIVERS}"
                echo -e "Hi,\n\nCoverity analysis at ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} is ready to upload.\nversion=\"${BRANCH_ID}-SHA:${branchCrc}\"\n\nThanks\n\nOBT" | mailx -s "Today coverity result" -u root  ${RECEIVERS}

                # Need to add error handling and retrying
                echo "Uploading started"
                echo "REPORT_FILE_NAME: '$REPORT_FILE_NAME'"
                echo "PROJECT_ID      : '$PROJECT_ID'"

                # To prevent upload, only for debug
                if [[ $DO_UPLOAD -eq 0 ]]
                then
                    echo "Upload disabled, exit."
                    exit -1
                fi

                echo "Get upload parameters:"
                res=$(curl -X POST -d version="${BRANCH_ID}-SHA:${branchCrc}" -d description="Upload by $OBT_ID" -d email=attila.vamos@gmail.com -d token=$COVERITY_TOKEN -d file_name="${REPORT_FILE_NAME}" https://scan.coverity.com/projects/$PROJECT_ID/builds/init )
                retCode=$?
                echo -e "Ret code: $retCode\nResult: ${res}"

                # Check the response
                # If
                #     "Your build is already in the queue for analysis...."
                # or
                #     "The build submission quota for this project has been reached..."
                # is there then nothing to do
                #
                if [[ "$res" =~ "already in the queue" || "$res" =~ "submission quota" ]]
                then
                    echo "Skip the rest, result is already uploaded."
                else
                    uploadUrl=$( echo -e "$res" | sed -n 's/.*"url":"\([^"]*\)",.*/\1/p' )  # the '-e' for echo necessary to avoid '&' chars conversion to '\u0026' code
                    echo "uploadUrl: '$uploadUrl'"

                    buildId=$(echo "$res" | sed -n 's/.*"build_id":\([^,]*\).*/\1/p' )
                    echo "buildId: $buildId"

                    echo "Upload  ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} file"
                    res=$(curl -X PUT --header 'Content-Type: application/json' --upload-file ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} --http1.1 $uploadUrl)
                    echo "Result: ${res}"

                    if [[ "$res" =~ "<Error>" ]]
                    then
                        echo "Problem with upload. Skip the rest."
                    else
                        echo "Trigger the build on Scan."
                        res=$(curl -X PUT -d token=$COVERITY_TOKEN https://scan.coverity.com/projects/$PROJECT_ID/builds/$buildId/enqueue)
                        echo "Result: ${res}"
                    fi
                fi

                if [[ $CLEAN_UP -eq 1 ]]
                then
                    echo "Clean-up, remove the generated cov-int directory"
                    rm -rf cov-int
                fi
                popd
            fi
       fi
    else
        echo "Coverity analysis doesn't installed on this machine."
    fi

else
    if [[ $WEEK_DAY -eq $COVERITY_TEST_DAY ]]
    then
        echo "Today is $WEEK_DAY_NAME but the current branch: $BRANCH_ID doesn't match to $COVERITY_TEST_BRANCH."
    else
        echo "Today is $WEEK_DAY_NAME. Coverity will run on next $NEXT_TEST_DAY_NAME."
    fi
fi

echo "End."

