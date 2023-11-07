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
COVERITY_BIN_DIR=~/cov-analysis-linux64-2022.6.0/bin

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
            
                cp ${REPORT_FILE_NAME} ${COVERITY_REPORT_PATH}/.
                echo "Send Email to ${RECEIVERS}"
                echo -e "Hi,\n\nCoverity analysis at ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} is ready to upload.\n\nThanks\n\nOBT" | mailx -s "Today coverity result" -u root  ${RECEIVERS}
           
                # To upload
                # When you upload the build can you also include the commit SHA in the version (Gavin)
                #
                echo "Get ${BRANCH_ID} branch SHA"
                pushd ~/build/CE/platform/HPCC-Platform/
               
                branchCrc=$( git log -1 | grep '^commit' | cut -s -d' ' -f 2)
                
                echo ${branchCrc}
                popd

                echo "Uploading started"

                curlParams="--form token=$COVERITY_TOKEN --form email=${ADMIN_EMAIL_ADDRESS} --form file=@${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} --form version=\"${BRANCH_ID}-SHA:${branchCrc}\" --form description=\"Upload by OBT\" "
                     
                echo "curl params: ${curlParams}"

                res=$( curl ${curlParams} https://scan.coverity.com/builds?project=$COVERITY_PROJECT_NAME 2>&1 )
            
                echo "Upload finished."
                echo "Result: ${res}"

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

