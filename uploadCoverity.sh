#!/bin/bash

# Enable to upload any of the possible hpcc-yyyy-mm-dd.tgz and hpcc-cloud-yyyy-mm-dd.tgz results


# Git branch settings

. ./settings.sh

# To enable to specify different coverity result file date than the today's date
# use "yyyy-mm-dd" format
# TO-DO: do it nicer and enable to specify source path to get the corret commit ID
#
if [ "$1." == "." ]
then
    SHORT_DATE=$(date "+%Y-%m-%d")
else
    SHORT_DATE=$1
fi

REPORT_FILE_NAME=hpcc-$SHORT_DATE.tgz
CONTAINERIZED=0

if [[ -f ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} ]]
then
        COVERITY_PROJECT_NAME=HPCC-Platform
        PROJECT_ID=1115
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
else
    REPORT_FILE_NAME=hpcc-cloud-$SHORT_DATE.tgz
    if [[ -f ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} ]]
    then
            CONTAINERIZED=1
            COVERITY_PROJECT_NAME=HPCC-Platform-Cloud
            PROJECT_ID=29342

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
    else
        echo "Coverity scan file not found."
        exit -1
    fi
fi

WEEK_DAY=$(date "+%w")
RECEIVERS=attila.vamos@lexisnexisrisk.com,attila.vamos@gmail.com

echo "Start Coverity scan upload."

# To upload
# When you upload the build can you also include the commit SHA in the version (Gavin)
#
echo "Get ${BRANCH_ID} branch SHA"
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

res=$(curl -X POST -d version="${BRANCH_ID}-SHA:${branchCrc}" -d description="Upload by $OBT_ID" -d email=attila.vamos@gmail.com -d token=$COVERITY_TOKEN -d file_name="${REPORT_FILE_NAME}" https://scan.coverity.com/projects/$PROJECT_ID/builds/init )
echo "Result: ${res}"

#uploadUrl=$(jq -r '.url' response)
uploadUrl=$( echo "$res" | sed -n 's/.*"url":"\([^"]*\)",.*/\1/p' )
echo "uploadUrl: '$uploadUrl'"

#buildId=$(jq -r '.build_id' response)
buildId=$(echo "$res" | sed -n 's/.*"build_id":\([^,]*\).*/\1/p' )
echo "buildId: $buildId"

res=$(curl -X PUT --header 'Content-Type: application/json' --upload-file ${COVERITY_REPORT_PATH}/${REPORT_FILE_NAME} --http1.1 $uploadUrl)
echo "Result: ${res}"

echo "Trigger the build on Scan."
res=$(curl -X PUT -d token=$COVERITY_TOKEN https://scan.coverity.com/projects/$PROJECT_ID/builds/$buildId/enqueue)
echo "Result: ${res}"

echo "End."

