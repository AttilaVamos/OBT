#!/bin/bash
PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
#set -x

# Git branch settings
. ./settings.sh

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
COVERITY_BIN_DIR=~/cov-analysis-linux64-2024.6.1/bin

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
            export VCPKG_NUGET_REPOSITORY=https://github.com/hpcc-systems/vHPCC-Platformcpkg
            
            if [[ $DRY_RUN -ne 1 ]]
            then
                pushd ~/build/CE/platform/build    
                rm cov-int -r

                find . -name *.ccfxprep -delete
                make clean -j
                
                if [[ -f ~/vcpkg_downloads-$BRANCH_ID.zip ]] 
                then 
                    res=$( unzip ~/vcpkg_downloads-$BRANCH_ID.zip 2>&1 )
                    [[ $? -ne 0 ]] && myEcho "$res"
                fi
                
                cmake -DCONTAINERIZED=$CONTAINERIZED ../HPCC-Platform
                
                ${COVERITY_BIN_DIR}/cov-build   --dir cov-int make -j ${NUMBER_OF_BUILD_THREADS}
                tar czvf ${REPORT_FILE_NAME} cov-int
                find . -name *.ccfxprep -delete
            
                cp -v ${REPORT_FILE_NAME} ${COVERITY_REPORT_PATH}/.
                find . -iname '*annotation*.csv' -type f  -exec  cp -v  {}  ${COVERITY_REPORT_PATH}/  \;

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
                    echo "$branchDir not found"
                    branchCrc="NotFound"
                fi

                echo ${branchCrc}

                echo "Send Email to ${RECEIVERS}"
                echo -e "Hi,\n\nCoverity analysis at ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} is ready to upload.\nversion=\"${BRANCH_ID}-SHA:${branchCrc}\"\n\nThanks\n\nOBT" | mailx -s "Today coverity result" -u root  ${RECEIVERS}

                # Need to add error handling and retrying
                echo "Uploading started"
                echo "REPORT_FILE_NAME: '$REPORT_FILE_NAME'"
                echo "PROJECT_ID      : '$PROJECT_ID'"

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

                echo "Clean-up, remove the generated cov-int directory"
                rm -rf cov-int
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

